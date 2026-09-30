data "azurerm_subscription" "current" {}

# ADR-0004 backstop: catches a forgotten always-on resource from any claim.
resource "azurerm_consumption_budget_subscription" "idp_platform" {
  name            = "idp-platform-monthly"
  subscription_id = data.azurerm_subscription.current.id
  amount          = var.monthly_limit_usd
  time_grain      = "Monthly"

  time_period {
    start_date = var.start_date
  }

  filter {
    tag {
      name   = "Project"
      values = ["idp-platform"]
    }
  }

  notification {
    enabled        = true
    operator       = "GreaterThan"
    threshold      = 50
    threshold_type = "Actual"
    contact_emails = [var.alert_email]
  }

  notification {
    enabled        = true
    operator       = "GreaterThan"
    threshold      = 100
    threshold_type = "Forecasted"
    contact_emails = [var.alert_email]
  }
}
