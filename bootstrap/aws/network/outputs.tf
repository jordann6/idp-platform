output "vpc_id" {
  description = "Shared platform VPC ID."
  value       = aws_vpc.platform.id
}

output "vpc_cidr" {
  description = "Shared platform VPC CIDR, the source for platform-network ingress intent."
  value       = aws_vpc.platform.cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs, one per AZ."
  value       = aws_subnet.private[*].id
}

output "db_subnet_group_name" {
  description = "RDS subnet group for the xdatabase-aws Composition (EnvironmentConfig platform-regions)."
  value       = aws_db_subnet_group.platform.name
}

output "postgres_security_group_id" {
  description = "Shared Postgres security group for the xdatabase-aws Composition (EnvironmentConfig platform-regions)."
  value       = aws_security_group.postgres.id
}
