# Secret Manager.
#
# Terraform creates the CONTAINERS and the access bindings. It does not create
# the values, and by default it does not create a version either. That is
# deliberate and it is the fail-closed choice:
#
#   * A Cloud Run revision that references a secret with no version FAILS TO
#     DEPLOY, loudly, at the exact moment someone forgot to populate it.
#   * A placeholder version would instead let a service boot, authenticate
#     against nothing, and write "REPLACE_ME" somewhere as though it were a
#     credential.
#
# Populate each one by hand, once, and never through Terraform:
#
#   printf %s "$VALUE" | gcloud secrets versions add <secret-id> \
#     --project=gha-indie-worker --data-file=-
#
# A value added that way is never read back into state, and the ignore_changes
# below means a later apply will not revert it.
#
# NAMING: the ids under "web" and "admin" are not a style choice — they are the
# exact strings the four repositories' deploy-cloud-run.yml pass to
# `--set-secrets`. They must not be renamed here alone.

locals {
  # accessors: which runtime service accounts may read the payload. A secret
  # with an empty list is operator-only — it exists so there is one place the
  # value lives, but no workload can read it.
  secrets = {
    # ---- web-server.rs (ids fixed by its deploy-cloud-run.yml) -------------
    "gha-indie-worker-web-session-secret" = {
      accessors   = ["web"]
      description = "GHA_INDIE_WORKER_SESSION_SECRET — signs the web session cookie."
    }
    "gha-indie-worker-web-rate-limit-secret" = {
      accessors   = ["web"]
      description = "GHA_INDIE_WORKER_RATE_LIMIT_HMAC_SECRET for the web plane. Keys are opaque HMAC digests; this is the key."
    }
    "gha-indie-worker-shared-auth-introspect" = {
      accessors   = ["web", "api"]
      description = "SHARED_AUTH_INTROSPECT_SECRET — the product instance's service credential. At least 32 non-whitespace bytes."
    }
    "gha-indie-worker-canonical-read-url" = {
      accessors   = ["web"]
      description = "DATABASE_URL_CANONICAL for the web server — a READ-ONLY role on the canonical Neon project."
    }

    # ---- api-server.rs ------------------------------------------------------
    "gha-indie-worker-database-url-canonical" = {
      accessors   = ["api"]
      description = "DATABASE_URL_CANONICAL for the API. Canonical project only; the admin project is not reachable from this plane."
    }
    "gha-indie-worker-database-url-auth" = {
      accessors   = ["api"]
      description = "DATABASE_URL_AUTH for the API — the auth project."
    }
    "gha-indie-worker-api-rate-limit-secret" = {
      accessors   = ["api"]
      description = "GHA_INDIE_WORKER_RATE_LIMIT_HMAC_SECRET for the API plane."
    }
    "gha-indie-worker-github-webhook-secret" = {
      accessors   = ["api"]
      description = "GHA_INDIE_WORKER_GITHUB_WEBHOOK_SECRET — X-Hub-Signature-256 HMAC key. At least 32 non-whitespace bytes."
    }
    "gha-indie-worker-embeddings-api-key" = {
      accessors   = ["api"]
      description = "GHA_INDIE_WORKER_EMBEDDINGS_API_KEY for the OpenAI-compatible provider."
    }
    "gha-indie-worker-supabase-anon-key" = {
      accessors   = ["api"]
      description = "SUPABASE_ANON_KEY. Public-by-design, but rotated with the project, so it lives with the rest."
    }
    "gha-indie-worker-supabase-jwt-secret" = {
      accessors   = ["api"]
      description = "SUPABASE_JWT_SECRET — HS256 verification key for Supabase-issued session tokens."
    }
    "gha-indie-worker-neon-api-key" = {
      accessors   = []
      description = "Neon control-plane API key. Operator-only: used by a human running neon/scripts, never by a running service."
    }
    "gha-indie-worker-supabase-access-token" = {
      accessors   = []
      description = "Supabase management API token. Operator-only, same reasoning as the Neon key."
    }

    # ---- admin plane (ids fixed by the admin deploy-cloud-run.yml files) ----
    "shared-auth-admin-introspect-secret" = {
      accessors   = ["admin-api"]
      description = "SHARED_AUTH_ADMIN_INTROSPECT_SECRET — the ADMIN shared-auth instance. Never the product instance's credential."
    }
    "admin-database-url" = {
      accessors   = ["admin-api"]
      description = "ADMIN_DATABASE_URL — the admin Neon project, reachable only from the admin plane."
    }
    "admin-mcp-bearer" = {
      accessors   = ["admin-api"]
      description = "GHA_INDIE_WORKER_MCP_BEARER for the org MCP server."
    }
    "ores-chat-admin-token" = {
      accessors   = ["admin-api"]
      description = "ORES_CHAT_ADMIN_TOKEN for the operator chat surfaces."
    }
    "admin-internal-secret" = {
      accessors   = ["admin-web", "admin-api"]
      description = "GHA_INDIE_WORKER_ADMIN_INTERNAL_SECRET — the mesh-hop shared secret, compared in constant time at both ends."
    }
  }

  # (secret, service account) pairs, flattened for one binding each.
  secret_accessors = merge([
    for id, cfg in local.secrets : {
      for account in cfg.accessors : "${id}::${account}" => {
        secret_id = id
        account   = account
      }
    }
  ]...)
}

resource "google_secret_manager_secret" "this" {
  for_each = local.secrets

  project   = var.project_id
  secret_id = each.key

  labels = {
    managed-by = "terraform"
    plane      = startswith(each.key, "admin") || startswith(each.key, "shared-auth-admin") || startswith(each.key, "ores-chat-admin") ? "admin" : "product"
  }

  # Pinned to one region rather than replicated automatically: the payloads are
  # database URLs and signing keys for a fleet whose data residency is a
  # contract, not a preference.
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [google_project_service.enabled]
}

# Off by default. See variables.tf for why a placeholder version is worse than
# no version at all.
resource "google_secret_manager_secret_version" "placeholder" {
  for_each = var.create_placeholder_secret_versions ? google_secret_manager_secret.this : {}

  secret      = each.value.id
  secret_data = "REPLACE_ME"

  lifecycle {
    # The real value is added out of band with `gcloud secrets versions add`.
    # Without this, the next apply would replace an operator's live credential
    # with the placeholder string.
    ignore_changes = [secret_data, enabled]
  }
}

resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each = local.secret_accessors

  project   = var.project_id
  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime[each.value.account].email}"
}
