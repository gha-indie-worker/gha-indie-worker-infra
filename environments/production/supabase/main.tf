locals {
  supabase_projects = {
    canonical = {
      name        = "gha-indie-worker-canonical"
      region      = "us-east-2"
      project_ref = "mktabbhmldkewllyfizc"
    }
    auth = {
      name        = "gha-indie-worker-auth"
      region      = "us-east-2"
      project_ref = "qelemqszswrasjtgwfag"
    }
  }
}

module "supabase" {
  source = "../../../modules/supabase"

  organization_id    = var.supabase_organization_id
  manage_projects    = var.manage_supabase_projects
  projects           = local.supabase_projects
  database_passwords = var.supabase_database_passwords
}

output "project_refs" { value = module.supabase.project_refs }
