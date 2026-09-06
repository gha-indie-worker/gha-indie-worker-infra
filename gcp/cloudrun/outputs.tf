output "fallback_urls" {
  description = "Paste these into cloudflare/edge-router/router.config.json, replacing the *-REPLACE.a.run.app placeholders."
  value = {
    web = google_cloud_run_v2_service.web.uri
    api = google_cloud_run_v2_service.api.uri
  }
}

output "admin_urls" {
  description = "Internal-only; never goes in a public router config."
  value = {
    admin_api = google_cloud_run_v2_service.admin_api.uri
    admin_web = google_cloud_run_v2_service.admin_web.uri
    mcp       = google_cloud_run_v2_service.mcp.uri
  }
}

output "nat_addresses" {
  description = "Allow-list these at Neon/Supabase: the admin address is the ONLY one the admin projects should accept."
  value = {
    product = google_compute_address.nat_product.address
    admin   = google_compute_address.nat_admin.address
  }
}
