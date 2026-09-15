locals {
  indiebuild_ci_control_plane = {
    persistence_project_key = "canonical"
    persistence_project_id  = local.projects.canonical.id
    schema_namespace        = var.namespace
    webhook_state           = "stateless"
  }
}

check "indiebuild_ci_reuses_existing_neon_topology" {
  assert {
    condition = (
      length(local.projects) == 3 &&
      contains(keys(local.projects), local.indiebuild_ci_control_plane.persistence_project_key) &&
      local.indiebuild_ci_control_plane.persistence_project_id == "crimson-cell-39815049"
    )
    error_message = "PR CI must reuse the existing canonical/auth/admin Neon topology; do not create a shadow CI project."
  }
}

output "indiebuild_ci_control_plane" {
  description = "Non-secret desired state for the external PR-CI persistence boundary."
  value       = local.indiebuild_ci_control_plane
}
