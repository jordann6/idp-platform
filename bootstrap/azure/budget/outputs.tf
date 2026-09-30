output "budget_id" {
  description = "Azure budget resource ID."
  value       = azurerm_consumption_budget_subscription.idp_platform.id
}
