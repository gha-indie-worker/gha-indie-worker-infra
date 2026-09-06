terraform {
  required_version = ">= 1.6.0"
  required_providers {
    neon = {
      source  = "kislerdm/neon"
      version = "~> 0.6"
    }
  }
}

provider "neon" {
  # NEON_API_KEY from the environment (ores-sops); never committed.
}
