module "neon" {
  source = "../../../modules/neon"

  neon_org_id                      = var.neon_org_id
  region_id                        = var.region_id
  namespace                        = var.namespace
  admin_private_networking_enabled = var.admin_private_networking_enabled
}

output "admin_project_id" { value = module.neon.admin_project_id }
output "product_project_ids" { value = module.neon.product_project_ids }
