output "role_arn" {
  description = "Publish role ARN. make ci-publish sets it as an organization Actions variable; it carries the account ID, so it never enters git."
  value       = aws_iam_role.publish.arn
}

output "subject" {
  description = "OIDC subject pattern the trust accepts."
  value       = local.subject
}

output "repository_prefix" {
  description = "ECR Public repository name prefix the role may push to."
  value       = "${var.github_org}/"
}
