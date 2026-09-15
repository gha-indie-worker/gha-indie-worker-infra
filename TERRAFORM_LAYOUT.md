# Terraform modules / environments contract

This repository uses the fleet `modules/` + `environments/` topology.

## Ownership

- `modules/<provider>/...` contains reusable provider-dependent Terraform child modules.
- `environments/<environment>/<state-root>/...` contains Terraform root modules, provider configuration, state/backend ownership and environment-specific values.
- Provider-native repositories remain provider-native: `supabase/` owns Supabase config/migrations/functions, `neon/` owns Neon inventory/schema metadata, and `cloudflare/edge-router/` owns Wrangler Worker routes.

Child modules are environment-agnostic. They MUST NOT contain backend blocks, committed state, `.terraform/`, environment `.tfvars`, credentials, or provider configuration blocks.

## Preserved production state roots

The migration deliberately preserves the five pre-existing state histories:

| old root | new root | child module |
|---|---|---|
| `terraform/gcp` | `environments/production/gcp-platform` | `modules/gcp/platform` |
| `gcp/cloudrun` | `environments/production/gcp-cloudrun` | `modules/gcp/cloudrun` |
| `terraform/cloudflare` | `environments/production/cloudflare-platform` | `modules/cloudflare/platform` |
| `cloudflare/dns` | `environments/production/cloudflare-dns` | `modules/cloudflare/dns` |
| `neon` Terraform files | `environments/production/neon` | `modules/neon/projects` |

Do not combine these state histories just because their modules now share a provider directory. The overlapping GCP and Cloudflare roots pre-date this migration and remain independently managed until a separately reviewed state-consolidation plan proves one authority is obsolete.

## State migration

The new production roots include Terraform `moved` blocks for every managed root resource. Those blocks preserve addresses only after the new root is attached to the SAME state that belonged to its old root. Follow `docs/terraform-layout-migration.md`; never initialize a fresh production state and apply it as a shortcut.

Run Terraform from a concrete root, e.g. `terraform -chdir=environments/production/gcp-platform plan` or use `scripts/apply-terraform.sh production/gcp-platform`.
