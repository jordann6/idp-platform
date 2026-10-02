variable "subscription_id" {
  description = "Azure subscription the platform network lives in. Set in the gitignored terraform.tfvars, never committed."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a subscription GUID."
  }
}

variable "location" {
  description = "Azure region for platform region us-east. eastus is restricted for Postgres Flexible Server on this subscription, so us-east maps to eastus2 (ADR-0003)."
  type        = string
  default     = "eastus2"
}

variable "storage_service_tag" {
  description = "Regional Storage service tag the delegated subnets may reach: WAL archival for Postgres, image layers for the ACR cache. Must match location."
  type        = string
  default     = "Storage.EastUS2"
}

variable "vnet_cidr" {
  description = "Platform VNet address space. Distinct from AWS 10.60.0.0/16 and GCP 10.70.0.0/16."
  type        = string
  default     = "10.80.0.0/16"
}

variable "postgres_subnet_cidr" {
  description = "Subnet delegated to Postgres Flexible Server. Cannot grow once a server exists, so it starts at /24."
  type        = string
  default     = "10.80.1.0/24"
}

variable "apps_subnet_cidr" {
  description = "Subnet delegated to the Container Apps environment (ADR-0022). /27 is the workload profiles minimum and cannot change once an environment uses it."
  type        = string
  default     = "10.80.2.0/27"
}

variable "acr_service_tag" {
  description = "Regional Azure Container Registry service tag the apps subnet may reach for the per-session image cache. Must match location."
  type        = string
  default     = "AzureContainerRegistry.EastUS2"
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
