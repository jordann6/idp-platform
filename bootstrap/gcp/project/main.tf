# One dedicated project for the platform's GCP footprint, so a project-scoped
# budget sees every dollar and teardown is a single boundary.
resource "random_id" "suffix" {
  byte_length = 2
}

# Trivy cannot link the audit config below to a project whose ID is computed,
# so it reports audit logging as missing. google_project_iam_audit_config
# all_services configures it.
# trivy:ignore:AVD-GCP-0079
resource "google_project" "platform" {
  name                = "idp-platform"
  project_id          = "${var.project_prefix}-${random_id.suffix.hex}"
  org_id              = var.org_id
  billing_account     = var.billing_account
  auto_create_network = false
  deletion_policy     = "DELETE"
}

resource "google_project_service" "enabled" {
  for_each = toset(var.services)

  project                    = google_project.platform.project_id
  service                    = each.value
  disable_on_destroy         = false
  disable_dependent_services = false
}

# Admin Activity logs are always on. Data Access logs are opt in; turning them
# on for every service gives the provider identity's reads and writes an audit
# trail (the CloudTrail equivalent from ADR-0001). Volume is a handful of
# entries per reconcile, well inside the free Logging allotment.
resource "google_project_iam_audit_config" "all_services" {
  project = google_project.platform.project_id
  service = "allServices"

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  audit_log_config {
    log_type = "DATA_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}
