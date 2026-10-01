variable "org_id" {
  description = "Organization the project is created under. Supplied from terraform.tfvars, never committed."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.org_id))
    error_message = "org_id must be the numeric organization ID."
  }
}

variable "billing_account" {
  description = "Billing account linked to the project. Supplied from terraform.tfvars, never committed."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}$", var.billing_account))
    error_message = "billing_account must look like XXXXXX-XXXXXX-XXXXXX."
  }
}

variable "project_prefix" {
  description = "Project ID prefix. A random suffix keeps the ID globally unique."
  type        = string
  default     = "idp-platform"
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

variable "services" {
  description = "APIs the platform needs in this project, and nothing else."
  type        = list(string)
  default = [
    "billingbudgets.googleapis.com",
    "cloudbilling.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "orgpolicy.googleapis.com",
    "servicenetworking.googleapis.com",
    "serviceusage.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
  ]
}
