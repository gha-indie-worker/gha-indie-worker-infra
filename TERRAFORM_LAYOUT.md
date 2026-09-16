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

`bash scripts/check-terraform-layout.sh` enforces the base 15 topology invariants. `bash scripts/check-terraform-state-safety.sh` enforces a second independent 15-invariant layer over migration identity and state ownership. The second layer checks exact module labels and providers, one-source root composition, non-empty provider modules, local-only module sources, paired and unique move addresses, pure namespace moves, destination/resource correspondence, cross-root destination uniqueness, credential-literal rejection, preview/staging non-ownership, and the provider-native Supabase boundary.

A change to `moved.tf` is not documentation-only. If a move is removed, duplicated, retargeted, or points at a resource that the child module no longer declares, CI must fail before a production state plan can be trusted.

Run Terraform from a concrete root, e.g. `terraform -chdir=environments/production/gcp-platform plan` or use `scripts/apply-terraform.sh production/gcp-platform`.

## Application checkout is not Terraform authority

`_apps/gha-monorepo` is an optional, exact-revision Git submodule used when infra tooling needs to inspect application source. `dist/` is local/generated output. Neither directory participates in Terraform module or state ownership, and no `source =` under `modules/` or `environments/` may point at either location. This keeps plan/state behavior independent of submodule initialization and generated build output.
