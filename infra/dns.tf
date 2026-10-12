# ---------- Cloud DNS: custom domain for the website ----------
# Created in the console first, then imported into Terraform.

resource "google_dns_managed_zone" "main" {
  name        = "volunteerhub-zone"
  dns_name    = "volunteerhub-lw.com."
  description = "Public zone for the VolunteerHub website"
  visibility  = "public"
}

# volunteerhub-lw.com -> load balancer IP
resource "google_dns_record_set" "apex" {
  managed_zone = google_dns_managed_zone.main.name
  name         = google_dns_managed_zone.main.dns_name
  type         = "A"
  ttl          = 18000
  rrdatas      = [google_compute_global_address.lb_ip.address]
}

# www.volunteerhub-lw.com -> load balancer IP
resource "google_dns_record_set" "www" {
  managed_zone = google_dns_managed_zone.main.name
  name         = "www.${google_dns_managed_zone.main.dns_name}"
  type         = "A"
  ttl          = 18000
  rrdatas      = [google_compute_global_address.lb_ip.address]
}

# ---------- Take over the resources that already exist ----------
import {
  to = google_dns_managed_zone.main
  id = "projects/volunteerhub-lw-2026/managedZones/volunteerhub-zone"
}
import {
  to = google_dns_record_set.apex
  id = "projects/volunteerhub-lw-2026/managedZones/volunteerhub-zone/rrsets/volunteerhub-lw.com./A"
}
import {
  to = google_dns_record_set.www
  id = "projects/volunteerhub-lw-2026/managedZones/volunteerhub-zone/rrsets/www.volunteerhub-lw.com./A"
}

output "website_url" {
  value = "http://${trimsuffix(google_dns_managed_zone.main.dns_name, ".")}"
}
