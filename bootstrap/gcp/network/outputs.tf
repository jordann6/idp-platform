output "network_self_link" {
  description = "Network self link, the privateNetwork value for Cloud SQL (platform-regions EnvironmentConfig)."
  value       = google_compute_network.platform.id
}

output "network_name" {
  description = "Network name."
  value       = google_compute_network.platform.name
}

output "subnet_name" {
  description = "Platform subnet name."
  value       = google_compute_subnetwork.platform.name
}

output "psa_range_name" {
  description = "Private Service Access allocated range, the allocatedIpRange value for Cloud SQL."
  value       = google_compute_global_address.psa.name
}
