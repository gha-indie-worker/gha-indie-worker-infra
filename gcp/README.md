# GCP for `gha-indie-worker` (project `gha-indie-worker`)

Cloud Run is the **fallback** half of the edge contract: `ores-edge-router` sends traffic to the
k8s-cluster origin while `/healthz` **and** `/readyz` pass, and to these services when it does not
(and immediately, in-request, on a 502/503/504 or connection error from the primary).

## Two planes, two networks

```
                     ┌──────────────────────── Cloudflare (indiebuild.dev) ───────────────────────┐
  public             │  app. user. org. m. api. auth.        admin. admin-api. (Access-gated)     │
                     └──────┬──────────────────────────────────────────────┬─────────────────────┘
                            │ primary                                      │ primary (k8s only)
                     ┌──────▼──────────┐                            ┌──────▼──────────────┐
                     │ k8s-cluster     │                            │ k8s-cluster (admin) │
                     └──────┬──────────┘                            └──────┬──────────────┘
                            │ fallback                                     │ NO public fallback
        ┌───────────────────▼────────────────────┐          ┌──────────────▼────────────────────────┐
        │ PRODUCT plane — subnet 10.20.0.0/20    │          │ ADMIN plane — subnet 10.20.16.0/20    │
        │  web-server        (ingress: all)      │          │  admin-web-server   (ingress: internal)│
        │  api-server        (ingress: all)      │          │  admin-api-server   (ingress: internal)│
        │  connector: giw-product                │          │  mcp-server         (ingress: internal)│
        │  → Neon canonical + auth               │          │  connector: giw-admin                  │
        │  → Supabase canonical + auth           │          │  → Neon ADMIN project only             │
        │                                        │          │  → Supabase ADMIN project only         │
        └────────────────────────────────────────┘          └────────────────────────────────────────┘
                     no route between the two subnets; no shared service account; no shared secret
```

The separation is enforced three ways, so a single mistake does not open the admin database:

1. **Network** — separate subnets, separate Serverless VPC Access connectors, a deny-all egress
   firewall rule with per-plane allow rules. The product connector has no route to the admin subnet.
2. **IAM** — one service account per service. Only `sa-admin-api` and `sa-admin-web` can access the
   `giw-admin-*` secrets; only they may invoke each other and the MCP server (`roles/run.invoker`
   is granted to named service accounts, never `allUsers`).
3. **Application** — the admin binaries refuse to start when the product `DATABASE_URL` is set
   without `GHA_INDIE_WORKER_ADMIN_DATABASE_URL`, refuse a non-loopback bind without an explicit
   opt-in, and reject any shared-auth token whose issuer is the customer realm.

## Architecture note (arm64 vs Cloud Run)

k8s-cluster nodes are aarch64, so the primary images are `linux/arm64`. **Cloud Run does not run
arm64**, so the fallback deploys the `linux/amd64` image from the same multi-arch build
(`Dockerfile.x86-64.dkf`). One `docker buildx build --platform linux/arm64,linux/amd64` produces
both; the manifest list means k8s and Cloud Run pull the right one by digest.

## Apply

```sh
cd gcp/cloudrun
tofu init
tofu plan -out=plan.tfplan -var image_digest_web=sha256:… -var image_digest_api=sha256:…
tofu apply plan.tfplan
```

Images are pinned **by digest**, never by tag: a mutable tag would let a rebuilt image reach
production without review. The images workflow prints the digests.
