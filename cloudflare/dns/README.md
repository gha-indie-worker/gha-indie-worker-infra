# Cloudflare DNS for `indiebuild.dev`

Two layers, deliberately split (same split the fleet uses for every other zone):

| layer | owned by | what it declares |
|---|---|---|
| **DNS records** | this directory (`terraform`/`tofu`) | `origin-hetzner` (unproxied, what the Worker probes) + one proxied record per public subdomain |
| **Worker + routes** | `../edge-router/` (`router.config.json` → rendered `wrangler.toml`) | which origin each host uses, health failover, Cloudflare Access on the admin hosts |

Never hand-edit `wrangler.toml`; it is rendered from `router.config.json` by
[`ores-edge-router`](https://github.com/ORESoftware/ores-edge-router).

## Subdomain contract

| host | serves | origin (primary → fallback) | access |
|---|---|---|---|
| `app.indiebuild.dev` | primary web server (MASH/Leptos/Dioxus) | k8s → Cloud Run `gha-indie-worker-web-server` | public |
| `user.indiebuild.dev` | B2C login + user pages | same web server, host-routed | public |
| `org.indiebuild.dev` | B2B org login + org pages | same web server, host-routed | public |
| `m.indiebuild.dev` | mobile web | same web server, mobile shell | public |
| `api.indiebuild.dev` | JSON API + WebSocket | k8s → Cloud Run `gha-indie-worker-api-server` | public (bearer) |
| `auth.indiebuild.dev` | shared-auth customer realm | shared-auth k8s → redirect to ores-shared-auth.com | public |
| `admin.indiebuild.dev` | admin web console | k8s only — **no public fallback** | Cloudflare Access |
| `admin-api.indiebuild.dev` | admin JSON API | k8s only — **no public fallback** | Cloudflare Access |
| `api-admin.indiebuild.dev` | fleet-canonical alias of `admin-api` | same | Cloudflare Access |
| `www.indiebuild.dev` | marketing (Astro on GitHub Pages) | `gha-indie-worker.github.io` | public |

The admin hosts have no Cloud Run fallback **by design**: the admin plane lives in the admin VPC and
must not be reachable from the public internet even during a cluster outage.

## Apply

```sh
cd cloudflare/dns
tofu init && tofu plan -out=plan.tfplan     # review: adds only
tofu apply plan.tfplan
```

`CLOUDFLARE_API_TOKEN` comes from `ores-sops` (`env/dec/prod.env`), never from git.
