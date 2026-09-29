# ---------- 1. Global public IP address ----------
resource "google_compute_global_address" "lb_ip" {
  name = "volunteerhub-lb-ip"
}

# ---------- 5. Backend service: send traffic to healthy VMs ----------
resource "google_compute_backend_service" "web" {
  name                  = "volunteerhub-web-backend"
  protocol              = "HTTP"
  port_name             = "http" # the named port from the MIG
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.web.id]

  backend {
    group           = google_compute_instance_group_manager.web.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

# ---------- 4. URL map: all requests go to the web backend ----------
resource "google_compute_url_map" "web" {
  name            = "volunteerhub-url-map"
  default_service = google_compute_backend_service.web.id
}

# ---------- 3. HTTP proxy ----------
resource "google_compute_target_http_proxy" "web" {
  name    = "volunteerhub-http-proxy"
  url_map = google_compute_url_map.web.id
}

# ---------- 2. Forwarding rule: listen on port 80 ----------
resource "google_compute_global_forwarding_rule" "http" {
  name                  = "volunteerhub-http-rule"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.lb_ip.address
  port_range            = "80"
  target                = google_compute_target_http_proxy.web.id
}
