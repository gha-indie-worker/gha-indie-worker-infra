output "tunnel_id" {
  description = "Cloudflare Tunnel UUID. This is not the runtime tunnel credential/token."
  value       = cloudflare_zero_trust_tunnel_cloudflared.laptop_ci.id
}

output "tunnel_name" {
  description = "Cloudflare Tunnel name."
  value       = cloudflare_zero_trust_tunnel_cloudflared.laptop_ci.name
}

output "hostname" {
  description = "Public webhook hostname for the laptop CI worker."
  value       = var.hostname
}

output "origin_service" {
  description = "Non-secret loopback origin configured for cloudflared."
  value       = local.origin_service
}
