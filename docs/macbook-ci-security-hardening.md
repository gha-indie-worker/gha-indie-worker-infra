# MacBook CI security hardening (review-only)

This change stacks on gha-indie-worker-infra#142. It does not apply a Cloudflare
route, enable an extra repository, mutate GitHub runner registrations, modify
macOS LaunchAgents, or change a protected branch. Local GitHub-native runs from
that PR remain **Linux OCI guests inside the Lima VM**; they are **not native
macOS job execution**.

## Runtime admission

The existing per-repository allowlist and exact runner image digest remain
mandatory before requesting a short-lived registration token. The host broker
now rejects root execution, rejects a root VM shell session, disables shell
xtrace, and refuses malformed token replies. The container uses
`--cap-drop=ALL` and `--security-opt no-new-privileges` in addition to one-job
`--ephemeral`, no default labels, no image pulls, fixed resource limits and
`--rm`. Confirm the warmed image's test-tool requirements still run with those
restrictions before promotion. **A nonroot VM session alone does not prove the
container runtime is rootless.** Verify the daemon socket, cgroup settings,
network policy and guest isolation on the real MacBook separately.

The MacBook broker now uses an owner-only per-login lock at
`~/.cache/indiebuild-runner/active.lock` to reject concurrent launches before
requesting any GitHub registration token. Names incorporate a per-invocation
UUID, and normal/signal shutdown attempts to force-remove the attached Lima
container. A power loss or SIGKILL may leave the lock intact deliberately.
**Never delete a stale lock just to resume CI**: first inspect runner/container
state in the guest, check GitHub's runner registration state, stop/remove any
survivors, and only then remove the lock. Locking is **per macOS account**, not
a proof of machine-wide mutual exclusion or host/LAN isolation. A failed
container cleanup leaves the lock in place. The offline lifecycle fixture uses
mocked `gh`, `limactl`, and `nerdctl`; it does not certify a live MacBook.

This broker is a **registration-token** prototype, not a GitHub JIT config API
integration. It does not bind a runner to a specific GitHub workflow/job ID or
reliably prevent admission of untrusted fork PRs. Do not expand it to public
fork workloads until job-origin trust and host/LAN egress isolation are proven.
GitHub App least-privilege JIT one-job admission remains tracked at
giw-desktop-infra#18.

## Cloudflare

The example tunnel configuration now exposes **only**
`origin-status.indiebuild.dev -> http://127.0.0.1:18091` and an explicit final
`http_status:404`. The public apex and `builds.indiebuild.dev` continue to be
served by the separate reviewed Cloudflare availability Worker, *not* as
additional tunnel hostnames. Never proxy GIW/Scintilla daemon control ports
`8770` and `8765`, or tunnel metrics `20392`.

For a locally managed tunnel, an operator should copy the example into an
owner-only external config and run (on macOS with `cloudflared` installed):

```sh
cloudflared tunnel --config "$HOME/.config/indiebuild-status/cloudflared.yml" ingress validate
cloudflared tunnel --config "$HOME/.config/indiebuild-status/cloudflared.yml" ingress rule https://origin-status.indiebuild.dev/health
cloudflared tunnel --config "$HOME/.config/indiebuild-status/cloudflared.yml" ingress rule https://indiebuild.dev/v1/jobs/dispatch
```

Expect only the first rule to select the app origin; the unrelated hostname
must fall back to `http_status:404`. The offline syntax/structural tests do not
prove live Cloudflare Access, WAF, DNS, tunnel credentials or ingress. Inspect
actual provider state and exercise negative path, method, HMAC and port probes
independently before promoting the webhook tunnel.

## Verification and promotion

```sh
bash -n scripts/ci/run-local-runner.sh
node --test scripts/ci/validate-macbook-ci.test.mjs
node scripts/ci/validate-macbook-ci.mjs
```

The offline receipt validator rejects duplicate/mismatched run and job IDs,
missing source/workflow SHAs, nonexistent runner identity, unadmitted repo,
wrong runner label, pending/failed jobs, or no real successful `Run ...` steps.
It is **not a live GitHub API attestation** and cannot detect receipts
fabricated to conform to its schema. For production evidence, independently
read back GitHub's run/job/step results, exact current PR head and workflow blob
from the GitHub API and compare with the receipt. Keep the proof bounded to the
exact recorded source SHA; do not present a past success as current success.

This change does not certify native macOS toolchain execution, crash cleanup,
LAN/network isolation, registry revocation on forced termination, or unattended
FileVault/sleep recovery. Those require a private controlled fixture repository
and a real physical-laptop run. Independent review is required before any
merge or operational rollout.
