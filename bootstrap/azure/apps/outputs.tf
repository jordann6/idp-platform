output "environment_id" {
  description = "Container Apps environment ID, the containerAppEnvironmentId for every WebService. Embeds the subscription, so it goes to the bootstrap-only EnvironmentConfig, not the synced region map."
  value       = azurerm_container_app_environment.platform.id
}

output "environment_default_domain" {
  description = "Default domain of the environment; every app is served at <app>.<domain>."
  value       = azurerm_container_app_environment.platform.default_domain
}

output "cache_registry" {
  description = "Login server of the ECR Public cache; the Composition rewrites public.ecr.aws images to <registry>/ecr-public."
  value       = azurerm_container_registry.cache.login_server
}

output "runtime_identity_id" {
  description = "Runtime identity attached to every container app, used for the registry pull."
  value       = local.auth.webservice_runtime_identity_id
}
