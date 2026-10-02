variable "subscription_id" {
  description = "Azure subscription the provider identity is scoped to. Set in the gitignored terraform.tfvars, never committed."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a subscription GUID."
  }
}

variable "location" {
  description = "Azure region for the identity resource group (platform region us-east, ADR-0003)."
  type        = string
  default     = "eastus"
}

variable "owner" {
  description = "Owner tag value."
  type        = string
  default     = "jordan"
}

variable "cost_center" {
  description = "CostCenter tag value, format cc-NNNN."
  type        = string
  default     = "cc-1001"

  validation {
    condition     = can(regex("^cc-[0-9]{4}$", var.cost_center))
    error_message = "cost_center must match cc-NNNN."
  }
}

variable "crossplane_namespace" {
  description = "Namespace the Crossplane providers run in."
  type        = string
  default     = "crossplane-system"
}

variable "provider_service_accounts" {
  description = "Fixed provider service account names set by DeploymentRuntimeConfig (ADR-0011). Azure matches subjects exactly, one federated credential each, 20 maximum."
  type        = list(string)
  default     = ["provider-family-azure", "provider-azure-dbforpostgresql", "provider-azure-containerapp"]

  validation {
    condition     = length(var.provider_service_accounts) <= 20
    error_message = "A user-assigned managed identity supports at most 20 federated credentials."
  }
}
