locals {
  name = "idp-platform-${var.platform_region}"
}

# ADR-0008: one shared, private-by-default network per cloud. No internet
# gateway, no NAT, no public subnet. Claims attach to it through the
# EnvironmentConfig and never see a network primitive.
resource "aws_vpc" "platform" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = local.name
  }
}

resource "aws_subnet" "private" {
  count = length(var.azs)

  vpc_id                  = aws_vpc.platform.id
  availability_zone       = var.azs[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name}-private-${var.azs[count.index]}"
    Tier = "private"
  }
}

# Only the local route plus the S3 gateway endpoint. No 0.0.0.0/0 route exists.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.platform.id

  tags = {
    Name = "${local.name}-private"
  }
}

resource "aws_route_table_association" "private" {
  count = length(var.azs)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Private path to S3 without NAT. Gateway endpoints carry no hourly charge.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.platform.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${local.name}-s3"
  }
}

# Adopt the default security group and strip every rule, so anything launched
# without an explicit group can neither receive nor send traffic.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.platform.id

  tags = {
    Name = "${local.name}-default-deny"
  }
}

# Shared implementation of the "reachable only from the platform network"
# intent for Postgres. Every per-claim group would carry this identical rule,
# so per-claim groups add no isolation and would put provider-aws-ec2 and ec2
# write permissions on the control plane. Trade-off recorded in DECISIONS.md.
resource "aws_security_group" "postgres" {
  #checkov:skip=CKV2_AWS_5:Attached to RDS instances by the xdatabase-aws Composition, not by Terraform.
  name        = "${local.name}-postgres"
  description = "Postgres from the platform VPC only. No egress."
  vpc_id      = aws_vpc.platform.id

  tags = {
    Name = "${local.name}-postgres"
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_vpc" {
  security_group_id = aws_security_group.postgres.id
  description       = "Postgres from the platform VPC CIDR"
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = aws_vpc.platform.cidr_block
}

resource "aws_db_subnet_group" "platform" {
  name        = local.name
  description = "Private subnets for idp-platform databases in ${var.platform_region}."
  subnet_ids  = aws_subnet.private[*].id
}

# Flow logs give network evidence for the deny-public-database control
# (CC6.6). CloudWatch rather than S3 so no second bucket is needed.
# AWS-managed encryption is used; a CMK would add a standing $1 per month.
#trivy:ignore:AWS-0017
resource "aws_cloudwatch_log_group" "flow_logs" {
  #checkov:skip=CKV_AWS_158:Log group is encrypted with the CloudWatch managed key; a CMK adds standing cost for a deploy-demo-destroy network carrying no secrets.
  #checkov:skip=CKV_AWS_338:Seven day retention on purpose; demo network, evidence is exported when needed.
  name              = "/idp-platform/vpc-flow-logs/${local.name}"
  retention_in_days = var.flow_log_retention_days
}

data "aws_iam_policy_document" "flow_logs_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${local.name}-flow-logs"
  description        = "Lets VPC Flow Logs write to the idp-platform flow log group."
  assume_role_policy = data.aws_iam_policy_document.flow_logs_trust.json
}

data "aws_iam_policy_document" "flow_logs" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "write-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json
}

resource "aws_flow_log" "platform" {
  vpc_id               = aws_vpc.platform.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn         = aws_iam_role.flow_logs.arn

  tags = {
    Name = local.name
  }
}
