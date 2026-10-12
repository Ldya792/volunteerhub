# ---------- Cloud Monitoring and scheduled disk snapshots ----------

variable "alert_email" {
  description = "Email address that receives alerts (set from a GitHub secret)"
  type        = string
  sensitive   = true
}

resource "google_monitoring_notification_channel" "email" {
  display_name = "VolunteerHub alerts email"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
}

resource "google_monitoring_uptime_check_config" "site" {
  display_name = "VolunteerHub website /health"
  timeout      = "10s"
  period       = "60s"
  http_check {
    path    = "/health"
    port    = 80
    use_ssl = false
  }
  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = trimsuffix(google_dns_managed_zone.main.dns_name, ".")
    }
  }
}

resource "google_monitoring_alert_policy" "site_down" {
  display_name          = "VolunteerHub website is down"
  combiner              = "OR"
  notification_channels = [google_monitoring_notification_channel.email.id]
  conditions {
    display_name = "Uptime check failing"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\" AND metric.label.\"check_id\"=\"${google_monitoring_uptime_check_config.site.uptime_check_id}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "60s"
      aggregations {
        alignment_period     = "1200s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.*"]
      }
      trigger {
        count = 1
      }
    }
  }
}

resource "google_monitoring_alert_policy" "high_cpu" {
  display_name          = "VolunteerHub VM CPU above 80%"
  combiner              = "OR"
  notification_channels = [google_monitoring_notification_channel.email.id]
  conditions {
    display_name = "CPU utilization > 80% for 5 minutes"
    condition_threshold {
      filter          = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.type=\"gce_instance\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "300s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
}

resource "google_compute_resource_policy" "daily_snapshots" {
  name   = "volunteerhub-daily-snapshots"
  region = var.region
  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = "04:00"
      }
    }
    retention_policy {
      max_retention_days    = 7
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }
    snapshot_properties {
      storage_locations = [var.region]
      labels = {
        app = "volunteerhub"
      }
    }
  }
}
