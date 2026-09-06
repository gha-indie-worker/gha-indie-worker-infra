# ---------------------------------------------------------------------------------------------
# PRODUCT PLANE — the public fallback behind Cloudflare. ingress = all, because the edge Worker
# must reach it from outside when the k8s origin is down. Authenticity is enforced in the app:
# ores-middleware trusts only Cloudflare's proxy ranges and requires the shared edge secret.
# ---------------------------------------------------------------------------------------------

locals {
  # ores-middleware reads these; the same names are used by the k8s deployment so the two origins
  # behave identically. See github.com/ORESoftware/ores-middleware (bootstrap.rs).
  middleware_env = {
    ORES_MIDDLEWARE_ENV                       = "production"
    ORES_MIDDLEWARE_TLS_MODE                  = "behind-trusted-proxy"
    ORES_MIDDLEWARE_TRUSTED_PROXY_CIDRS       = "173.245.48.0/20,103.21.244.0/22,103.22.200.0/22,103.31.4.0/22,141.101.64.0/18,108.162.192.0/18,190.93.240.0/20,188.114.96.0/20,197.234.240.0/22,198.41.128.0/17,162.158.0.0/15,104.16.0.0/13,104.24.0.0/14,172.64.0.0/13,131.0.72.0/22,2400:cb00::/32,2606:4700::/32,2803:f800::/32,2405:b500::/32,2405:8100::/32,2a06:98c0::/29,2c0f:f248::/32"
    ORES_MIDDLEWARE_TIMEOUT_MS                = "30000"
    ORES_MIDDLEWARE_MAX_BODY_BYTES            = "8388608"
    ORES_MIDDLEWARE_RATE_LIMIT_ENABLED        = "true"
    ORES_MIDDLEWARE_RATE_LIMIT_ALGORITHM      = "token-bucket"
    ORES_MIDDLEWARE_RATE_LIMIT_LAYER          = "edge"
    ORES_MIDDLEWARE_RATE_LIMIT_FAILURE_MODE   = "fail-closed"
    ORES_MIDDLEWARE_RATE_LIMIT_KEY_DERIVATION = "external-hmac-sha256"
    ORES_MIDDLEWARE_RATE_LIMIT_KEY_NAMESPACE  = "gha-indie-worker"
    ORES_MIDDLEWARE_RATE_LIMIT_KEY_VERSION    = "v1"
  }

  otel_env = {
    ORES_OTEL_SERVICE_NAMESPACE = "gha-indie-worker"
    ORES_OTEL_EXPORTER          = "otlp"
    ORES_OTEL_ENDPOINT          = "https://otel.indiebuild.dev"
    ORES_OTEL_SAMPLE_RATIO      = "0.1"
  }
}

resource "google_cloud_run_v2_service" "web" {
  name                = "gha-indie-worker-web-server"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false
  description         = "MASH/Leptos/Dioxus web server — Cloud Run fallback for app./user./org./m.${var.domain}"

  template {
    service_account = google_service_account.svc["web"].email
    timeout         = "60s"

    scaling {
      min_instance_count = var.min_instances_product
      max_instance_count = 20
    }

    vpc_access {
      connector = google_vpc_access_connector.product.id
      egress    = "ALL_TRAFFIC" # so Neon/Supabase see the product NAT address
    }

    containers {
      image = var.image_web

      ports {
        name           = "http1"
        container_port = 8080
      }

      resources {
        limits   = { cpu = "1", memory = "512Mi" }
        cpu_idle = true
      }

      dynamic "env" {
        for_each = merge(local.middleware_env, local.otel_env, {
          GHA_INDIE_WORKER_WEB_BIND   = "0.0.0.0:8080"
          GHA_INDIE_WORKER_PUBLIC_URL = "https://app.${var.domain}"
          GHA_INDIE_WORKER_API_URL    = "https://api.${var.domain}"
          SHARED_AUTH_BASE_URL        = "https://auth.${var.domain}"
          SHARED_AUTH_ISSUER          = "https://auth.${var.domain}"
          SHARED_AUTH_AUDIENCE        = "indiebuild-web"
          ORES_CHAT_BASE_URL          = "https://chat.ores-chat.com"
          ORES_OTEL_SERVICE_NAME      = "gha-indie-worker-web-server"
        })
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = {
          DATABASE_URL                           = "giw-database-url-canonical"
          AUTH_DATABASE_URL                      = "giw-database-url-auth"
          SUPABASE_URL                           = "giw-supabase-url"
          SUPABASE_ANON_KEY                      = "giw-supabase-anon-key"
          SHARED_AUTH_INTROSPECTION_CREDENTIAL   = "giw-shared-auth-introspect-secret"
          ORES_MIDDLEWARE_RATE_LIMIT_HMAC_SECRET = "giw-rate-limit-hmac-secret"
          GHA_INDIE_WORKER_EDGE_SHARED_SECRET    = "giw-edge-shared-secret"
          ORES_CHAT_SERVICE_TOKEN                = "giw-ores-chat-service-token"
        }
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.product[env.value].secret_id
              version = "latest"
            }
          }
        }
      }

      startup_probe {
        http_get {
          path = "/healthz"
        }
        initial_delay_seconds = 2
        period_seconds        = 3
        failure_threshold     = 10
      }

      liveness_probe {
        http_get {
          path = "/healthz"
        }
        period_seconds = 30
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

resource "google_cloud_run_v2_service" "api" {
  name                = "gha-indie-worker-api-server"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false
  description         = "JSON API + WebSocket — Cloud Run fallback for api.${var.domain}"

  template {
    service_account = google_service_account.svc["api"].email
    timeout         = "3600s" # long-lived WebSocket sessions

    scaling {
      min_instance_count = var.min_instances_product
      max_instance_count = 30
    }

    vpc_access {
      connector = google_vpc_access_connector.product.id
      egress    = "ALL_TRAFFIC"
    }

    containers {
      image = var.image_api

      ports {
        name           = "http1"
        container_port = 8080
      }

      resources {
        limits   = { cpu = "2", memory = "1Gi" }
        cpu_idle = false # WebSocket + TCP sessions need CPU between requests
      }

      dynamic "env" {
        for_each = merge(local.middleware_env, local.otel_env, {
          GHA_INDIE_WORKER_API_BIND     = "0.0.0.0:8080"
          GHA_INDIE_WORKER_API_TCP_BIND = "0.0.0.0:9090"
          GHA_INDIE_WORKER_WS_MAX_CONNS = "5000"
          SHARED_AUTH_BASE_URL          = "https://auth.${var.domain}"
          SHARED_AUTH_ISSUER            = "https://auth.${var.domain}"
          SHARED_AUTH_AUDIENCE          = "indiebuild-api"
          ORES_OTEL_SERVICE_NAME        = "gha-indie-worker-api-server"
        })
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = {
          DATABASE_URL                           = "giw-database-url-canonical"
          AUTH_DATABASE_URL                      = "giw-database-url-auth"
          SUPABASE_URL                           = "giw-supabase-url"
          SUPABASE_SERVICE_ROLE_KEY              = "giw-supabase-service-role"
          SHARED_AUTH_INTROSPECTION_CREDENTIAL   = "giw-shared-auth-introspect-secret"
          ORES_MIDDLEWARE_RATE_LIMIT_HMAC_SECRET = "giw-rate-limit-hmac-secret"
          GHA_INDIE_WORKER_EDGE_SHARED_SECRET    = "giw-edge-shared-secret"
          NATS_CREDENTIALS                       = "giw-nats-credentials"
          ORES_CHAT_SERVICE_TOKEN                = "giw-ores-chat-service-token"
        }
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.product[env.value].secret_id
              version = "latest"
            }
          }
        }
      }

      startup_probe {
        http_get {
          path = "/healthz"
        }
        period_seconds    = 3
        failure_threshold = 10
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

# ---------------------------------------------------------------------------------------------
# ADMIN PLANE — ingress INTERNAL. Not reachable from the internet at all: no Cloudflare fallback,
# no allUsers invoker. Reached from the admin VPC (and, in production, from the k8s admin
# namespace over the VPC peering the cluster already has).
# ---------------------------------------------------------------------------------------------

locals {
  admin_common_env = merge(local.middleware_env, local.otel_env, {
    ORES_MIDDLEWARE_RATE_LIMIT_LAYER = "service"
    SHARED_AUTH_ADMIN_ISSUER         = "https://auth-admin.${var.domain}"
    SHARED_AUTH_ADMIN_AUDIENCE       = "indiebuild-admin"
    # Deep links to the ADMIN provider projects (never the canonical/auth ones).
    GHA_INDIE_WORKER_PLANE = "admin"
    # MCP: the admin plane talks to our own MCP servers for development/introspection.
    GHA_INDIE_WORKER_MCP_URL = "https://gha-indie-worker-mcp-server-REPLACE.a.run.app"
  })

  admin_common_secrets = {
    GHA_INDIE_WORKER_ADMIN_DATABASE_URL        = "giw-admin-database-url"
    ADMIN_SUPABASE_URL                         = "giw-admin-supabase-url"
    ADMIN_SUPABASE_SERVICE_ROLE_KEY            = "giw-admin-supabase-service-role"
    GHA_INDIE_WORKER_ADMIN_RDS_URL             = "giw-admin-rds-url"
    SHARED_AUTH_ADMIN_INTROSPECTION_CREDENTIAL = "giw-shared-auth-admin-introspect-secret"
    GHA_INDIE_WORKER_ADMIN_ALLOWLIST           = "giw-admin-allowlist"
    GHA_INDIE_WORKER_MCP_TOKEN                 = "giw-mcp-service-token"
  }
}

resource "google_cloud_run_v2_service" "admin_api" {
  name                = "gha-indie-worker-admin-api-server"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  deletion_protection = true
  description         = "Private super-admin JSON API — admin VPC only, admin Neon/Supabase/RDS only"

  template {
    service_account = google_service_account.svc["admin_api"].email

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    vpc_access {
      connector = google_vpc_access_connector.admin.id
      egress    = "ALL_TRAFFIC" # admin NAT address is what the admin projects allow-list
    }

    containers {
      image = var.image_admin_api

      ports {
        name           = "http1"
        container_port = 8787
      }

      resources {
        limits = { cpu = "1", memory = "512Mi" }
      }

      dynamic "env" {
        for_each = merge(local.admin_common_env, {
          GHA_INDIE_WORKER_ADMIN_BIND              = "0.0.0.0:8787"
          GHA_INDIE_WORKER_ADMIN_ALLOW_PUBLIC_BIND = "1" # Cloud Run must bind 0.0.0.0; ingress=internal is the real boundary
          ORES_OTEL_SERVICE_NAME                   = "gha-indie-worker-admin-api-server"
        })
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.admin_common_secrets
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.admin[env.value].secret_id
              version = "latest"
            }
          }
        }
      }

      startup_probe {
        http_get {
          path = "/healthz"
        }
        period_seconds    = 3
        failure_threshold = 10
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

resource "google_cloud_run_v2_service" "admin_web" {
  name                = "gha-indie-worker-admin-web-server"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  deletion_protection = true
  description         = "Private super-admin MASH console — admin VPC only, behind Cloudflare Access at the edge"

  template {
    service_account = google_service_account.svc["admin_web"].email

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    vpc_access {
      connector = google_vpc_access_connector.admin.id
      egress    = "ALL_TRAFFIC"
    }

    containers {
      image = var.image_admin_web

      ports {
        name           = "http1"
        container_port = 8788
      }

      resources {
        limits = { cpu = "1", memory = "512Mi" }
      }

      dynamic "env" {
        for_each = merge(local.admin_common_env, {
          GHA_INDIE_WORKER_ADMIN_BIND              = "0.0.0.0:8788"
          GHA_INDIE_WORKER_ADMIN_ALLOW_PUBLIC_BIND = "1"
          GHA_INDIE_WORKER_ADMIN_API_URL           = google_cloud_run_v2_service.admin_api.uri
          ORES_OTEL_SERVICE_NAME                   = "gha-indie-worker-admin-web-server"
        })
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.admin_common_secrets
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.admin[env.value].secret_id
              version = "latest"
            }
          }
        }
      }

      startup_probe {
        http_get {
          path = "/healthz"
        }
        period_seconds    = 3
        failure_threshold = 10
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

resource "google_cloud_run_v2_service" "mcp" {
  name                = "gha-indie-worker-mcp-server"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  deletion_protection = false
  description         = "Hardened read-only MCP server; reachable only from the admin plane"

  template {
    service_account = google_service_account.svc["mcp"].email

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    vpc_access {
      connector = google_vpc_access_connector.admin.id
      egress    = "ALL_TRAFFIC"
    }

    containers {
      image = var.image_mcp

      ports {
        name           = "http1"
        container_port = 8790
      }

      resources {
        limits = { cpu = "1", memory = "512Mi" }
      }

      dynamic "env" {
        for_each = merge(local.otel_env, {
          GHA_INDIE_WORKER_MCP_BIND = "0.0.0.0:8790"
          GHA_INDIE_WORKER_MCP_MODE = "read-only"
          ORES_OTEL_SERVICE_NAME    = "gha-indie-worker-mcp-server"
        })
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = { GHA_INDIE_WORKER_MCP_TOKEN = "giw-mcp-service-token" }
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.admin[env.value].secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}
