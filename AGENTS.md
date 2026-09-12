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

## Repository-local Git worktrees


- Infra layout: `terraform/gcp` (project, VPC, Cloud Run, WIF), `terraform/cloudflare` (DNS, Access, WAF), `cloudflare/edge-router` (Worker routes), `k8s/`, `neon/`, `supabase/`.
- Apply order: GCP first, then Cloudflare DNS/Access/WAF, then the edge-router Worker, then Neon/Supabase desired state. Each step produces an input to the next.
- Worker routes belong to `cloudflare/edge-router/wrangler.toml`; DNS records belong to Terraform. One object, one owner — never both.
- `wrangler.toml` is RENDERED from `router.config.json`. Never hand-edit it; CI fails on drift.
- CI never applies Terraform. `terraform.yml` plans only; an apply is a human running `scripts/apply-terraform.sh <root> --apply`.
- No secret value is ever committed. Terraform creates Secret Manager containers, not versions; k8s manifests reference secrets by name only.
- The admin plane is closed by four independent gates (Cloudflare Access, the edge Worker, Cloud Run internal ingress, network policy + firewall). Never relax one on the assumption that another still holds.
- `infra-isolation/` is vendored and fail-closed. Only `contract.json` is org-specific and editable; never weaken a check to make it pass.
- Create or use a Git worktree only when the human operator explicitly authorizes it for the current task. Concurrency or a dirty checkout is not permission by itself.
- Put every authorized worktree at `<repository-root>/tmp/worktrees/<name>`; from the repository root, use `./tmp/worktrees/<name>`. Never place worktrees beside repositories or organization directories.
- Keep `tmp`, `temp`, `tmp/worktrees`, and `temp/worktrees` ignored in the repository-root `.gitignore`. Do not commit files from those directories.
- Relocate or remove a worktree only when the operator explicitly requests it. Before removal, preserve and publish intended changes, verify its commit is represented on the target branch, and confirm there are no tracked, untracked, ignored-sensitive, or in-use files that must survive. Remove it with `git worktree remove <path>` without `--force`; never delete a worktree directory with `rm`.
