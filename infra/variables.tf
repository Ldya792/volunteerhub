variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
  default     = "volunteerhub-lw-2026"
}

variable "region" {
  description = "Region for all resources"
  type        = string
  default     = "us-east1"
}

variable "zone" {
  description = "Zone for zonal resources"
  type        = string
  default     = "us-east1-b"
}

variable "subnet_cidr" {
  description = "Private IP range for the web subnet"
  type        = string
  default     = "10.10.1.0/24"
}
