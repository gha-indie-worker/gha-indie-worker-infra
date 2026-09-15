variable "neon_org_id" {
  type        = string
  default     = "org-misty-grass-10005930"
  description = "Neon org — 1:1 with the GitHub org gha-indie-worker."
}

variable "region_id" {
  type        = string
  default     = "aws-us-east-1"
  description = "Same region as the Cloud Run services (us-east1) to keep round-trips short."
}

variable "namespace" {
  type        = string
  default     = "gha_indie_worker"
  description = "Postgres role/schema prefix for this org."
}

variable "admin_private_networking_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    Neon private networking needs the Scale plan; every fleet org is on Free today, so this stays
    false and the admin project keeps refusing every connection. Flip it only together with the
    four-step acceptance in README.md.
  EOT
}
