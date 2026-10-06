# ---------- Latest Ubuntu 24.04 LTS image ----------
data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2404-lts-amd64"
  project = "ubuntu-os-cloud"
}

# ---------- Instance template: the blueprint for each web VM ----------
resource "google_compute_instance_template" "web" {
  name_prefix  = "volunteerhub-web-"
  machine_type = "e2-small" # 2 vCPUs (shared), 2 GB RAM
  tags         = ["web"]    # matches the firewall rules

  disk {
    source_image = data.google_compute_image.ubuntu.self_link
    disk_size_gb = 10
    disk_type    = "pd-balanced"
    boot         = true
    auto_delete  = true
  }

  # No access_config block = no public IP address
  network_interface {
    subnetwork = google_compute_subnetwork.web.id
  }

  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"] # access is controlled by IAM roles instead
  }

  metadata = {
    enable-oslogin = "TRUE" # SSH access through Google accounts and IAM
  }

  metadata_startup_script = file("${path.module}/../scripts/startup.sh")

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  lifecycle {
    create_before_destroy = true
  }
}


# ---------- Health check: is each VM's web server answering? ----------
resource "google_compute_health_check" "web" {
  name                = "volunteerhub-web-hc"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 80
    request_path = "/health"
  }
}
# ---------- Managed instance group: 2 self-healing VMs ----------
resource "google_compute_instance_group_manager" "web" {
  name               = "volunteerhub-web-mig"
  zone               = var.zone
  base_instance_name = "volunteerhub-web"
  target_size        = 2

  version {
    instance_template = google_compute_instance_template.web.id
  }

  named_port {
    name = "http"
    port = 80
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.web.id
    initial_delay_sec = 300 # give the startup script 5 minutes to install Node.js and the app
  }

  # Rolling update: remove 1 old VM, then create its replacement.
  # Never more than 2 VMs (matches the approved design).
  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 0
    max_unavailable_fixed = 1
    replacement_method    = "RECREATE"
  }
}

