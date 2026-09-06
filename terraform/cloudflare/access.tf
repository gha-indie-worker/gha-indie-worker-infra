# Cloudflare Zero Trust Access.
#
# Access is the OUTER of two independent gates on the admin plane:
#   1. here — no request reaches the admin origin without a valid Access
#      assertion (identity + MFA), and
#   2. in GCP — the admin Cloud Run services have INGRESS_TRAFFIC_INTERNAL_ONLY
#      and no allUsers invoker binding, so even a bypassed edge reaches nothing.
# The edge Worker adds a third: hosts marked access = "cloudflare-access" in
# router.config.json are refused when the assertion header is absent.
#
# Losing any one of these must not open the admin plane. That is why the Access
# policy is not the only thing standing between the internet and admin data.

locals {
  # One allow rule per operator email, plus the IdP-backed group when one is set.
  admin_include = concat(
    [for email in var.admin_access_emails : { email = { email = email } }],
    var.admin_access_group_id != "" ? [{ group = { id = var.admin_access_group_id } }] : []
  )

  # "Require" is an AND over every entry, applied on top of "include".
  admin_require = var.access_require_mfa ? [{ auth_method = { auth_method = "mfa" } }] : []

  admin_apps = {
    admin = {
      name   = "gha-indie-worker admin console"
      domain = "admin.${var.zone_name}"
    }
    admin-api = {
      name   = "gha-indie-worker admin API"
      domain = "admin-api.${var.zone_name}"
    }
  }
}

resource "cloudflare_zero_trust_access_policy" "admin_operators" {
  account_id = var.cloudflare_account_id
  name       = "gha-indie-worker admin operators"
  decision   = "allow"

  include = local.admin_include
  require = local.admin_require

  session_duration = var.access_session_duration
}

# Everything that is not explicitly allowed is denied by Access itself, but an
# explicit terminal deny makes that visible in the Zero Trust UI and survives
# someone adding a second, looser allow policy above it.
resource "cloudflare_zero_trust_access_policy" "admin_deny_everyone_else" {
  account_id = var.cloudflare_account_id
  name       = "gha-indie-worker admin — deny everyone else"
  decision   = "deny"

  include = [{ everyone = {} }]
}

resource "cloudflare_zero_trust_access_application" "admin" {
  for_each = local.admin_apps

  zone_id          = local.zone_id
  name             = each.value.name
  domain           = each.value.domain
  type             = "self_hosted"
  session_duration = var.access_session_duration

  # The Access cookie is host-scoped, script-invisible and not replayable on a
  # different device, and the app is not advertised in the App Launcher.
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

# ---- the router's own status endpoint ---------------------------------------
# GET /__ores/router/status dumps the edge health table: which origin each host
# is currently using and why. That is operational detail about our topology, so
# it gets the same identity gate as the admin console. Access matches on
# host + path, so one application covers the endpoint on the host operators
# actually curl.

resource "cloudflare_zero_trust_access_application" "router_status" {
  zone_id          = local.zone_id
  name             = "gha-indie-worker edge router status"
  domain           = "${var.router_status_host}.${var.zone_name}/__ores/router/status"
  type             = "self_hosted"
  session_duration = var.access_session_duration

  auto_redirect_to_identity  = false
  http_only_cookie_attribute = true
  app_launcher_visible       = false

  policies = [
    { id = cloudflare_zero_trust_access_policy.admin_operators.id, precedence = 1 },
    { id = cloudflare_zero_trust_access_policy.admin_deny_everyone_else.id, precedence = 2 },
  ]
}
