variable "region" {
  description = "AWS region for the provider."
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

variable "monthly_limit_usd" {
  description = "Monthly budget for resources tagged Project=idp-platform (ADR-0004 backstop)."
  type        = number
  default     = 10
}

variable "alert_email" {
  description = "Address that receives budget alerts."
  type        = string
  default     = "jordandn6@outlook.com"
}
