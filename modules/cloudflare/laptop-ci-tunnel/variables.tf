variable "cloudflare_account_id" {
  description = "Cloudflare account id that owns the remotely managed laptop CI tunnel."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id must be a 32-character lowercase hex id."
  }
}

variable "zone_id" {
  description = "Cloudflare zone id for the laptop CI hostname."
  type        = string

  validation {
    condition     = length(trimspace(var.zone_id)) > 0
    error_message = "zone_id must not be empty."
  }
}

variable "hostname" {
  description = "Public webhook hostname for the laptop CI worker. This is intentionally distinct from the Access-protected local developer hostname."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", var.hostname)) && length(var.hostname) <= 253
    error_message = "hostname must be a lowercase DNS hostname."
  }
}

variable "tunnel_name" {
  description = "Name of the remotely managed Cloudflare Tunnel."
  type        = string

  validation {
    condition     = length(trimspace(var.tunnel_name)) >= 3
    error_message = "tunnel_name must contain at least three non-whitespace characters."
  }
}

variable "origin_port" {
  description = "Loopback port exposed by the local gha-indie-worker webhook listener. The module never accepts an arbitrary origin host."
  type        = number
  default     = 8100

  validation {
    condition     = var.origin_port >= 1 && var.origin_port <= 65535 && floor(var.origin_port) == var.origin_port
    error_message = "origin_port must be an integer from 1 through 65535."
  }
}
