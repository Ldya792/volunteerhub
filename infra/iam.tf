# ---------- Service account for the web VMs ----------
resource "google_service_account" "vm" {
  account_id   = "volunteerhub-vm"
  display_name = "VolunteerHub web VM service account"
}

# Least privilege: only write logs and metrics (more roles added in Step 11)
resource "google_project_iam_member" "vm_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.vm.email}"
}

resource "google_project_iam_member" "vm_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.vm.email}"
}

