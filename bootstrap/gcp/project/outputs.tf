output "project_id" {
  description = "Platform project ID."
  value       = google_project.platform.project_id
}

output "project_number" {
  description = "Platform project number, used in the workload identity pool audience."
  value       = google_project.platform.number
}
