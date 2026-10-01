output "budget_name" {
  description = "Budget resource name."
  value       = google_billing_budget.idp_platform.name
}
