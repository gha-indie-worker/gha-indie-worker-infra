# Optional public ingress for the developer laptop's gha-indie-worker gateway.
#
# The public contract intentionally uses ONE first-level hostname plus path
# routing by default:
#   https://local.<zone>/p/<project>/<session>/<service>/...
#
# Multi-label dynamic hostnames remain useful on localhost, but Universal SSL
# on a full Cloudflare zone does not cover deeper names such as
# api.project.session.local.<zone>. Do not add wildcard public DNS for those
# names unless Total TLS or an explicitly matching advanced/custom certificate
# is enabled first.

variable "laptop_tunnel_cname" {
  description = "Cloudflare Tunnel target (<uuid>.cfargotunnel.com) for the laptop gateway. Empty disables public laptop ingress. The tunnel UUID/target is not a secret; its credentials file/token is."
  type        = string
  default     = ""

  validation {
    condition = var.laptop_tunnel_cname == "" || can(regex(
      "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\\.cfargotunnel\\.com$",
      var.laptop_tunnel_cname
    ))
    error_message = "laptop_tunnel_cname must be empty or <uuid>.cfargotunnel.com."
  }
}

variable "laptop_ingress_subdomain" {
  description = "First-level hostname used for protected laptop path routing. Keep this one label so Universal SSL covers it."
  type        = string
  default     = "local"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.laptop_ingress_subdomain)) && length(var.laptop_ingress_subdomain) <= 63
    error_message = "laptop_ingress_subdomain must be one lowercase DNS label of at most 63 bytes."
  }
}

variable "laptop_ingress_require_access" {
  description = "Protect local.<zone> with Cloudflare Access. Default true. Webhooks that cannot complete interactive Access must use a separate signed endpoint, not weaken this preview/control hostname."
  type        = bool
  default     = true
}

variable "access_team_domain" {
  description = "Cloudflare Access issuer origin, e.g. https://example.cloudflareaccess.com. Used by the hardened edge Worker verifier and emitted as a deployment input."
  type        = string
  default     = ""

  validation {
    condition = var.access_team_domain == "" || can(regex(
      "^https://[a-z0-9-]+\\.cloudflareaccess\\.com$",
      var.access_team_domain
    ))
    error_message = "access_team_domain must be empty or an https://<team>.cloudflareaccess.com origin."
  }
}

locals {
  laptop_ingress_enabled  = var.laptop_tunnel_cname != ""
  laptop_ingress_hostname = "${var.laptop_ingress_subdomain}.${var.zone_name}"
}

resource "cloudflare_dns_record" "laptop_ingress" {
  count = local.laptop_ingress_enabled ? 1 : 0

  zone_id = local.zone_id
  name    = local.laptop_ingress_hostname
  type    = "CNAME"
  content = var.laptop_tunnel_cname
  proxied = true
  ttl     = 1
  comment = "managed by modules/cloudflare — protected laptop gha-indie-worker / ores-compose tunnel"
}

resource "cloudflare_zero_trust_access_application" "laptop_ingress" {
  count = local.laptop_ingress_enabled && var.laptop_ingress_require_access ? 1 : 0

  zone_id          = local.zone_id
  name             = "gha-indie-worker laptop compose ingress"
  domain           = local.laptop_ingress_hostname
  type             = "self_hosted"
  session_duration = var.access_session_duration

  auto_redirect_to_identity  = false
  http_only_cookie_attribute = true
  same_site_cookie_attribute = "strict"
  enable_binding_cookie      = true
  app_launcher_visible       = false

  policies = [
    { id = cloudflare_zero_trust_access_policy.admin_operators.id, precedence = 1 },
    { id = cloudflare_zero_trust_access_policy.admin_deny_everyone_else.id, precedence = 2 },
  ]
}

output "laptop_ingress" {
  description = "Public laptop ingress contract. The Access AUD is needed by cloudflared's optional second JWT check."
  value = {
    enabled       = local.laptop_ingress_enabled
    hostname      = local.laptop_ingress_hostname
    tunnel_target = var.laptop_tunnel_cname != "" ? var.laptop_tunnel_cname : null
    access_aud = (
      local.laptop_ingress_enabled && var.laptop_ingress_require_access
      ? cloudflare_zero_trust_access_application.laptop_ingress[0].aud
      : null
    )
  }
}

output "edge_router_access_verification" {
  description = "Non-secret verifier inputs for ORESoftware/ores-edge-router. Feed these to Worker vars; do not derive issuer/audience from an unverified JWT."
  value = {
    team_domain = var.access_team_domain
    audiences = {
      admin     = cloudflare_zero_trust_access_application.admin["admin"].aud
      admin-api = cloudflare_zero_trust_access_application.admin["admin-api"].aud
      __status  = cloudflare_zero_trust_access_application.router_status.aud
    }
  }
}
