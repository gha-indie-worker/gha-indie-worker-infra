terraform {
  required_version = ">= 1.9.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
  # Existing remote-state users should retain the historical prefix when migrating:
  # backend "gcs" { bucket = "gha-indie-worker-tfstate" prefix = "gcp" }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
