terraform {
  required_version = ">= 1.9.0"
  required_providers {
    supabase = {
      source  = "supabase/supabase"
      version = ">= 1.10.1, < 2.0.0"
    }
  }
}

variable "organization_id" {
  type        = string
  description = "Supabase organization id/slug."
}

variable "manage_projects" {
  type        = bool
  default     = false
  description = "Create/manage project resources only after existing projects have been imported into the environment state."
}

variable "projects" {
  type = map(object({
    name          = string
    region        = string
    project_ref   = string
    instance_size = optional(string, "micro")
  }))
  description = "Known Supabase projects. project_ref is the existing project reference used while manage_projects=false."
}

variable "database_passwords" {
  type        = map(string)
  sensitive   = true
  default     = {}
  description = "Database passwords supplied only from encrypted runtime inputs when project management is enabled."
}

resource "supabase_project" "managed" {
  for_each = var.manage_projects ? var.projects : {}

  organization_id         = var.organization_id
  name                    = each.value.name
  database_password       = var.database_passwords[each.key]
  region                  = each.value.region
  instance_size           = each.value.instance_size
  legacy_api_keys_enabled = false

  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = contains(keys(var.database_passwords), each.key) && length(var.database_passwords[each.key]) >= 16
      error_message = "A >=16-character database password must be supplied for every managed Supabase project."
    }
  }
}

output "project_refs" {
  value = {
    for key, project in var.projects :
    key => var.manage_projects ? supabase_project.managed[key].id : project.project_ref
  }
  description = "Supabase project refs, whether observed/imported or Terraform-managed."
}
