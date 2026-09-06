# Secret *containers* are declared here; versions are added out-of-band (ores-sops -> gcloud), so no
# secret value ever appears in git or in a terraform plan. Access is granted per plane.

locals {
  product_secrets = [
    "giw-database-url-canonical", # Neon canonical (product data)
    "giw-database-url-auth",      # Neon auth realm (shared-auth customer)
    "giw-supabase-url",
    "giw-supabase-anon-key",
    "giw-supabase-service-role",
    "giw-shared-auth-introspect-secret",
    "giw-rate-limit-hmac-secret",
    "giw-nats-credentials",
    "giw-edge-shared-secret", # proves a request came from our Cloudflare Worker
    "giw-ores-chat-service-token",
  ]

  admin_secrets = [
    "giw-admin-database-url", # Neon ADMIN project — admin plane only
    "giw-admin-supabase-url",
    "giw-admin-supabase-service-role",
    "giw-admin-rds-url", # AWS RDS admin database
    "giw-shared-auth-admin-introspect-secret",
    "giw-admin-allowlist",
    "giw-mcp-service-token",
  ]
}

resource "google_secret_manager_secret" "product" {
  for_each  = toset(local.product_secrets)
  secret_id = each.value
  replication {
    auto {}
  }
  labels = { plane = "product", org = "gha-indie-worker" }
}

resource "google_secret_manager_secret" "admin" {
  for_each  = toset(local.admin_secrets)
  secret_id = each.value
  replication {
    auto {}
  }
  labels = { plane = "admin", org = "gha-indie-worker" }
}

# Product services read product secrets only.
resource "google_secret_manager_secret_iam_member" "product_access" {
  for_each = {
    for pair in setproduct(local.product_plane, local.product_secrets) :
    "${pair[0]}/${pair[1]}" => { svc = pair[0], secret = pair[1] }
  }
  secret_id = google_secret_manager_secret.product[each.value.secret].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.svc[each.value.svc].email}"
}

# Admin services read admin secrets only. There is deliberately no grant that gives a product
# service account access to an admin secret, and none that gives an admin service the product
# database URL — the admin binaries panic at boot if they see one.
resource "google_secret_manager_secret_iam_member" "admin_access" {
  for_each = {
    for pair in setproduct(["admin_web", "admin_api"], local.admin_secrets) :
    "${pair[0]}/${pair[1]}" => { svc = pair[0], secret = pair[1] }
  }
  secret_id = google_secret_manager_secret.admin[each.value.secret].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.svc[each.value.svc].email}"
}

resource "google_secret_manager_secret_iam_member" "mcp_access" {
  secret_id = google_secret_manager_secret.admin["giw-mcp-service-token"].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.svc["mcp"].email}"
}
