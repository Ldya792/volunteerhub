# ---------- VPC network ----------
resource "google_compute_network" "vpc" {
  name                    = "volunteerhub-vpc"
  auto_create_subnetworks = false # custom mode: we create our own subnets
  routing_mode            = "REGIONAL"
}

# ---------- Subnet ----------
resource "google_compute_subnetwork" "web" {
  name                     = "volunteerhub-web-subnet"
  ip_cidr_range            = var.subnet_cidr
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true # VMs reach Google APIs without public IPs
}

# ---------- Firewall: load balancer traffic and health checks ----------
resource "google_compute_firewall" "allow_lb" {
  name    = "volunteerhub-allow-lb"
  network = google_compute_network.vpc.id

  direction     = "INGRESS"
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"] # Google load balancer ranges
  target_tags   = ["web"]

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}

# ---------- Firewall: SSH only through Identity-Aware Proxy ----------
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "volunteerhub-allow-iap-ssh"
  network = google_compute_network.vpc.id

  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"] # Google IAP range
  target_tags   = ["web"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# ---------- Cloud Router and Cloud NAT: outbound internet only ----------
resource "google_compute_router" "router" {
  name    = "volunteerhub-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "volunteerhub-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}



