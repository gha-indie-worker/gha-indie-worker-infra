# All inputs for the indiebuild.dev Cloudflare edge. Nothing here is a secret:
# the API token comes from the CLOUDFLARE_API_TOKEN environment variable.

variable "cloudflare_account_id" {
  description = "Cloudflare account that owns the zone and the Zero Trust organisation."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be the 32-character hex account id."
  }
}

variable "zone_name" {
  description = "Apex domain served by Cloudflare. One org, one domain (AGENTS.md 1:1)."
  type        = string
  default     = "indiebuild.dev"
}

variable "zone_id" {
  description = "Zone id. Leave empty to look the zone up by name instead (one extra API read per plan)."
  type        = string
  default     = ""
}

variable "gcp_region" {
  description = "Region the Cloud Run fallbacks run in. Recorded in outputs so the edge-router config and this zone cannot disagree about where the fallback lives."
  type        = string
  default     = "us-central1"
}

# ---- origins ----------------------------------------------------------------

variable "k8s_origin_ip" {
  description = "Public IPv4 of the primary k8s-cluster ingress (Hetzner). Published UNPROXIED as origin-hetzner.<zone> so the edge Worker can reach the origin directly; per the ores-edge-router convention."
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.k8s_origin_ip))
    error_message = "k8s_origin_ip must be a bare IPv4 address."
  }
}

variable "aws_origin_ip" {
  description = "Public IPv4 of the secondary cluster edge (AWS), published UNPROXIED as origin-aws.<zone>. Set to \"\" while there is no AWS edge; the record is then not created."
  type        = string
  default     = ""
}

variable "proxied_origin_target" {
  description = "What the proxied product records point at. Defaults to origin-hetzner.<zone>: every product request is answered by the edge Worker, and this value is only what Cloudflare falls back to when no Worker route matches."
  type        = string
  default     = ""
}

variable "cloud_run_web_host" {
  description = "Cloud Run hostname of gha-indie-worker-web (e.g. gha-indie-worker-web-xxxxxxxxxx-uc.a.run.app). Not a DNS record here — the edge Worker uses it as the fallback origin. Exported so router.config.json and Terraform stay in step."
  type        = string
  default     = ""
}

variable "cloud_run_api_host" {
  description = "Cloud Run hostname of gha-indie-worker-api. Fallback origin for api.<zone>."
  type        = string
  default     = ""
}

variable "cloud_run_admin_web_host" {
  description = "Cloud Run hostname of gha-indie-worker-admin-web. INTERNAL ingress: it is deliberately NOT a fallback origin — admin has no public fallback."
  type        = string
  default     = ""
}

variable "cloud_run_admin_api_host" {
  description = "Cloud Run hostname of gha-indie-worker-admin-api. INTERNAL ingress; not a fallback origin."
  type        = string
  default     = ""
}

# ---- auth (managed elsewhere by default) ------------------------------------

variable "manage_auth_record" {
  description = "Create auth.<zone> here. Default false: shared-auth is a separate system (github.com/shared-auth) with its own gateway and its own Terraform, and two roots owning one record is how records get deleted by surprise."
  type        = bool
  default     = false
}

variable "auth_origin_target" {
  description = "CNAME target for auth.<zone> when manage_auth_record is true — the shared-auth gateway hostname."
  type        = string
  default     = ""
}

# ---- Cloudflare Access -------------------------------------------------------

variable "admin_access_emails" {
  description = "Email addresses allowed into admin.<zone> and admin-api.<zone>. An empty list is a hard error: an Access application with no allow rule is a padlock with no door behind it."
  type        = list(string)

  validation {
    condition     = length(var.admin_access_emails) > 0
    error_message = "admin_access_emails must name at least one operator."
  }
}

variable "admin_access_group_id" {
  description = "Optional Cloudflare Access group id (the group that maps to your IdP group). Empty means email allow-list only."
  type        = string
  default     = ""
}

variable "access_session_duration" {
  description = "Access session lifetime for the admin applications."
  type        = string
  default     = "24h"
}

variable "access_require_mfa" {
  description = "Require an MFA-backed authentication method for the admin applications."
  type        = bool
  default     = true
}

variable "router_status_host" {
  description = "Which subdomain's /__ores/router/status endpoint gets its own Access application. The endpoint exists on every host the Worker serves; one application is enough to keep the health table off the public internet, because Access matches host+path."
  type        = string
  default     = "api"
}

# ---- WAF / rate limiting / cache ---------------------------------------------

variable "api_rate_limit_requests" {
  description = "Requests per period, per client IP, allowed against api.<zone> before the rate-limiting rule blocks."
  type        = number
  default     = 600
}

variable "api_rate_limit_period" {
  description = "Rate-limit counting period in seconds. Cloudflare only accepts 10, 60, 120, 300, 600 or 3600."
  type        = number
  default     = 60

  validation {
    condition     = contains([10, 60, 120, 300, 600, 3600], var.api_rate_limit_period)
    error_message = "api_rate_limit_period must be one of 10, 60, 120, 300, 600, 3600."
  }
}

variable "api_rate_limit_mitigation_timeout" {
  description = "How long a client stays blocked once it trips the api rate limit, in seconds."
  type        = number
  default     = 60
}

variable "enable_bot_challenge" {
  description = "Managed-challenge known bots on the human-facing hosts (app./org./user.)."
  type        = bool
  default     = true
}

variable "bot_challenge_exempt_expression" {
  description = "Requests exempted from the bot challenge. The default keeps robots.txt, sitemaps and the well-known namespace answerable, because a challenged sitemap is an SEO outage. Widen it if you want verified search crawlers to reach marketing pages — see README.md."
  type        = string
  default     = "http.request.uri.path in {\"/robots.txt\" \"/sitemap.xml\"} or starts_with(http.request.uri.path, \"/.well-known/\")"
}

variable "immutable_asset_path" {
  description = "Wildcard path whose responses are content-addressed and may be cached forever."
  type        = string
  default     = "/assets/releases/*"
}

variable "immutable_asset_ttl_seconds" {
  description = "Edge and browser TTL for immutable_asset_path."
  type        = number
  default     = 31536000
}

# ---- TLS / transport posture --------------------------------------------------

variable "hsts_max_age" {
  description = "Strict-Transport-Security max-age in seconds. Start at 86400 while you are still moving hosts around; raise it once every subdomain is genuinely HTTPS-only, because HSTS is not reversible for clients that already saw it."
  type        = number
  default     = 31536000
}

variable "hsts_include_subdomains" {
  description = "Apply HSTS to every subdomain. Requires that EVERY host under the zone, including any future one, serves HTTPS."
  type        = bool
  default     = true
}

variable "hsts_preload" {
  description = "Send the preload token. Leave false until you actually intend to submit the domain to the browser preload list; the token is a promise browsers keep for years."
  type        = bool
  default     = false
}

# ---- email posture ------------------------------------------------------------

variable "manage_email_posture" {
  description = "Publish a hard no-mail posture for the apex: null MX, SPF -all and a p=reject DMARC record. indiebuild.dev sends no mail today, and a domain with no SPF/DMARC is a free spoofing target. Set false the day you start sending mail — before you send it."
  type        = bool
  default     = true
}

variable "dmarc_rua" {
  description = "Optional DMARC aggregate report address (mailto:...). Empty means no rua tag."
  type        = string
  default     = ""
}
