terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "tf-backend-jord-projs"
    key          = "idp-platform/bootstrap/aws/budget.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "idp-platform"
      Environment = "bootstrap"
      Owner       = var.owner
      ManagedBy   = "terraform"
      CostCenter  = var.cost_center
    }
  }
}
