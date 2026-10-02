variable "region" {
  description = "ECR Public's API lives only in us-east-1, and the boundary denies every other region."
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

variable "github_org" {
  description = "GitHub organization that holds scaffolded repositories (ADR-0024). Also the ECR Public repository prefix."
  type        = string
  default     = "idp-platform-apps"
}

variable "github_org_id" {
  description = "Numeric ID of github_org. GitHub's immutable OIDC subject carries it, so a released and reclaimed organization name cannot match the trust."
  type        = string
  default     = "337025991"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_org_id))
    error_message = "github_org_id must be the numeric organization ID."
  }
}

variable "publish_ref" {
  description = "The only git ref allowed to publish. Pull request runs build and scan but never assume the role."
  type        = string
  default     = "refs/heads/main"
}
