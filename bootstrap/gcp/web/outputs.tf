output "cache_repository_id" {
  description = "Artifact Registry remote repository for ECR Public images (EnvironmentConfig platform-regions)."
  value       = google_artifact_registry_repository.ecr_public.repository_id
}

output "runtime_service_account_id" {
  description = "Account ID of the web service runtime identity (EnvironmentConfig platform-regions); the Composition adds the project domain."
  value       = google_service_account.runtime.account_id
}
