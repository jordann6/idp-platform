output "issuer_url" {
  description = "K3s service-account-issuer value. Every cloud trust in ADR-0001 references this exact string."
  value       = "https://${aws_cloudfront_distribution.issuer.domain_name}"
}

output "jwks_uri" {
  description = "K3s service-account-jwks-uri value."
  value       = "https://${aws_cloudfront_distribution.issuer.domain_name}/openid/v1/jwks"
}

output "distribution_id" {
  description = "CloudFront distribution ID."
  value       = aws_cloudfront_distribution.issuer.id
}

output "bucket_name" {
  description = "Issuer bucket name."
  value       = aws_s3_bucket.issuer.id
}
