output "zone_id" {
  description = "Zone id for indiebuild.dev, whether it was supplied or looked up."
  value       = local.zone_id
}

output "zone_name" {
  description = "Apex domain this root manages."
  value       = var.zone_name
}

output "product_hostnames" {
  description = "Every proxied product hostname this root manages, in the order the edge Worker sees them."
  value       = sort([for label in keys(local.product_hosts) : "${label}.${var.zone_name}"])
}

output "origin_hostnames" {
  description = "Unproxied origin records the edge Worker connects to. These are the values router.config.json must use as `primary.url` hosts."

  value = {
    hetzner = local.origin_hetzner_fqdn
    aws     = var.aws_origin_ip != "" ? local.origin_aws_fqdn : null
  }
}

output "edge_router_inputs" {
  description = "Everything cloudflare/edge-router/router.config.json needs from this root. If a fallback host here is empty, that host has no Cloud Run fallback yet and the Worker must be configured accordingly."

  value = {
    domain     = var.zone_name
    gcp_region = var.gcp_region
    primary    = "https://${local.origin_hetzner_fqdn}"

    fallbacks = {
      web       = var.cloud_run_web_host
      api       = var.cloud_run_api_host
      admin_web = var.cloud_run_admin_web_host
      admin_api = var.cloud_run_admin_api_host
    }
  }
}

output "access_application_ids" {
  description = "Access application ids, for auditing what is actually gated."

  value = merge(
    { for k, app in cloudflare_zero_trust_access_application.admin : k => app.id },
    { router-status = cloudflare_zero_trust_access_application.router_status.id }
  )
}

output "access_policy_ids" {
  description = "Access policy ids reused by every admin application."

  value = {
    operators = cloudflare_zero_trust_access_policy.admin_operators.id
    deny_rest = cloudflare_zero_trust_access_policy.admin_deny_everyone_else.id
  }
}

output "ruleset_ids" {
  description = "Ruleset ids by phase."

  value = {
    http_ratelimit               = cloudflare_ruleset.api_rate_limit.id
    http_request_cache_settings  = cloudflare_ruleset.cache.id
    http_request_firewall_custom = var.enable_bot_challenge ? cloudflare_ruleset.zone_firewall_custom[0].id : null
  }
}

output "worker_routes_are_not_managed_here" {
  description = "A reminder, emitted by design: Worker routes belong to cloudflare/edge-router/wrangler.toml. If you are looking for a route in this state, it is not here."
  value       = "see cloudflare/edge-router/README.md"
}
