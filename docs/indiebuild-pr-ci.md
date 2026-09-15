# External PR CI when GitHub-hosted minutes are unavailable

## Trust boundary

`hooks.indiebuild.dev` is only an edge ingress. Cloudflare bounds and forwards the exact raw webhook body; the Rust origin verifies `X-Hub-Signature-256`, applies the repository/profile allowlist, rejects draft/fork execution, dispatches a fixed build profile, and writes `indiebuild.dev/ci` to the exact PR head SHA.

The edge never owns GitHub status/build-server credentials and never executes repository code. Unknown repositories fail closed.

## Initial fixed profile

The initial allowlist contains ten Rust repositories and only the `rust-verify` profile: formatting, Clippy with warnings denied, and tests against the committed lockfile. Arbitrary workflow commands from PR content are not accepted.

## Activation order

1. Merge and publish the reviewed Rust PR-gateway image from `gha-clone-server.rs`.
2. Provision `gha-indie-worker-pr-gateway` through the sealed-secret path; do not put values in this repository.
3. Apply `k8s/pr-gateway.yaml` using the normal human-gated cluster path.
4. Deploy `cloudflare/pr-gateway` with runtime `PR_GATEWAY_ORIGIN` set to the restricted HTTPS Rust origin.
5. Configure the signed GitHub pull-request webhook at `https://hooks.indiebuild.dev/webhooks/github`.
6. Prove a signed event produces `pending -> success|failure` on the exact head SHA before making `indiebuild.dev/ci` required.

A zero-job GitHub Actions `startup_failure` is infrastructure non-evidence when hosted minutes are exhausted. It is not a substitute for the external status or for real stepful validation when capacity exists.

## Provider boundaries

- Neon stays exactly canonical/auth/admin; PR dispatch does not create a fourth project.
- Supabase gets no CI project and stores no webhook/status/build credentials.
- Kubernetes runs a least-privilege gateway control plane; repository code executes only in the worker/build executor.
- Cloudflare only preserves/bounds/proxies the webhook and exposes no arbitrary proxy target from request data.
