output "client_id" {
  description = "Managed identity client ID for the ClusterProviderConfig."
  value       = azurerm_user_assigned_identity.provider.client_id
}

output "tenant_id" {
  description = "Entra tenant ID for the ClusterProviderConfig."
  value       = azurerm_user_assigned_identity.provider.tenant_id
}

output "subscription_id" {
  description = "Subscription ID for the ClusterProviderConfig."
  value       = var.subscription_id
}
