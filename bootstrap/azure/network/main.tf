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

# Phase 4 (ADR-0022): the per-session Container Apps environment and every
# WebService live here, so the Crossplane identity's Container Apps role is
# scoped to this group alone, as the Postgres role is to the data group.
resource "azurerm_resource_group" "apps" {
  name     = "rg-${local.name}-apps"
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

# Phase 4 (ADR-0022): the subnet a workload profiles Container Apps
# environment is injected into. /27 is the documented minimum, and the
# environment's own infrastructure reserves 14 of its addresses. It stands
# between sessions at no cost; the environment that uses it is per session
# (bootstrap/azure/apps). Default outbound access is off, as on the Postgres
# subnet: the environment brings its own egress through its managed load
# balancer, and the NSG below decides where that egress may go.
resource "azurerm_subnet" "apps" {
  name                            = "snet-apps"
  resource_group_name             = azurerm_resource_group.network.name
  virtual_network_name            = azurerm_virtual_network.platform.name
  address_prefixes                = [var.apps_subnet_cidr]
  default_outbound_access_enabled = false

  delegation {
    name = "container-apps"

    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Default deny (CC6.6), opening only what the Container Apps documentation
# lists as required for a workload profiles environment. Outbound goes to
# Microsoft service tags only, never to Internet: images come from the
# per-session ACR cache of ECR Public, so the ACR and regional Storage tags
# replace an internet route, the same posture as the AWS pull-through cache
# and the GCP remote repository. Public ingress to an external environment
# arrives on its managed public IP, not through this subnet, so the inbound
# deny does not block it. Azure DNS (168.63.129.16) is not subject to NSGs.
resource "azurerm_network_security_group" "apps" {
  name                = "nsg-${local.name}-apps"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  tags                = local.tags

  security_rule {
    name                       = "allow-lb-probes"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "30000-32767"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = var.apps_subnet_cidr
  }

  security_rule {
    name                       = "allow-within-subnet-inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.apps_subnet_cidr
    destination_address_prefix = var.apps_subnet_cidr
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
    name                       = "allow-within-subnet-outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.apps_subnet_cidr
    destination_address_prefix = var.apps_subnet_cidr
  }

  security_rule {
    name                       = "allow-microsoft-container-registry"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = var.apps_subnet_cidr
    destination_address_prefix = "MicrosoftContainerRegistry"
  }

  security_rule {
    name                       = "allow-frontdoor-first-party"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = var.apps_subnet_cidr
    destination_address_prefix = "AzureFrontDoor.FirstParty"
  }

  security_rule {
    name                       = "allow-entra-id"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = var.apps_subnet_cidr
    destination_address_prefix = "AzureActiveDirectory"
  }

  security_rule {
    name                       = "allow-acr-cache"
    priority                   = 140
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = var.apps_subnet_cidr
    destination_address_prefix = var.acr_service_tag
  }

  security_rule {
    name                       = "allow-acr-storage"
    priority                   = 150
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = var.apps_subnet_cidr
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

resource "azurerm_subnet_network_security_group_association" "apps" {
  subnet_id                 = azurerm_subnet.apps.id
  network_security_group_id = azurerm_network_security_group.apps.id
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
