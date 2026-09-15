variable "project_id" {
  type        = string
  default     = "gha-indie-worker"
  description = "GCP project — 1:1 with the GitHub org."
}

variable "region" {
  type        = string
  default     = "us-east1"
  description = "Matches the Neon region (aws-us-east-1) to keep DB round-trips short."
}

variable "domain" {
  type    = string
  default = "indiebuild.dev"
}

variable "image_web" {
  type        = string
  description = "Full image ref for the web server, PINNED BY DIGEST (…@sha256:…)."
}

variable "image_api" {
  type        = string
  description = "Full image ref for the API server, pinned by digest."
}

variable "image_admin_web" {
  type        = string
  description = "Full image ref for the admin web server, pinned by digest."
}

variable "image_admin_api" {
  type        = string
  description = "Full image ref for the admin API server, pinned by digest."
}

variable "image_mcp" {
  type        = string
  description = "Full image ref for the MCP server, pinned by digest."
}

variable "admin_allowlist" {
  type        = string
  description = "Comma-separated super-admin UUIDs (GHA_INDIE_WORKER_ADMIN_ALLOWLIST)."
  sensitive   = true
}

variable "min_instances_product" {
  type        = number
  default     = 0
  description = "0 = scale to zero. The fallback is cold most of the time; the edge router's in-request retry absorbs the cold start."
}

locals {
  # Every image must be digest-pinned: a tag can be moved after review.
  images = {
    web       = var.image_web
    api       = var.image_api
    admin_web = var.image_admin_web
    admin_api = var.image_admin_api
    mcp       = var.image_mcp
  }
}

check "images_are_digest_pinned" {
  assert {
    condition     = alltrue([for _, i in local.images : can(regex("@sha256:[0-9a-f]{64}$", i))])
    error_message = "Every Cloud Run image must be pinned by digest (…@sha256:<64 hex>), not by tag."
  }
}
