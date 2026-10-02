variable "subscription_id" {
  description = "Azure subscription the platform lives in. Set in the gitignored terraform.tfvars, never committed."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a subscription GUID."
  }
}

variable "environment_name" {
  description = "Container Apps environment every WebService runs in. Fixed, so the Composition can name it."
  type        = string
  default     = "cae-idp-platform-us-east"
}

variable "infrastructure_resource_group_name" {
  description = "Name for the environment's managed infrastructure group (public IPs and load balancer). Fixed rather than Azure's ME_ default so the budget filter can list it (ADR-0004)."
  type        = string
  default     = "rg-idp-platform-us-east-apps-infra"
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
