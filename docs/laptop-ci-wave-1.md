# Laptop CI wave 1

This document defines the first broad local IndieBuild trial. The machine-readable cohort is `cohorts/laptop-ci-wave-1.json`: 30 open pull requests across 16 GitHub organizations.

## Purpose

The trial is intended to answer four independent questions:

1. Can `ores-compose` materialize and launch the local IndieBuild control plane reproducibly?
2. Can `gha-indie-worker` verify an immutable pull-request head using an operator-reviewed profile without exposing host credentials to tested code?
3. Can the result be published as a GitHub **Check Run owned by the dedicated IndieBuild App** and bound to the exact head?
4. Does the local result agree with repository-native GitHub Actions when a stepful hosted run exists, and can differences be classified instead of hidden?

This wave is **advisory**. Do not make its result a required merge context until the promotion gates below are satisfied.

## Launch boundary

`ores-compose` owns long-running local processes and their dependency graph. `giw` is the operator UX for setup, webhook registration, inspection, and cohort submission; it should not become a second independent supervisor for the same worker/tunnel processes.

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

The cohort manifest names the tracked prerequisites. In particular:

- `ORESoftware/ores-compose#152` must provide fail-closed per-service env/secret isolation so Cloudflare and GitHub credentials are not ambient in sibling/tested processes.
- `gha-indie-worker/gha-indie-worker.rs#77` must resolve/verify the GitHub App installation server-side for each repository. One global installation id is not sufficient across 16 organizations.
- authoritative reporting must use `indiebuild.dev/ci` only for an App-owned Check Run. Any PAT Commit Status fallback uses `indiebuild.dev/ci-advisory` and is non-counting.
- exact-head checkout/hardening comes from worker #73/#74.

## Submission protocol

For every cohort entry:

1. Read the PR from GitHub immediately before submission.
2. Require `state=open` and require the PR head repository to equal the base repository; fork heads are refused.
3. Capture the current 40/64-character lowercase head object id.
4. Submit that immutable id with the operator-selected profile from the cohort manifest.
5. Never re-resolve a branch inside the worker.
6. If the PR head changes after capture, the result belongs only to the captured old head and must not satisfy the new head.

The manifest deliberately does **not** pin today's SHA. The execution receipt does.

## Execution receipt

Retain one receipt per attempt containing at least:

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

## Profile preflight

Wave 1 intentionally uses only installed fixed profiles: `rust-verify`, `node-verify`, and `flutter-verify`.

Before scheduling a job, preflight the selected profile's structural requirements. Examples:

- `rust-verify`: repository must have the reviewed Rust layout and a lockfile required by its locked cargo commands;
- `node-verify`: one supported lockfile must exist;
- `flutter-verify`: Flutter package metadata/lock must be present.

A preflight mismatch is a cohort result (`unsupported-profile-layout`), not permission to synthesize a custom PR-provided command.

## Promotion gate

Only after the advisory cohort has been exercised should `ores-gh-bots` count IndieBuild. Promotion requires:

- the current PR head equals the check's head SHA;
- check name/context is exactly `indiebuild.dev/ci`;
- check status is completed and conclusion is success;
- the check belongs to the configured dedicated IndieBuild GitHub App ID;
- PAT statuses under `indiebuild.dev/ci-advisory` never count;
- worker restart/recovery reconciles orphaned in-progress checks;
- a newer head cannot inherit a prior head's result;
- local evidence and hosted Actions disagreements are retained and investigated, not overwritten.

`ORESoftware/ores-gh-bots` already supports binding required CI contexts to expected App IDs through `REQUIRED_CI_CONTEXTS` and `REQUIRED_CI_APP_IDS`. Once the IndieBuild App is registered, the intended gate configuration is structurally:

```text
REQUIRED_CI_CONTEXTS=indiebuild.dev/ci,...
REQUIRED_CI_APP_IDS=indiebuild.dev/ci=<INDIEBUILD_APP_ID>,...
```

The review-provider attestations remain a separate evidence class. CI success must not be inferred from PR comments or agent-review markers.

## Rollout

Run the cohort in small batches first (for example 5 -> 10 -> 30) while keeping the complete manifest fixed. Capture exact-head receipts on every attempt. Re-run an entry only for an explicit reason (new head, infrastructure retry, or profile correction), and retain the earlier receipt rather than replacing it.

A successful wave is not "30 green PRs". It is 30 attributable outcomes whose source checkout, dependency preparation, execution, and GitHub reporting can each be explained and reproduced.
