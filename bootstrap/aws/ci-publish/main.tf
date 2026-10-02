data "aws_caller_identity" "current" {}

# ADR-0024: the GitHub Actions OIDC provider already exists in the account,
# created outside this repository and used by other roles. Read it, never
# create or adopt it; deleting it elsewhere breaks publishing (see README).
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_host = "token.actions.githubusercontent.com"

  # GitHub's immutable subject: repo:<org>@<org id>/<repo>@<repo id>:ref:<ref>.
  # Repository names and git refs cannot contain a colon, so the wildcard
  # cannot reach past the repository segment into the ref.
  subject = "repo:${var.github_org}@${var.github_org_id}/*:ref:${var.publish_ref}"

  repository_arn = "arn:aws:ecr-public::${data.aws_caller_identity.current.account_id}:repository/${var.github_org}/*"
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${local.oidc_host}:sub"
      values   = [local.subject]
    }
  }
}

# Ceiling for the publish role: ECR Public and the bearer token it needs,
# nothing else, in us-east-1 only. Deleting images or repositories and
# changing repository policies are denied here as well as never granted, so
# a later widening of the identity policy still cannot remove an image.
#trivy:ignore:AWS-0345
data "aws_iam_policy_document" "boundary" {
  #checkov:skip=CKV_AWS_111:Permissions boundary, a ceiling that grants nothing; the identity policy scopes resources.
  #checkov:skip=CKV_AWS_109:Permissions boundary, a ceiling that grants nothing; the identity policy scopes resources.
  #checkov:skip=CKV_AWS_356:Permissions boundary, a ceiling that grants nothing; the identity policy scopes resources.
  statement {
    sid       = "PublishServices"
    actions   = ["ecr-public:*", "sts:GetServiceBearerToken"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyDestructive"
    effect = "Deny"
    actions = [
      "ecr-public:BatchDeleteImage",
      "ecr-public:DeleteRepository",
      "ecr-public:DeleteRepositoryPolicy",
      "ecr-public:SetRepositoryPolicy",
      "ecr-public:UntagResource",
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
  name        = "idp-ci-publish-boundary"
  description = "Permissions boundary for the idp-platform CI image publishing role."
  policy      = data.aws_iam_policy_document.boundary.json
}

resource "aws_iam_role" "publish" {
  name                 = "idp-ci-publish"
  description          = "Assumed by GitHub Actions on main in ${var.github_org} to push images to ECR Public (ADR-0024)."
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  permissions_boundary = aws_iam_policy.boundary.arn
  max_session_duration = 3600
}

data "aws_iam_policy_document" "publish" {
  #checkov:skip=CKV_AWS_107:A registry push needs the ECR Public auth token and its STS bearer token; the bearer token is limited to ecr-public.amazonaws.com.
  # Neither action accepts a resource. The bearer token is limited to the
  # ECR Public service name.
  statement {
    sid       = "AuthToken"
    actions   = ["ecr-public:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "BearerToken"
    actions   = ["sts:GetServiceBearerToken"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "sts:AWSServiceName"
      values   = ["ecr-public.amazonaws.com"]
    }
  }

  # Create on first publish, only under the organization prefix, only with
  # Project=idp-platform and a team-* Team tag, and with no other tag keys.
  # CreateRepository and TagResource are the only ECR Public actions that
  # accept request tag conditions.
  statement {
    sid       = "CreateTaggedRepository"
    actions   = ["ecr-public:CreateRepository", "ecr-public:TagResource"]
    resources = [local.repository_arn]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = ["idp-platform"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/Team"
      values   = ["team-*"]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["Project", "Team"]
    }
  }

  statement {
    sid = "PushImages"
    actions = [
      "ecr-public:BatchCheckLayerAvailability",
      "ecr-public:InitiateLayerUpload",
      "ecr-public:UploadLayerPart",
      "ecr-public:CompleteLayerUpload",
      "ecr-public:PutImage",
      "ecr-public:DescribeRepositories",
      "ecr-public:DescribeImages",
    ]
    resources = [local.repository_arn]
  }
}

resource "aws_iam_policy" "publish" {
  name        = "idp-ci-publish"
  description = "Push-only ECR Public access under the ${var.github_org}/ prefix for idp-platform CI."
  policy      = data.aws_iam_policy_document.publish.json
}

resource "aws_iam_role_policy_attachment" "publish" {
  role       = aws_iam_role.publish.name
  policy_arn = aws_iam_policy.publish.arn
}
