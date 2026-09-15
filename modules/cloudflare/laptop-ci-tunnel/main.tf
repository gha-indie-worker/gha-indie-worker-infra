locals {
  # Keep the tunnel origin structurally confined to local loopback. Request or
  # environment data cannot turn this Terraform contract into an arbitrary proxy.
  origin_service = "http://127.0.0.1:${var.origin_port}"
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "laptop_ci" {
  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "laptop_ci" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.laptop_ci.id

  config = {
    ingress = [
      {
        hostname = var.hostname
        service  = local.origin_service
      },
      {
        service = "http_status:404"
      }
    ]
  }
}

resource "cloudflare_dns_record" "laptop_ci" {
  zone_id = var.zone_id
  name    = var.hostname
  type    = "CNAME"
  ttl     = 1
  content = "${cloudflare_zero_trust_tunnel_cloudflared.laptop_ci.id}.cfargotunnel.com"
  proxied = true
  comment = "gha-indie-worker laptop CI webhook ingress; worker HMAC remains an independent auth gate"
}
