# gha-indie-worker-infra

Canonical infrastructure repository for `gha-indie-worker`. Cluster source of truth remains `ORESoftware/k8s-cluster`.

## Terraform topology

Terraform follows the fleet modules/environments contract:

| path | ownership |
|---|---|
| `modules/gcp/` | reusable GCP provider implementation |
| `modules/cloudflare/` | reusable Cloudflare provider implementation |
| `modules/neon/` | reusable Neon provider implementation |
| `modules/supabase/` | admitted Supabase Terraform boundary; currently no Terraform-managed Supabase resources |
| `environments/production/` | provider config, independent production state roots and module composition |
| `environments/{preview,staging}/` | admitted environment namespaces; no long-lived state yet |

Provider-native sources stay where their tools discover them: `cloudflare/edge-router/`, `neon/`, `supabase/`, and `k8s/`.

The five pre-existing Terraform state histories remain separate. See `TERRAFORM_LAYOUT.md` and `docs/terraform-layout-migration.md` before the first apply from a new root.

## Application checkout

`_apps/gha-monorepo` is a pinned Git submodule for `gha-indie-worker/gha-indie-worker-monorepo`. Initialize the exact recorded revision with:

```sh
scripts/sync-apps.sh
```

Use `scripts/update-app-pin.sh` only to deliberately review and stage a newer monorepo pin. `dist/` and every other `_apps/*` child are ignored local/generated material. Terraform is forbidden from sourcing modules from `_apps/` or `dist/`; infrastructure plans must remain reproducible without the optional application checkout. See `docs/apps-checkout.md`.

## Database isolation tests

Run `npm ci --ignore-scripts && npm test` in `infra-isolation/` for the canonical/auth/admin infrastructure contract and adversarial tests. Live isolation acceptance requires fresh provider/AWS evidence and explicitly authorized read-only probes; missing projects, private endpoints or evidence remain blocked rather than passing.

## Apply policy

Nothing applies on merge. CI formats, initializes without production state where appropriate, validates, and may produce reviewed plans. Human applies use `scripts/apply-terraform.sh <environment/root> --apply` against the existing state for that root.

See `docs/planes.md` for why the admin plane has no public fallback.
