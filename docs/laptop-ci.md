# Laptop PR CI

This is the opportunistic local CI lane for `ci-laptop.indiebuild.dev`. It is an independent continuity path, not a replacement for native GitHub Actions semantics.

## Trust boundary

The local parent process may hold all control-plane credentials, but `ores-compose` service admission is explicit:

- `ci-worker` receives the IndieBuild GitHub App identity/private-key **path**, GitHub webhook HMAC secret, worker API secret, durable worker state path, and the operator-owned private provenance checkout path required only by its build bootstrap;
- `cloudflare-tunnel` receives only the Cloudflare Tunnel token as `TUNNEL_TOKEN`;
- `api` and `web` receive none of those values;
- build, service and healthcheck subprocesses start from `env_clear()` under the `ORESoftware/ores-compose#154` executor contract;
- tested PR code runs inside the worker's fixed profile container and does not receive worker/tunnel control-plane values.

`ores-compose#154` currently scopes environment by **service**, not by execution phase. Until `ORESoftware/ores-compose#161` lands, the trusted worker bootstrap removes the service's runtime secret bindings before Git/Cargo/helper processes are created, the trusted runtime launcher removes the build-only private provenance path before helper processes and final worker `exec`, and trusted readiness wrappers remove worker/tunnel secrets and build-only paths before `curl` is exec'd. The long-running worker and `cloudflared` processes therefore retain only the values they actually need.

The public Cloudflare hostname is also not a public worker API. The zone firewall blocks every request to `ci-laptop.indiebuild.dev` except **POST `/webhooks/github`**. The worker independently verifies GitHub's `X-Hub-Signature-256` HMAC before interpreting a delivery.

## Required operator environment

Set these in the operator shell or an operator-owned secret launcher. Do not commit their values:

```sh
export INDIEBUILD_WORK_ROOT="$HOME/.local/state/indiebuild/worker"
export INDIEBUILD_LIBS_SOURCE_DIR="$HOME/codes/k8s-libs-and-shared-defs"
export INDIEBUILD_GITHUB_APP_ID='...'
export INDIEBUILD_GITHUB_APP_PRIVATE_KEY_PATH="$HOME/.config/indiebuild/app.private-key.pem"
export INDIEBUILD_GITHUB_WEBHOOK_SECRET='...'
export INDIEBUILD_WORKER_AUTH_SECRET='...'
export INDIEBUILD_CLOUDFLARE_TUNNEL_TOKEN='...'
```

`INDIEBUILD_WORK_ROOT` must be an absolute, operator-owned persistent directory outside the materialized monorepo checkout. The trusted worker launcher enforces that rule, canonicalizes the path, applies `umask 077`, and refuses startup when required App/webhook/auth inputs are empty or the App key is not a readable regular file. The worker stores build logs and durable authoritative-report intents there so a source refresh or worker restart cannot erase reconciliation state.

`INDIEBUILD_LIBS_SOURCE_DIR` is **not a credential**. It is an absolute path to the operator's normal checkout of private `ORESoftware/k8s-libs-and-shared-defs`. Before each build, prepare that checkout at the exact `remote/libs` gitlink OID recorded by the pinned `k8s-cluster` commit. The trusted bootstrap verifies the exact HEAD and reviewed HTTPS origin, exports only that committed tree via `git archive`, and never passes this path or any credential used to prepare it into Cargo or the final worker process.

The private-key binding is a **path**, not PEM contents. `gha-indie-worker.rs` reads that file once at startup and never passes its contents into a tested job.

## Required code pins

The production `.ores-compose.yaml` is intentionally reproducible and currently pins:

- monorepo source-adapter head `gha-indie-worker/gha-indie-worker-monorepo#9@7843f373202f082f18c9a8175496ad4a4b2ed317`;
- split worker commit `be8f6aac3eb6e1d1f76d613e3082ca2114ceb2bf`;
- provenance workspace commit `ORESoftware/k8s-cluster@5cfac43c6900898f36f588d044ca34083da1c726`;
- private `remote/libs` tree: whatever exact gitlink OID that immutable provenance commit records; the bootstrap derives and verifies it rather than duplicating the SHA in config.

The source adapter validates cached Git origins, removes stale/untracked provenance files before Cargo sees them, disables ambient/global Git config and dangerous protocols, verifies and archives the exact private libs gitlink from the operator checkout, builds Git/Cargo under a scrubbed environment, and writes a SHA-256 provenance receipt binding worker, provenance, private-libs and binary identities. The runtime launcher validates that receipt and binary hash before the final worker `exec`.

When a dependency PR merges with a different SHA, advance the pin explicitly. Do not replace an immutable pin with a branch name. The pins above are frozen for this review unless a dependency itself changes.

The compose executable must include the executor half of `ORESoftware/ores-compose#154`: service environment admission before source side effects plus `env_clear()` for build, service and healthcheck commands. `#161` is the follow-up for first-class build/start/healthcheck environment separation; remove the temporary shell scrub wrappers after that contract lands.

## Preflight isolation acceptance

Before putting real credentials in the parent process, run the fake-sentinel acceptance harness against the intended `ores-compose` binary:

```sh
ORES_COMPOSE_BIN=/path/to/ores-compose \
  bash scripts/test-laptop-ci-secret-isolation.sh
```

The test must report `PASS`. It checks:

1. worker, tunnel and unrelated sibling services see only their declared variables;
2. that property holds for build, long-running service and healthcheck subprocesses;
3. an unrelated parent sentinel is absent everywhere;
4. a declared-but-missing required binding fails before source materialization and before process side effects;
5. the production manifest uses App-required reporting, external durable state, and the exact reviewed source-adapter pin;
6. the private provenance checkout path is required only by the worker service;
7. the Cloudflare edge policy exposes only POST `/webhooks/github`.

## Prepare the private provenance checkout

The source adapter does **not** receive a PAT, App token, SSH agent, or credential helper for the private libs repository. Prepare the checkout outside the compose source tree using the operator's normal authenticated Git environment, then leave it detached at the exact gitlink commit.

One deterministic way to inspect the required OID is:

```sh
git -C /path/to/k8s-cluster ls-tree \
  5cfac43c6900898f36f588d044ca34083da1c726 -- remote/libs
```

Then in the operator-owned `k8s-libs-and-shared-defs` checkout, fetch that OID using your normal authenticated workflow and detach HEAD at it. `scripts/bootstrap-ci-worker.sh` independently proves the resulting HEAD and exact reviewed HTTPS origin before exporting the tree. A dirty working tree does not alter the build because the bootstrap archives the committed OID, not working-tree bytes.

## Start the local stack

From this infra repository:

```sh
ores-compose check .ores-compose.yaml
ores-compose plan .ores-compose.yaml
ores-compose up .ores-compose.yaml
```

The trusted monorepo bootstrap reconstructs the split worker in its immutable source-provenance workspace and builds `dd-build-server` at the pinned SHA. The trusted launcher checks runtime inputs and binary provenance before `exec`-ing that worker. The worker binds only `127.0.0.1:8100`; `cloudflared` connects outward from the same laptop.

For an operator shutdown:

```sh
ores-compose down .ores-compose.yaml
```

## Cloudflare provisioning

The Terraform resource is opt-in. In the production Cloudflare platform root, set `enable_laptop_ci_tunnel = true` only after the isolation test passes and the App/webhook configuration is ready.

Terraform owns the remotely managed tunnel and `ci-laptop.indiebuild.dev` DNS record. `cloudflared` consumes the generated tunnel token at runtime; the token is not stored in the compose manifest or placed on its command line. The firewall entry point rejects every other method/path on that hostname before traffic reaches the tunnel.

## Current verification boundary

`gha-indie-worker-monorepo#9` now has a stepful green hosted **provenance contract** on exact head `7843f373202f082f18c9a8175496ad4a4b2ed317`. It executes shell syntax plus negative-path tests proving that a missing private source checkout is rejected before `.ores`/source side effects, receipt/launcher contracts bind the private gitlink and worker binary, ambient Git credential shapes are not admitted, and readiness wrappers drop phase-inappropriate values.

That hosted workflow intentionally does **not** claim a full worker compile because the exact `remote/libs` authority is private. Full compilation requires the operator-owned exact checkout described above. Separately, #49's infra/static contracts have had real stepful green runs; any workflow that fails at GitHub startup with no executed steps remains infrastructure non-evidence, not a source failure.

## Live acceptance sequence

Use the standalone `gha-indie-worker-api-server.rs` smoke repository first; its Cargo manifest has no sibling path dependencies.

1. Prepare `INDIEBUILD_LIBS_SOURCE_DIR` at the exact provenance gitlink OID.
2. Run the fake-sentinel isolation harness above against the exact #154 `ores-compose` binary.
3. Run `scripts/bootstrap-ci-worker.sh` through the pinned compose build and retain its receipt; prove the built executable hash matches that receipt.
4. Start `.ores-compose.yaml` with the real operator-owned bindings.
5. Confirm loopback `http://127.0.0.1:8100/readyz` is healthy and Cloudflare tunnel readiness is healthy locally.
6. Enable/apply the optional laptop tunnel Terraform and verify public non-webhook paths and non-POST methods are blocked.
7. Deliver a signed same-repository `pull_request` event for the smoke repo and retain the exact head SHA, worker job id, Check Run id, App id and terminal conclusion.
8. Kill the worker after local execution becomes terminal but before/while GitHub delivery is pending, restart the same pinned stack, and verify the durable report-intent reconciler either completes the same Check Run or refuses success.
9. Only after that succeeds, run #47's 30-PR / 16-org cohort observationally and compare against native stepful CI where available.

## Evidence promotion

The worker runs in `app-required` mode and writes the authoritative context `indiebuild.dev/ci`. A result is not merge-authoritative merely because that context exists.

Promotion remains closed until all of these are demonstrated end-to-end:

- exact current PR head was the checked commit;
- Check Run is completed/success;
- Check Run is owned by the dedicated IndieBuild GitHub App ID;
- context is exactly `indiebuild.dev/ci`;
- crash/restart reconciliation either recovers the correct terminal evidence or refuses success;
- `gha-indie-worker.rs#79` has complete `filter=all` Check Run recovery;
- `gha-indie-worker.rs#80` has serialized monotonic report-intent transitions;
- the operator-owned #47 cohort has run observationally across its 30 PRs / 16 orgs and receipts reconcile against native stepful CI where available;
- `ores-gh-bots` independently authenticates the current-head App Check Run before counting it.

Until all of those are true, `indiebuild.dev/ci` remains non-counting regardless of a green Check Run. PAT Commit Status remains advisory under the distinct `indiebuild.dev/ci-advisory` context and must never satisfy the trusted predicate.
