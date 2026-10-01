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

variable "platform_region" {
  description = "Platform region this network serves (ADR-0003)."
  type        = string
  default     = "us-east"
}

variable "region" {
  description = "GCP region the platform region maps to."
  type        = string
  default     = "us-east1"
}

variable "subnet_cidr" {
  description = "Primary range of the platform subnet. Distinct from the AWS VPC (10.60.0.0/16) so the clouds never overlap."
  type        = string
  default     = "10.70.0.0/20"
}

variable "psa_address" {
  description = "Base address of the Private Service Access range Google allocates Cloud SQL from."
  type        = string
  default     = "10.71.0.0"
}

variable "psa_prefix_length" {
  description = "Prefix length of the Private Service Access range. /20 is enough for many small instances."
  type        = number
  default     = 20
}
