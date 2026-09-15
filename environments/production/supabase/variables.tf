variable "supabase_organization_id" {
  type        = string
  default     = "agcymjepsfsztukakrrl"
  description = "Supabase organization containing gha-indie-worker projects."
}

variable "manage_supabase_projects" {
  type        = bool
  default     = false
  description = "Enable only after importing the existing canonical/auth projects into Terraform state."
}

variable "supabase_database_passwords" {
  type        = map(string)
  sensitive   = true
  default     = {}
  description = "Database passwords sourced from encrypted runtime secrets when project management is enabled."
}
