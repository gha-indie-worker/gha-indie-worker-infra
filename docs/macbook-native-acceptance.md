# Physical MacBook GitHub-native Actions acceptance (manual; no promotion)

This is an **operator-gated** test for the actual GitHub Actions protocol in the
existing rootless Lima Linux guest. The branch containing the test fixture is in
the previously admitted repository
`ores-truffle-oreslang/oreslang-target-profiles`. Do **not** change the
allowlist, publish new runner credentials, enable public-fork jobs, or treat the
offline fixture as proof of the real machine.

## Prepare and trust the source

1. The fixture was independently staged in `oreslang-target-profiles#93`
   and merged into the default branch on 2026-11-14 at exact SHA
   `eded2037a3db1d691d48bcfd5c907ffc108949a0`. GitHub
   `workflow_dispatch` requires the workflow to exist on the default branch.
   Verify the branch still contains the reviewed
   `.github/workflows/indiebuild-native-acceptance.yml` file before dispatch.
   If `main` moves, re-review the changed revision before accepting results.
2. On the physical MacBook, verify the expected unprivileged Lima VM, rootless
   container engine, admitted image digest, owner-only host credentials, and
   LAN/host egress restrictions. These security requirements are **not proven**
   by `bash -n`, offline mocks or GitHub's cloud-hosted macOS test runner.
3. Record an immutable source commit independently *before dispatch*, e.g.
   using GitHub API readback of the selected trusted ref; do not take it from
   a mutable branch after the run. A mismatch must fail verification.

## Run two real ephemeral Linux-ARM64 jobs

In one terminal on the MacBook, launch **exactly two jobs** for the already
admitted repository (or verify the supervised broker will launch two sequential
ephemeral runners):

```sh
scripts/ci/run-local-runner.sh ores-truffle-oreslang/oreslang-target-profiles 2
```

Use a separate authenticated operator terminal to dispatch the trusted manual
workflow after its PR is merged to the default branch:

```sh
gh workflow run indiebuild-native-acceptance.yml \
  -R ores-truffle-oreslang/oreslang-target-profiles --ref main
```

Do not trigger this workflow from a public fork. The fixture does not use
`pull_request`, `pull_request_target`, `push`, or repository dispatch.
It has read-only `contents` permissions and no job-provided secrets.

The two jobs exercise native GitHub `runs-on`, `needs`, `if`, `env`,
`timeout-minutes`, exact-SHA checkout, a pinned artifact upload/download,
and SHA-256 verification. An expected outcome is **two separate GitHub
self-hosted runner IDs** and one fresh artifact attached to this run.

## Independently read back the result

Capture `RUN_ID` from GitHub Actions and compare it with the independently
recorded exact commit `HEAD_SHA`:

```sh
node scripts/ci/verify-native-acceptance.mjs \
  ores-truffle-oreslang/oreslang-target-profiles "$RUN_ID" "$HEAD_SHA"
```

This fetches the live run, both jobs and artifact via the current `gh`
authentication, then **downloads the actual artifact bytes into a temporary
owner-only directory** and independently verifies that exactly two small
regular files exist (`commit.sha`, `commit.sha256`), the receipt equals the
supplied commit SHA byte-for-byte, and its manifest matches SHA-256 of the
downloaded receipt. The temporary directory is removed even on failure.

Verification fails closed on skipped/failed steps, wrong runner identity,
cross-run or old-attempt jobs, duplicate required steps, reused ephemeral
runners, wrong workflow/commit, out-of-order dependencies, expired artifacts,
forged receipt paths, unexpected files, symlinks or incorrect bytes. Preserve
the **run URL, job IDs, runner IDs, commit SHA, image digest, artifact ID and
validation output** in the operator evidence. This is still not host attestation.

The artifact retention is one day; capture readback before it expires.
This verification checks GitHub's own API records, not a fabricated fixture.

## Negative / failure-path acceptance

In a separate controlled run, cancel an in-progress job through GitHub and
verify that the broker stops its exact guest container, removes its ephemeral
registration, releases the per-login lock only after cleanup, and leaves no
host processes or workspace files. Test a forced process kill and guest crash:
a retained stale lock is correct until an operator independently inspects the
guest and GitHub runner registry. Do not delete the lock automatically or
silently clear it on reboot.

Also prove that a second broker cannot acquire the per-login lock, and that
an unadmitted repository fails **before** requesting any registration token.
Check the actual guest network rules prevent untrusted CI workloads from
reaching LAN machines, the macOS host, Bretelle control ports, cloud
metadata, and CI administration APIs while preserving the intended trusted
GitHub endpoints.

**Go/no-go:** remain in review-only mode until physical host evidence,
job-identity-bound admission (or equivalent independently reviewed trust
boundary), real cancellation and credential revocation, network isolation,
and separate infra-plan CI resolution all pass. Existing registration-token
prototypes do not establish GitHub job-ID-bound JIT admission.
