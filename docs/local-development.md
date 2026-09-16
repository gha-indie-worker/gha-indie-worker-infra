# Laptop and Codespaces development contract

The infra repository owns one application `.ores-compose.yaml`. Laptop and Codespaces use that same manifest and exact application source commit; environment-specific application service graphs are forbidden.

## Current application readiness

The pinned application monorepo now contains long-lived API and web server revisions. The application compose contract binds them only on loopback:

- API: `127.0.0.1:18090` with `/healthz` and `/readyz`;
- web: `127.0.0.1:18091` with `/healthz` and `/readyz`;
- web reaches the API through `GHA_INDIE_WORKER_API_HTTP_BASE=http://127.0.0.1:18090`.

Port `8080` is reserved exclusively for the shared `ORESoftware/codespaces-cluster` Rust edge. The application compose manifest must not claim it.

`config/codespaces-cluster.toml` is this repository's trusted edge route table:

- `/api/*` -> API on `127.0.0.1:18090`, with the `/api` prefix stripped;
- all other application paths -> web on `127.0.0.1:18091`.

The edge's own `/healthz`, `/readyz`, and `/routes` endpoints remain control-plane endpoints and are not shadowed by the web root route.

## Workflow

1. `scripts/dev/bootstrap` initializes `_apps/gha-monorepo` and its tracked nested gitlinks at the recorded revisions. It uses checkout semantics only; it does not rebase/reset/force-push.
2. `scripts/dev/doctor` verifies the infra gitlink, application compose source pin, required tools, initialized source, and real application server pins.
3. `just codespace-edge-up` clones or fast-forwards the shared `ORESoftware/codespaces-cluster` checkout, builds its Rust controller, then starts this repository's application compose stack first. The shared controller uses a separate `.ores/codespaces-cluster-app` state directory and waits for web readiness on port 18091.
4. After the application is ready, the same command starts the shared Rust edge on `127.0.0.1:8080` with `CODESPACES_CLUSTER_CONFIG` pointing at this repository's route table. Only after edge `/readyz` passes does `oresc` start `cloudflared`.
5. `just codespace-edge-status` reports the application supervisor, shared edge/connector state, and verifies `GET /api/readyz` through port 8080.
6. `just codespace-edge-down` stops the Cloudflare connector and shared edge first, then stops the application compose supervisor. Shutdown attempts both layers even if one half reports an error.
7. `status` and `down` deliberately do not fetch or mutate the shared checkout while it owns running supervisors.
8. For laptop development, copy the appropriate Cloudflare config outside the repository and run `scripts/dev/tunnel laptop /abs/config.yml` only if that legacy config-driven path is required.

`local.indiebuild.dev` and `codespace.indiebuild.dev` are Access-protected interactive surfaces. `hooks.indiebuild.dev` / `ci-laptop.indiebuild.dev` remain separate signed-machine/webhook surfaces; never weaken Access to make automation work.

## Codespace bootstrap

The devcontainer installs reviewed private `ORESoftware/ores-cli` revision `c854130ee147e9793a3af8736e90241630a5c934`. That revision contains the external-origin connector behavior consumed by the shared full lifecycle.

Because `ORESoftware/ores-cli` is private and cross-owner, configure `ORES_CLI_READ_TOKEN` as a fine-grained Codespaces secret with read-only Contents access to that repository. Configure `TUNNEL_TOKEN` separately for the pre-provisioned named Cloudflare tunnel. The bootstrap token is used only for Git/Cargo installation and must not become application configuration.

Port 8080 stays private to the Codespace and is marked `onAutoForward: ignore`; Cloudflare connects to loopback from `cloudflared` inside the same Codespace rather than proxying a `*.app.github.dev` URL.

## Secret boundary

No tunnel token, GitHub bootstrap token, or credential JSON belongs in Git, `.ores-compose.yaml`, `config/codespaces-cluster.toml`, process arguments, Terraform variables committed to the repository, or devcontainer configuration. Real tunnel configs/credential files live outside the checkout. `.runtime/` and `.ores/` are transient runtime state and must not become credential stores.
