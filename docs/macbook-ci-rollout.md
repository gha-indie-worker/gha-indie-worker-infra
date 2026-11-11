# MacBook CI deployment — 2026-11-10

## Executed acceptance

The native GitHub Actions runner protocol executes each repository's workflow
steps in a fresh rootless OCI container inside this MacBook's `atto-ci` Linux VM.
GitHub sends the job instructions, supplies the repository-scoped job token, and
receives logs and the final result. No hosted polling/dispatch job is needed.
The local machine does not maintain a repository-specific build command table.

| Repository | Executed run | Result |
| --- | --- | --- |
| ores-truffle-oreslang/oreslang-target-profiles | [42930910494](https://github.com/ores-truffle-oreslang/oreslang-target-profiles/actions/runs/42930910494) | success |
| ores-truffle-oreslang/oreslang-static-analysis.rs | [42930912035](https://github.com/ores-truffle-oreslang/oreslang-static-analysis.rs/actions/runs/42930912035) | success |
| ores-truffle-oreslang/oreslang-format | [42930916290](https://github.com/ores-truffle-oreslang/oreslang-format/actions/runs/42930916290) | stable and Rust 1.85 jobs succeeded |

`evidence/macbook-native-ci-2026-11-10.json` records the original required CI
workflows at their final heads. `evidence/macbook-ci-2026-11-10.json` retains the
earlier additional-workflow proof. The receipts record exact commit/tree/workflow blob
hashes, executed step conclusions, native job IDs, runner IDs/names, image digest
and GitHub usage responses. All three usage responses have an empty `billable`
map. This proves the listed workflow executions; it does not certify guest
language parity or physical real-time deadlines.

Earlier attempts retained real failures. Target-profile tests still expected a
hostile getter to be invoked even though descriptor snapshots intentionally avoid
that getter; the regression now asserts zero getter calls while retaining denial
of throwing reflection traps. The formatter had four Rust files with formatting
drift; they were formatted without changing test assertions. Slow toolchain
bootstrap attempts were cancelled and recorded before replacing their images.

## Runtime and configuration

- `config/macbook-ci-repositories.json` is the operator-reviewed repository list.
- `scripts/ci/run-local-runner.sh OWNER/REPO [jobs]` brokers a short-lived registration
  token on the host, then starts a one-job runner. A repository outside the list
  is refused before registration.
- The admitted local image is `indiebuild-runner:2.338.2-ready`, checked against
  `indiebuild-runner@sha256:6c241aa7944a536aaf0117ea7ecfb6e1973177330bd8976f11a819bc5f46b3cd`.
- The official runner base is
  `ghcr.io/actions/actions-runner@sha256:759a1d94a15b05941aba5196974ff43fe15b4cbba29b694b35cbc32a1166b232`.
  Compiler/linker prerequisites and stable Rust 1.99.1 plus Rust 1.85.0 were warmed
  into the local image. The Rust 1.85 archives were checked against the official
  static.rust-lang.org manifest before installation. Local preparation metadata
  remains at `~/.local/share/indiebuild/toolchain-cache/manifest.json`.
- Each job is limited to 2 CPUs, 4 GiB RAM and 1024 PIDs. No host-home mount,
  container-engine socket, privileged mode or operator credential is supplied.
- The disposable runner removes its registration after the job, and `--rm`
  removes its container. A LaunchAgent starts a new one-job runner afterward.

The repositories’ original `ci.yml` jobs now select the
`indiebuild-linux-arm64` label while retaining their required check names and
complete test steps. They pin checkout to the exact admitted head, request
read-only repository contents and disable persisted checkout credentials.
Superseded work is cancelled through native workflow concurrency. The extra
`IndieBuild / ...` proof workflow is manual-only to avoid duplicate execution.
GitHub’s repository workflow approval settings remain in force. These rollout
branches are reviewable changes; no source merge or branch-protection bypass
was performed.

## Supervision and status

Run `scripts/ci/install-macbook-services.sh` to install/update the login helpers (boot-managed services are skipped):

- `dev.indiebuild.runner.<repository>` — one supervised broker per admitted repo;
- `dev.indiebuild.status-refresh` — refresh original `ci.yml` results every 30 seconds;
- `dev.indiebuild.status-tunnel` — the read-only connector, promoted to a boot service.

The status refresher alone uses the host's existing `gh` login. It writes an
atomic owner-only `~/.local/share/indiebuild/runs.json`. The web service receives
only this evidence path, with no GitHub, Cloudflare or Bretelle management token.
Its `/api/runs` returns 503 when evidence is absent or invalid. Native GitHub
Check Runs remain the authority for merge decisions.

The web binary is now independently supervised by system LaunchDaemon
`dev.indiebuild.web` on `127.0.0.1:18091`. Bretelle hosts a different native
application on `:18092`, through its private control-plane/gateway/health-agent
stack. Both tunnel connectors and public application services start at boot
under the normal user. The GitHub runners/evidence refresher remain login agents.

`https://indiebuild.dev` and `https://builds.indiebuild.dev` serve IndieBuild.
A Cloudflare-hosted availability Worker proxies a dedicated origin hostname,
adds Server status/healthz controls, and serves an explicit outage page when
the origin cannot respond. See `cloudflare/edge-router/availability/README.md`.
The old local.indiebuild.dev developer tunnel remains disabled.

## DNS state and approved apply

The DNS record belongs to the existing `production/cloudflare-dns` root through
`module.cloudflare_dns.cloudflare_dns_record.local_status[0]`. The optional
activation input remains outside Git at
`~/.config/indiebuild-status/dns.tfvars`; include it in subsequent plans.

The user explicitly authorized the saved one-record plan as an exception to the
human-only apply rule. Plan SHA-256:
`427e145cdf3b574cf8f008bea7bc0be22db521d4e78256957ddcd3e366ca2c93`.
The apply added one CNAME and changed/destroyed zero resources. The scoped plan
was intentionally limited to this addition; it is not a full-fleet convergence
claim. The root's local state and provider cache remain outside version control.
The record ID is `0712b80605f1c6d890e9f16e8619da6f`.

Cloudflare credentials and tunnel JSON remain in owner-only directories outside
Git. The admin plane was not changed. CI helpers use the login Keychain; public
application services and connectors now run as boot services.

The user separately authorized the saved apex/availability plan: two DNS records
were added (indiebuild.dev and origin-status.indiebuild.dev), with no changes or
deletions. The apex record uses the existing Terraform apex resource address.
The Worker route/configuration is separate from the pre-existing fleet router.
The operator installed scripts/ci/install-boot-services.sh with administrator
privileges; system services were inspected running as the normal user.
