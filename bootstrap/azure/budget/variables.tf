variable "subscription_id" {
  description = "Azure subscription the budget watches. Set in the gitignored terraform.tfvars, never committed."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a subscription GUID."
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

variable "start_date" {
  description = "First day of the first budget month, RFC 3339."
  type        = string
  default     = "2026-09-01T00:00:00Z"
}
