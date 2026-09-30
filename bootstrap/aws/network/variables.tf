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
  description = "Platform region this network serves (ADR-0003). Used in resource names so the EnvironmentConfig can map to them."
  type        = string
  default     = "us-east"
}

variable "vpc_cidr" {
  description = "CIDR for the shared platform VPC."
  type        = string
  default     = "10.60.0.0/16"
}

variable "azs" {
  description = "Availability zones for the private subnets. RDS subnet groups need at least two."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.azs) >= 2
    error_message = "At least two availability zones are required for an RDS subnet group."
  }
}

variable "flow_log_retention_days" {
  description = "Retention for VPC flow logs. Short on purpose: demo network, deploy-demo-destroy."
  type        = number
  default     = 7
}
