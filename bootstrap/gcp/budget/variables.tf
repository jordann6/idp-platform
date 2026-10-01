variable "billing_account" {
  description = "Billing account the budget lives on. Supplied from terraform.tfvars, never committed."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}$", var.billing_account))
    error_message = "billing_account must look like XXXXXX-XXXXXX-XXXXXX."
  }
}

variable "monthly_limit_usd" {
  description = "Monthly budget for the platform project (ADR-0004 backstop)."
  type        = number
  default     = 10
}

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
