# Workload Identity Federation for GitHub Actions.
#
# There is no service-account JSON key in this project, in any repository, or in
# any GitHub secret. A workflow presents its OIDC token, STS exchanges it for a
# short-lived credential, and the attribute condition below decides whether that
# token is allowed to become the deployer at all.
#
# THE ATTRIBUTE CONDITION IS THE SECURITY BOUNDARY. Without it — or with a
# condition that only checks the audience — ANY GitHub repository in the world
# can present a valid GitHub OIDC token and impersonate this account. The
# condition is evaluated by Google before the exchange, and the
# roles/iam.workloadIdentityUser binding narrows it a second time by principal.

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"
  description               = "OIDC federation for github.com/${var.github_org}. No JSON keys exist."

  depends_on = [google_project_service.enabled]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  # Only tokens whose repository_owner is this org are accepted. Everything
  # else is refused before any binding is consulted.
  attribute_condition = "assertion.repository_owner == '${var.github_org}'"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
    "attribute.workflow"         = "assertion.workflow"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Which repositories may actually become the deployer. This is the list to edit
# when a new deployable service joins the org — not the attribute condition.
locals {
  deploying_repositories = [
    "${var.github_org}/gha-indie-worker-web-server.rs",
    "${var.github_org}/gha-indie-worker-api-server.rs",
    "${var.github_org}/gha-indie-worker-admin-web-server.rs",
    "${var.github_org}/gha-indie-worker-admin-api-server.rs",
  ]
}

resource "google_service_account_iam_member" "github_impersonates_deployer" {
  for_each = toset(local.deploying_repositories)

  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${each.value}"
}
