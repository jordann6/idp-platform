output "cluster_name" {
  description = "Shared ECS cluster for the xwebservice-aws Composition (EnvironmentConfig platform-regions)."
  value       = aws_ecs_cluster.web.name
}

output "tasks_security_group_id" {
  description = "Shared web service task security group (EnvironmentConfig platform-regions)."
  value       = aws_security_group.tasks.id
}

output "log_group_name" {
  description = "Web service container log group (EnvironmentConfig platform-regions)."
  value       = aws_cloudwatch_log_group.web.name
}

output "apps_domain" {
  description = "Domain public services are served under, as <name>.<team>.<apps_domain>."
  value       = local.apps_domain
}

output "internal_domain" {
  description = "Domain internal services are served under. Resolves only when the internal ALB is enabled."
  value       = local.internal_domain
}

# The outputs below embed the account ID, so make aws-ingress applies them as
# the bootstrap-only platform-aws-ingress EnvironmentConfig, never git.
output "public_listener_arn" {
  description = "HTTPS listener on the public ALB."
  value       = aws_lb_listener.public_https.arn
}

output "internal_listener_arn" {
  description = "HTTPS listener on the internal ALB, empty when it is disabled."
  value       = var.internal_alb_enabled ? aws_lb_listener.internal_https[0].arn : ""
}

output "execution_role_arn" {
  description = "Shared ECS task execution role the provider may pass."
  value       = aws_iam_role.execution.arn
}

output "ecr_cache_registry" {
  description = "Registry and prefix the Composition rewrites ECR Public image references to."
  value       = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com/${local.ecr_upstream}"
}
