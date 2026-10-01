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

  # Filtered on the platform's resource groups, not the Project tag. A tag
  # filter only sees spend on resources that carry the tag, so an untagged
  # resource would bill without tripping the alert. Every platform resource
  # lives in one of these groups, the Azure equivalent of the dedicated GCP
  # project the GCP budget filters on (ADR-0004).
  filter {
    dimension {
      name     = "ResourceGroupName"
      operator = "In"
      values   = var.resource_group_names
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
