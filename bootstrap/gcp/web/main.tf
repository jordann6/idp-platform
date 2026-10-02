data "terraform_remote_state" "project" {
  backend = "s3"

  config = {
    bucket = "tf-backend-jord-projs"
    key    = "idp-platform/bootstrap/gcp/project.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "auth" {
  backend = "s3"

  config = {
    bucket = "tf-backend-jord-projs"
    key    = "idp-platform/bootstrap/gcp/crossplane-auth.tfstate"
    region = "us-east-1"
  }
}

locals {
  project_id     = data.terraform_remote_state.project.outputs.project_id
  provider_email = data.terraform_remote_state.auth.outputs.service_account_email
}

# ADR-0022 for GCP. Cloud Run pulls only from Artifact Registry, Container
# Registry, and Docker Hub, so a public.ecr.aws image reaches it through this
# remote repository, the GCP counterpart of the ECR pull-through cache. It
# keeps one image reference valid on both clouds. Cached versions are deleted
# a day after upload, so nothing accumulates between demo sessions.
resource "google_artifact_registry_repository" "ecr_public" {
  #checkov:skip=CKV_GCP_84:Caches public ECR Public images only and is encrypted with the Google-managed key; a CMEK adds a standing KMS charge for no confidentiality gain.
  location      = var.region
  repository_id = var.cache_repository_id
  description   = "Pull-through cache of ECR Public for idp-platform web services."
  format        = "DOCKER"
  mode          = "REMOTE_REPOSITORY"

  remote_repository_config {
    description = "ECR Public"

    docker_repository {
      custom_repository {
        uri = "https://public.ecr.aws"
      }
    }
  }

  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "delete-after-retention"
    action = "DELETE"

    condition {
      older_than = var.cache_retention
    }
  }
}

# The identity every web service runs as. It holds no role, so a service has
# no access to any GCP API; without it, Cloud Run would run as the default
# compute service account. Per-service identities are out of scope (ADR-0022).
resource "google_service_account" "runtime" {
  account_id   = "idp-webservice-runtime"
  display_name = "idp-platform web service runtime"
  description  = "Runs every xwebservice-gcp Cloud Run service. Holds no roles."
}

# The Crossplane provider may attach this one account to a service and no
# other: actAs on the account itself, not at project level.
resource "google_service_account_iam_member" "provider_act_as" {
  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${local.provider_email}"
}
