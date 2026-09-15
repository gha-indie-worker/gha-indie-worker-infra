# The admin project's endpoint stays closed until private networking exists. Encoding it as a
# guarded resource means "closed" is the declared state, not an accident someone later "fixes".

resource "neon_endpoint" "admin_private" {
  count = var.admin_private_networking_enabled ? 1 : 0

  project_id = neon_project.this["admin"].id
  branch_id  = neon_project.this["admin"].default_branch_id
  type       = "read_write"

  # Autosuspend fast: the admin plane is used by a handful of humans, not by traffic.
  suspend_timeout_seconds = 60
}

check "admin_stays_closed_until_accepted" {
  assert {
    condition     = var.admin_private_networking_enabled == false || var.region_id == "aws-us-east-1"
    error_message = "Private networking may only be enabled in the region whose VPC endpoint was accepted."
  }
}

output "admin_project_id" {
  value       = neon_project.this["admin"].id
  description = "Admin plane only. The product services must never be given this project's connection string."
}

output "product_project_ids" {
  value = {
    canonical = neon_project.this["canonical"].id
    auth      = neon_project.this["auth"].id
  }
}
