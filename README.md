# gha-indie-worker-infra

Cloudflare Workers and Kubernetes manifests for `gha-indie-worker`. Cluster source of truth remains github.com/oresoftware/k8s-cluster.


## Database isolation tests

Run `npm ci --ignore-scripts && npm test` in [`infra-isolation/`](infra-isolation/README.md)
for the canonical/auth/admin infrastructure contract and adversarial tests.
The dedicated GitHub Actions check is offline; live isolation acceptance requires
fresh provider/AWS evidence and explicitly authorized read-only probes. Missing
projects, private endpoints, or evidence remain blocked rather than passing.

## Cloud edge and providers

| directory | what it declares |
|---|---|
| `cloudflare/dns/` | DNS records for `indiebuild.dev` (terraform): `origin-hetzner` unproxied + one proxied record per host |
| `cloudflare/edge-router/` | `router.config.json` — the subdomain contract; `wrangler.toml` is rendered from it |
| `gcp/cloudrun/` | Cloud Run fallback services, the product/admin VPC split, IAM, Secret Manager containers |
| `neon/` | the three Neon projects (canonical, auth, admin) — infrastructure only, never schema |
| `supabase/` | per-project overlays (RLS, grants, Auth/Storage/Realtime); schema authority stays in orm-core |
| `infra-isolation/` | the adversarial tests that prove the two planes cannot reach each other |

Nothing here applies on merge. `infra-plan.yml` formats, validates and runs the isolation tests;
every apply is a human running `tofu apply` against a reviewed plan.

See [`docs/planes.md`](docs/planes.md) for why the admin plane has no public fallback.
