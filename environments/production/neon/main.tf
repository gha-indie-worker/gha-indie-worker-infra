module "neon_projects" {
  source = "../../../modules/neon/projects"

  neon_org_id                       = var.neon_org_id
  region_id                         = var.region_id
  namespace                         = var.namespace
  admin_private_networking_enabled  = var.admin_private_networking_enabled
}
