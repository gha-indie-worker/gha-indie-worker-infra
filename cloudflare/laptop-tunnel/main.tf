data "cloudflare_zone" "indiebuild" {
  filter = {
    name = var.zone_name
  }
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
        service  = var.origin_service
      },
      {
        service = "http_status:404"
      }
    ]
  }
}

resource "cloudflare_dns_record" "laptop_ci" {
  zone_id = data.cloudflare_zone.indiebuild.id
  name    = var.hostname
  type    = "CNAME"
  ttl     = 1
  content = "${cloudflare_zero_trust_tunnel_cloudflared.laptop_ci.id}.cfargotunnel.com"
  proxied = true
  comment = "gha-indie-worker laptop CI ingress via Cloudflare Tunnel"
}
