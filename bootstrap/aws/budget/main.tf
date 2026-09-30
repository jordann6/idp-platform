# Tag-filtered budgets only see spend once the tag keys are activated for cost
# allocation. Activation applies account-wide and takes up to 24 hours.
resource "aws_ce_cost_allocation_tag" "this" {
  for_each = toset(["Project", "CostCenter"])

  tag_key = each.value
  status  = "Active"
}

# ADR-0004 backstop: catches a forgotten always-on resource from any claim.
resource "aws_budgets_budget" "idp_platform" {
  name         = "idp-platform-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Project$idp-platform"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }

  depends_on = [aws_ce_cost_allocation_tag.this]
}
