# WAF, rate limiting and cache rules.
#
# Ruleset rules are ORDERED: the list order in each resource is the evaluation
# order at the edge. Reordering the list reorders production.

locals {
  human_hosts_expr = "http.host in {\"app.${var.zone_name}\" \"org.${var.zone_name}\" \"user.${var.zone_name}\" \"m.${var.zone_name}\"}"
  api_host_expr    = "http.host eq \"api.${var.zone_name}\""
}

# ---- rate limiting on api.<zone> ---------------------------------------------
# The API is the only host that a script hammers by design, and it is the one
# whose upstream costs money. Counting is per client IP at the edge; the
# application's own limiter (opaque HMAC principals, identity before network
# location) is the accurate one. This exists so a flood never reaches it.

resource "cloudflare_ruleset" "api_rate_limit" {
  zone_id = local.zone_id
  name    = "gha-indie-worker api rate limit"
  kind    = "zone"
  phase   = "http_ratelimit"

  rules = [{
    ref         = "api_per_ip"
    description = "Block a single IP that exceeds the per-period budget on api.${var.zone_name}"
    expression  = local.api_host_expr
    action      = "block"

    action_parameters = {
      response = {
        status_code  = 429
        content_type = "application/json"
        content      = "{\"error\":\"rate_limited\",\"detail\":\"too many requests from this address\"}"
      }
    }

    ratelimit = {
      characteristics     = ["ip.src", "cf.colo.id"]
      period              = var.api_rate_limit_period
      requests_per_period = var.api_rate_limit_requests
      mitigation_timeout  = var.api_rate_limit_mitigation_timeout

      # WebSocket upgrades on /v1/ws are long-lived single requests; counting
      # them alongside REST calls would throttle a client for staying connected.
      counting_expression = "${local.api_host_expr} and not starts_with(http.request.uri.path, \"/v1/ws\")"
    }
  }]
}

# ---- custom firewall ----------------------------------------------------------
# One zone entry-point ruleset owns this phase. The laptop CI rule is therefore
# composed into the same ordered rule list as the human-host bot challenge.
#
# `ci-laptop.indiebuild.dev` is a webhook ingress, not a public worker API. The
# tunnel still terminates at loopback:8100, but Cloudflare blocks every request
# except the exact GitHub webhook POST before it can reach the tunnel. HMAC at
# the worker remains an independent second authentication boundary.

resource "cloudflare_ruleset" "zone_firewall_custom" {
  count = (var.enable_bot_challenge || var.enable_laptop_ci_webhook_path_guard) ? 1 : 0

  zone_id = local.zone_id
  name    = "gha-indie-worker custom firewall"
  kind    = "zone"
  phase   = "http_request_firewall_custom"

  rules = concat(
    var.enable_laptop_ci_webhook_path_guard ? [{
      ref         = "block_laptop_ci_non_webhook_requests"
      description = "Expose only POST /webhooks/github on the opportunistic laptop CI hostname"
      expression  = "(http.host eq \"${var.laptop_ci_webhook_hostname}\") and ((http.request.uri.path ne \"/webhooks/github\") or (http.request.method ne \"POST\"))"
      action      = "block"
    }] : [],
    var.enable_bot_challenge ? [{
      ref         = "challenge_known_bots_on_human_hosts"
      description = "Managed challenge for known bots on the human-facing hosts"
      expression  = "(${local.human_hosts_expr}) and (cf.client.bot) and not (${var.bot_challenge_exempt_expression})"
      action      = "managed_challenge"
    }] : []
  )
}

# ---- cache rules ---------------------------------------------------------------
# /assets/releases/<release-id>/... is content-addressed by release id, so those
# bytes never change under a URL and can be cached forever. Everything else on
# this zone is either a per-session HTML render, an authenticated JSON response
# or an admin surface — caching any of it at the edge is how one tenant sees
# another tenant's page. So: one immutable allow-list, then bypass.

resource "cloudflare_ruleset" "cache" {
  zone_id = local.zone_id
  name    = "gha-indie-worker cache policy"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [
    {
      ref         = "immutable_release_assets"
      description = "Cache ${var.immutable_asset_path} forever — content-addressed by release id"
      expression  = "starts_with(http.request.uri.path, \"${trimsuffix(var.immutable_asset_path, "*")}\")"
      action      = "set_cache_settings"

      action_parameters = {
        cache = true

        edge_ttl = {
          mode    = "override_origin"
          default = var.immutable_asset_ttl_seconds
        }
        browser_ttl = {
          mode    = "override_origin"
          default = var.immutable_asset_ttl_seconds
        }
        # A release id is already in the path; a query string cannot change the
        # bytes, so it must not fragment the cache.
        cache_key = {
          ignore_query_strings_order = true
          cache_by_device_type       = false
        }
        respect_strong_etags = true
      }
    },
    {
      ref         = "bypass_everything_else"
      description = "Never cache anything else on this zone"
      expression  = "true"
      action      = "set_cache_settings"

      action_parameters = {
        cache = false
      }
    },
  ]
}
