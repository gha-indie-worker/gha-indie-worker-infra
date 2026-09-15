module "cloudflare" {
  source = "../../../modules/cloudflare"

  cloudflare_account_id                 = var.cloudflare_account_id
  zone_name                             = var.zone_name
  zone_id                               = var.zone_id
  gcp_region                            = var.gcp_region
  k8s_origin_ip                         = var.k8s_origin_ip
  aws_origin_ip                         = var.aws_origin_ip
  proxied_origin_target                 = var.proxied_origin_target
  cloud_run_web_host                    = var.cloud_run_web_host
  cloud_run_api_host                    = var.cloud_run_api_host
  cloud_run_admin_web_host              = var.cloud_run_admin_web_host
  cloud_run_admin_api_host              = var.cloud_run_admin_api_host
  manage_auth_record                    = var.manage_auth_record
  auth_origin_target                    = var.auth_origin_target
  admin_access_emails                   = var.admin_access_emails
  admin_access_group_id                 = var.admin_access_group_id
  access_session_duration               = var.access_session_duration
  access_require_mfa                    = var.access_require_mfa
  router_status_host                    = var.router_status_host
  api_rate_limit_requests               = var.api_rate_limit_requests
  api_rate_limit_period                 = var.api_rate_limit_period
  api_rate_limit_mitigation_timeout     = var.api_rate_limit_mitigation_timeout
  enable_bot_challenge                  = var.enable_bot_challenge
  bot_challenge_exempt_expression       = var.bot_challenge_exempt_expression
  immutable_asset_path                  = var.immutable_asset_path
  immutable_asset_ttl_seconds           = var.immutable_asset_ttl_seconds
  hsts_max_age                          = var.hsts_max_age
  hsts_include_subdomains               = var.hsts_include_subdomains
  hsts_preload                          = var.hsts_preload
  manage_email_posture                  = var.manage_email_posture
  dmarc_rua                             = var.dmarc_rua
}

output "zone_id" { value = module.cloudflare.zone_id }
output "zone_name" { value = module.cloudflare.zone_name }
output "product_hostnames" { value = module.cloudflare.product_hostnames }
output "origin_hostnames" { value = module.cloudflare.origin_hostnames }
output "edge_router_inputs" { value = module.cloudflare.edge_router_inputs }
output "access_application_ids" { value = module.cloudflare.access_application_ids }
output "access_policy_ids" { value = module.cloudflare.access_policy_ids }
output "ruleset_ids" { value = module.cloudflare.ruleset_ids }
output "worker_routes_are_not_managed_here" { value = module.cloudflare.worker_routes_are_not_managed_here }
