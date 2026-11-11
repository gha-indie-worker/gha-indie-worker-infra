variable "local_status_tunnel_cname" {
  description = "Optional pre-provisioned MacBook status tunnel target. Empty disables builds.<zone>. This publishes only the read-only status origin."
  type        = string
  default     = ""

  validation {
    condition = var.local_status_tunnel_cname == "" || can(regex(
      "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\.cfargotunnel\\.com$", var.local_status_tunnel_cname
    ))
    error_message = "Expected an existing tunnel UUID followed by .cfargotunnel.com."
  }
}

resource "cloudflare_dns_record" "local_status" {
  count   = var.local_status_tunnel_cname == "" ? 0 : 1
  zone_id = data.cloudflare_zone.this.id
  name    = "builds.${var.zone_name}"
  type    = "CNAME"
  content = var.local_status_tunnel_cname
  proxied = true
  ttl     = 1
  comment = "Terraform-owned read-only IndieBuild local execution status"
}
