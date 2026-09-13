# cloudflare/

| path | status | what it is |
|---|---|---|
| `edge-router/` | **current** | the real edge Worker: health-based failover for every `indiebuild.dev` host, adopted from `ores-edge-router` |
| `laptop-tunnel/` | **current** | remotely managed Cloudflare Tunnel for `ci-laptop.indiebuild.dev` -> laptop `gha-indie-worker` on `127.0.0.1:8100` |
| `worker.js`, `wrangler.toml` | **superseded — not deployed** | the original `gha-indie-worker-edge` placeholder |

The laptop tunnel is intentionally separate from `edge-router/`: it is an opportunistic CI ingress, not a production origin or failover target. GitHub push webhooks can reach it without consuming GitHub-hosted Actions minutes, and the worker verifies its own webhook HMAC before accepting work.

## Why the placeholder is kept rather than deleted

`worker.js` is nine lines: answer `/health` with `{ok:true}`, pass everything
else through untouched. `edge-router/` does that and everything the product
actually needs — per-host origins, `/healthz` + `/readyz` gating with hysteresis,
same-request retry onto the Cloud Run fallback, `cloudflare-access` enforcement
on the admin hosts, and `x-ores-origin` / `x-ores-route` on every response.

It stays in the tree for one reason: **it may still be deployed.** A Worker named
`gha-indie-worker-edge` that was ever `wrangler deploy`-ed still exists in the
Cloudflare account, with whatever routes it was given, until someone deletes it.
Deleting the source here would not delete the Worker — it would only remove the
record of what that Worker does, while it kept serving traffic. Two workers
matching the same route is decided by Cloudflare's route specificity, not by
which repository you edited.

Its `/health` behaviour was **not** folded into the new Worker. The edge router
already exposes `/__ores/router/healthz` (the router's own liveness) and
`/__ores/router/status` (the health table, behind Cloudflare Access), which is
strictly more information under the fleet's naming. Adding a second, differently
named endpoint would give monitoring two answers to the same question.

## Decommissioning it

After `edge-router/` is deployed and serving, and after you have confirmed the
routes moved:

```console
npx wrangler deployments list --name gha-indie-worker-edge   # is it real?
npx wrangler delete --name gha-indie-worker-edge             # then delete it
```

Only then remove `worker.js` and `wrangler.toml` from this directory — in that
order, so the repository never claims something is gone while it is still
running.
