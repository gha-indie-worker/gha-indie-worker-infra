moved {
  from = data.cloudflare_zone.this
  to   = module.cloudflare_dns.data.cloudflare_zone.this
}

moved {
  from = cloudflare_dns_record.origin_hetzner
  to   = module.cloudflare_dns.cloudflare_dns_record.origin_hetzner
}

moved {
  from = cloudflare_dns_record.host
  to   = module.cloudflare_dns.cloudflare_dns_record.host
}

moved {
  from = cloudflare_dns_record.www
  to   = module.cloudflare_dns.cloudflare_dns_record.www
}

moved {
  from = cloudflare_dns_record.apex
  to   = module.cloudflare_dns.cloudflare_dns_record.apex
}
