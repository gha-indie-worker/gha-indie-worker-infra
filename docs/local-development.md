# Laptop and Codespaces development contract

The infra repository owns one `.ores-compose.yaml`. Laptop and Codespaces use that same manifest and exact source commit; environment-specific service graphs are forbidden.

## Current readiness

The source/materialization contract is now exact, but the runtime is intentionally **not declared healthy yet**. The pinned API and web server revisions currently print their configured bind/output and exit instead of maintaining listening HTTP servers. `scripts/dev/doctor` recognizes those exact stub pins and fails closed. Do not bypass the doctor by adding `sleep`, fake health checks or a moving branch reference.

The advanced `ores.compose.v1` source contract is also being promoted through `ORESoftware/ores-compose`; the manifest is authored against its reviewed exact-source schema (`repository`, 40-hex `commit`, traversal-free `checkout_dir`). Runtime activation waits for that stack and the real server listeners.

## Workflow

1. `scripts/dev/bootstrap` initializes `_apps/gha-monorepo` and its tracked nested gitlinks at the recorded revisions. It uses checkout semantics only; it does not rebase/reset/force-push.
2. `scripts/dev/doctor` verifies the infra gitlink, compose source pin, required tools, initialized source and the known server-readiness blocker.
3. Once doctor passes, start the local ores-compose gateway bound to `127.0.0.1:8080`.
4. Copy the appropriate Cloudflare config outside the repository and run `scripts/dev/tunnel laptop /abs/config.yml` or `scripts/dev/tunnel codespace /abs/config.yml`.

`local.indiebuild.dev` and `codespace.indiebuild.dev` are Access-protected interactive surfaces. `hooks.indiebuild.dev` / `ci-laptop.indiebuild.dev` remain separate signed-machine/webhook surfaces; never weaken Access to make automation work.

## Secret boundary

No tunnel token or credential JSON belongs in Git, `.ores-compose.yaml`, process arguments, Terraform variables committed to the repository, or devcontainer configuration. Real tunnel configs/credential files live outside the checkout. `.runtime/` is ignored for non-secret transient state, but the tunnel wrapper still rejects a real config path inside the repository.
