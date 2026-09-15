variable "laptop_tunnel_cname" {
  description = "Cloudflare Tunnel target (<uuid>.cfargotunnel.com) for the laptop gateway. Empty disables public laptop ingress."
  type        = string
  default     = ""

  validation {
    condition     = var.laptop_tunnel_cname == "" || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\\.cfargotunnel\\.com$", var.laptop_tunnel_cname))
    error_message = "laptop_tunnel_cname must be empty or <uuid>.cfargotunnel.com."
  }
}

variable "laptop_ingress_subdomain" {
  description = "First-level hostname used for protected laptop path routing."
  type        = string
  default     = "local"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.laptop_ingress_subdomain)) && length(var.laptop_ingress_subdomain) <= 63
    error_message = "laptop_ingress_subdomain must be one lowercase DNS label of at most 63 bytes."
  }
}

variable "laptop_ingress_require_access" {
  description = "Protect the laptop ingress with Cloudflare Access."
  type        = bool
  default     = true
}

variable "access_team_domain" {
  description = "Cloudflare Access issuer origin used by the hardened edge verifier."
  type        = string
  default     = ""

  validation {
    condition     = var.access_team_domain == "" || can(regex("^https://[a-z0-9-]+\\.cloudflareaccess\\.com$", var.access_team_domain))
    error_message = "access_team_domain must be empty or an https://<team>.cloudflareaccess.com origin."
  }
}
