variable "zone_name" {
  description = "Apex domain for this org (1:1 with the GitHub org, the Neon org, the Supabase org, the GCP project and the Linear project)."
  type        = string
  default     = "indiebuild.dev"
}

variable "k8s_edge_ip" {
  description = "Unproxied A record target: the k8s-cluster edge that ores-edge-router probes and proxies to."
  type        = string
  default     = "95.217.171.250"
}

variable "github_pages_cname" {
  description = "GitHub Pages host serving the marketing site."
  type        = string
  default     = "gha-indie-worker.github.io"
}

variable "proxied_hosts" {
  description = "Labels that get a proxied A record so the edge-router Worker route has a DNS target."
  type        = list(string)
  default     = ["app", "user", "org", "m", "api", "auth", "admin", "admin-api", "api-admin"]
}
