output "zone_id" {
  value       = data.cloudflare_zone.this.id
  description = "Cloudflare zone id for indiebuild.dev; consumed by the edge-router deploy workflow."
}

output "proxied_hostnames" {
  value       = [for h in var.proxied_hosts : "${h}.${var.zone_name}"]
  description = "Hosts the edge-router Worker must claim routes for."
}
