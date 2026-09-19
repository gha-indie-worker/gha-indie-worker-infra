# Laptop CI wave 1

This document defines the first broad local IndieBuild trial. The machine-readable cohort is `cohorts/laptop-ci-wave-1.json`: 30 pull requests across 16 GitHub organizations.

## Purpose

The trial is intended to answer four independent questions:

1. Can `ores-compose` materialize and launch the local IndieBuild control plane reproducibly?
2. Can `gha-indie-worker` verify an immutable pull-request head using an operator-reviewed profile without exposing host credentials to tested code?
3. Can the result be published as a GitHub **Check Run owned by the dedicated IndieBuild App** and bound to the exact head?
4. Does the local result agree with repository-native GitHub Actions when a stepful hosted run exists, and can differences be classified instead of hidden?

This wave is **advisory**. Do not make its result a required merge context until the promotion gates below are satisfied.

## Launch boundary

`ores-compose` owns long-running local processes and their dependency graph. `giw` is the operator UX for setup, webhook registration, inspection, and cohort submission; it must not become a second independent supervisor for the same worker/tunnel processes.

The public path is:

```text
GitHub pull_request webhook
  -> https://ci-laptop.indiebuild.dev/webhooks/github
  -> Cloudflare Tunnel
  -> loopback gha-indie-worker
  -> exact-head fixed profile
  -> GitHub App Check Run
```

Only the signed webhook endpoint is public. Build-control endpoints, API/web helper services, and logs remain local/private.

## Prerequisites

The cohort manifest is the machine-readable prerequisite authority for this wave. In particular:

- `ORESoftware/ores-compose#154` implements `#152`: fail-closed per-service env/secret policy plus executor isolation. The parser alone is insufficient; build commands, services, and healthchecks must all use `env_clear()` so Cloudflare/GitHub credentials are not ambient in sibling or tested processes.
- `gha-indie-worker/gha-indie-worker.rs#77` must resolve/verify the GitHub App installation server-side for each repository. One global installation id is not sufficient across 16 organizations.
- `gha-indie-worker/gha-indie-worker.rs#78` must durably reconcile report delivery after crash/restart. A locally succeeded job whose terminal App Check Run was never delivered is **not** trusted CI success.
- authoritative reporting uses `indiebuild.dev/ci` only for an App-owned Check Run. Any PAT Commit Status fallback uses `indiebuild.dev/ci-advisory` and is non-counting.
- exact-head checkout/hardening comes from worker #73/#74.
- `gha-indie-worker/gha-indie-worker-infra#46` owns the current `ores.compose.v1` worker + tunnel control-plane composition.

## Operator commands

Validate the complete cohort without submitting work:

```bash
scripts/run-laptop-ci-wave-1.sh --dry-run
```

Run one cohort entry first:

```bash
scripts/run-laptop-ci-wave-1.sh --entry ORESoftware/ores-compose#150
```

Continue through independent failures while retaining every receipt event:

```bash
scripts/run-laptop-ci-wave-1.sh --continue-on-failure
```

The runner is intentionally serial. Job concurrency, CPU/memory limits, queueing, cancellation, and fairness belong to the worker scheduler where they can be audited as execution policy rather than hidden in a shell loop.

Receipts are append-only NDJSON below `.indiebuild/receipts/` by default and are created with restrictive local permissions where the platform supports them.

## Submission protocol

For every cohort entry the runner:

1. Reads the PR from GitHub immediately before submission.
2. Requires `state=open`, non-draft state, and the PR head repository to equal the base repository; fork heads are refused.
3. Captures the current **40-character lowercase** Git head object id.
4. Records an `entry_admitted` event before submission.
5. Submits only the operator-selected fixed profile from the cohort manifest through `giw --json verify`.
6. Requires `giw` to echo the exact admitted SHA together with a job id and terminal status.
7. Re-reads the PR after execution. If the head moved, the result is recorded as `stale=true` and cannot be current success.
8. Never lets a branch name substitute for the captured immutable object id inside the worker.

The manifest deliberately does **not** pin today's SHA. The execution receipt does.

## Execution receipt

`cohorts/laptop-ci-wave-1-receipt.schema.json` defines the append-only event envelope used by the operator runner. The first slice records admission and worker completion evidence without pretending that the local receipt itself is GitHub authority.

The eventual worker-owned durable receipt should additionally retain:

```json
{
  "repo": "owner/name",
  "pullRequest": 123,
  "headSha": "...",
  "profile": "rust-verify",
  "jobId": "...",
  "checkoutVerified": true,
  "zed": {
    "mode": "frozen",
    "lockDigest": "...",
    "verified": true
  },
  "result": "success|failure|error|cancelled|timeout",
  "logDigest": "sha256:...",
  "reporting": {
    "kind": "app-check|advisory-status|none",
    "context": "indiebuild.dev/ci",
    "appId": 0,
    "checkRunId": 0,
    "delivered": true
  },
  "nativeGitHubActions": {
    "available": true,
    "stepful": true,
    "conclusion": "success|failure|cancelled|..."
  }
}
```

Secret values, private keys, webhook secrets, tokens, and full unredacted environments are never receipt fields.

## Zed / zpkg dependency boundary

Wave 1 may use the existing `zed` CLI path because that is the currently implemented behavior. Do **not** describe that as an SDK integration.

Current architecture:

```text
zed-cli
  managed_install.rs
  manifestless.rs
  ops.rs
  materialize.rs
  locking/config/store/adapters

zed-lib-core
  resolution + planning primitives
```

The target architecture is:

```text
zed-lib-core
  install_frozen(...)
  verify_install(...)
  immutable materialization receipt
        ↑
   zed-cli (thin projection)
        ↑
   ores-compose (in-process consumer)
```

The extraction is complete only when CLI and in-process callers share the same behavioral implementation and conformance fixtures. Wrapping `zed` as a child process under a Rust function is not the target SDK.

Until that extraction lands, the receipt should state that the CLI lane was used and retain the lock digest / exact materialization evidence required to reproduce it.

## Profile preflight

Wave 1 intentionally uses only installed fixed profiles. The cohort currently selects `rust-verify`, `node-verify`, and `flutter-verify`; the runner itself has a closed operator profile allowlist for other reviewed worker profiles.

Before scheduling a job, preflight the selected profile's structural requirements. Examples:

- `rust-verify`: repository must have the reviewed Rust layout and a lockfile required by its locked cargo commands;
- `node-verify`: one supported lockfile must exist;
- `flutter-verify`: Flutter package metadata/lock must be present.

A preflight mismatch is a cohort result (`unsupported-profile-layout`), not permission to synthesize a custom PR-provided command.

## Promotion gate

Only after the advisory cohort has been exercised should `ores-gh-bots` count IndieBuild. Promotion requires:

- the current PR head equals the check's head SHA;
- check name/context is exactly `indiebuild.dev/ci`;
- check source is a GitHub Check Run, not a Commit Status;
- raw Check Run status is exactly `completed`;
- raw Check Run conclusion is exactly `success` — `neutral` and `skipped` are not authoritative IndieBuild success;
- the check belongs to the configured dedicated IndieBuild GitHub App ID;
- PAT statuses under `indiebuild.dev/ci-advisory` never count;
- the terminal verdict was actually delivered to GitHub;
- worker restart/recovery reconciles orphaned in-progress checks and undelivered terminal verdicts without inferring success;
- a newer head cannot inherit a prior head's result;
- local evidence and hosted Actions disagreements are retained and investigated, not overwritten.

`ORESoftware/ores-gh-bots` already supports binding required CI contexts to expected App IDs through `REQUIRED_CI_CONTEXTS` and `REQUIRED_CI_APP_IDS`. Once the IndieBuild App is registered, the intended gate configuration is structurally:

```text
REQUIRED_CI_CONTEXTS=indiebuild.dev/ci,...
REQUIRED_CI_APP_IDS=indiebuild.dev/ci=<INDIEBUILD_APP_ID>,...
```

The current `ores-gh-bots#58` implementation still needs two fixes before promotion:

1. provider review state must not become countable before the corresponding terminal provider Check Run has been successfully published;
2. App-bound required CI must inspect the raw Check Run conclusion so `neutral`/`skipped` cannot normalize into `success`.

The review-provider attestations remain a separate evidence class. CI success must not be inferred from PR comments or agent-review markers.

## Hosted Actions comparison

A red hosted workflow with **zero executable steps** is runner/admission/infrastructure evidence, not a code failure and not a pass. Record it separately from stepful test results.

When hosted Actions are available, compare against the same PR head SHA. A comparison is meaningful only when both lanes demonstrably executed work for the same immutable revision.

## Rollout

Run the cohort in small batches first (for example 1 -> 5 -> 10 -> 30) while keeping the complete manifest fixed. Capture exact-head receipts on every attempt. Re-run an entry only for an explicit reason (new head, infrastructure retry, or profile correction), and retain the earlier receipt rather than replacing it.

A successful wave is not "30 green PRs". It is 30 attributable outcomes whose source checkout, dependency preparation, execution, report delivery, and GitHub identity can each be explained and reproduced.
