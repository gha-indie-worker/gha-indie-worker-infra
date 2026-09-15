terraform {
  required_version = ">= 1.9.0"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
  # Existing remote-state users should retain the historical prefix when migrating:
  # backend "gcs" { bucket = "gha-indie-worker-tfstate" prefix = "cloudflare" }
}

provider "cloudflare" {}
