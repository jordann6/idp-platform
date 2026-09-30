variable "region" {
  description = "The only region the provider role may act in."
  type        = string
  default     = "us-east-1"
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
  description = "Fixed provider service account names set by DeploymentRuntimeConfig (ADR-0011). Each phase adds the sub-providers it installs."
  type        = list(string)
  default     = ["provider-aws-s3"]
}

variable "verify_bucket_prefix" {
  description = "Name prefix for the Phase 0 verification bucket. The Phase 0 policy grants S3 access to this prefix only."
  type        = string
  default     = "idp-platform-verify-"
}
