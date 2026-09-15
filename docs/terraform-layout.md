# Terraform module/environment layout

Canonical layout:

```text
environments/
  production/
    gcp/
    cloudflare/
    neon/
    supabase/
modules/
  gcp/
  cloudflare/
  neon/
  supabase/
```

`modules/*` owns provider-specific resources and provider requirements. `environments/*` owns provider configuration, backend/state selection, environment inputs, module composition, and exported environment outputs. Native non-Terraform assets stay with their systems (`cloudflare/edge-router`, `supabase/`, `neon/` evidence/config).

## Existing state

The module boundary changes Terraform resource addresses from `TYPE.NAME` to `module.<provider>.TYPE.NAME`. Before the first apply of a migrated state, migrate addresses deliberately. Use `scripts/migrate-terraform-state-to-modules.sh <provider>` from a reviewed checkout after configuring the same backend/state used by the historical root. Never accept a destroy/recreate plan as a substitute for state migration.

## Application checkout

`_apps/gha-monorepo` is a tracked git submodule pointing at `gha-indie-worker/gha-indie-worker-monorepo`. Run `scripts/sync-apps.sh` after cloning this repo. `_apps/*` is ignored except for that gitlink, and `dist/` is entirely ignored.
