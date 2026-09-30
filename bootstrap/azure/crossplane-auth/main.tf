data "azurerm_subscription" "current" {}

data "terraform_remote_state" "issuer" {
  backend = "s3"

  config = {
    bucket = "tf-backend-jord-projs"
    key    = "idp-platform/bootstrap/aws/oidc-issuer.tfstate"
    region = "us-east-1"
  }
}

locals {
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

  name      = "k3s-${each.value}"
  parent_id = azurerm_user_assigned_identity.provider.id
  issuer    = local.issuer_url
  subject   = "system:serviceaccount:${var.crossplane_namespace}:${each.value}"
  audience  = ["api://AzureADTokenExchange"]
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
