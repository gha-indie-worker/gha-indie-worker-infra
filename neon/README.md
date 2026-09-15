# Neon for `gha-indie-worker`

Neon remains 1:1 with the GitHub org. Provider-native inventory, project metadata, schema verification and GitOps documentation stay in this directory.

Terraform ownership moved without changing the managed Neon objects:

- child module: `modules/neon/projects`
- production root/state: `environments/production/neon`
- old Terraform root: `neon/`

The three project roles remain `canonical` (product data), `auth` (customer auth realm) and `admin` (admin plane). The admin project remains intentionally closed until its private-networking acceptance is satisfied.

Schema migrations do not come from this Terraform module. `dpm` remains the migration tool and the product schema authority remains outside this infrastructure root. Pull-request Neon branches remain provider-native and are managed by `.github/workflows/neon-preview.yml`.

See `docs/terraform-layout-migration.md` before attaching the new root to existing state.
