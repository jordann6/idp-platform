locals {
  name = "idp-platform-us-east"

  tags = {
    Project     = "idp-platform"
    Environment = "bootstrap"
    Owner       = var.owner
    ManagedBy   = "terraform"
    CostCenter  = var.cost_center
  }
}

# Azure puts every resource in a resource group, which AWS and GCP do not. The
# network is Terraform's alone; the data group is the only place the Crossplane
# identity may create databases, so its role is scoped to that group (ADR-0021).
resource "azurerm_resource_group" "network" {
  name     = "rg-${local.name}-network"
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "data" {
  name     = "rg-${local.name}-data"
  location = var.location
  tags     = local.tags
}

# ADR-0008: one shared private network per cloud. No public IP, no NAT gateway,
# no gateway subnet.
resource "azurerm_virtual_network" "platform" {
  name                = "vnet-${local.name}"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  address_space       = [var.vnet_cidr]
  tags                = local.tags
}

# Flexible Server with private access is injected into a subnet delegated to
# it. Several servers can share the subnet; nothing else can live in it. The
# service adds a Microsoft.Storage service endpoint when the first server is
# created (WAL archival), so it is declared here, or the next apply would
# remove it and break the server. Default outbound access is off: the subnet
# has no implicit internet path, the Azure stand-in for no internet gateway.
resource "azurerm_subnet" "postgres" {
  name                            = "snet-postgres"
  resource_group_name             = azurerm_resource_group.network.name
  virtual_network_name            = azurerm_virtual_network.platform.name
  address_prefixes                = [var.postgres_subnet_cidr]
  service_endpoints               = ["Microsoft.Storage"]
  default_outbound_access_enabled = false

  delegation {
    name = "postgres-flexible"

    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Default deny (CC6.6). Azure's built-in NSG rules (AllowVnetInBound,
# AllowInternetOutBound) cannot be deleted, so explicit deny-all rules at
# priority 4096 override them. What stays open is what the service documents
# as required: tcp/5432 inside the platform network, and tcp/443 to regional
# Storage for WAL archival.
resource "azurerm_network_security_group" "postgres" {
  name                = "nsg-${local.name}-postgres"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  tags                = local.tags

  security_rule {
    name                       = "allow-postgres-from-vnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = var.vnet_cidr
    destination_address_prefix = var.postgres_subnet_cidr
  }

  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-postgres-within-subnet"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = var.postgres_subnet_cidr
    destination_address_prefix = var.postgres_subnet_cidr
  }

  security_rule {
    name                       = "allow-storage-wal-archival"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = var.postgres_subnet_cidr
    destination_address_prefix = var.storage_service_tag
  }

  security_rule {
    name                       = "deny-all-outbound"
    priority                   = 4096
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "postgres" {
  subnet_id                 = azurerm_subnet.postgres.id
  network_security_group_id = azurerm_network_security_group.postgres.id
}

# Flexible Server with private access requires a private DNS zone ending in
# postgres.database.azure.com; the service writes each server's A record here.
resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.network.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "link-${local.name}"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.platform.id
  registration_enabled  = false
  tags                  = local.tags
}
