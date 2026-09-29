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

## Cloudflare Tunnel authority

The managed lifecycle (`just codespace-edge-up` -> `oresc codespace edge up`) uses a **remotely managed Cloudflare Tunnel**. This is the one supported authority for automated laptop ingress:

- `TUNNEL_TOKEN` is the canonical connector credential; `CF_TUNNEL_TOKEN` is compatibility input only;
- the token is supplied through the process environment and is never placed on argv or committed to Git;
- hostname/origin routing is configured remotely in Cloudflare/Terraform and must route `local.indiebuild.dev` to `http://127.0.0.1:8080`;
- Cloudflare Access policy is managed remotely and must protect the browser/control-plane hostname;
- `oresc` verifies a compatible `cloudflared`, starts only after the local origin is ready, strips bootstrap credentials from long-running children, and owns connector teardown through its recorded process identity;
- `just codespace-edge-up` fails before starting any local layer if neither tunnel-token environment variable is present.

Cloudflare recommends remotely managed tunnels for most deployments because configuration can be managed through the dashboard, API, or Terraform. Retrieve the connector token from the tunnel's **Add a replica** flow or the Cloudflare Tunnel token API, then inject it through the approved local secret mechanism. Treat the token as a secret: anyone holding it can run a connector for that tunnel.

`config.example.yml` is retained only as a clearly marked **manual/legacy locally-managed alternative**. The managed `just`/`oresc` lifecycle does not read it. Do not assume copying that file to `~/.config/gha-indie-worker/cloudflared.yml` changes what `oresc` runs.

For a deliberate manual locally-managed tunnel, the example remains fail-closed:

- only `local.indiebuild.dev` reaches the laptop;
- the local origin is `127.0.0.1:8080`, never `0.0.0.0`;
- unknown hosts terminate in `http_status:404`;
- no `noTLSVerify` escape hatch is used;
- Cloudflare Access is checked at the edge and again by `cloudflared` before origin forwarding;
- the real tunnel credentials path/token is never stored in Git.

`terraform/cloudflare/laptop-ingress.tf` creates the proxied first-level DNS record and Access application when `laptop_tunnel_cname` is configured. The CNAME target (`<uuid>.cfargotunnel.com`) and Access AUD are identifiers rather than credentials; connector tokens and locally-managed credential JSON remain secret.

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
