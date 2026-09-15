# gha-indie-worker-infra

Infrastructure source of truth for `gha-indie-worker`. Cluster source of truth remains github.com/oresoftware/k8s-cluster.

## Terraform/OpenTofu layout

New infrastructure changes use a strict module/environment split:

- `modules/{gcp,cloudflare,neon,supabase}`: provider-dependent resources, module variables, and module outputs;
- `environments/production/{gcp,cloudflare,neon,supabase}`: provider configuration, state/backend selection, environment inputs, and module composition;
- native system assets remain outside Terraform (`cloudflare/edge-router`, `supabase/`, Neon evidence/config, `k8s/`).

The older Terraform roots are migration references only; do not add new resources there. See `docs/terraform-layout.md` before moving existing state across the module boundary.

Nothing applies on merge. CI formats/validates and may plan; every apply is human-gated through `scripts/apply-terraform.sh`.

## Application checkout

`_apps/gha-monorepo` is a git submodule for `gha-indie-worker/gha-indie-worker-monorepo`. Initialize it with:

```sh
scripts/sync-apps.sh
```

`dist/` and all other `_apps/*` content are ignored; only the explicit `gha-monorepo` gitlink is tracked.

## Database isolation tests

Run `npm ci --ignore-scripts && npm test` in `infra-isolation/` for the canonical/auth/admin infrastructure contract and adversarial tests. Missing projects, private endpoints, or evidence remain blocked rather than passing.
