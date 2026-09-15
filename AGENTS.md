# GHA Indie Worker — infra

Canonical `infra` repository for [`gha-indie-worker`](https://github.com/gha-indie-worker).

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

- Terraform child modules live only under `modules/{gcp,cloudflare,neon,supabase}` (provider submodules are allowed).
- Terraform root/state ownership lives only under `environments/<environment>/<state-root>`.
- Production preserves independent state roots for GCP platform, GCP Cloud Run, Cloudflare platform, Cloudflare DNS and Neon; never merge state histories merely because modules share a provider.
- Provider-native sources remain in their discovery roots: `cloudflare/edge-router`, `neon/`, `supabase/`, `k8s/`.
- `supabase/` is the native authority today; do not invent Terraform-owned Supabase resources just to make the module non-empty.
- Provider blocks/backends/environment tfvars do not belong in `modules/`; provider auth/config and state belong in `environments/`.
- When moving managed resources into modules, preserve state with reviewed `moved` blocks and the migration runbook. A destroy/recreate caused only by the layout migration is a hard blocker.
- Apply order: GCP first, then Cloudflare DNS/Access/WAF, then the edge-router Worker, then Neon/Supabase desired state. Each step produces an input to the next.
- Worker routes belong to `cloudflare/edge-router/wrangler.toml`; DNS records belong to Terraform. One object, one owner — never both.
- `wrangler.toml` is RENDERED from `router.config.json`. Never hand-edit it; CI fails on drift.
- CI never applies Terraform. `terraform.yml` plans only; an apply is a human running `scripts/apply-terraform.sh <environment/root> --apply`.
- No secret value is ever committed. Terraform creates Secret Manager containers, not versions; k8s manifests reference secrets by name only.
- The admin plane is closed by four independent gates (Cloudflare Access, the edge Worker, Cloud Run internal ingress, network policy + firewall). Never relax one on the assumption that another still holds.
- `infra-isolation/` is vendored and fail-closed. Only `contract.json` is org-specific and editable; never weaken a check to make it pass.

## Application checkout boundary

- `_apps/gha-monorepo` is a tracked gitlink to `gha-indie-worker/gha-indie-worker-monorepo`, pinned by the parent infra commit. Treat it as read-only input while doing infra work.
- Initialize the recorded pin with `scripts/sync-apps.sh`; never make ordinary infra validation follow remote `main` implicitly.
- Advance the pin only as a deliberate reviewable gitlink change, e.g. with `scripts/update-app-pin.sh`; make product changes in the monorepo itself, not through the submodule checkout.
- `dist/` is generated/local output. `_apps/*` is ignored except for the one tracked monorepo gitlink. Do not commit generated app trees under either directory.
- Terraform under `modules/` or `environments/` must never source from `_apps/` or `dist/`; state and plans must be reproducible without initializing the app submodule.

## Repository-local Git worktrees

- Create or use a Git worktree only when the human operator explicitly authorizes it for the current task. Concurrency or a dirty checkout is not permission by itself.
- Put every authorized worktree at `<repository-root>/tmp/worktrees/<name>`; from the repository root, use `./tmp/worktrees/<name>`. Never place worktrees beside repositories or organization directories.
- Keep `tmp`, `temp`, `tmp/worktrees`, and `temp/worktrees` ignored in the repository-root `.gitignore`. Do not commit files from those directories.
- Relocate or remove a worktree only when the operator explicitly requests it. Before removal, preserve and publish intended changes, verify its commit is represented on the target branch, and confirm there are no tracked, untracked, ignored-sensitive, or in-use files that must survive. Remove it with `git worktree remove <path>` without `--force`; never delete a worktree directory with `rm`.
