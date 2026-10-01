variable "owner" {
  description = "owner label value."
  type        = string
  default     = "jordan"
}

variable "cost_center" {
  description = "cost_center label value, format cc-NNNN."
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
  description = "Fixed provider service account names set by DeploymentRuntimeConfig (ADR-0011). Only the sub-providers that call GCP APIs are listed; the family provider makes no cloud calls."
  type        = list(string)
  default     = ["provider-gcp-storage", "provider-gcp-sql"]
}

variable "token_audience" {
  description = "Audience of the projected K3s token. Fixed, so the DeploymentRuntimeConfig in git carries no project number."
  type        = string
  default     = "idp-platform-gcp-wif"
}

variable "token_path" {
  description = "Path of the projected token inside the provider pod."
  type        = string
  default     = "/var/run/secrets/idp-platform/gcp/token"
}

variable "verify_bucket_prefix" {
  description = "Prefix of the Phase 0 verification bucket; the storage grant is conditioned on it."
  type        = string
  default     = "idp-verify-"
}
