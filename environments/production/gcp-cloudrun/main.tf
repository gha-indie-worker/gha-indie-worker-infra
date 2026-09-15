module "gcp_cloudrun" {
  source = "../../../modules/gcp/cloudrun"

  project_id            = var.project_id
  region                = var.region
  domain                = var.domain
  image_web             = var.image_web
  image_api             = var.image_api
  image_admin_web       = var.image_admin_web
  image_admin_api       = var.image_admin_api
  image_mcp             = var.image_mcp
  admin_allowlist       = var.admin_allowlist
  min_instances_product = var.min_instances_product
}
