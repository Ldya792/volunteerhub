terraform {
  required_version = ">= 1.14"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }

  backend "gcs" {
    bucket = "volunteerhub-lw-2026-tfstate"
    prefix = "terraform/state"
  }
}