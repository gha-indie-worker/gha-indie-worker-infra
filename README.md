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
| `scripts/check-platform-contract.mjs` | credential-free topology guard for every requested host, Cloud Run service, and admin boundary |

Nothing here applies on merge. `infra-plan.yml` formats, validates and runs the isolation tests;
every apply is a human running `tofu apply` against a reviewed plan.

See [`docs/planes.md`](docs/planes.md) for why the admin plane has no public fallback.

Run the full offline gate from the repository root:

```sh
node scripts/check-platform-contract.mjs
node scripts/check-db-providers.mjs
(cd cloudflare/edge-router && npm ci --ignore-scripts && npm test)
(cd infra-isolation && npm ci --ignore-scripts && npm test)
```

The edge-router dependency is pinned to an immutable upstream commit and fetched as an HTTPS
tarball, so CI does not depend on SSH keys or an untagged Git ref. `compatibility-date.txt` is the
reviewed Cloudflare runtime-date source; the generated `wrangler.toml` is checked by `npm test`.

These checks are intentionally source-only. They do not claim that DNS, Cloudflare Access,
Artifact Registry, Cloud Run, or provider private networking is live. The current live acceptance
gate remains blocked until the `indiebuild.dev` zone has its records and Access applications, the
`gha-indie-worker` GCP project has billing and required APIs enabled, and immutable image digests
plus provider evidence are supplied.
