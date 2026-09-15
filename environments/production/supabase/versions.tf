terraform {
  required_version = ">= 1.9.0"
  required_providers {
    supabase = {
      source  = "supabase/supabase"
      version = ">= 1.10.1, < 2.0.0"
    }
  }
}

provider "supabase" {
  # SUPABASE_ACCESS_TOKEN is supplied through the environment/secret manager.
}
