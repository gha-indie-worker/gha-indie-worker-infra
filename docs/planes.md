# Two planes, and why the admin plane has no fallback

## The rule

`gha-indie-worker` runs two independent planes. A **product** plane serving customers at
`app./user./org./m./api.indiebuild.dev`, and an **admin** plane serving a handful of super-admins at
`admin./admin-api.indiebuild.dev`. They share no network route, no service account, no secret, and
no database.

## Why not one plane with a role check

Because a role check is one bug away from being bypassed, and the blast radius is every customer's
data. The admin plane holds the tenant inventory, the allow-list, and the append-only audit log —
the things an attacker who already has a foothold would want next. So the separation is defended at
four independent layers, and an attacker has to beat all four:

| layer | control | what it stops |
|---|---|---|
| Edge | Cloudflare Access on `admin.` and `admin-api.`; **no Cloud Run fallback** | reaching the admin plane from the internet at all |
| Network | separate subnet + connector; a deny-all firewall rule from product→admin; separate NAT addresses, so the admin database's allow-list names only the admin address | a compromised product service opening a connection to the admin database |
| IAM | one service account per service; admin secrets granted only to `sa-giw-admin-*`; `run.invoker` granted to named service accounts, never `allUsers` | a leaked product credential reading an admin secret |
| Application | the admin binaries panic at boot if the product `DATABASE_URL` is set without the admin one; every admin route requires a shared-auth token from the **admin issuer** and rejects the customer issuer; every mutating route additionally requires membership of the super-admin allow-list | a valid customer token being replayed against the admin API |

## The consequence we accept

If the admin cluster is down, the admin console is down. There is no Cloud Run fallback for
`admin.` or `admin-api.` and there should not be one: a public fallback for the admin plane would
undo the edge layer entirely, and the failure mode it protects against (an operator briefly cannot
suspend a tenant) is far less bad than the one it would create.

## The MCP connection

The admin plane talks to `gha-indie-worker-mcp-server` for development and introspection. That
server is `ingress: internal` in the same admin subnet, invokable only by `sa-giw-admin-api` and
`sa-giw-admin-web`, and runs read-only (`GHA_INDIE_WORKER_MCP_MODE=read-only`). It is a tool the
admin plane uses, never a way into it: nothing outside the admin subnet can call it, and it holds
no write capability that would make it worth reaching.

## Current provisioning state (2026-09-07)

- Neon: canonical + auth **active**; admin **provisioned but closed** (public and VPC connections
  both blocked). Opening it needs private networking, which needs the Scale plan.
- Supabase: canonical + auth are **declared but currently `INACTIVE` in the live control plane**
  (read-only audit on 2026-09-07), isolated by the `gha_indie_worker` schema when resumed; admin
  **not created** (cost + PrivateLink entitlement decisions). Do not treat the desired-state
  `state: "active"` fields in `.db-providers.json` as provider readiness.
- Until the Neon admin project opens, the admin plane's system of record is the AWS RDS admin
  database, reachable only from the admin NAT address.

None of these gaps are engineering work. They are three billing decisions, and
`.db-providers.json` records each one under `blockedOn` so nobody has to rediscover them.
