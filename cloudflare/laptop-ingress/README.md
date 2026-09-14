# Laptop `gha-indie-worker` / `ores-compose` ingress

This directory defines the public-to-laptop trust boundary for local PR/test environments. The laptop exposes **one** loopback gateway; individual compose services and their dynamically allocated ports/sockets are never public.

```text
browser / operator
      |
Cloudflare Access
      |
Cloudflare Tunnel
      |
127.0.0.1:8080  gha-indie-worker ingress
      |
(project, session, service) admission
      |
ores-compose ensure(project, session)
      |
private per-session Rust LB
      |
healthy replica(s) in that session network
```

## Public URL contract

Use path routing as the public default:

```text
https://local.indiebuild.dev/p/zed-pkg/pr-481/api/v1/packages
https://local.indiebuild.dev/p/zed-pkg/pr-481/web/
```

This deliberately keeps the public hostname at one subdomain level. Cloudflare Universal SSL in a normal full-zone setup covers `*.indiebuild.dev`, but not deeper names such as `api.zed-pkg.pr-481.local.indiebuild.dev`.

The laptop router still supports the clearer nested-host form for direct/local traffic:

```text
api.zed-pkg.pr-481.local.indiebuild.dev
web.zed-pkg.pr-481.local.indiebuild.dev
```

Do not publish those deeper names until the zone has Total TLS or a reviewed advanced/custom certificate that actually covers them.

## Cloudflare Tunnel

`config.example.yml` is intentionally safe-by-default:

- only `local.indiebuild.dev` reaches the laptop;
- the local origin is `127.0.0.1:8080`, never `0.0.0.0`;
- unknown hosts terminate in `http_status:404`;
- no `noTLSVerify` escape hatch is used;
- Cloudflare Access is checked at the edge and again by `cloudflared` before origin forwarding;
- the real tunnel credentials path/token is never stored in Git.

Copy the example outside the repo and substitute the tunnel UUID, Access team name, and Access AUD. `terraform/cloudflare/laptop-ingress.tf` creates the proxied first-level DNS record and Access application when `laptop_tunnel_cname` is configured.

The CNAME target (`<uuid>.cfargotunnel.com`) and Access AUD are identifiers rather than credentials. The tunnel credential JSON/token remains secret and local to the machine.

## Laptop gateway requirements

The `gha-indie-worker` server must enforce all of these even if Cloudflare is bypassed during local testing:

1. Bind the public gateway to loopback or an explicitly private Unix socket. Never bind the project routers directly to all interfaces.
2. Permit `/p/...` routing only for an explicit host allowlist. For the public tunnel deployment include `local.indiebuild.dev` in `GHA_INDIE_WORKER_ROUTING_PATH_HOSTS`.
3. Parse project/session/service names as canonical DNS labels and reject traversal/ambiguous encodings before any startup side effect.
4. Run project/service admission before `ores-compose ensure`. A request hostname/path is not authority to create a project.
5. Accept from `ores-compose` only a loopback TCP or runtime-root Unix-socket ingress endpoint. Never proxy an arbitrary URL returned by the runtime.
6. Strip inbound forwarding, hop-by-hop, `x-ores-*`, and Access identity headers before adding trusted metadata.
7. Bound active sessions and concurrent lazy starts. Coalesce simultaneous requests for the same project/session.
8. Use generation/fencing tokens so a stale supervisor cannot reclaim a restarted session.
9. Wait for the per-session LB readiness endpoint before forwarding; select healthy replicas only.
10. Preserve WebSocket/SSE/streaming semantics explicitly rather than forwarding arbitrary `Connection` headers.

These invariants are implemented/tracked in:

- `gha-indie-worker/gha-indie-worker-api-server.rs#21`
- `ORESoftware/ores-compose#2` and its hardened session-core PR
- `ORESoftware/ores-edge-router` for the shared Cloudflare Worker trust boundary

## Webhooks are a separate surface

Do **not** weaken Access on `local.indiebuild.dev` just because GitHub or another machine sender cannot complete an interactive Access login. A webhook should use a separate hostname/path with its own signature verification, replay protection, body-size limit, and rate limit. It can enqueue an admitted job that later starts a compose session; it should not share the browser/control-plane authentication rule.

## Deployment inputs

Terraform emits:

- `laptop_ingress.hostname`
- `laptop_ingress.access_aud`
- `edge_router_access_verification.team_domain`
- the per-host Access audiences used by the shared edge Worker

The hardened edge Worker must receive the trusted team-domain and AUD mapping as deployment variables. Never select a JWKS URL or accepted audience from claims inside an unverified token.
