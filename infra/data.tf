# ---------- Private bucket for event flyer images ----------
resource "google_storage_bucket" "flyers" {
  name          = "${var.project_id}-flyers" # bucket names are global, so include the project ID
  location      = var.region                 # us-east1: same region as the VMs
  storage_class = "STANDARD"

  uniform_bucket_level_access = true       # permissions only through IAM
  public_access_prevention    = "enforced" # can never be made public

  force_destroy = true # lets terraform destroy remove the bucket even if it has flyers
}

# ---------- Firestore database for events and sign-ups ----------
resource "google_firestore_database" "main" {
  name        = "(default)" # the free tier applies to the default database
  location_id = var.region  # us-east1: next to the VMs
  type        = "FIRESTORE_NATIVE"

  delete_protection_state = "DELETE_PROTECTION_DISABLED" # allows cleanup after grading
  deletion_policy         = "DELETE"                     # terraform destroy really deletes it
}

# ---------- Secret Manager: container for the website's session secret ----------
# The value is added later with gcloud, so it never appears in Terraform state.
resource "google_secret_manager_secret" "session" {
  secret_id = "volunteerhub-session-secret"

  replication {
    user_managed {
      replicas {
        location = var.region # keep the secret in us-east1
      }
    }
  }
}

# ---------- Secret Manager: container for the admin password ----------
resource "google_secret_manager_secret" "admin_password" {
  secret_id = "volunteerhub-admin-password"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}




# Private bucket for application releases (zip files the VMs download at boot)
resource "google_storage_bucket" "releases" {
  name                        = "${var.project_id}-releases"
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 5
    }
    action {
      type = "Delete"
    }
  }
}
