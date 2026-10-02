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

variable "platform_region" {
  description = "Platform region this ingress serves (ADR-0003). Must match the network module."
  type        = string
  default     = "us-east"
}

variable "public_subnet_netnums" {
  description = "cidrsubnet netnums for the ALB-only public /20s, one per AZ of the network module. Kept clear of the private /20s at 0 and 1."
  type        = list(number)
  default     = [8, 9]
}

variable "parent_zone" {
  description = "Existing public Route 53 zone the apps domain lives under. Only the validation and wildcard records are written to it."
  type        = string
  default     = "jordandesigns.io"
}

variable "apps_subdomain" {
  description = "Label under parent_zone for web services. A service is <name>.<team>.<apps_subdomain>.<parent_zone>."
  type        = string
  default     = "apps"
}

variable "teams" {
  description = "Team namespaces that get a wildcard certificate name and DNS record. Onboarding a team on AWS is a diff here (ADR-0022)."
  type        = list(string)
  default     = ["team-demo", "team-data", "team-ops"]

  validation {
    condition     = length(var.teams) > 0 && length(var.teams) <= 9 && alltrue([for t in var.teams : can(regex("^team-[a-z0-9-]+$", t))])
    error_message = "teams must be 1 to 9 team-* namespaces (one certificate holds at most 10 names)."
  }
}

variable "internal_alb_enabled" {
  description = "Create the internal ALB for visibility internal. Off by default: a second ALB is another hourly charge."
  type        = bool
  default     = false
}

variable "endpoint_az_count" {
  description = "How many AZs get the ECR and logs interface endpoints. One keeps the hourly charge down for demos; tasks in the other AZ reach them across AZs."
  type        = number
  default     = 1
}

variable "log_retention_days" {
  description = "Retention for web service container logs. Short on purpose: deploy-demo-destroy."
  type        = number
  default     = 7
}
