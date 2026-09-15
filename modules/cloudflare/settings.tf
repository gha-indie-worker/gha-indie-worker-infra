# Zone-level transport posture.
#
# In provider v5 each setting is its own resource, so a setting this repository
# does not declare is left exactly as it is rather than being reset to a
# provider default — which is what you want when a zone is older than its
# Terraform.

resource "cloudflare_zone_setting" "ssl" {
  zone_id    = local.zone_id
  setting_id = "ssl"

  # "strict" = Cloudflare verifies the origin certificate. "full" accepts a
  # self-signed origin, which means an attacker between Cloudflare and the
  # origin can present any certificate. The k8s ingress and Cloud Run both have
  # real certificates, so there is no reason to accept less.
  value = "strict"
}

resource "cloudflare_zone_setting" "min_tls_version" {
  zone_id    = local.zone_id
  setting_id = "min_tls_version"
  value      = "1.2"
}

resource "cloudflare_zone_setting" "always_use_https" {
  zone_id    = local.zone_id
  setting_id = "always_use_https"
  value      = "on"
}

resource "cloudflare_zone_setting" "tls_1_3" {
  zone_id    = local.zone_id
  setting_id = "tls_1_3"
  value      = "on"
}

resource "cloudflare_zone_setting" "opportunistic_encryption" {
  zone_id    = local.zone_id
  setting_id = "opportunistic_encryption"
  value      = "on"
}

resource "cloudflare_zone_setting" "automatic_https_rewrites" {
  zone_id    = local.zone_id
  setting_id = "automatic_https_rewrites"
  value      = "on"
}

resource "cloudflare_zone_setting" "browser_check" {
  zone_id    = local.zone_id
  setting_id = "browser_check"
  value      = "on"
}

# HSTS. Raising max_age is easy; lowering it is not — a browser that has already
# seen a one-year header keeps refusing plaintext for a year regardless of what
# the zone says afterwards. include_subdomains commits EVERY future subdomain to
# HTTPS. preload is a separate, effectively permanent promise and stays off
# until someone deliberately submits the domain.
resource "cloudflare_zone_setting" "security_header" {
  zone_id    = local.zone_id
  setting_id = "security_header"

  value = {
    strict_transport_security = {
      enabled            = true
      max_age            = var.hsts_max_age
      include_subdomains = var.hsts_include_subdomains
      preload            = var.hsts_preload
      nosniff            = true
    }
  }
}
