# Edge router for `indiebuild.dev`

`router.config.json` is the **only** thing edited here. `wrangler.toml` is rendered from it by
[`ores-edge-router`](https://github.com/ORESoftware/ores-edge-router) — never hand-edit it, and never
commit a rendered copy that disagrees with the config.

## What it does

While the k8s origin answers **both** `/healthz` and `/readyz`, traffic goes to k8s. A cron probe
every minute records health in KV with hysteresis (2 consecutive failures to go down, 2 to come
back). Independently, an *idempotent* request that gets a 502/503/504/52x or a connection error
from the primary is retried against the Cloud Run fallback inside the same request, so a fresh
outage is covered before the cron notices. Non-idempotent requests are never replayed.

Every response carries `x-ores-origin: k8s|cloudrun|github` and `x-ores-route: <reason>`;
`GET /__ores/router/status` dumps the health table.

## The hosts

`app.` `user.` `org.` `m.` — one web server, host-routed. `api.` — the JSON API and its WebSocket
upgrade (`websocket: true` passes `Upgrade:` through untouched). `auth.` — the shared-auth customer
realm. `admin.` and `admin-api.` (plus the fleet-canonical alias `api-admin.`) — **Cloudflare Access
required and no fallback**: if the admin cluster is down, the admin plane is down, which is the
correct behaviour for a plane that must never be publicly reachable. `www.` — the Astro marketing
site on GitHub Pages.

## Deploy

```sh
cd cloudflare/edge-router
npm install
npm run validate                       # schema + canonical-host check
wrangler kv namespace create HEALTH    # once; put the id in CF_HEALTH_KV_ID
HEALTH_KV_ID=<id> npm run deploy
```

**Prerequisites, in order:**
1. `cloudflare/dns` applied — `origin-hetzner.indiebuild.dev` (unproxied) plus the proxied host records.
2. `gcp/cloudrun` applied — take the `fallback_urls` output and replace the two
   `*-REPLACE.a.run.app` placeholders in `router.config.json`. **The router is not correct until
   those placeholders are gone**; `npm run validate` warns while they remain.
3. Cloudflare Access applications covering `admin.` and `admin-api.` (and `api-admin.`).

## Why the placeholders are checked in

They make the dependency explicit and reviewable. A config that pointed at a plausible-but-wrong
Cloud Run URL would fail open — traffic to a 404 during an outage — which is worse than a validator
that refuses to deploy.
