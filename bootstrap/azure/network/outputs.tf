output "location" {
  description = "Azure region for platform region us-east."
  value       = var.location
}

output "data_resource_group_name" {
  description = "Resource group the xdatabase-azure Composition creates servers in."
  value       = azurerm_resource_group.data.name
}

output "data_resource_group_id" {
  description = "Data resource group ID, the scope of the Crossplane Postgres role."
  value       = azurerm_resource_group.data.id
}

output "network_resource_group_name" {
  description = "Resource group holding the shared network."
  value       = azurerm_resource_group.network.name
}

output "network_resource_group_id" {
  description = "Network resource group ID, the assignable scope of the Crossplane network join role."
  value       = azurerm_resource_group.network.id
}

output "postgres_subnet_name" {
  description = "Delegated subnet name."
  value       = azurerm_subnet.postgres.name
}

output "postgres_subnet_id" {
  description = "Delegated subnet ID, the delegatedSubnetId value for Flexible Server."
  value       = azurerm_subnet.postgres.id
}

output "vnet_name" {
  description = "Platform VNet name."
  value       = azurerm_virtual_network.platform.name
}

output "private_dns_zone_name" {
  description = "Private DNS zone name."
  value       = azurerm_private_dns_zone.postgres.name
}

output "private_dns_zone_id" {
  description = "Private DNS zone ID, the privateDnsZoneId value for Flexible Server."
  value       = azurerm_private_dns_zone.postgres.id
}
