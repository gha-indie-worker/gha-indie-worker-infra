# The admin plane: gha-indie-worker-admin-web and gha-indie-worker-admin-api.
#
# Three properties define this file, and none of them may be relaxed one at a
# time:
#   1. ingress = INGRESS_TRAFFIC_INTERNAL_ONLY — a request from the internet to
#      the *.run.app URL is refused by Google's front end before any of our code
#      or IAM runs.
#   2. no allUsers invoker binding — there is no member here that a stranger
#      could be.
#   3. the admin VPC connector with ALL_TRAFFIC egress — every outbound call
#      leaves through the admin network, so the admin database's allow-list and
#      the plane-separation firewall rules see the admin identity and nothing
#      else.
# Cloudflare Access in front of admin.indiebuild.dev is a fourth, independent
# gate; it is not a substitute for any of these.
#
# THE BIND ADDRESS IS LOAD-BEARING. Both admin binaries default to
# 127.0.0.1:8787 / :8788 and REFUSE a non-loopback bind unless
# GHA_INDIE_WORKER_ADMIN_ALLOW_PUBLIC_BIND is exactly "1". They do not read
# Cloud Run's $PORT. So the container would listen on loopback:8787 while Cloud
# Run waited on 8080, and the revision would never become ready. Both variables
# are set here, next to the ingress setting that makes them safe — never baked
# into the image, which stays loopback-only by default.

locals {
  admin_common_env = {
    GHA_INDIE_WORKER_ENV                     = "prod"
    GHA_INDIE_WORKER_ADMIN_BIND              = "0.0.0.0:8080"
    GHA_INDIE_WORKER_ADMIN_ALLOW_PUBLIC_BIND = "1"
    GHA_INDIE_WORKER_ADMIN_ALLOWLIST         = var.admin_allowlist
    SHARED_AUTH_ADMIN_AUDIENCE               = "gha-indie-worker-admin"
    RUST_LOG                                 = "info"
    ORES_MIDDLEWARE_ENV                      = "prod"
  }

  admin_api_env = merge(local.admin_common_env, {
    SHARED_AUTH_ADMIN_BASE    = var.shared_auth_admin_base
    GHA_INDIE_WORKER_MCP_URL  = var.admin_mcp_url
    GHA_INDIE_WORKER_NATS_URL = var.admin_nats_url
    ORES_CHAT_API_BASE        = var.ores_chat_api_base

    # Read only to build the refusal list: a customer-instance token must be
    # rejected by this process, so it has to know what one looks like.
    GHA_INDIE_WORKER_ADMIN_DENY_AUDIENCES = "gha-indie-worker-api,gha-indie-worker-web"
  }, var.admin_api_service_env)

  admin_web_env = merge(local.admin_common_env, {
    GHA_INDIE_WORKER_ADMIN_API_BASE = var.admin_api_base

    # The actor headers are only trustworthy inside a mesh that injects them.
    # Outside one they are attacker-controlled, so: off.
    GHA_INDIE_WORKER_ADMIN_TRUST_MESH_HEADERS = "0"
  }, var.admin_web_service_env)

  admin_api_secrets = {
    SHARED_AUTH_ADMIN_INTROSPECT_SECRET    = "shared-auth-admin-introspect-secret"
    ADMIN_DATABASE_URL                     = "admin-database-url"
    GHA_INDIE_WORKER_MCP_BEARER            = "admin-mcp-bearer"
    ORES_CHAT_ADMIN_TOKEN                  = "ores-chat-admin-token"
    GHA_INDIE_WORKER_ADMIN_INTERNAL_SECRET = "admin-internal-secret"
  }

  admin_web_secrets = {
    GHA_INDIE_WORKER_ADMIN_INTERNAL_SECRET = "admin-internal-secret"
  }
}

resource "google_cloud_run_v2_service" "admin_api" {
  project             = var.project_id
  name                = "gha-indie-worker-admin-api"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  deletion_protection = var.cloud_run_deletion_protection

  description = "admin-api.indiebuild.dev — INTERNAL INGRESS ONLY. Admin JSON API."

  template {
    service_account                  = google_service_account.runtime["admin-api"].email
    timeout                          = "60s"
    max_instance_request_concurrency = var.container_concurrency

    scaling {
      min_instance_count = var.admin_min_instances
      max_instance_count = var.admin_max_instances
    }

    vpc_access {
      connector = google_vpc_access_connector.admin.id

      # ALL_TRAFFIC, not PRIVATE_RANGES_ONLY: the admin database and the admin
      # shared-auth instance are reached over public DNS with an IP allow-list,
      # and that allow-list can only name the admin network if every outbound
      # packet leaves through it.
      egress = "ALL_TRAFFIC"
    }

    containers {
      image = "${local.registry_base}/gha-indie-worker-admin-api-server.rs:${var.image_tag}"

      ports {
        name           = "http1"
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
        cpu_idle          = var.admin_min_instances == 0
        startup_cpu_boost = false
      }

      dynamic "env" {
        for_each = local.admin_api_env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.admin_api_secrets
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.this[env.value].secret_id
              version = "latest"
            }
          }
        }
      }

      startup_probe {
        initial_delay_seconds = 5
        period_seconds        = 5
        timeout_seconds       = 3
        failure_threshold     = 6

        http_get {
          path = "/healthz"
        }
      }

      liveness_probe {
        initial_delay_seconds = 10
        period_seconds        = 30
        timeout_seconds       = 3
        failure_threshold     = 3

        http_get {
          path = "/readyz"
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }
}

resource "google_cloud_run_v2_service" "admin_web" {
  project             = var.project_id
  name                = "gha-indie-worker-admin-web"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  deletion_protection = var.cloud_run_deletion_protection

  description = "admin.indiebuild.dev — INTERNAL INGRESS ONLY. Admin console."

  template {
    service_account                  = google_service_account.runtime["admin-web"].email
    timeout                          = "60s"
    max_instance_request_concurrency = var.container_concurrency

    scaling {
      min_instance_count = var.admin_min_instances
      max_instance_count = var.admin_max_instances
    }

    vpc_access {
      connector = google_vpc_access_connector.admin.id
      egress    = "ALL_TRAFFIC"
    }

    containers {
      image = "${local.registry_base}/gha-indie-worker-admin-web-server.rs:${var.image_tag}"

      ports {
        name           = "http1"
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
        cpu_idle          = var.admin_min_instances == 0
        startup_cpu_boost = false
      }

      dynamic "env" {
        for_each = local.admin_web_env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.admin_web_secrets
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.this[env.value].secret_id
              version = "latest"
            }
          }
        }
      }

      startup_probe {
        initial_delay_seconds = 5
        period_seconds        = 5
        timeout_seconds       = 3
        failure_threshold     = 6

        http_get {
          path = "/healthz"
        }
      }

      liveness_probe {
        initial_delay_seconds = 10
        period_seconds        = 30
        timeout_seconds       = 3
        failure_threshold     = 3

        http_get {
          path = "/readyz"
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }
}

# There is intentionally NO google_cloud_run_v2_service_iam_member for the admin
# services. Adding one with member = "allUsers" would not make them reachable —
# internal ingress refuses the request first — but it would remove the second of
# the three independent controls, and it would do so silently. If you need a
# human to reach the admin console, that is what Cloudflare Access and the
# cluster ingress are for.
