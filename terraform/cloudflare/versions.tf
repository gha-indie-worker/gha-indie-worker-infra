terraform {
  required_version = ">= 1.9.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }

  # ---------------------------------------------------------------------------
  # State backend — DELIBERATELY COMMENTED OUT.
  #
  # State bootstrap is a manual, one-time step: the bucket has to exist before
  # `terraform init` can talk to it, and creating it from this root would make
  # the root depend on its own state. Create it once by hand:
  #
  #   gcloud storage buckets create gs://gha-indie-worker-tfstate \
  #     --project=gha-indie-worker --location=us-central1 \
  #     --uniform-bucket-level-access --public-access-prevention
  #   gcloud storage buckets update gs://gha-indie-worker-tfstate --versioning
  #
  # then uncomment this block and run `terraform init -migrate-state`.
  # Until then state is local and MUST NOT be committed (see .gitignore).
  #
  # backend "gcs" {
  #   bucket = "gha-indie-worker-tfstate"
  #   prefix = "cloudflare"
  # }
  # ---------------------------------------------------------------------------
}

# CLOUDFLARE_API_TOKEN is read from the environment. Never put a token in a
# .tf or .tfvars file — see README.md for the exact scopes the token needs.
provider "cloudflare" {}
