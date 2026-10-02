data "azurerm_subscription" "current" {}

data "terraform_remote_state" "issuer" {
  backend = "s3"

  config = {
    bucket = "tf-backend-jord-projs"
    key    = "idp-platform/bootstrap/aws/oidc-issuer.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "tf-backend-jord-projs"
    key    = "idp-platform/bootstrap/azure/network.tfstate"
    region = "us-east-1"
  }
}

locals {
  network    = data.terraform_remote_state.network.outputs
  issuer_url = data.terraform_remote_state.issuer.outputs.issuer_url

  tags = {
    Project     = "idp-platform"
    Environment = "bootstrap"
    Owner       = var.owner
    ManagedBy   = "terraform"
    CostCenter  = var.cost_center
  }
}

resource "azurerm_resource_group" "identity" {
  name     = "rg-idp-platform-identity"
  location = var.location
  tags     = local.tags
}

# Azure side of ADR-0001. A user-assigned managed identity, not an app
# registration, so no client secret can ever be issued for it.
resource "azurerm_user_assigned_identity" "provider" {
  name                = "id-idp-crossplane-provider-azure"
  resource_group_name = azurerm_resource_group.identity.name
  location            = azurerm_resource_group.identity.location
  tags                = local.tags
}

# Exact subject match only (ADR-0011): one credential per provider service
# account, which is why every provider gets a fixed name.
resource "azurerm_federated_identity_credential" "provider" {
  for_each = toset(var.provider_service_accounts)

  name                      = "k3s-${each.value}"
  user_assigned_identity_id = azurerm_user_assigned_identity.provider.id
  issuer                    = local.issuer_url
  subject                   = "system:serviceaccount:${var.crossplane_namespace}:${each.value}"
  audience                  = ["api://AzureADTokenExchange"]
}

# Phase 0: resource group lifecycle only, for the verification ResourceGroup.
# Phase 3 adds what the Azure Compositions manage as its own reviewed diff.
resource "azurerm_role_definition" "phase0" {
  name        = "idp-crossplane-provider-azure-phase0"
  scope       = data.azurerm_subscription.current.id
  description = "Phase 0 verification permissions for the idp-platform Crossplane Azure provider."

  permissions {
    actions = [
      "Microsoft.Resources/subscriptions/read",
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      "Microsoft.Resources/subscriptions/resourceGroups/write",
      "Microsoft.Resources/subscriptions/resourceGroups/delete",
    ]
    not_actions = []
  }

  assignable_scopes = [data.azurerm_subscription.current.id]
}

resource "azurerm_role_assignment" "phase0" {
  scope              = data.azurerm_subscription.current.id
  role_definition_id = azurerm_role_definition.phase0.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.provider.principal_id
  principal_type     = "ServicePrincipal"
}

# Phase 3: exactly what xdatabase-azure needs, as two roles so no single grant
# spans both groups (ADR-0021). Azure RBAC cannot condition a create on a name
# prefix or a request tag the way the AWS role does (ADR-0014), so the
# resource group is the boundary: the identity can manage Flexible Servers
# only inside the data group, and has no network write anywhere.
resource "azurerm_role_definition" "postgres" {
  name        = "idp-crossplane-provider-azure-postgres"
  scope       = local.network.data_resource_group_id
  description = "Postgres Flexible Server lifecycle for the idp-platform Crossplane Azure provider, data resource group only."

  permissions {
    actions = [
      "Microsoft.DBforPostgreSQL/flexibleServers/read",
      "Microsoft.DBforPostgreSQL/flexibleServers/write",
      "Microsoft.DBforPostgreSQL/flexibleServers/delete",
      "Microsoft.DBforPostgreSQL/flexibleServers/databases/read",
      "Microsoft.DBforPostgreSQL/flexibleServers/databases/write",
      "Microsoft.DBforPostgreSQL/flexibleServers/databases/delete",
    ]
    not_actions = []
  }

  assignable_scopes = [local.network.data_resource_group_id]
}

resource "azurerm_role_assignment" "postgres" {
  scope              = local.network.data_resource_group_id
  role_definition_id = azurerm_role_definition.postgres.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.provider.principal_id
  principal_type     = "ServicePrincipal"
}

# Creating a server with private access is a linked authorization: ARM also
# checks join on the delegated subnet and on the private DNS zone. Read and
# join only, assigned on those two resources, not on their resource group.
resource "azurerm_role_definition" "network_join" {
  name        = "idp-crossplane-provider-azure-network-join"
  scope       = local.network.network_resource_group_id
  description = "Join the shared Postgres subnet and private DNS zone for the idp-platform Crossplane Azure provider."

  permissions {
    actions = [
      "Microsoft.Network/virtualNetworks/subnets/read",
      "Microsoft.Network/virtualNetworks/subnets/join/action",
      "Microsoft.Network/privateDnsZones/read",
      "Microsoft.Network/privateDnsZones/join/action",
    ]
    not_actions = []
  }

  # Custom roles accept only management group, subscription, or resource
  # group assignable scopes, so the role is defined on the network group and
  # assigned below on the two resources alone.
  assignable_scopes = [local.network.network_resource_group_id]
}

resource "azurerm_role_assignment" "network_join" {
  for_each = {
    subnet   = local.network.postgres_subnet_id
    dns_zone = local.network.private_dns_zone_id
  }

  scope              = each.value
  role_definition_id = azurerm_role_definition.network_join.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.provider.principal_id
  principal_type     = "ServicePrincipal"
}

# Phase 4 (ADR-0022): what xwebservice-azure needs, on the apps group only.
# Container app lifecycle, plus read and join on the shared environment,
# which is a linked authorization when an app is created in it. No
# environment write: the environment is Terraform's (bootstrap/azure/apps).
# listSecrets is read by the provider on every observe of a container app.
resource "azurerm_role_definition" "containerapps" {
  name        = "idp-crossplane-provider-azure-containerapps"
  scope       = local.network.apps_resource_group_id
  description = "Container Apps lifecycle for the idp-platform Crossplane Azure provider, apps resource group only."

  permissions {
    actions = [
      "Microsoft.App/containerApps/read",
      "Microsoft.App/containerApps/write",
      "Microsoft.App/containerApps/delete",
      "Microsoft.App/containerApps/listSecrets/action",
      "Microsoft.App/containerApps/revisions/read",
      "Microsoft.App/managedEnvironments/read",
      "Microsoft.App/managedEnvironments/join/action",
    ]
    not_actions = []
  }

  assignable_scopes = [local.network.apps_resource_group_id]
}

resource "azurerm_role_assignment" "containerapps" {
  scope              = local.network.apps_resource_group_id
  role_definition_id = azurerm_role_definition.containerapps.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.provider.principal_id
  principal_type     = "ServicePrincipal"
}

# The identity every WebService runs as and pulls its image with. It holds no
# role here; bootstrap/azure/apps grants it AcrPull on the per-session cache
# and nothing else, so a web service can reach no Azure API. The GCP
# counterpart is idp-webservice-runtime in bootstrap/gcp/web.
resource "azurerm_user_assigned_identity" "webservice_runtime" {
  name                = "id-idp-webservice-runtime"
  resource_group_name = azurerm_resource_group.identity.name
  location            = local.network.location
  tags                = local.tags
}

# Attaching a user-assigned identity to a container app is authorized as
# assign on that identity, the Azure counterpart of iam:PassRole on AWS and
# actAs on GCP. Granted on the runtime identity alone, not on its group, so
# the provider cannot attach its own identity or any other to a workload.
resource "azurerm_role_definition" "assign_runtime_identity" {
  name        = "idp-crossplane-provider-azure-assign-runtime"
  scope       = azurerm_resource_group.identity.id
  description = "Attach the web service runtime identity to container apps, for the idp-platform Crossplane Azure provider."

  permissions {
    actions = [
      "Microsoft.ManagedIdentity/userAssignedIdentities/read",
      "Microsoft.ManagedIdentity/userAssignedIdentities/assign/action",
    ]
    not_actions = []
  }

  assignable_scopes = [azurerm_resource_group.identity.id]
}

resource "azurerm_role_assignment" "assign_runtime_identity" {
  scope              = azurerm_user_assigned_identity.webservice_runtime.id
  role_definition_id = azurerm_role_definition.assign_runtime_identity.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.provider.principal_id
  principal_type     = "ServicePrincipal"
}
