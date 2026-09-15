# GHA Indie Worker — infra

Canonical `infra` repository for `gha-indie-worker`.

- Internal runtimes: Rust, TypeScript, Dart.
- Contracts: JSON Schema in `gha-indie-worker-interfaces`.
- Auth: github.com/shared-auth.
- Sync: github.com/opto-sync.
- Telemetry: github.com/ores-otel.
- Flags: github.com/flags-2-env.
- Packages: github.com/zed-pkg.
- Never use React/JSX or webviews.
- Resolve git conflicts semantically; never rebase, stash, or reset.

## Infrastructure layout

- Provider-dependent Terraform lives only in `modules/{gcp,cloudflare,neon,supabase}` for new work.
- Environment/provider/backend composition lives in `environments/<environment>/<provider>`; production is `environments/production`.
- Historical provider roots are migration references only. Do not add resources there; remove them after state addresses are migrated and verified.
- Apply order: GCP first, then Cloudflare DNS/Access/WAF, then the edge-router Worker, then Neon/Supabase desired state. Each step produces an input to the next.
- Worker routes belong to `cloudflare/edge-router/wrangler.toml`; DNS records belong to Terraform. One object, one owner — never both.
- `wrangler.toml` is rendered from `router.config.json`. Never hand-edit it; CI fails on drift.
- CI never applies Terraform. Applies are explicit human actions through `scripts/apply-terraform.sh`.
- No secret value is ever committed. Terraform creates Secret Manager containers, not versions; k8s manifests reference secrets by name only.
- The admin plane is closed by independent gates (Cloudflare Access, edge Worker, Cloud Run internal ingress, network policy + firewall). Never relax one on the assumption another still holds.
- `infra-isolation/` is vendored and fail-closed. Only `contract.json` is org-specific and editable; never weaken a check to make it pass.

## Local application checkout

- `_apps/gha-monorepo` is the sole tracked submodule under `_apps/` and points to `gha-indie-worker/gha-indie-worker-monorepo`.
- `dist/` and all other `_apps/*` contents are ignored. Use `scripts/sync-apps.sh`; do not commit build products from either directory.

## Repository-local Git worktrees

- Create or use a Git worktree only when the human operator explicitly authorizes it for the current task.
- Put every authorized worktree at `<repository-root>/tmp/worktrees/<name>`.
- Keep `tmp`, `temp`, `tmp/worktrees`, and `temp/worktrees` ignored.
- Relocate or remove a worktree only when explicitly requested; preserve intended changes first and use `git worktree remove` without `--force`.
