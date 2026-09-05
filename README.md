# gha-indie-worker-infra

Cloudflare Workers and Kubernetes manifests for `gha-indie-worker`. Cluster source of truth remains github.com/oresoftware/k8s-cluster.


## Database isolation tests

Run `npm ci --ignore-scripts && npm test` in [`infra-isolation/`](infra-isolation/README.md)
for the canonical/auth/admin infrastructure contract and adversarial tests.
The dedicated GitHub Actions check is offline; live isolation acceptance requires
fresh provider/AWS evidence and explicitly authorized read-only probes. Missing
projects, private endpoints, or evidence remain blocked rather than passing.
