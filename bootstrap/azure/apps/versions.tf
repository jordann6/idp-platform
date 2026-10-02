terraform {
  required_version = ">= 1.11.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket       = "tf-backend-jord-projs"
    key          = "idp-platform/bootstrap/azure/apps.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  features {}
}
