terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # ---------------------------------------------------------------------------
  # State backend — DELIBERATELY COMMENTED OUT.
  #
  # The bucket must exist before `terraform init` can use it, and creating it
  # from this root would make the root depend on its own state. One-time manual
  # bootstrap (see README.md for the full sequence):
  #
  #   gcloud storage buckets create gs://gha-indie-worker-tfstate \
  #     --project=gha-indie-worker --location=us-central1 \
  #     --uniform-bucket-level-access --public-access-prevention
  #   gcloud storage buckets update gs://gha-indie-worker-tfstate --versioning
  #
  # Then uncomment and run `terraform init -migrate-state`. State contains
  # resource attributes that are effectively credentials-adjacent; it never goes
  # in git (see .gitignore).
  #
  # backend "gcs" {
  #   bucket = "gha-indie-worker-tfstate"
  #   prefix = "gcp"
  # }
  # ---------------------------------------------------------------------------
}

provider "google" {
  project = var.project_id
  region  = var.region
}
