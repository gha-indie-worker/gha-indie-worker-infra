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

## Laptop / Codespaces runtime contract

This repository is the single `.ores-compose.yaml` authority. The manifest pins the same exact monorepo commit as `_apps/gha-monorepo`; laptop and Codespaces must not substitute a moving branch or a second service graph.

Use `scripts/dev/bootstrap`, then `scripts/dev/doctor`. The pinned API/web revisions now run real loopback HTTP listeners, so `ores-compose up .ores-compose.yaml` can supervise the local application and a named Cloudflare Tunnel in one graph when `GIW_CLOUDFLARED_CONFIG` points at an external fail-closed tunnel config. `scripts/dev/tunnel standalone <config>` validates a single protected `local.indiebuild.dev` hostname with `/v1/*` routed to the API on `18090` and all other requests routed to the web server on `18091`. This avoids competing with the existing production `api.indiebuild.dev` Worker route. Laptop/codespace modes remain available for the shared port-8080 ingress. See `docs/local-development.md`.

## Database isolation tests

Run `npm ci --ignore-scripts && npm test` in `infra-isolation/` for the canonical/auth/admin infrastructure contract and adversarial tests. Live isolation acceptance requires fresh provider/AWS evidence and explicitly authorized read-only probes; missing projects, private endpoints or evidence remain blocked rather than passing.

## Apply policy

Nothing applies on merge. CI formats, initializes without production state where appropriate, validates, and may produce reviewed plans. Human applies use `scripts/apply-terraform.sh <environment/root> --apply` against the existing state for that root.

See `docs/planes.md` for why the admin plane has no public fallback.


## Remote CI runner substrate

Remote/prod untrusted CI execution is isolated under `k8s/runners/`. GIW does
not operate a reusable shared runner pool: the product control plane creates one
ephemeral execution per job, while the Kubernetes namespace enforces restricted
Pod Security, quotas, bounded defaults, a tokenless runner service account, and
default-deny networking.

Apply the namespace/policy substrate before enabling remote job placement:

```sh
kubectl kustomize k8s/runners
kubectl apply --dry-run=server -k k8s/runners
kubectl apply -k k8s/runners
```

The actual per-job Job/Pod spec is produced by the GIW/Scintilla execution
adapter and must satisfy the invariants documented in
`k8s/runners/README.md`. A mutable long-lived runner Deployment is not an
acceptable substitute.
