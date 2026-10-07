# ---------- CI/CD: keyless login from GitHub Actions ----------
locals {
  github_repo = "Ldya792/volunteerhub"
}

# Pool: a container for external identities (here: GitHub)
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions"
  description               = "Keyless login for the volunteerhub GitHub workflows"
}

# Provider: trusts GitHub's OIDC tokens, but ONLY from my repository
resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }
  attribute_condition = "assertion.repository == \"${local.github_repo}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# ---------- Service account 1: read-only, used for terraform plan on PRs ----------
resource "google_service_account" "tf_plan" {
  account_id   = "gha-terraform-plan"
  display_name = "GitHub Actions - Terraform plan (read-only)"
}

resource "google_service_account_iam_member" "tf_plan_wif" {
  service_account_id = google_service_account.tf_plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${local.github_repo}"
}

resource "google_project_iam_member" "tf_plan" {
  for_each = toset([
    "roles/viewer",               # read resource settings
    "roles/iam.securityReviewer", # read IAM policies
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.tf_plan.email}"
}

# ---------- Service account 2: admin, used ONLY from the main branch ----------
resource "google_service_account" "tf_apply" {
  account_id   = "gha-terraform-apply"
  display_name = "GitHub Actions - Terraform apply and deploy (main only)"
}

resource "google_service_account_iam_member" "tf_apply_wif" {
  service_account_id = google_service_account.tf_apply.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.ref/refs/heads/main"
}

resource "google_project_iam_member" "tf_apply" {
  for_each = toset([
    "roles/editor",                          # create and change most resources
    "roles/resourcemanager.projectIamAdmin", # project-level role bindings
    "roles/iam.serviceAccountAdmin",         # service accounts and their bindings
    "roles/iam.workloadIdentityPoolAdmin",   # this WIF pool and provider
    "roles/secretmanager.admin",             # secret-level role bindings
    "roles/storage.admin",                   # bucket-level role bindings
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.tf_apply.email}"
}

# ---------- Both need the Terraform state (read + lock) ----------
resource "google_storage_bucket_iam_member" "tf_state" {
  for_each = {
    plan  = google_service_account.tf_plan.email
    apply = google_service_account.tf_apply.email
  }
  bucket = "${var.project_id}-tfstate"
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${each.value}"
}

# ---------- Values the GitHub workflows need ----------
output "wif_provider" {
  value = google_iam_workload_identity_pool_provider.github.name
}
output "tf_plan_sa" {
  value = google_service_account.tf_plan.email
}
output "tf_apply_sa" {
  value = google_service_account.tf_apply.email
}
