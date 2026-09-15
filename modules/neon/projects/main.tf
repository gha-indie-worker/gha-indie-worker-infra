locals {
  # The three projects the 2026-09-05 provisioning pass created for this org. Ids are recorded so
  # terraform adopts the existing projects (tofu import) rather than creating duplicates.
  projects = {
    canonical = { id = "crimson-cell-39815049", db = "canonical", role = "app", plane = "product" }
    auth      = { id = "fancy-brook-94928157", db = "auth", role = "auth", plane = "product" }
    admin     = { id = "round-butterfly-64996380", db = "admin", role = "admin", plane = "admin" }
  }
}

resource "neon_project" "this" {
  for_each = local.projects

  name      = "gha-indie-worker-${each.key}"
  region_id = var.region_id
  org_id    = var.neon_org_id

  # History retention: 7 days on product data (PITR for an operator mistake), 30 on the admin
  # plane, where the audit trail matters more than the storage cost.
  history_retention_seconds = each.value.plane == "admin" ? 2592000 : 604800

  lifecycle {
    # These projects already exist; never let a plan destroy one.
    prevent_destroy = true
  }
}

resource "neon_role" "owner" {
  for_each = local.projects

  project_id = neon_project.this[each.key].id
  branch_id  = neon_project.this[each.key].default_branch_id
  name       = "${var.namespace}_${each.value.role}"
}

resource "neon_database" "db" {
  for_each = local.projects

  project_id = neon_project.this[each.key].id
  branch_id  = neon_project.this[each.key].default_branch_id
  name       = each.value.db
  owner_name = neon_role.owner[each.key].name
}
