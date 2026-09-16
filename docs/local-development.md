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
3. `just codespace-edge-up` materializes the exact reviewed shared edge revision from `config/codespaces-cluster.rev` only when that checkout/object is missing, builds its Rust controller, then starts this repository's application compose stack first. The shared controller uses a separate `.ores/codespaces-cluster-app` state directory and waits for web readiness on port 18091.
4. After the application is ready, the same command starts the shared Rust edge on `127.0.0.1:8080` with `CODESPACES_CLUSTER_CONFIG` pointing at this repository's route table. Only after edge `/readyz` passes does `oresc` start `cloudflared`.
5. `just codespace-edge-status` reports the application supervisor, shared edge/connector state, and verifies `GET /api/readyz` through port 8080.
6. `just codespace-edge-down` stops the Cloudflare connector and shared edge first, then stops the application compose supervisor. Shutdown attempts both layers even if one half reports an error.
7. `status` and `down` deliberately do not fetch or mutate the shared checkout while it owns running supervisors.
8. For laptop development, copy the appropriate Cloudflare config outside the repository and run `scripts/dev/tunnel laptop /abs/config.yml` only if that legacy config-driven path is required.

`local.indiebuild.dev` and `codespace.indiebuild.dev` are Access-protected interactive surfaces. `hooks.indiebuild.dev` / `ci-laptop.indiebuild.dev` remain separate signed-machine/webhook surfaces; never weaken Access to make automation work.

## Codespace bootstrap

A fresh/rebuilt devcontainer provisions the reviewed private tools needed by this lifecycle:

- `ORESoftware/ores-cli@c854130ee147e9793a3af8736e90241630a5c934`, with the reviewed revision recorded in `config/ores-cli.rev`;
- `ORESoftware/ores-compose@c81058821fcdd9a19c145e8e685d21ef5b1d6673`, with the reviewed revision recorded in `config/ores-compose.rev`;
- the shared `ORESoftware/codespaces-cluster` source is materialized later at the exact commit recorded in `config/codespaces-cluster.rev`.

The three `config/*.rev` files are review authorities for private bootstrap/runtime tooling. They must contain exactly one full 40-hex commit SHA. The Rust dev-runtime validator, contract tests, devcontainer install commands, and Codespace edge workflow cross-check those values so a pin cannot move in only one surface.

All three repositories are private and cross-owner from `gha-indie-worker`. Configure `ORES_CLI_READ_TOKEN` as a fine-grained Codespaces secret with **read-only Contents access limited to exactly those three repositories**. The historical variable name is retained for compatibility even though its bootstrap scope now covers the three reviewed ORE tooling repositories. Configure `TUNNEL_TOKEN` separately for the pre-provisioned named Cloudflare tunnel.

`ORES_CLI_READ_TOKEN` is a bootstrap/network credential only. `just codespace-edge-up` injects it as `GH_TOKEN` only around a required private clone/fetch or missing-tool bootstrap operation. It is not exported into the recipe shell and is not inherited by the long-running application controller, shared Rust edge, `oresc` supervisor, or `cloudflared` connector.

The devcontainer also performs a read-only `gh repo view ORESoftware/codespaces-cluster` preflight so insufficient repository scope fails during rebuild rather than during first traffic activation.

Port 8080 stays private to the Codespace and is marked `onAutoForward: ignore`; Cloudflare connects to loopback from `cloudflared` inside the same Codespace rather than proxying a `*.app.github.dev` URL.

## Secret boundary

No tunnel token, GitHub bootstrap token, or credential JSON belongs in Git, `.ores-compose.yaml`, `config/codespaces-cluster.toml`, process arguments, Terraform variables committed to the repository, or devcontainer configuration. Real tunnel configs/credential files live outside the checkout. `.runtime/` and `.ores/` are transient runtime state and must not become credential stores.
