module "cloudflare_dns" {
  source = "../../../modules/cloudflare/dns"

  zone_name          = var.zone_name
  k8s_edge_ip        = var.k8s_edge_ip
  github_pages_cname = var.github_pages_cname
  proxied_hosts      = var.proxied_hosts
}
