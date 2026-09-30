data "aws_caller_identity" "current" {}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_response_headers_policy" "security" {
  name = "Managed-SecurityHeadersPolicy"
}

locals {
  bucket_name = "idp-platform-oidc-${data.aws_caller_identity.current.account_id}"

  discovery_docs = {
    ".well-known/openid-configuration" = "${path.module}/discovery/openid-configuration.json"
    "openid/v1/jwks"                   = "${path.module}/discovery/jwks.json"
  }
}

# Holds only the K3s service account issuer's public discovery document and
# JWKS. It is the trust root for every cloud federation in ADR-0001, so it is
# private, versioned, and readable only through CloudFront.
resource "aws_s3_bucket" "issuer" {
  #checkov:skip=CKV_AWS_18:Access logging needs a second bucket; the bucket holds only public keys and CloudTrail data events cover writes if needed.
  #checkov:skip=CKV_AWS_144:Cross-region replication is out of scope; objects are regenerated from the cluster.
  #checkov:skip=CKV_AWS_145:SSE-S3 is sufficient for public key material and avoids a KMS key policy for the CloudFront OAC.
  #checkov:skip=CKV2_AWS_62:No consumers need event notifications.
  #checkov:skip=CKV2_AWS_61:Only two Terraform-managed objects; noncurrent versions are negligible.
  bucket        = local.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "issuer" {
  bucket = aws_s3_bucket.issuer.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "issuer" {
  bucket = aws_s3_bucket.issuer.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "issuer" {
  bucket = aws_s3_bucket.issuer.id

  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-S3 is sufficient for public key material and avoids a KMS key policy for the CloudFront OAC.
#trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "issuer" {
  bucket = aws_s3_bucket.issuer.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudfront_origin_access_control" "issuer" {
  name                              = local.bucket_name
  description                       = "idp-platform K3s OIDC issuer"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# WAF adds a standing monthly charge to serve two static public documents.
#trivy:ignore:AWS-0011
resource "aws_cloudfront_distribution" "issuer" {
  #checkov:skip=CKV_AWS_68:WAF adds a standing monthly charge to serve two static public documents.
  #checkov:skip=CKV2_AWS_47:WAF adds a standing monthly charge to serve two static public documents.
  #checkov:skip=CKV_AWS_86:Legacy CloudFront logging requires S3 ACLs, which this project never enables.
  #checkov:skip=CKV_AWS_310:Origin failover is out of scope for a single-bucket issuer.
  #checkov:skip=CKV_AWS_374:Cloud STS endpoints fetch from many regions; geo restriction would break federation.
  #checkov:skip=CKV_AWS_174:The default CloudFront certificate does not allow pinning TLS 1.2; a custom domain is out of scope for Phase 0.
  #checkov:skip=CKV_AWS_305:No root document by design; only the two OIDC paths are served and the root returns 403.
  #checkov:skip=CKV2_AWS_42:Custom certificate out of scope; the cloudfront.net certificate is trusted by all three cloud STS services.
  enabled         = true
  comment         = "idp-platform K3s OIDC issuer"
  price_class     = "PriceClass_100"
  is_ipv6_enabled = true

  origin {
    origin_id                = "issuer-bucket"
    domain_name              = aws_s3_bucket.issuer.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.issuer.id
  }

  # Caching is disabled so a rotated JWKS is served immediately. Traffic is a
  # handful of STS fetches per hour, so origin cost is effectively zero.
  default_cache_behavior {
    target_origin_id           = "issuer-bucket"
    viewer_protocol_policy     = "https-only"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = data.aws_cloudfront_cache_policy.disabled.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id
    compress                   = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

data "aws_iam_policy_document" "issuer_bucket" {
  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.issuer.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.issuer.arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.issuer.arn, "${aws_s3_bucket.issuer.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "issuer" {
  bucket = aws_s3_bucket.issuer.id
  policy = data.aws_iam_policy_document.issuer_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.issuer]
}

resource "aws_s3_object" "discovery" {
  for_each = var.publish_discovery_docs ? local.discovery_docs : {}

  bucket       = aws_s3_bucket.issuer.id
  key          = each.key
  source       = each.value
  source_hash  = filemd5(each.value)
  content_type = "application/json"

  depends_on = [aws_s3_bucket_ownership_controls.issuer]
}
