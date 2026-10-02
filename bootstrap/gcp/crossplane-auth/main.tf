data "terraform_remote_state" "issuer" {
  backend = "s3"

  config = {
    bucket = "tf-backend-jord-projs"
    key    = "idp-platform/bootstrap/aws/oidc-issuer.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "project" {
  backend = "s3"

  config = {
    bucket = "tf-backend-jord-projs"
    key    = "idp-platform/bootstrap/gcp/project.tfstate"
    region = "us-east-1"
  }
}

locals {
  project_id = data.terraform_remote_state.project.outputs.project_id
  issuer_url = data.terraform_remote_state.issuer.outputs.issuer_url

  subjects = [for sa in var.provider_service_accounts : "system:serviceaccount:${var.crossplane_namespace}:${sa}"]
}

# GCP side of ADR-0001. The pool trusts the K3s issuer, and the attribute
# condition admits only the exact provider service account subjects (ADR-0011),
# the same tightness as the Azure federated credentials. A prefix match would
# have worked here; exact matching keeps one identity model across clouds.
resource "google_iam_workload_identity_pool" "k3s" {
  workload_identity_pool_id = "idp-k3s"
  display_name              = "idp-platform K3s"
  description               = "K3s control plane service account issuer (ADR-0001)."
}

resource "google_iam_workload_identity_pool_provider" "k3s" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.k3s.workload_identity_pool_id
  workload_identity_pool_provider_id = "k3s-oidc"
  display_name                       = "K3s OIDC"

  attribute_mapping = {
    "google.subject" = "assertion.sub"
  }

  attribute_condition = "assertion.sub in ${jsonencode(local.subjects)}"

  oidc {
    issuer_uri        = local.issuer_url
    allowed_audiences = [var.token_audience]
  }
}

# The provider identity. Federated principals impersonate it; it never has a
# key because the org policy below forbids creating one.
resource "google_service_account" "provider" {
  account_id   = "idp-crossplane-provider-gcp"
  display_name = "idp-platform Crossplane GCP provider"
  description  = "Impersonated by the K3s provider pods through workload identity federation (ADR-0001)."
}

resource "google_service_account_iam_member" "workload_identity_user" {
  for_each = toset(local.subjects)

  service_account_id = google_service_account.provider.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.k3s.name}/subject/${each.value}"
}

# Phase 0: bucket lifecycle on the verification prefix only. Phase 2 adds what
# xdatabase-gcp manages as its own reviewed diff.
resource "google_project_iam_member" "verify_storage" {
  project = local.project_id
  role    = "roles/storage.admin"
  member  = google_service_account.provider.member

  condition {
    title       = "verify-bucket-prefix"
    description = "Only buckets named with the Phase 0 verification prefix."
    expression  = "resource.name.startsWith(\"projects/_/buckets/${var.verify_bucket_prefix}\")"
  }
}

# Phase 2: what xdatabase-gcp manages, and nothing else. Custom roles rather
# than roles/cloudsql.admin, which also carries import, export, clone, and
# failover.
#
# Instance lifecycle is conditioned on the idp- name prefix, the same scope the
# AWS role puts on RDS identifiers (ADR-0014). Database and user permissions
# cannot be: Cloud SQL does not supply resource.name to IAM conditions for them,
# so a prefix condition denies every call even on an idp- instance (observed in
# the Data Access log, ADR-0020). They are granted unconditioned instead. The
# project holds only platform instances, and an instance can only exist under
# the prefix, so the practical scope is unchanged.
resource "google_project_iam_custom_role" "cloudsql_instances" {
  role_id     = "idpCrossplaneCloudSqlInstances"
  title       = "idp-platform Crossplane Cloud SQL instances"
  description = "Cloud SQL instance lifecycle for xdatabase-gcp."
  permissions = [
    "cloudsql.instances.create",
    "cloudsql.instances.delete",
    "cloudsql.instances.get",
    "cloudsql.instances.update",
  ]
}

resource "google_project_iam_member" "cloudsql_instances" {
  project = local.project_id
  role    = google_project_iam_custom_role.cloudsql_instances.id
  member  = google_service_account.provider.member

  condition {
    title       = "idp-instance-prefix"
    description = "Only Cloud SQL instances named with the idp- prefix."
    expression  = "resource.name.startsWith(\"projects/${local.project_id}/instances/idp-\")"
  }
}

resource "google_project_iam_custom_role" "cloudsql_contents" {
  role_id     = "idpCrossplaneCloudSqlContents"
  title       = "idp-platform Crossplane Cloud SQL databases and users"
  description = "Cloud SQL database and user lifecycle for xdatabase-gcp."
  permissions = [
    "cloudsql.databases.create",
    "cloudsql.databases.delete",
    "cloudsql.databases.get",
    "cloudsql.databases.list",
    "cloudsql.databases.update",
    "cloudsql.users.create",
    "cloudsql.users.delete",
    "cloudsql.users.get",
    "cloudsql.users.list",
    "cloudsql.users.update",
  ]
}

resource "google_project_iam_member" "cloudsql_contents" {
  project = local.project_id
  role    = google_project_iam_custom_role.cloudsql_contents.id
  member  = google_service_account.provider.member
}

# ADR-0001: no service account key can exist in this project, so federation is
# the only way in. Cloud SQL public IP is blocked as defense in depth for the
# deny-public-database control, below the Composition and the Kyverno policy.
resource "google_org_policy_policy" "disable_sa_key_creation" {
  name   = "projects/${local.project_id}/policies/iam.disableServiceAccountKeyCreation"
  parent = "projects/${local.project_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

resource "google_org_policy_policy" "sql_restrict_public_ip" {
  name   = "projects/${local.project_id}/policies/sql.restrictPublicIp"
  parent = "projects/${local.project_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# Phase 4: Cloud Run services for xwebservice-gcp (ADR-0022), on the idp- name
# prefix in the platform region only, the same scope as Cloud SQL instances.
# setIamPolicy is included because invokerIamDisabled, which makes a public
# service reachable without an allUsers binding, is authorized as an IAM
# policy change. Acting as the runtime service account is granted on that one
# account in bootstrap/gcp/web, not at project level.
resource "google_project_iam_custom_role" "cloudrun_services" {
  role_id     = "idpCrossplaneCloudRunServices"
  title       = "idp-platform Crossplane Cloud Run services"
  description = "Cloud Run service lifecycle for xwebservice-gcp."
  permissions = [
    "run.services.create",
    "run.services.delete",
    "run.services.get",
    "run.services.getIamPolicy",
    "run.services.setIamPolicy",
    "run.services.update",
  ]
}

resource "google_project_iam_member" "cloudrun_services" {
  project = local.project_id
  role    = google_project_iam_custom_role.cloudrun_services.id
  member  = google_service_account.provider.member

  condition {
    title       = "idp-service-prefix"
    description = "Only Cloud Run services in the platform region named with the idp- prefix."
    expression  = "resource.name.startsWith(\"projects/${local.project_id}/locations/${var.web_region}/services/${var.web_name_prefix}\")"
  }
}

# Long-running operation polling. Operation names never match the service
# prefix, so a condition would deny every poll; read only (ADR-0020 pattern).
resource "google_project_iam_custom_role" "cloudrun_operations" {
  role_id     = "idpCrossplaneCloudRunOperations"
  title       = "idp-platform Crossplane Cloud Run operations"
  description = "Read Cloud Run long-running operations for xwebservice-gcp."
  permissions = [
    "run.operations.get",
  ]
}

resource "google_project_iam_member" "cloudrun_operations" {
  project = local.project_id
  role    = google_project_iam_custom_role.cloudrun_operations.id
  member  = google_service_account.provider.member
}
