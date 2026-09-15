moved {
  from = data.cloudflare_zone.by_name
  to   = module.cloudflare_platform.data.cloudflare_zone.by_name
}

moved {
  from = cloudflare_zero_trust_access_policy.admin_operators
  to   = module.cloudflare_platform.cloudflare_zero_trust_access_policy.admin_operators
}

moved {
  from = cloudflare_zero_trust_access_policy.admin_deny_everyone_else
  to   = module.cloudflare_platform.cloudflare_zero_trust_access_policy.admin_deny_everyone_else
}

moved {
  from = cloudflare_zero_trust_access_application.admin
  to   = module.cloudflare_platform.cloudflare_zero_trust_access_application.admin
}

moved {
  from = cloudflare_zero_trust_access_application.router_status
  to   = module.cloudflare_platform.cloudflare_zero_trust_access_application.router_status
}

moved {
  from = cloudflare_dns_record.product
  to   = module.cloudflare_platform.cloudflare_dns_record.product
}

moved {
  from = cloudflare_dns_record.origin_hetzner
  to   = module.cloudflare_platform.cloudflare_dns_record.origin_hetzner
}

moved {
  from = cloudflare_dns_record.origin_aws
  to   = module.cloudflare_platform.cloudflare_dns_record.origin_aws
}

moved {
  from = cloudflare_dns_record.auth
  to   = module.cloudflare_platform.cloudflare_dns_record.auth
}

moved {
  from = cloudflare_dns_record.null_mx
  to   = module.cloudflare_platform.cloudflare_dns_record.null_mx
}

moved {
  from = cloudflare_dns_record.spf
  to   = module.cloudflare_platform.cloudflare_dns_record.spf
}

moved {
  from = cloudflare_dns_record.dmarc
  to   = module.cloudflare_platform.cloudflare_dns_record.dmarc
}

moved {
  from = cloudflare_dns_record.laptop_ingress
  to   = module.cloudflare_platform.cloudflare_dns_record.laptop_ingress
}

moved {
  from = cloudflare_zero_trust_access_application.laptop_ingress
  to   = module.cloudflare_platform.cloudflare_zero_trust_access_application.laptop_ingress
}

moved {
  from = cloudflare_ruleset.api_rate_limit
  to   = module.cloudflare_platform.cloudflare_ruleset.api_rate_limit
}

moved {
  from = cloudflare_ruleset.zone_firewall_custom
  to   = module.cloudflare_platform.cloudflare_ruleset.zone_firewall_custom
}

moved {
  from = cloudflare_ruleset.cache
  to   = module.cloudflare_platform.cloudflare_ruleset.cache
}

moved {
  from = cloudflare_zone_setting.ssl
  to   = module.cloudflare_platform.cloudflare_zone_setting.ssl
}

moved {
  from = cloudflare_zone_setting.min_tls_version
  to   = module.cloudflare_platform.cloudflare_zone_setting.min_tls_version
}

moved {
  from = cloudflare_zone_setting.always_use_https
  to   = module.cloudflare_platform.cloudflare_zone_setting.always_use_https
}

moved {
  from = cloudflare_zone_setting.tls_1_3
  to   = module.cloudflare_platform.cloudflare_zone_setting.tls_1_3
}

moved {
  from = cloudflare_zone_setting.opportunistic_encryption
  to   = module.cloudflare_platform.cloudflare_zone_setting.opportunistic_encryption
}

moved {
  from = cloudflare_zone_setting.automatic_https_rewrites
  to   = module.cloudflare_platform.cloudflare_zone_setting.automatic_https_rewrites
}

moved {
  from = cloudflare_zone_setting.browser_check
  to   = module.cloudflare_platform.cloudflare_zone_setting.browser_check
}

moved {
  from = cloudflare_zone_setting.security_header
  to   = module.cloudflare_platform.cloudflare_zone_setting.security_header
}
