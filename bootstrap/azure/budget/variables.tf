variable "subscription_id" {
  description = "Azure subscription the budget watches. Set in the gitignored terraform.tfvars, never committed."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a subscription GUID."
  }
}

variable "monthly_limit_usd" {
  description = "Monthly budget for everything in the platform resource groups (ADR-0004 backstop)."
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

variable "resource_group_names" {
  description = "Every resource group the platform owns: identity, shared network, the data group Crossplane creates servers in, the apps group for web services, the Container Apps environment's managed infrastructure group (public IPs and load balancer, named by bootstrap/azure/apps so it can be listed here), and the Phase 0 verification group."
  type        = list(string)
  default = [
    "rg-idp-platform-identity",
    "rg-idp-platform-us-east-network",
    "rg-idp-platform-us-east-data",
    "rg-idp-platform-us-east-apps",
    "rg-idp-platform-us-east-apps-infra",
    "rg-idp-platform-verify",
  ]
}
