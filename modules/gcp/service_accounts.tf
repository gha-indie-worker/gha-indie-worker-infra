# One runtime service account per service, and one deployer.
#
# Least privilege here means: a runtime identity gets NO project-level role at
# all. Everything it may do is granted as a binding on the specific secret it
# needs (secrets.tf). A service that is compromised can read the four strings it
# was given and nothing else — not the other plane's secrets, not the registry,
# not the other services.

locals {
  runtime_accounts = {
    web = {
      account_id = "giw-web-run"
      name       = "gha-indie-worker-web runtime"
    }
    api = {
      account_id = "giw-api-run"
      name       = "gha-indie-worker-api runtime"
    }
    admin-web = {
      account_id = "giw-admin-web-run"
      name       = "gha-indie-worker-admin-web runtime"
    }
    admin-api = {
      account_id = "giw-admin-api-run"
      name       = "gha-indie-worker-admin-api runtime"
    }
  }
}

resource "google_service_account" "runtime" {
  for_each = local.runtime_accounts

  project      = var.project_id
  account_id   = each.value.account_id
  display_name = each.value.name
  description  = "Runtime identity for Cloud Run service ${each.key}. Holds only the secret-accessor bindings granted in secrets.tf."

  depends_on = [google_project_service.enabled]
}

# The identity GitHub Actions impersonates through Workload Identity Federation.
# It never has a JSON key; see wif.tf.
resource "google_service_account" "deployer" {
  project      = var.project_id
  account_id   = "giw-github-deployer"
  display_name = "GitHub Actions deployer"
  description  = "Impersonated by GitHub Actions in the gha-indie-worker org through workload identity federation. No JSON key exists for this account."

  depends_on = [google_project_service.enabled]
}

# What the deployer may do: push images, deploy revisions, and act as the four
# runtime accounts (required to set a service's identity). Nothing else — it
# cannot read secret payloads, create service accounts or touch IAM.
resource "google_project_iam_member" "deployer" {
  for_each = toset([
    "roles/run.admin",
    "roles/artifactregistry.writer",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

# serviceAccountUser is granted per runtime account rather than project-wide, so
# the deployer can only assign the four identities it is meant to assign.
resource "google_service_account_iam_member" "deployer_acts_as_runtime" {
  for_each = google_service_account.runtime

  service_account_id = each.value.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deployer.email}"
}
