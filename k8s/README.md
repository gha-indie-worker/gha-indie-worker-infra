# k8s/

Workload manifests for the four servers. **The cluster itself is not defined
here** — its source of truth is
[github.com/ORESoftware/k8s-cluster](https://github.com/ORESoftware/k8s-cluster):
nodes, the ingress controller, cert-manager, the CNI, storage classes and the
sealed-secrets controller all live there. This directory only describes what runs
on it for this org.

These are the **primary** origins. Cloud Run (`terraform/gcp`) is the fallback the
edge Worker uses when `/healthz` or `/readyz` here stops answering.

## Layout

| file | namespace | serves |
|---|---|---|
| `namespace.yaml` | both | the two namespaces, and the admin default-deny |
| `web-server.yaml` | `gha-indie-worker` | `app.` `user.` `org.` `m.indiebuild.dev` |
| `api-server.yaml` | `gha-indie-worker` | `api.indiebuild.dev` |
| `admin-web-server.yaml` | `gha-indie-worker-admin` | `admin.indiebuild.dev` |
| `admin-api-server.yaml` | `gha-indie-worker-admin` | `admin-api.indiebuild.dev` |

Apply `namespace.yaml` **first**. A default-deny policy that arrives after the
pods it constrains leaves a window in which they are unconstrained.

```console
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/web-server.yaml -f k8s/api-server.yaml
kubectl apply -f k8s/admin-api-server.yaml -f k8s/admin-web-server.yaml
```

## Two namespaces, and why the admin one is default-deny

The admin plane is a separate namespace whose baseline is *nothing*:
`default-deny-all` selects every pod and names both policy types with no rules,
so all ingress and all egress are denied. Everything the admin workloads may do
is then re-granted explicitly, and the product namespace appears in none of those
grants.

The consequence is deliberate: a new pod added to `gha-indie-worker-admin` has no
network at all until somebody writes it a policy. A forgotten policy shows up as
an obviously broken pod rather than as an accidentally reachable one.

This is the cluster half of the same boundary `terraform/gcp/firewall.tf` draws
in GCP. Neither is sufficient alone, and the admin plane also sits behind
Cloudflare Access and internal-only Cloud Run ingress.

## Things in here that are easy to get wrong

**The web server's probes carry a `Host` header.** `web-server.rs` routes on
`Host` and answers 404 on *every* path — `/healthz` included — for a host it does
not recognise. Without `Host: app.indiebuild.dev` on the probes, no pod ever
becomes ready.

**The admin binaries refuse to bind publicly by default.** Both default to
loopback (`127.0.0.1:8787` / `:8788`), refuse a non-loopback bind unless
`GHA_INDIE_WORKER_ADMIN_ALLOW_PUBLIC_BIND=1`, and do **not** read `$PORT`. Both
variables are set in the manifests, next to the network policy that makes them
safe — never in the image, which stays loopback-only.

**`readOnlyRootFilesystem: true` means writes need a volume.** Each pod gets one
`emptyDir` at `/tmp` and nothing else. A process that suddenly needs to write
elsewhere is a change worth reviewing, not a volume worth adding quietly.

**Secrets are referenced by name only.** Every `secretKeyRef` names a Secret this
repository does not contain and never will; values are managed by the cluster's
sealed-secrets controller. Nothing here is a credential.

**`/readyz` and `/healthz` mean different things.** `/healthz` is liveness: the
process is alive. `/readyz` is readiness: it can actually serve — the API reports
not-ready without a database, so a pod that cannot persist leaves the load
balancer instead of accepting writes it will drop. Readiness probes use
`/readyz`; liveness probes use `/healthz`. Swapping them turns a dependency
outage into a crash loop.

**`maxUnavailable: 0` with a PodDisruptionBudget of `minAvailable: 1`.** Rolling
updates add a pod before removing one, and voluntary disruptions (node drains)
cannot take the last one.

## Not verified

`kubectl apply --dry-run=server` and `kubeconform` both need a cluster or a
schema bundle, and neither was available offline. What has been checked: every
document parses as YAML, every `apiVersion`/`kind` pair is spelled as in the
current stable APIs, and each manifest's `selector` matches its own pod labels.
Run `kubectl apply --dry-run=server -f k8s/` before merging.
