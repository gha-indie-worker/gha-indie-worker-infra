# Optional signed-webhook ingress for an intermittently-online laptop CI worker.
# This belongs to the existing Cloudflare platform state; PR #13 never landed,
# so there is no separate production state history to preserve for this resource.

variable "enable_laptop_ci_tunnel" {
  description = "Create the remotely managed ci-laptop tunnel/DNS resources. Keep false until the worker's exact-SHA/HMAC acceptance gate is ready."
  type        = bool
  default     = false
}

variable "laptop_ci_hostname" {
  description = "Public webhook hostname for the laptop CI worker."
  type        = string
  default     = "ci-laptop.indiebuild.dev"
}

variable "laptop_ci_tunnel_name" {
  description = "Cloudflare Tunnel name for the laptop CI worker."
  type        = string
  default     = "indiebuild-laptop-ci"
}

variable "laptop_ci_origin_port" {
  description = "Loopback port used by the local worker webhook listener."
  type        = number
  default     = 8100

  validation {
    condition     = var.laptop_ci_origin_port >= 1 && var.laptop_ci_origin_port <= 65535 && floor(var.laptop_ci_origin_port) == var.laptop_ci_origin_port
    error_message = "laptop_ci_origin_port must be an integer from 1 through 65535."
  }
}

module "laptop_ci_tunnel" {
  count  = var.enable_laptop_ci_tunnel ? 1 : 0
  source = "../../../modules/cloudflare/laptop-ci-tunnel"

  cloudflare_account_id = var.cloudflare_account_id
  zone_id               = module.cloudflare_platform.zone_id
  hostname              = var.laptop_ci_hostname
  tunnel_name           = var.laptop_ci_tunnel_name
  origin_port           = var.laptop_ci_origin_port
}

output "laptop_ci_tunnel" {
  description = "Non-secret laptop CI tunnel metadata; null while the optional ingress is disabled."
  value = var.enable_laptop_ci_tunnel ? {
    id             = module.laptop_ci_tunnel[0].tunnel_id
    name           = module.laptop_ci_tunnel[0].tunnel_name
    hostname       = module.laptop_ci_tunnel[0].hostname
    origin_service = module.laptop_ci_tunnel[0].origin_service
  } : null
}
