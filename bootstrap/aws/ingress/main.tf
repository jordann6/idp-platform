data "aws_caller_identity" "current" {}

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "tf-backend-jord-projs"
    key    = "idp-platform/bootstrap/aws/network.tfstate"
    region = "us-east-1"
  }
}

data "aws_subnet" "private" {
  count = length(local.private_subnet_ids)
  id    = local.private_subnet_ids[count.index]
}

data "aws_route53_zone" "parent" {
  name         = var.parent_zone
  private_zone = false
}

data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${var.region}.s3"
}

locals {
  name               = "idp-platform-${var.platform_region}"
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr           = data.terraform_remote_state.network.outputs.vpc_cidr
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
  azs                = data.aws_subnet.private[*].availability_zone
  apps_domain        = "${var.apps_subdomain}.${var.parent_zone}"
  internal_domain    = "internal.${local.apps_domain}"
  account_id         = data.aws_caller_identity.current.account_id
  ecr_upstream       = "ecr-public"
}

# ADR-0022, amending ADR-0008 for web traffic. An internet-facing ALB needs
# public subnets behind an internet gateway, which the private-only platform
# network does not have. This module adds both for the life of a demo session
# and holds nothing else in them: the ALB is the only resource with a public
# address, tasks stay in the private subnets, and the private route table is
# untouched, so nothing private gains a route to the internet.
resource "aws_internet_gateway" "ingress" {
  vpc_id = local.vpc_id

  tags = {
    Name = "${local.name}-ingress"
  }
}

resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id                  = local.vpc_id
  availability_zone       = local.azs[count.index]
  cidr_block              = cidrsubnet(local.vpc_cidr, 4, var.public_subnet_netnums[count.index])
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name}-public-${local.azs[count.index]}"
    Tier = "public-alb-only"
  }
}

resource "aws_route_table" "public" {
  vpc_id = local.vpc_id

  tags = {
    Name = "${local.name}-public"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ingress.id
}

resource "aws_route_table_association" "public" {
  count = length(local.azs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security groups. Default-deny, each rule names its peer group (ADR-0008).
resource "aws_security_group" "alb_public" {
  name        = "${local.name}-alb-public"
  description = "Public web ALB: HTTPS in from the internet, out to web service tasks only."
  vpc_id      = local.vpc_id

  tags = {
    Name = "${local.name}-alb-public"
  }
}

#trivy:ignore:AWS-0107
resource "aws_vpc_security_group_ingress_rule" "alb_public_https" {
  security_group_id = aws_security_group.alb_public.id
  description       = "HTTPS from the internet; this ALB exists to serve visibility public"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_public_to_tasks" {
  security_group_id            = aws_security_group.alb_public.id
  description                  = "To web service tasks on unprivileged ports"
  ip_protocol                  = "tcp"
  from_port                    = 1024
  to_port                      = 65535
  referenced_security_group_id = aws_security_group.tasks.id
}

resource "aws_security_group" "alb_internal" {
  count = var.internal_alb_enabled ? 1 : 0

  name        = "${local.name}-alb-internal"
  description = "Internal web ALB: HTTPS in from the platform VPC, out to web service tasks only."
  vpc_id      = local.vpc_id

  tags = {
    Name = "${local.name}-alb-internal"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_internal_https" {
  count = var.internal_alb_enabled ? 1 : 0

  security_group_id = aws_security_group.alb_internal[0].id
  description       = "HTTPS from the platform VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = local.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "alb_internal_to_tasks" {
  count = var.internal_alb_enabled ? 1 : 0

  security_group_id            = aws_security_group.alb_internal[0].id
  description                  = "To web service tasks on unprivileged ports"
  ip_protocol                  = "tcp"
  from_port                    = 1024
  to_port                      = 65535
  referenced_security_group_id = aws_security_group.tasks.id
}

# Shared by every web service task, the same trade as the shared Postgres
# group in ADR-0014: no isolation between services at this layer.
resource "aws_security_group" "tasks" {
  #checkov:skip=CKV2_AWS_5:Attached to ECS services by the xwebservice-aws Composition, not by Terraform.
  name        = "${local.name}-webservice-tasks"
  description = "Web service tasks: in from the web ALBs, out to the ECR, logs, and S3 endpoints only."
  vpc_id      = local.vpc_id

  tags = {
    Name = "${local.name}-webservice-tasks"
  }
}

resource "aws_vpc_security_group_ingress_rule" "tasks_from_alb_public" {
  #checkov:skip=CKV_AWS_25:Source is the public ALB's security group, not 0.0.0.0/0; the unprivileged range includes 3389 only because each service picks its own port.
  security_group_id            = aws_security_group.tasks.id
  description                  = "From the public web ALB"
  ip_protocol                  = "tcp"
  from_port                    = 1024
  to_port                      = 65535
  referenced_security_group_id = aws_security_group.alb_public.id
}

resource "aws_vpc_security_group_ingress_rule" "tasks_from_alb_internal" {
  count = var.internal_alb_enabled ? 1 : 0

  security_group_id            = aws_security_group.tasks.id
  description                  = "From the internal web ALB"
  ip_protocol                  = "tcp"
  from_port                    = 1024
  to_port                      = 65535
  referenced_security_group_id = aws_security_group.alb_internal[0].id
}

resource "aws_vpc_security_group_egress_rule" "tasks_to_endpoints" {
  security_group_id            = aws_security_group.tasks.id
  description                  = "HTTPS to the ECR and logs interface endpoints"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.endpoints.id
}

resource "aws_vpc_security_group_egress_rule" "tasks_to_s3" {
  security_group_id = aws_security_group.tasks.id
  description       = "HTTPS to S3 through the gateway endpoint, where ECR serves image layers"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_prefix_list.s3.id
}

resource "aws_security_group" "endpoints" {
  name        = "${local.name}-webservice-endpoints"
  description = "ECR and logs interface endpoints: HTTPS in from web service tasks only."
  vpc_id      = local.vpc_id

  tags = {
    Name = "${local.name}-webservice-endpoints"
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_tasks" {
  security_group_id            = aws_security_group.endpoints.id
  description                  = "HTTPS from web service tasks"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.tasks.id
}

# Image pulls without NAT (ADR-0008): ECR API and registry, plus CloudWatch
# Logs for the awslogs driver. Image layers come from S3 through the gateway
# endpoint the network module already has. These bill hourly, so they live
# here and are destroyed with the session, not in the network module.
resource "aws_vpc_endpoint" "interface" {
  for_each = toset(["ecr.api", "ecr.dkr", "logs"])

  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = slice(local.private_subnet_ids, 0, var.endpoint_az_count)
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name}-${each.key}"
  }
}

# The developer names an image on ECR Public; ECR fetches it through this
# rule into a private repository under ecr-public/ on the first pull. Only
# credential-free upstreams are configured, so the image must come from ECR
# Public on AWS (ADR-0022). Repositories the cache creates are not managed by
# Terraform; make aws-ingress-clean deletes them before this module is
# destroyed.
resource "aws_ecr_pull_through_cache_rule" "ecr_public" {
  ecr_repository_prefix = local.ecr_upstream
  upstream_registry_url = "public.ecr.aws"
}

resource "aws_ecs_cluster" "web" {
  #checkov:skip=CKV_AWS_65:Container Insights bills per metric; demo cluster, deploy-demo-destroy, logs go to CloudWatch through awslogs.
  name = local.name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

#trivy:ignore:AWS-0017
resource "aws_cloudwatch_log_group" "web" {
  #checkov:skip=CKV_AWS_158:Log group is encrypted with the CloudWatch managed key; a CMK adds standing cost for demo container logs carrying no secrets.
  #checkov:skip=CKV_AWS_338:Seven day retention on purpose; demo services, deploy-demo-destroy.
  name              = "/idp-platform/webservices/${var.platform_region}"
  retention_in_days = var.log_retention_days
}

# One task execution role for every web service: pull the image and write
# logs, nothing else. The Crossplane provider may pass only this role, so a
# claim cannot give a task any other AWS identity. Per-service task roles are
# out of scope because the provider's boundary denies IAM writes (ADR-0022).
data "aws_iam_policy_document" "execution_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${local.name}-webservice-execution"
  description        = "ECS task execution role for idp-platform web services: image pull and logs only."
  assume_role_policy = data.aws_iam_policy_document.execution_trust.json
}

data "aws_iam_policy_document" "execution" {
  # GetAuthorizationToken has no resource-level permissions.
  #checkov:skip=CKV_AWS_356:ecr:GetAuthorizationToken does not support resource-level permissions.
  #checkov:skip=CKV_AWS_111:ecr:GetAuthorizationToken does not support resource-level permissions.
  statement {
    sid       = "RegistryAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # A pull-through cache pull creates the repository and imports the image on
  # first use, as the pulling principal.
  statement {
    sid = "PullThroughCache"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchImportUpstreamImage",
      "ecr:CreateRepository",
    ]
    resources = ["arn:aws:ecr:${var.region}:${local.account_id}:repository/${local.ecr_upstream}/*"]
  }

  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.web.arn}:*"]
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "pull-and-log"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

# TLS. One certificate per ALB with a wildcard per team, so a service is
# <name>.<team>.<apps domain>. A single *.<apps domain> with <name>-<team>
# would be ambiguous (a-b in team c against a in team b-c), and the ALB would
# route both hosts to whichever rule has the lower priority.
resource "aws_acm_certificate" "public" {
  domain_name               = "*.${var.teams[0]}.${local.apps_domain}"
  subject_alternative_names = [for t in slice(var.teams, 1, length(var.teams)) : "*.${t}.${local.apps_domain}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "internal" {
  count = var.internal_alb_enabled ? 1 : 0

  domain_name               = "*.${var.teams[0]}.${local.internal_domain}"
  subject_alternative_names = [for t in slice(var.teams, 1, length(var.teams)) : "*.${t}.${local.internal_domain}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  validation_options = merge(
    { for o in aws_acm_certificate.public.domain_validation_options : o.domain_name => o },
    var.internal_alb_enabled ? { for o in aws_acm_certificate.internal[0].domain_validation_options : o.domain_name => o } : {},
  )
}

resource "aws_route53_record" "validation" {
  for_each = local.validation_options

  zone_id         = data.aws_route53_zone.parent.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "public" {
  certificate_arn         = aws_acm_certificate.public.arn
  validation_record_fqdns = [for o in aws_acm_certificate.public.domain_validation_options : aws_route53_record.validation[o.domain_name].fqdn]
}

resource "aws_acm_certificate_validation" "internal" {
  count = var.internal_alb_enabled ? 1 : 0

  certificate_arn         = aws_acm_certificate.internal[0].arn
  validation_record_fqdns = [for o in aws_acm_certificate.internal[0].domain_validation_options : aws_route53_record.validation[o.domain_name].fqdn]
}

# The one public load balancer for every web service (ADR-0004, ADR-0022).
# Each WebService adds a target group and a host-header rule, never an ALB.
#trivy:ignore:AWS-0053
resource "aws_lb" "public" {
  #checkov:skip=CKV_AWS_150:Deletion protection off on purpose; the module is destroyed at the end of every demo session.
  #checkov:skip=CKV_AWS_91:Access logs need a bucket and standing storage; deploy-demo-destroy, VPC flow logs cover network evidence.
  #checkov:skip=CKV2_AWS_28:WAF adds a standing web ACL charge; demo services serve a static page and live for one session.
  #checkov:skip=CKV2_AWS_20:No HTTP listener exists, so there is nothing to redirect; the ALB serves HTTPS only.
  name                       = "${local.name}-web"
  internal                   = false
  load_balancer_type         = "application"
  subnets                    = aws_subnet.public[*].id
  security_groups            = [aws_security_group.alb_public.id]
  drop_invalid_header_fields = true
  enable_deletion_protection = false
}

resource "aws_lb_listener" "public_https" {
  load_balancer_arn = aws_lb.public.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.public.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "no such service"
      status_code  = "404"
    }
  }
}

resource "aws_lb" "internal" {
  #checkov:skip=CKV_AWS_150:Deletion protection off on purpose; the module is destroyed at the end of every demo session.
  #checkov:skip=CKV_AWS_91:Access logs need a bucket and standing storage; deploy-demo-destroy, VPC flow logs cover network evidence.
  #checkov:skip=CKV2_AWS_28:WAF adds a standing web ACL charge; internal demo services are reachable only from the platform VPC.
  #checkov:skip=CKV2_AWS_20:No HTTP listener exists, so there is nothing to redirect; the ALB serves HTTPS only.
  count = var.internal_alb_enabled ? 1 : 0

  name                       = "${local.name}-web-int"
  internal                   = true
  load_balancer_type         = "application"
  subnets                    = local.private_subnet_ids
  security_groups            = [aws_security_group.alb_internal[0].id]
  drop_invalid_header_fields = true
  enable_deletion_protection = false
}

resource "aws_lb_listener" "internal_https" {
  count = var.internal_alb_enabled ? 1 : 0

  load_balancer_arn = aws_lb.internal[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.internal[0].certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "no such service"
      status_code  = "404"
    }
  }
}

# One wildcard alias per team, so a claim never needs DNS write access.
resource "aws_route53_record" "public_wildcard" {
  for_each = toset(var.teams)

  zone_id = data.aws_route53_zone.parent.zone_id
  name    = "*.${each.key}.${local.apps_domain}"
  type    = "A"

  alias {
    name                   = aws_lb.public.dns_name
    zone_id                = aws_lb.public.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "internal_wildcard" {
  for_each = var.internal_alb_enabled ? toset(var.teams) : toset([])

  zone_id = data.aws_route53_zone.parent.zone_id
  name    = "*.${each.key}.${local.internal_domain}"
  type    = "A"

  alias {
    name                   = aws_lb.internal[0].dns_name
    zone_id                = aws_lb.internal[0].zone_id
    evaluate_target_health = false
  }
}
