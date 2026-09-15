variable "laptop_tunnel_cname" {
  type        = string
  default     = ""
  description = "Cloudflare Tunnel target (<uuid>.cfargotunnel.com) for the protected laptop ingress. Empty disables it."
}

variable "laptop_ingress_subdomain" {
  type        = string
  default     = "local"
  description = "Single DNS label used for the protected laptop ingress."
}

variable "laptop_ingress_require_access" {
  type        = bool
  default     = true
  description = "Require Cloudflare Access for the laptop ingress."
}

variable "access_team_domain" {
  type        = string
  default     = ""
  description = "Cloudflare Access issuer origin used by the edge-router verifier."
}
