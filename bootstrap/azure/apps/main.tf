# ADR-0022 for Azure. The shared Container Apps environment and the image
# cache bill hourly (the environment's managed public IPs and load balancer,
# and the registry), so this module is created for a demo session and
# destroyed with it, like bootstrap/aws/ingress. Everything it attaches to
# (the apps group, the delegated subnet, the runtime identity, the Crossplane
# role) is standing and free, in bootstrap/azure/network and crossplane-auth.

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "tf-backend-jord-projs"
    key    = "idp-platform/bootstrap/azure/network.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "auth" {
  backend = "s3"

  config = {
    bucket = "tf-backend-jord-projs"
    key    = "idp-platform/bootstrap/azure/crossplane-auth.tfstate"
    region = "us-east-1"
  }
}

locals {
  network = data.terraform_remote_state.network.outputs
  auth    = data.terraform_remote_state.auth.outputs

  # Registry names are global, 5 to 50 lowercase alphanumerics. A hash of the
  # subscription keeps the name deterministic and unique without putting the
  # subscription ID in it.
  registry_name = "acridp${substr(sha256(var.subscription_id), 0, 10)}"

  tags = {
    Project     = "idp-platform"
    Environment = "bootstrap"
    Owner       = var.owner
    ManagedBy   = "terraform"
    CostCenter  = var.cost_center
  }
}

# The image cache, the counterpart of the ECR pull-through cache on AWS and
# the Artifact Registry remote repository on GCP. ECR Public is a supported
# upstream for unauthenticated pulls on every tier, so Basic is enough. With
# it, the apps subnet reaches only Microsoft service tags and never the
# internet (bootstrap/azure/network).
resource "azurerm_container_registry" "cache" {
  #checkov:skip=CKV_AZURE_139:Private endpoints need Premium (about $1.67 a day); Basic has no network rules, and pulls are authenticated by the runtime identity, admin user off, anonymous pull off. It caches public ECR Public images only.
  #checkov:skip=CKV_AZURE_163:Defender for Containers vulnerability scanning is a subscription plan with a standing charge; the cached images are public and pinned by digest at admission (Phase 5 adds a registry allowlist).
  #checkov:skip=CKV_AZURE_164:Content trust needs Premium; integrity comes from the digest pin the WebService XRD enforces.
  #checkov:skip=CKV_AZURE_165:Geo-replication needs Premium and is out of scope (CLAUDE.md, no multi-region).
  #checkov:skip=CKV_AZURE_166:Quarantine needs Premium; the cache holds only digest-pinned public images.
  #checkov:skip=CKV_AZURE_167:Retention of untagged manifests needs Premium; the registry is destroyed at the end of every session, which deletes everything in it.
  #checkov:skip=CKV_AZURE_233:Zone redundancy needs Premium and is out of scope for a per-session demo cache.
  #checkov:skip=CKV_AZURE_237:Dedicated data endpoints need Premium; the NSG allows only the regional ACR and Storage service tags instead.
  name                          = local.registry_name
  resource_group_name           = local.network.apps_resource_group_name
  location                      = local.network.location
  sku                           = "Basic"
  admin_enabled                 = false
  anonymous_pull_enabled        = false
  public_network_access_enabled = true
  tags                          = local.tags
}

# One rule for the whole upstream: public.ecr.aws/<path> is served as
# <registry>/ecr-public/<path>, the same rewrite the AWS cache uses.
resource "azurerm_container_registry_cache_rule" "ecr_public" {
  name                  = "ecr-public"
  container_registry_id = azurerm_container_registry.cache.id
  source_repo           = "public.ecr.aws/*"
  target_repo           = "ecr-public/*"
}

# The runtime identity pulls images and does nothing else.
resource "azurerm_role_assignment" "runtime_acr_pull" {
  scope                = azurerm_container_registry.cache.id
  role_definition_name = "AcrPull"
  principal_id         = local.auth.webservice_runtime_principal_id
  principal_type       = "ServicePrincipal"
}

# One shared environment per platform region, never one per claim (ADR-0008),
# injected into the delegated apps subnet. External, because whether apps can
# be reached from the internet is a property of the environment, not the app:
# a public WebService is an external app on it, and an internal WebService is
# an app with external ingress off, which only other apps in the environment
# can reach (a recorded leak, ADR-0022). Consumption workload profile only:
# no dedicated profile, so no plan management charge, and apps scale to zero.
# No log destination, so no Log Analytics workspace bills between sessions.
# Not zone redundant: that needs a larger subnet and is out of scope for a
# per-session demo environment (CLAUDE.md).
resource "azurerm_container_app_environment" "platform" {
  name                               = var.environment_name
  resource_group_name                = local.network.apps_resource_group_name
  location                           = local.network.location
  infrastructure_subnet_id           = local.network.apps_subnet_id
  infrastructure_resource_group_name = var.infrastructure_resource_group_name
  internal_load_balancer_enabled     = false
  zone_redundancy_enabled            = false
  tags                               = local.tags

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}
