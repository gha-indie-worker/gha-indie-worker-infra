moved {
  from = neon_project.this
  to   = module.neon_projects.neon_project.this
}

moved {
  from = neon_role.owner
  to   = module.neon_projects.neon_role.owner
}

moved {
  from = neon_database.db
  to   = module.neon_projects.neon_database.db
}

moved {
  from = neon_endpoint.admin_private
  to   = module.neon_projects.neon_endpoint.admin_private
}
