data "cloudflare_zone" "this" {
  filter = {
    name = var.zone_name
  }
}

# What the Worker probes (/healthz + /readyz) and proxies to while healthy.
# Unproxied on purpose: the Worker needs the real origin, not Cloudflare's edge.
resource "cloudflare_dns_record" "origin_hetzner" {
  zone_id = data.cloudflare_zone.this.id
  name    = "origin-hetzner.${var.zone_name}"
  type    = "A"
  ttl     = 300
  content = var.k8s_edge_ip
  proxied = false
  comment = "ores-edge-router origin (unproxied): health-probed, proxied to while /healthz+/readyz pass"
}

# One proxied record per public host. The Worker route (owned by ../edge-router/wrangler.toml)
# intercepts these before they reach the origin; the record only has to exist and be orange-clouded.
resource "cloudflare_dns_record" "host" {
  for_each = toset(var.proxied_hosts)

  zone_id = data.cloudflare_zone.this.id
  name    = "${each.value}.${var.zone_name}"
  type    = "A"
  ttl     = 1 # required when proxied
  content = var.k8s_edge_ip
  proxied = true
  comment = "ores-edge-router route target for ${each.value}.${var.zone_name} (k8s primary, Cloud Run fallback)"
}

# Marketing site is static and does not go through the Worker.
resource "cloudflare_dns_record" "www" {
  zone_id = data.cloudflare_zone.this.id
  name    = "www.${var.zone_name}"
  type    = "CNAME"
  ttl     = 1
  content = var.github_pages_cname
  proxied = true
  comment = "Astro marketing site on GitHub Pages"
}

resource "cloudflare_dns_record" "apex" {
  zone_id = data.cloudflare_zone.this.id
  name    = var.zone_name
  type    = "CNAME"
  ttl     = 1
  content = var.github_pages_cname
  proxied = true
  comment = "Apex -> marketing site (CNAME flattening)"
}
