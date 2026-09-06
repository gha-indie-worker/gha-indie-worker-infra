# One service account per service. Nothing is granted to allUsers anywhere in this file.

locals {
  service_accounts = {
    web       = { id = "sa-giw-web", display = "gha-indie-worker web server (product plane)" }
    api       = { id = "sa-giw-api", display = "gha-indie-worker API server (product plane)" }
    admin_web = { id = "sa-giw-admin-web", display = "gha-indie-worker admin web console (admin plane)" }
    admin_api = { id = "sa-giw-admin-api", display = "gha-indie-worker admin API (admin plane)" }
    mcp       = { id = "sa-giw-mcp", display = "gha-indie-worker MCP server (admin plane)" }
  }

  product_plane = ["web", "api"]
  admin_plane   = ["admin_web", "admin_api", "mcp"]
}

resource "google_service_account" "svc" {
  for_each     = local.service_accounts
  account_id   = each.value.id
  display_name = each.value.display
}

resource "google_artifact_registry_repository" "images" {
  location      = var.region
  repository_id = "gha-indie-worker"
  format        = "DOCKER"
  description   = "Multi-arch service images; k8s pulls arm64, Cloud Run pulls amd64 from the same manifest list."

  docker_config {
    immutable_tags = true
  }
}

resource "google_artifact_registry_repository_iam_member" "pull" {
  for_each   = google_service_account.svc
  location   = google_artifact_registry_repository.images.location
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${each.value.email}"
}

# Telemetry: every service writes to ores-otel's collector, and to Cloud Logging as a floor.
resource "google_project_iam_member" "logging" {
  for_each = google_service_account.svc
  project  = var.project_id
  role     = "roles/logging.logWriter"
  member   = "serviceAccount:${each.value.email}"
}

resource "google_project_iam_member" "metrics" {
  for_each = google_service_account.svc
  project  = var.project_id
  role     = "roles/monitoring.metricWriter"
  member   = "serviceAccount:${each.value.email}"
}

# --- Invoker grants -------------------------------------------------------------------------
# The product services are the public fallback: the edge Worker reaches them over the internet,
# and the application (ores-middleware trusted-proxy + a Worker-shared secret) decides who may
# proceed. The ADMIN services are never public: only named service accounts may invoke them.

resource "google_cloud_run_v2_service_iam_member" "admin_api_invokers" {
  for_each = toset([
    google_service_account.svc["admin_web"].email,
    google_service_account.svc["mcp"].email,
  ])
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.admin_api.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${each.value}"
}

resource "google_cloud_run_v2_service_iam_member" "mcp_invokers" {
  for_each = toset([
    google_service_account.svc["admin_api"].email,
    google_service_account.svc["admin_web"].email,
  ])
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.mcp.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${each.value}"
}
