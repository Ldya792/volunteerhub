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

# ---------- Data access for the web VMs (least privilege) ----------

# Firestore: read and write documents (project level is the only option for Firestore)
resource "google_project_iam_member" "vm_firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.vm.email}"
}

# Cloud Storage: read and write objects in the flyer bucket ONLY
resource "google_storage_bucket_iam_member" "vm_flyers" {
  bucket = google_storage_bucket.flyers.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.vm.email}"
}

# Secret Manager: read the session secret ONLY
resource "google_secret_manager_secret_iam_member" "vm_session_secret" {
  secret_id = google_secret_manager_secret.session.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm.email}"
}

# Secret Manager: read the admin password ONLY
resource "google_secret_manager_secret_iam_member" "vm_admin_password" {
  secret_id = google_secret_manager_secret.admin_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm.email}"
}



# VMs can DOWNLOAD releases but never change them
resource "google_storage_bucket_iam_member" "vm_releases" {
  bucket = google_storage_bucket.releases.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.vm.email}"
}
