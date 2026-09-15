# Laptop and Codespaces development contract

The infra repository owns one application `.ores-compose.yaml`. Laptop and Codespaces use that same manifest and exact application source commit; environment-specific application service graphs are forbidden.

## Current application readiness

The application source/materialization contract is exact, but the application runtime is intentionally **not declared healthy yet**. The pinned API and web server revisions currently print their configured bind/output and exit instead of maintaining listening HTTP servers. `scripts/dev/doctor` recognizes those exact stub pins and fails closed. Do not bypass the doctor by adding `sleep`, fake health checks or a moving branch reference.

This is separate from the shared Codespaces edge diagnostic cluster. `ORESoftware/codespaces-cluster` has its own small `.ores-compose.yaml` used to prove the common Cloudflare → tunnel → Rust `:8080` → path-routed local-service infrastructure independently of this repository's still-blocked application stack.

## Workflow

1. `scripts/dev/bootstrap` initializes `_apps/gha-monorepo` and its tracked nested gitlinks at the recorded revisions. It uses checkout semantics only; it does not rebase/reset/force-push.
2. `scripts/dev/doctor` verifies the infra gitlink, application compose source pin, required tools, initialized source and the known application-readiness blocker.
3. For shared Codespace edge infrastructure, use `just codespace-edge-up`. The wrapper clones/fast-forwards `ORESoftware/codespaces-cluster`, starts its local `ores-compose` cluster and Rust edge on `127.0.0.1:8080`, waits for `/readyz`, and only then starts `oresc`/`cloudflared`.
4. `just codespace-edge-status` reports both the shared local cluster and connector state. `just codespace-edge-down` stops the connector first, then gracefully stops the shared local `ores-compose` cluster. Status/down deliberately do not fetch or update the shared checkout while it owns a running supervisor.
5. The GHA Indie Worker application stack remains governed by this repository's `.ores-compose.yaml` and `scripts/dev/doctor`. When its real API/web listeners are admitted, application routes can be added behind the shared Rust edge without weakening the existing doctor gate.
6. For laptop development, copy the appropriate Cloudflare config outside the repository and run `scripts/dev/tunnel laptop /abs/config.yml` only if that legacy config-driven path is required.

`local.indiebuild.dev` and `codespace.indiebuild.dev` are Access-protected interactive surfaces. `hooks.indiebuild.dev` / `ci-laptop.indiebuild.dev` remain separate signed-machine/webhook surfaces; never weaken Access to make automation work.

## Codespace bootstrap

The devcontainer installs reviewed private `ORESoftware/ores-cli` revision `c854130ee147e9793a3af8736e90241630a5c934`. That revision contains the external-origin connector behavior consumed by the shared full lifecycle.

Because `ORESoftware/ores-cli` is private and cross-owner, configure `ORES_CLI_READ_TOKEN` as a fine-grained Codespaces secret with read-only Contents access to that repository. Configure `TUNNEL_TOKEN` separately for the pre-provisioned named Cloudflare tunnel. The bootstrap token is used only for Git/Cargo installation and must not become application configuration.

Port 8080 stays private to the Codespace and is marked `onAutoForward: ignore`; Cloudflare connects to loopback from `cloudflared` inside the same Codespace rather than proxying a `*.app.github.dev` URL.

## Secret boundary

No tunnel token, GitHub bootstrap token, or credential JSON belongs in Git, `.ores-compose.yaml`, process arguments, Terraform variables committed to the repository, or devcontainer configuration. Real tunnel configs/credential files live outside the checkout. `.runtime/` is ignored for non-secret transient state, but the legacy config-driven tunnel wrapper still rejects a real config path inside the repository.
