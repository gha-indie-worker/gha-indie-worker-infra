# Zero-hosted-minute PR CI with indiebuild.dev

## Contract

GitHub Actions remains the PR trigger/syntax surface, but its smoke job is skipped at **job** level with `if: ${{ false }}`. No runner is allocated. Long-form verification runs on gha-indie-worker infrastructure hosted behind indiebuild.dev and reports one commit status back to the exact PR head SHA:

`indiebuild.dev/ci`

The status is the merge gate once the external control plane is deployed and observed healthy.

## Initial allowlist

All initial repositories use the fixed `rust-verify` profile (`cargo fmt --check`, `cargo clippy --locked --all-targets --all-features -- -D warnings`, and `cargo test --locked --all-targets --all-features`). Each selected repo has a committed `Cargo.lock`.

| organization | repository | profile |
|---|---|---|
| gha-indie-worker | `gha-clone-server.rs` | `rust-verify` |
| gha-indie-worker | `gha-indie-worker-cli` | `rust-verify` |
| zed-pkg | `zed-sidecar.rs` | `rust-verify` |
| zed-pkg | `zed-mcp-server.rs` | `rust-verify` |
| shared-auth | `shared-auth-sidecar.rs` | `rust-verify` |
| shared-auth | `shared-auth-server.rs` | `rust-verify` |
| opto-sync | `opto-sync-sidecar.rs` | `rust-verify` |
| opto-sync | `opto-sync-api-server.rs` | `rust-verify` |
| fiducia-cloud | `fiducia-api-server.rs` | `rust-verify` |
| fiducia-cloud | `fiducia-mcp-server.rs` | `rust-verify` |

The runtime allowlist is the `INDIEBUILD_REPO_PROFILES` ConfigMap value in `k8s/pr-gateway.yaml`. Unknown repos are ignored and fork PRs are not executed.

## Request path

1. GitHub emits `pull_request` for `opened`, `synchronize`, `reopened`, or `ready_for_review`.
2. `hooks.indiebuild.dev` accepts only the webhook path, bounds the body, and forwards the exact bytes to the Rust gateway.
3. The Rust gateway verifies `X-Hub-Signature-256`, checks the repo/profile allowlist, rejects draft/fork execution, and posts `indiebuild.dev/ci = pending`.
4. The gateway submits a `run-profile` request to gha-indie-worker with `push=false` and an idempotent request ID derived from repository, PR number, SHA, and profile.
5. gha-indie-worker clones the named branch and executes only the fixed profile command sequence.
6. The gateway polls the job and changes the exact head SHA status to `success`, `failure`, or `error`.

## Activation order

Do not require the external status before it can be emitted.

1. Merge/build the `indiebuild-pr-gateway` target in `gha-clone-server.rs` and publish `ghcr.io/gha-indie-worker/gha-clone-server.rs:pr-gateway`.
2. Provision the sealed secret named `gha-indie-worker-pr-gateway`; secret values never enter this repository.
3. Apply `k8s/pr-gateway.yaml` through the normal human-gated deployment path.
4. Deploy `cloudflare/pr-gateway` with `PR_GATEWAY_ORIGIN` pointed at the restricted gateway origin.
5. Configure GitHub organization/repository webhooks for Pull requests at `https://hooks.indiebuild.dev/webhooks/github` using the same HMAC secret.
6. Send GitHub's ping and one test PR update; confirm `pending -> success/failure` on `indiebuild.dev/ci` and confirm the GitHub smoke job remains skipped with no runner steps.
7. Merge the per-repo smoke workflow PRs.
8. Only after step 6 is observed should branch protection require `indiebuild.dev/ci`.

## Provider boundaries

- **Cloudflare:** public webhook edge only. No GitHub or build-server credentials; raw request bytes stay intact for origin HMAC verification.
- **Neon:** no fourth CI project. `neon/ci_control_plane.tf` asserts reuse of the existing canonical/auth/admin topology; the gateway itself stays stateless.
- **Supabase:** no shadow CI project and no webhook/status secrets in Supabase. `supabase/ci-control-plane/config.toml` records this as desired state.
- **Kubernetes:** the gateway is a separate least-privilege workload. Secrets are referenced by name only, the filesystem is read-only, and network egress is bounded to DNS, GitHub/build-server HTTPS, and same-namespace service traffic.
