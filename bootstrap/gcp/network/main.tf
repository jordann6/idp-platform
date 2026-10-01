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
  name       = "idp-platform-${var.platform_region}"
}

# ADR-0008 for GCP: one shared private network per platform region. The default
# internet route is deleted at creation, which is the GCP equivalent of the AWS
# VPC having no internet gateway: nothing in this network can reach the
# internet, and there is no NAT or Cloud Router.
resource "google_compute_network" "platform" {
  name                            = local.name
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  delete_default_routes_on_create = true
}

resource "google_compute_subnetwork" "platform" {
  name                     = local.name
  network                  = google_compute_network.platform.id
  region                   = var.region
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Private Google Access sends Google API traffic to private.googleapis.com, so
# with the default route gone it needs its own route to that range. This is the
# GCP stand-in for the AWS gateway endpoints: cloud APIs without internet egress.
resource "google_compute_route" "private_google_access" {
  name             = "${local.name}-private-google-access"
  network          = google_compute_network.platform.id
  dest_range       = "199.36.153.8/30"
  next_hop_gateway = "default-internet-gateway"
  priority         = 1000
}

# Default deny. GCP already denies ingress implicitly, but the implied rule is
# invisible and cannot be logged. An explicit lowest-priority deny with logging
# makes the posture reviewable in code and in the logs, for both directions.
resource "google_compute_firewall" "deny_all_ingress" {
  name      = "${local.name}-deny-all-ingress"
  network   = google_compute_network.platform.id
  direction = "INGRESS"
  priority  = 65534

  source_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "deny_all_egress" {
  name      = "${local.name}-deny-all-egress"
  network   = google_compute_network.platform.id
  direction = "EGRESS"
  priority  = 65534

  destination_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Postgres from inside the platform subnet only, the same intent as the AWS
# shared security group (ADR-0014). Cloud SQL lives in Google's producer
# network, so this rule governs what platform workloads may send to it.
resource "google_compute_firewall" "postgres_egress" {
  name      = "${local.name}-postgres-egress"
  network   = google_compute_network.platform.id
  direction = "EGRESS"
  priority  = 1000

  destination_ranges = ["${var.psa_address}/${var.psa_prefix_length}"]

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "google_apis_egress" {
  name      = "${local.name}-google-apis-egress"
  network   = google_compute_network.platform.id
  direction = "EGRESS"
  priority  = 1000

  destination_ranges = ["199.36.153.8/30"]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Private Service Access: a reserved range peered to Google's service producer
# network, which is where Cloud SQL private IPs come from.
resource "google_compute_global_address" "psa" {
  name          = "${local.name}-psa"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = var.psa_address
  prefix_length = var.psa_prefix_length
  network       = google_compute_network.platform.id
}

# REMOVE_PEERING: deleting the connection is refused for a while after a Cloud
# SQL instance is deleted, and the peering it created would then block deleting
# the network. This removes the peering in that case so teardown completes.
resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.platform.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa.name]
  deletion_policy         = "REMOVE_PEERING"
}
