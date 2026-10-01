terraform {
  required_version = ">= 1.11.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "s3" {
    bucket       = "tf-backend-jord-projs"
    key          = "idp-platform/bootstrap/gcp/project.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "google" {
  default_labels = {
    project     = "idp-platform"
    environment = "bootstrap"
    owner       = var.owner
    managed-by  = "terraform"
    cost_center = var.cost_center
  }
}
