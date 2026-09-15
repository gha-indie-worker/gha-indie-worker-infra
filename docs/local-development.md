# Laptop and Codespaces development contract

The infra repository owns one `.ores-compose.yaml`. Laptop and Codespaces use that same manifest and exact source commit; environment-specific service graphs are forbidden.

## Current readiness

The source/materialization contract is now exact, but the runtime is intentionally **not declared healthy yet**. The pinned API and web server revisions currently print their configured bind/output and exit instead of maintaining listening HTTP servers. `scripts/dev/doctor` recognizes those exact stub pins and fails closed. Do not bypass the doctor by adding `sleep`, fake health checks or a moving branch reference.

The advanced `ores.compose.v1` source contract is also being promoted through `ORESoftware/ores-compose`; the manifest is authored against its reviewed exact-source schema (`repository`, 40-hex `commit`, traversal-free `checkout_dir`). Runtime activation waits for that stack and the real server listeners.

## Workflow

1. `scripts/dev/bootstrap` initializes `_apps/gha-monorepo` and its tracked nested gitlinks at the recorded revisions. It uses checkout semantics only; it does not rebase/reset/force-push.
2. `scripts/dev/doctor` verifies the infra gitlink, compose source pin, required tools, initialized source and the known server-readiness blocker.
3. Once doctor passes, start the local ores-compose gateway bound to `127.0.0.1:8080`.
4. On a laptop, copy the appropriate Cloudflare config outside the repository and run `scripts/dev/tunnel laptop /abs/config.yml`.
5. In a Codespace, use the standardized ORESoftware lifecycle instead of maintaining a second tunnel supervisor here:

   ```sh
   just codespace-edge-check
   just codespace-edge-up
   just codespace-edge-status
   just codespace-edge-down
   ```

   These recipes delegate to `oresc codespace edge up|status|down`. Port 8080 is intentionally marked `onAutoForward: ignore`; `cloudflared` reaches the loopback origin directly.

`local.indiebuild.dev` and `codespace.indiebuild.dev` are Access-protected interactive surfaces. `hooks.indiebuild.dev` / `ci-laptop.indiebuild.dev` remain separate signed-machine/webhook surfaces; never weaken Access to make automation work.

## Codespaces bootstrap

`ORESoftware/ores-cli` is private and belongs to a different owner than this repository. GitHub Codespaces cannot grant its source-repository token cross-owner access through the `repositories` devcontainer permission mechanism, so a fresh Codespace uses a separate read-only bootstrap credential.

Configure these as GitHub Codespaces secrets; never paste their values into this repository:

- `ORES_CLI_READ_TOKEN`: a fine-grained GitHub token limited to read-only Contents access on `ORESoftware/ores-cli`. It is used only by the post-create install path. Cargo uses the Git CLI credential helper so the token stays in the environment rather than a Git URL or argv.
- `TUNNEL_TOKEN`: the remotely managed Cloudflare Tunnel connector token used later by `oresc codespace edge up`.

The devcontainer records only the secret **names and descriptions**. Secret values are supplied by GitHub Codespaces at runtime. Rebuild or create a new Codespace after devcontainer changes; existing containers do not gain new provisioning automatically.

## Secret boundary

No tunnel token, GitHub token or credential JSON belongs in Git, `.ores-compose.yaml`, process arguments, Terraform variables committed to the repository, or devcontainer configuration. Real laptop tunnel configs/credential files live outside the checkout. `.runtime/` is ignored for non-secret transient state, but the laptop tunnel wrapper still rejects a real config path inside the repository.
