variable "region" {
  description = "AWS region for the issuer bucket."
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

variable "publish_discovery_docs" {
  description = "Upload the K3s OIDC discovery document and JWKS from ./discovery. Set false only when standing up a fresh issuer before K3s exists; regenerate the files with make discovery-docs after any signing key rotation."
  type        = bool
  default     = true
}
