data "aws_caller_identity" "current" {}

data "terraform_remote_state" "issuer" {
  backend = "s3"

  config = {
    bucket = "tf-backend-jord-projs"
    key    = "idp-platform/bootstrap/aws/oidc-issuer.tfstate"
    region = "us-east-1"
  }
}

locals {
  issuer_url  = data.terraform_remote_state.issuer.outputs.issuer_url
  issuer_host = trimprefix(local.issuer_url, "https://")
  subjects    = [for sa in var.provider_service_accounts : "system:serviceaccount:${var.crossplane_namespace}:${sa}"]
}

# AWS side of ADR-0001: trust the K3s service account issuer. STS fetches the
# JWKS from the issuer URL at AssumeRoleWithWebIdentity time, so the discovery
# documents must be published (oidc-issuer, publish_discovery_docs = true).
resource "aws_iam_openid_connect_provider" "k3s" {
  url            = local.issuer_url
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.k3s.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Exact subjects, not a wildcard, so the trust matches the Azure and GCP
    # models and a new provider cannot assume the role without a reviewed diff.
    condition {
      test     = "StringEquals"
      variable = "${local.issuer_host}:sub"
      values   = local.subjects
    }
  }
}

# Ceiling on anything the provider role can ever be granted, whatever later
# phases attach. The allowed services are the paved-road menu; adding a new
# infra type means widening this list in a reviewed diff. IAM, Organizations,
# and account APIs are never in the menu, and nothing runs outside the region.
#trivy:ignore:AWS-0345
data "aws_iam_policy_document" "boundary" {
  #checkov:skip=CKV_AWS_111:Permissions boundary, a ceiling that grants nothing; identity policies scope resources.
  #checkov:skip=CKV_AWS_109:Permissions boundary, a ceiling that grants nothing; identity policies scope resources.
  #checkov:skip=CKV_AWS_356:Permissions boundary, a ceiling that grants nothing; identity policies scope resources.
  statement {
    sid = "PavedRoadServices"
    actions = [
      "s3:*",
      "rds:*",
      "ec2:*",
      "kms:*",
      "eks:*",
      "elasticloadbalancing:*",
      "logs:*",
      "cloudwatch:*",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DenyOutsideRegion"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }
}

resource "aws_iam_policy" "boundary" {
  name        = "idp-crossplane-provider-aws-boundary"
  description = "Permissions boundary for the idp-platform Crossplane AWS provider role."
  policy      = data.aws_iam_policy_document.boundary.json
}

resource "aws_iam_role" "provider" {
  name                 = "idp-crossplane-provider-aws"
  description          = "Assumed by idp-platform Crossplane AWS providers via K3s OIDC web identity."
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  permissions_boundary = aws_iam_policy.boundary.arn
  max_session_duration = 3600
}

# Phase 0: exactly what the verification Bucket needs, on the verification
# prefix only. Phase 1 adds RDS as its own reviewed diff below.
data "aws_iam_policy_document" "phase0" {
  statement {
    sid = "VerifyBucketLifecycle"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:ListBucket",
      "s3:Get*",
      "s3:PutBucketTagging",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketOwnershipControls",
      "s3:PutEncryptionConfiguration",
      "s3:PutBucketVersioning",
    ]
    resources = ["arn:aws:s3:::${var.verify_bucket_prefix}*"]
  }
}

resource "aws_iam_policy" "phase0" {
  name        = "idp-crossplane-provider-aws-phase0"
  description = "Phase 0 verification permissions for the idp-platform Crossplane AWS provider."
  policy      = data.aws_iam_policy_document.phase0.json
}

resource "aws_iam_role_policy_attachment" "phase0" {
  role       = aws_iam_role.provider.name
  policy_arn = aws_iam_policy.phase0.arn
}

locals {
  rds_arn_prefix = "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}"
  db_arn         = "${local.rds_arn_prefix}:db:${var.db_identifier_prefix}*"

  # CreateDBInstance and ModifyDBInstance authorize against every resource the
  # instance references, not only the instance itself.
  db_dependency_arns = [
    "${local.rds_arn_prefix}:subgrp:${var.db_subnet_group_name}",
    "${local.rds_arn_prefix}:pg:default.postgres${var.postgres_major_version}",
    "${local.rds_arn_prefix}:og:default:postgres-${var.postgres_major_version}",
  ]
}

# Phase 1: RDS instance lifecycle for the xdatabase-aws Composition, on the
# platform identifier prefix only. Creation requires the Project tag and
# changes require it on the existing instance, so the role cannot touch an
# RDS instance it did not create. No ec2 write access: networking is shared
# bootstrap (ADR-0008). The RDS service-linked role already exists, so no IAM.
data "aws_iam_policy_document" "phase1" {
  statement {
    sid       = "CreateTaggedPlatformDatabases"
    actions   = ["rds:CreateDBInstance", "rds:AddTagsToResource"]
    resources = [local.db_arn]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = ["idp-platform"]
    }
  }

  statement {
    sid       = "ManagePlatformDatabases"
    actions   = ["rds:ModifyDBInstance", "rds:DeleteDBInstance", "rds:RebootDBInstance"]
    resources = [local.db_arn]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = ["idp-platform"]
    }
  }

  # Tag changes on an instance the platform already owns: an Owner or
  # Environment edit, or the provider's crossplane-name tag after a control
  # plane rebuild gives the MR a new name (ADR-0017). AddTagsToResource only
  # carries the changed tags, so the create-time RequestTag/Project condition
  # above cannot match it. The Project tag itself can be neither changed to
  # another value nor removed, so the role cannot release an instance from
  # its own scope.
  statement {
    sid       = "RetagPlatformDatabases"
    actions   = ["rds:AddTagsToResource"]
    resources = [local.db_arn]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = ["idp-platform"]
    }

    condition {
      test     = "StringEqualsIfExists"
      variable = "aws:RequestTag/Project"
      values   = ["idp-platform"]
    }
  }

  statement {
    sid       = "UntagPlatformDatabases"
    actions   = ["rds:RemoveTagsFromResource"]
    resources = [local.db_arn]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = ["idp-platform"]
    }

    condition {
      test     = "ForAllValues:StringNotEquals"
      variable = "aws:TagKeys"
      values   = ["Project"]
    }
  }

  statement {
    sid       = "ReferencePlatformDependencies"
    actions   = ["rds:CreateDBInstance", "rds:ModifyDBInstance"]
    resources = local.db_dependency_arns
  }

  statement {
    sid       = "ReadPlatformDatabases"
    actions   = ["rds:ListTagsForResource"]
    resources = [local.db_arn]
  }

  # The provider looks an instance up by filter before it knows its resource
  # ID, so AWS evaluates DescribeDBInstances against db:* in this account and
  # region. Read only (ADR-0014).
  statement {
    sid       = "DescribeDatabasesByFilter"
    actions   = ["rds:DescribeDBInstances"]
    resources = ["${local.rds_arn_prefix}:db:*"]
  }
}

resource "aws_iam_policy" "phase1" {
  name        = "idp-crossplane-provider-aws-phase1"
  description = "Phase 1 RDS permissions for the idp-platform Crossplane AWS provider."
  policy      = data.aws_iam_policy_document.phase1.json
}

resource "aws_iam_role_policy_attachment" "phase1" {
  role       = aws_iam_role.provider.name
  policy_arn = aws_iam_policy.phase1.arn
}
