data "terraform_remote_state" "project" {
  backend = "s3"

  config = {
    bucket = "tf-backend-jord-projs"
    key    = "idp-platform/bootstrap/gcp/project.tfstate"
    region = "us-east-1"
  }
}

locals {
  project_id     = data.terraform_remote_state.project.outputs.project_id
  project_number = data.terraform_remote_state.project.outputs.project_number
}

# ADR-0004 backstop. Filtered on the dedicated platform project rather than the
# project label: a label filter only sees spend on resources that carry the
# label, so an unlabeled resource would bill silently. The project boundary
# catches everything, and the platform owns nothing outside it. Alerts go to the
# billing account's administrators, which is the default recipient set.
resource "google_billing_budget" "idp_platform" {
  billing_account = var.billing_account
  display_name    = "idp-platform-monthly"

  budget_filter {
    projects               = ["projects/${local.project_number}"]
    credit_types_treatment = "INCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.monthly_limit_usd)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }
}
