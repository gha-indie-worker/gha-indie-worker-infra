# DNS for indiebuild.dev.
#
# THE SPLIT (identical to the one ores-edge-router documents):
#   * DNS records, Access applications, WAF/rate-limit/cache rulesets and zone
#     settings live HERE, in Terraform.
#   * Worker **routes** live in cloudflare/edge-router/wrangler.toml, which is
#     rendered from router.config.json and applied by `wrangler deploy`.
# Terraform never declares a route and wrangler never declares a record. A route
# and a record for the same host are two independent objects; when both roots
# claim both, each apply silently reverts the other.
#
# Records for app/user/org/m/api/admin/admin-api are PROXIED (orange cloud) so
# the Worker runs and the origin IP is never exposed. origin-hetzner and
# origin-aws are UNPROXIED on purpose — they are the addresses the Worker itself
# connects to, and proxying them would loop Cloudflare through Cloudflare.

data "cloudflare_zone" "by_name" {
  count = var.zone_id == "" ? 1 : 0

  filter = {
    name    = var.zone_name
    account = { id = var.cloudflare_account_id }
  }
}

locals {
  zone_id = var.zone_id != "" ? var.zone_id : data.cloudflare_zone.by_name[0].id

  origin_hetzner_fqdn = "origin-hetzner.${var.zone_name}"
  origin_aws_fqdn     = "origin-aws.${var.zone_name}"

  # What the proxied records point at when no Worker route matches.
  proxied_target = var.proxied_origin_target != "" ? var.proxied_origin_target : local.origin_hetzner_fqdn

  # The product surface. One web service answers app/user/org/m by Host header;
  # api is the JSON API; admin and admin-api are behind Access AND internal
  # ingress. Every one of them is served by the edge Worker.
  product_hosts = {
    app       = "primary product UI (web-server.rs, host-routed)"
    user      = "B2C surface (web-server.rs, host-routed)"
    org       = "B2B surface (web-server.rs, host-routed)"
    m         = "mobile web (web-server.rs, host-routed)"
    api       = "JSON API and /v1/ws (api-server.rs)"
    admin     = "admin console — Cloudflare Access + admin VPC only"
    admin-api = "admin JSON API — Cloudflare Access + admin VPC only"
  }
}

resource "cloudflare_dns_record" "product" {
  for_each = local.product_hosts

  zone_id = local.zone_id
  name    = "${each.key}.${var.zone_name}"
  type    = "CNAME"
  content = local.proxied_target
  proxied = true
  ttl     = 1 # required to be 1 ("automatic") whenever proxied = true
  comment = "managed by terraform/cloudflare — ${each.value}"
}

# ---- unproxied origins -------------------------------------------------------
# The Worker fetches these directly and sends the public hostname as `Host`, so
# the cluster ingress routes by host exactly as it does for direct traffic.

resource "cloudflare_dns_record" "origin_hetzner" {
  zone_id = local.zone_id
  name    = local.origin_hetzner_fqdn
  type    = "A"
  content = var.k8s_origin_ip
  proxied = false
  ttl     = 300
  comment = "managed by terraform/cloudflare — UNPROXIED primary cluster edge; the edge Worker's origin"
}

resource "cloudflare_dns_record" "origin_aws" {
  count = var.aws_origin_ip != "" ? 1 : 0

  zone_id = local.zone_id
  name    = local.origin_aws_fqdn
  type    = "A"
  content = var.aws_origin_ip
  proxied = false
  ttl     = 300
  comment = "managed by terraform/cloudflare — UNPROXIED secondary cluster edge"
}

# ---- auth.<zone> -------------------------------------------------------------
# shared-auth is an external system with its own infrastructure repository. By
# default this root does not touch its record; flip manage_auth_record only if
# this zone becomes the single owner of it.

resource "cloudflare_dns_record" "auth" {
  count = var.manage_auth_record ? 1 : 0

  zone_id = local.zone_id
  name    = "auth.${var.zone_name}"
  type    = "CNAME"
  content = var.auth_origin_target
  proxied = true
  ttl     = 1
  comment = "managed by terraform/cloudflare — shared-auth gateway (normally managed in shared-auth-infra)"

  lifecycle {
    precondition {
      condition     = var.auth_origin_target != ""
      error_message = "manage_auth_record = true requires auth_origin_target to name the shared-auth gateway."
    }
  }
}

# ---- email posture -----------------------------------------------------------
# indiebuild.dev sends and receives no mail. Publishing a null MX, an SPF record
# that authorises nobody and a p=reject DMARC record is what stops the domain
# being used to spoof us. These are the three records to REMOVE FIRST, not to
# work around, the day the product starts sending mail.

resource "cloudflare_dns_record" "null_mx" {
  count = var.manage_email_posture ? 1 : 0

  zone_id  = local.zone_id
  name     = var.zone_name
  type     = "MX"
  content  = "."
  priority = 0
  ttl      = 3600
  comment  = "managed by terraform/cloudflare — RFC 7505 null MX: this domain accepts no mail"
}

resource "cloudflare_dns_record" "spf" {
  count = var.manage_email_posture ? 1 : 0

  zone_id = local.zone_id
  name    = var.zone_name
  type    = "TXT"
  content = "\"v=spf1 -all\""
  ttl     = 3600
  comment = "managed by terraform/cloudflare — no host is authorised to send mail as this domain"
}

resource "cloudflare_dns_record" "dmarc" {
  count = var.manage_email_posture ? 1 : 0

  zone_id = local.zone_id
  name    = "_dmarc.${var.zone_name}"
  type    = "TXT"
  content = "\"v=DMARC1; p=reject; sp=reject; adkim=s; aspf=s;${var.dmarc_rua != "" ? " rua=${var.dmarc_rua};" : ""}\""
  ttl     = 3600
  comment = "managed by terraform/cloudflare — reject anything claiming to be from this domain"
}
