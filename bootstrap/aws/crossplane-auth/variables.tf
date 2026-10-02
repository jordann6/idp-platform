variable "region" {
  description = "The only region the provider role may act in."
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

variable "crossplane_namespace" {
  description = "Namespace the Crossplane providers run in."
  type        = string
  default     = "crossplane-system"
}

variable "provider_service_accounts" {
  description = "Fixed provider service account names set by DeploymentRuntimeConfig (ADR-0011). Each phase adds the sub-providers it installs."
  type        = list(string)
  default     = ["provider-aws-s3", "provider-aws-rds", "provider-aws-ecs", "provider-aws-elbv2"]
}

variable "web_cluster_name" {
  description = "Shared ECS cluster from bootstrap/aws/ingress. The Phase 4 policy scopes ECS services to it."
  type        = string
  default     = "idp-platform-us-east"
}

variable "web_alb_name_prefix" {
  description = "Name prefix of the web ALBs from bootstrap/aws/ingress (public and internal). Listener rules are scoped to these load balancers."
  type        = string
  default     = "idp-platform-us-east-web"
}

variable "web_execution_role_name" {
  description = "Shared ECS task execution role from bootstrap/aws/ingress, the only role the provider may pass. Named, not read from state, because the ingress module is destroyed between sessions."
  type        = string
  default     = "idp-platform-us-east-webservice-execution"
}

variable "web_name_prefix" {
  description = "Name prefix the xwebservice-aws Composition uses for ECS services, task definition families, and target groups."
  type        = string
  default     = "idp-"
}

variable "verify_bucket_prefix" {
  description = "Name prefix for the Phase 0 verification bucket. The Phase 0 policy grants S3 access to this prefix only."
  type        = string
  default     = "idp-platform-verify-"
}

variable "db_identifier_prefix" {
  description = "RDS instance identifier prefix the xdatabase-aws Composition uses for external names. The Phase 1 policy grants RDS access to this prefix only."
  type        = string
  default     = "idp-"
}

variable "db_subnet_group_name" {
  description = "Shared RDS subnet group from bootstrap/aws/network."
  type        = string
  default     = "idp-platform-us-east"
}

variable "postgres_major_version" {
  description = "Postgres major version the paved road offers. Selects the default parameter and option groups CreateDBInstance authorizes against."
  type        = string
  default     = "17"
}
