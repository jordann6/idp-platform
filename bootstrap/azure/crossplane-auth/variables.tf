variable "subscription_id" {
  description = "Azure subscription the provider identity is scoped to."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
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
  default     = ["provider-family-azure"]

  validation {
    condition     = length(var.provider_service_accounts) <= 20
    error_message = "A user-assigned managed identity supports at most 20 federated credentials."
  }
}
