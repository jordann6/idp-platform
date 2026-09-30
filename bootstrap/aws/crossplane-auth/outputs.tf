output "provider_role_arn" {
  description = "Role ARN for the ClusterProviderConfig webIdentity.roleARN."
  value       = aws_iam_role.provider.arn
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN for the K3s issuer."
  value       = aws_iam_openid_connect_provider.k3s.arn
}

output "verify_bucket_name" {
  description = "Name for the Phase 0 verification Bucket managed resource."
  value       = "${var.verify_bucket_prefix}${data.aws_caller_identity.current.account_id}"
}
