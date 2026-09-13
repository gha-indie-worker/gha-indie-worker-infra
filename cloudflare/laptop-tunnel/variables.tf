variable "cloudflare_account_id" {
  description = "Cloudflare account id that owns indiebuild.dev"
  type        = string
}

variable "zone_name" {
  description = "Cloudflare zone containing the laptop CI hostname"
  type        = string
  default     = "indiebuild.dev"
}

variable "hostname" {
  description = "Public hostname routed through the laptop tunnel"
  type        = string
  default     = "ci-laptop.indiebuild.dev"
}

variable "tunnel_name" {
  description = "Cloudflare Tunnel name"
  type        = string
  default     = "indiebuild-laptop-ci"
}

variable "origin_service" {
  description = "Origin reached by cloudflared on the laptop"
  type        = string
  default     = "http://127.0.0.1:8100"
}
