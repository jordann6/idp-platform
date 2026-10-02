output "client_id" {
  description = "Managed identity client ID for the ClusterProviderConfig."
  value       = azurerm_user_assigned_identity.provider.client_id
}

output "tenant_id" {
  description = "Entra tenant ID for the ClusterProviderConfig."
  value       = azurerm_user_assigned_identity.provider.tenant_id
}

output "webservice_runtime_identity_id" {
  description = "Resource ID of the web service runtime identity, attached to every container app (ADR-0022)."
  value       = azurerm_user_assigned_identity.webservice_runtime.id
}

output "webservice_runtime_principal_id" {
  description = "Principal ID of the web service runtime identity, granted AcrPull by bootstrap/azure/apps."
  value       = azurerm_user_assigned_identity.webservice_runtime.principal_id
}

output "subscription_id" {
  description = "Subscription ID for the ClusterProviderConfig."
  value       = var.subscription_id
}
