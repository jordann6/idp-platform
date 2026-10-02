terraform {
  required_version = ">= 1.11.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.1"
    }
  }

  backend "s3" {
    bucket       = "tf-backend-jord-projs"
    key          = "idp-platform/bootstrap/gcp/web.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

# Quota and billing for these API calls land on the platform project, not on
# whatever project the operator's gcloud credentials happen to default to.
provider "google" {
  project               = local.project_id
  billing_project       = local.project_id
  user_project_override = true

  default_labels = {
    project     = "idp-platform"
    environment = "bootstrap"
    owner       = var.owner
    managed-by  = "terraform"
    cost_center = var.cost_center
  }
}
