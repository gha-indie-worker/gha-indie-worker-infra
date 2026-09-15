# Service APIs.
#
# Every other resource in this root depends on google_project_service, because a
# first apply against a fresh project otherwise fails halfway through with
# "API not enabled" and leaves a partial state.
#
# sqladmin is deliberately ABSENT: this fleet's Postgres is Neon and Supabase.
# Enabling Cloud SQL would put a second, unmanaged database plane one click away
# from a service account that is allowed to create instances.

locals {
  services = [
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "vpcaccess.googleapis.com",
    "compute.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]
}

resource "google_project_service" "enabled" {
  for_each = toset(local.services)

  project = var.project_id
  service = each.value

  # Turning an API off can delete the resources that depend on it. Removing a
  # line above should be a deliberate, reviewed act, not a side effect of a plan.
  disable_on_destroy         = false
  disable_dependent_services = false
}
