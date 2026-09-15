# Laptop and Codespaces development contract

The infra repository owns one `.ores-compose.yaml`. Laptop and Codespaces use that same manifest and exact source commit; environment-specific service graphs are forbidden.

## Current readiness

The source/materialization contract is exact, but the application runtime is intentionally **not declared healthy yet**. The pinned API and web server revisions currently print their configured bind/output and exit instead of maintaining listening HTTP servers. `scripts/dev/doctor` recognizes those exact stub pins and fails closed. Do not bypass the doctor by adding `sleep`, fake health checks or a moving branch reference.

The advanced `ores.compose.v1` source contract is being promoted through `ORESoftware/ores-compose`; the manifest is authored against its reviewed exact-source schema (`repository`, 40-hex `commit`, traversal-free `checkout_dir`). Runtime activation waits for that stack and real server listeners.

## Workflow

1. `scripts/dev/bootstrap` initializes `_apps/gha-monorepo` and its tracked nested gitlinks at the recorded revisions. It uses checkout semantics only; it does not rebase/reset/force-push.
2. `scripts/dev/doctor` verifies the infra gitlink, compose source pin, required tools, initialized source and the known server-readiness blocker.
3. Once doctor passes, start the local `ores-compose` origin on `127.0.0.1:8080`. Keep it foreground-attached so logs and Ctrl-C retain one explicit shutdown boundary.
4. For laptop development, copy the appropriate Cloudflare config outside the repository and run `scripts/dev/tunnel laptop /abs/config.yml` if that legacy config-driven path is required.
5. For Codespaces, use the shared connector-only Rust lifecycle: `just codespace-edge-check`, then `just codespace-edge-up`. `oresc` requires the local origin's `/readyz` to be healthy before starting `cloudflared`, and `just codespace-edge-down` stops only the connector, not the local `ores-compose` origin.

`local.indiebuild.dev` and `codespace.indiebuild.dev` are Access-protected interactive surfaces. `hooks.indiebuild.dev` / `ci-laptop.indiebuild.dev` remain separate signed-machine/webhook surfaces; never weaken Access to make automation work.

## Codespace bootstrap

The devcontainer installs reviewed private `ORESoftware/ores-cli` revision `c854130ee147e9793a3af8736e90241630a5c934`. That revision uses the external-origin connector model while preserving fail-clean state/process hardening.

Because `ORESoftware/ores-cli` is private and cross-owner, configure `ORES_CLI_READ_TOKEN` as a fine-grained Codespaces secret with read-only Contents access to that repository. Configure `TUNNEL_TOKEN` separately for the pre-provisioned named Cloudflare tunnel. The bootstrap token is used only for Git/Cargo installation and must not become application configuration.

Port 8080 stays private to the Codespace and is marked `onAutoForward: ignore`; Cloudflare connects to loopback from `cloudflared` inside the same Codespace rather than proxying a `*.app.github.dev` URL.

## Secret boundary

No tunnel token or credential JSON belongs in Git, `.ores-compose.yaml`, process arguments, Terraform variables committed to the repository, or devcontainer configuration. Real tunnel configs/credential files live outside the checkout. `.runtime/` is ignored for non-secret transient state, but the legacy config-driven tunnel wrapper still rejects a real config path inside the repository.
