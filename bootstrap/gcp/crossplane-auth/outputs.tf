output "project_id" {
  description = "Platform project ID for the ClusterProviderConfig."
  value       = local.project_id
}

output "service_account_email" {
  description = "Provider service account the federated principals impersonate."
  value       = google_service_account.provider.email
}

output "workload_identity_provider" {
  description = "Full resource name of the pool provider."
  value       = google_iam_workload_identity_pool_provider.k3s.name
}

output "verify_bucket_name" {
  description = "Name for the Phase 0 verification Bucket managed resource."
  value       = "${var.verify_bucket_prefix}${local.project_id}"
}

# The external_account credential config the provider pods read through
# GOOGLE_APPLICATION_CREDENTIALS. It holds no key material: only the token file
# path, the STS audience, and which service account to impersonate.
output "credential_config" {
  description = "external_account ADC JSON, loaded into a ConfigMap by make gcp-provider."
  value = jsonencode({
    type                              = "external_account"
    audience                          = "//iam.googleapis.com/${google_iam_workload_identity_pool_provider.k3s.name}"
    subject_token_type                = "urn:ietf:params:oauth:token-type:jwt"
    token_url                         = "https://sts.googleapis.com/v1/token"
    service_account_impersonation_url = "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${google_service_account.provider.email}:generateAccessToken"
    credential_source = {
      file = var.token_path
      format = {
        type = "text"
      }
    }
  })
}
