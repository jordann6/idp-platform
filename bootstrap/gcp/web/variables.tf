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

variable "region" {
  description = "Region for the image cache. Must match the Cloud Run region in the platform-regions map (ADR-0003)."
  type        = string
  default     = "us-east1"
}

variable "cache_repository_id" {
  description = "Artifact Registry remote repository that fronts ECR Public. The xwebservice-gcp Composition rewrites public.ecr.aws images to it."
  type        = string
  default     = "ecr-public"
}

variable "cache_retention" {
  description = "How long a cached image version is kept after it was last pulled. Short on purpose: demo services, deploy-demo-destroy."
  type        = string
  default     = "86400s"
}
