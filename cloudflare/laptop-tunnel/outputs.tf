output "tunnel_id" {
  description = "Cloudflare Tunnel UUID used to obtain a runtime token"
  value       = cloudflare_zero_trust_tunnel_cloudflared.laptop_ci.id
}

output "hostname" {
  description = "Public hostname for the laptop worker"
  value       = var.hostname
}

output "tunnel_name" {
  description = "Cloudflare Tunnel name"
  value       = cloudflare_zero_trust_tunnel_cloudflared.laptop_ci.name
}
