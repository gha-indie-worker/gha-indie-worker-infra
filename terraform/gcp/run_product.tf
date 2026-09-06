# The product plane: gha-indie-worker-web and gha-indie-worker-api.
#
# These two are the edge router's FALLBACK origins. The primary is the
# k8s-cluster ingress; Cloudflare fails over to these when /healthz or /readyz
# on the primary stops answering. That is the whole reason they are reachable
# from the internet — a Cloudflare Worker cannot mint a Google identity token,
# so a private Cloud Run service is not a fallback, it is a 403. See
# var.product_services_public.
#
# Authentication is application-level and unaffected: every route on both
# services refuses an anonymous caller with 401, the API takes tenancy from the
# token rather than the body, and the web server 404s a host it does not know.

locals {
  registry_base = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"

  product_ingress = var.product_services_public ? "INGRESS_TRAFFIC_ALL" : "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  web_env = merge({
    GHA_INDIE_WORKER_ENV          = "production"
    GHA_INDIE_WORKER_WEB_BIND     = "0.0.0.0:8080"
    GHA_INDIE_WORKER_BASE_DOMAIN  = var.domain
    GHA_INDIE_WORKER_ASSETS_DIR   = "/app/assets"
    GHA_INDIE_WORKER_CHAT_ENABLED = "true"
    RUST_LOG                      = "info"
    SHARED_AUTH_BASE              = var.shared_auth_base
    SHARED_AUTH_AUDIENCE          = "gha-indie-worker-web"
    GHA_INDIE_WORKER_NATS_URL     = var.nats_url

    # Behind Cloudflare the client address arrives in a proxy header; the
    # middleware only honours it from a peer it trusts.
    ORES_MIDDLEWARE_ENV      = "production"
    ORES_MIDDLEWARE_TLS_MODE = "trusted-proxy"
  }, var.web_service_env)

  api_env = merge({
    GHA_INDIE_WORKER_ENV      = "prod"
    GHA_INDIE_WORKER_API_BIND = "0.0.0.0:8080"
    RUST_LOG                  = "info"
    SHARED_AUTH_BASE          = var.shared_auth_base
    SHARED_AUTH_AUDIENCE      = "gha-indie-worker-api"
    ORES_CHAT_API_BASE        = var.ores_chat_api_base
    GHA_INDIE_WORKER_NATS_URL = var.nats_url
    ORES_MIDDLEWARE_ENV       = "prod"
  }, var.api_service_env)

  # secret name -> Secret Manager secret id.
  web_secrets = {
    GHA_INDIE_WORKER_SESSION_SECRET         = "gha-indie-worker-web-session-secret"
    GHA_INDIE_WORKER_RATE_LIMIT_HMAC_SECRET = "gha-indie-worker-web-rate-limit-secret"
    SHARED_AUTH_INTROSPECT_SECRET           = "gha-indie-worker-shared-auth-introspect"
    DATABASE_URL_CANONICAL                  = "gha-indie-worker-canonical-read-url"
  }

  api_secrets = {
    DATABASE_URL_CANONICAL                  = "gha-indie-worker-database-url-canonical"
    DATABASE_URL_AUTH                       = "gha-indie-worker-database-url-auth"
    SHARED_AUTH_INTROSPECT_SECRET           = "gha-indie-worker-shared-auth-introspect"
    GHA_INDIE_WORKER_RATE_LIMIT_HMAC_SECRET = "gha-indie-worker-api-rate-limit-secret"
    GHA_INDIE_WORKER_GITHUB_WEBHOOK_SECRET  = "gha-indie-worker-github-webhook-secret"
    GHA_INDIE_WORKER_EMBEDDINGS_API_KEY     = "gha-indie-worker-embeddings-api-key"
    SUPABASE_ANON_KEY                       = "gha-indie-worker-supabase-anon-key"
    SUPABASE_JWT_SECRET                     = "gha-indie-worker-supabase-jwt-secret"
  }
}

resource "google_cloud_run_v2_service" "web" {
  project             = var.project_id
  name                = "gha-indie-worker-web"
  location            = var.region
  ingress             = local.product_ingress
  deletion_protection = var.cloud_run_deletion_protection

  description = "app./user./org./m.indiebuild.dev — one host-routed web server. Edge-router fallback for the k8s origin."

  template {
    service_account                  = google_service_account.runtime["web"].email
    timeout                          = "${var.request_timeout_seconds}s"
    max_instance_request_concurrency = var.container_concurrency

    scaling {
      min_instance_count = var.product_min_instances
      max_instance_count = var.product_max_instances
    }

    vpc_access {
      connector = google_vpc_access_connector.product.id

      # Only RFC1918 destinations go through the connector; everything else
      # leaves over the internet directly. The alternative (ALL_TRAFFIC) would
      # push every outbound call — including the ones to Neon and Supabase over
      # the public internet — through a connector sized for internal traffic.
      egress = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = "${local.registry_base}/gha-indie-worker-web-server.rs:${var.image_tag}"

      ports {
        name           = "http1"
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
        cpu_idle          = var.product_min_instances == 0
        startup_cpu_boost = true
      }

      dynamic "env" {
        for_each = local.web_env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.web_secrets
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

      # THE HOST HEADER IS NOT OPTIONAL HERE. web-server.rs routes by Host and
      # answers 404 on EVERY path — /healthz included — for a host it does not
      # recognise. A probe without this header marks every revision unhealthy.
      startup_probe {
        initial_delay_seconds = 5
        period_seconds        = 5
        timeout_seconds       = 3
        failure_threshold     = 6

        http_get {
          path = "/healthz"
          http_headers {
            name  = "Host"
            value = "app.${var.domain}"
          }
        }
      }

      liveness_probe {
        initial_delay_seconds = 10
        period_seconds        = 30
        timeout_seconds       = 3
        failure_threshold     = 3

        http_get {
          path = "/readyz"
          http_headers {
            name  = "Host"
            value = "app.${var.domain}"
          }
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  lifecycle {
    # The image is owned by the repository's deploy-cloud-run.yml, which pins a
    # digest. If Terraform managed it too, every apply would roll production
    # back to whatever tag this root last saw.
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }
}

resource "google_cloud_run_v2_service" "api" {
  project             = var.project_id
  name                = "gha-indie-worker-api"
  location            = var.region
  ingress             = local.product_ingress
  deletion_protection = var.cloud_run_deletion_protection

  description = "api.indiebuild.dev — JSON API and /v1/ws. Edge-router fallback for the k8s origin."

  template {
    service_account                  = google_service_account.runtime["api"].email
    timeout                          = "${var.request_timeout_seconds}s"
    max_instance_request_concurrency = var.container_concurrency

    scaling {
      min_instance_count = var.product_min_instances
      max_instance_count = var.product_max_instances
    }

    vpc_access {
      connector = google_vpc_access_connector.product.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = "${local.registry_base}/gha-indie-worker-api-server.rs:${var.image_tag}"

      ports {
        name           = "http1"
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
        cpu_idle          = var.product_min_instances == 0
        startup_cpu_boost = true
      }

      dynamic "env" {
        for_each = local.api_env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.api_secrets
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

      # The API answers /healthz for any host. /readyz reports not-ready without
      # a database, which is exactly what should take an instance out of
      # rotation, so it is the liveness path and not the startup one.
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

# Public invoker bindings. These exist only when product_services_public is
# true, and they are the ONLY allUsers bindings in this project.
resource "google_cloud_run_v2_service_iam_member" "web_public" {
  count = var.product_services_public ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.web.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service_iam_member" "api_public" {
  count = var.product_services_public ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
