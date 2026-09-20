# Laptop PR CI

This is the opportunistic local CI lane for `ci-laptop.indiebuild.dev`. It is an independent continuity path, not a replacement for native GitHub Actions semantics.

## Trust boundary

The local parent process may hold all control-plane credentials, but `ores-compose` service admission is explicit:

- `ci-worker` receives the IndieBuild GitHub App identity/private-key **path**, GitHub webhook HMAC secret, worker API secret, and durable worker state path;
- `cloudflare-tunnel` receives only the Cloudflare Tunnel token as `TUNNEL_TOKEN`;
- `api` and `web` receive none of those values;
- build, service and healthcheck subprocesses start from `env_clear()` under the `ORESoftware/ores-compose#154` executor contract;
- tested PR code runs inside the worker's fixed profile container and does not receive worker/tunnel control-plane values.

The public Cloudflare hostname is also not a public worker API. The zone firewall blocks every request to `ci-laptop.indiebuild.dev` except **POST `/webhooks/github`**. The worker independently verifies GitHub's `X-Hub-Signature-256` HMAC before interpreting a delivery.

## Required operator environment

Set these in the operator shell or an operator-owned secret launcher. Do not commit their values:

```sh
export INDIEBUILD_WORK_ROOT="$HOME/.local/state/indiebuild/worker"
export INDIEBUILD_GITHUB_APP_ID='...'
export INDIEBUILD_GITHUB_APP_PRIVATE_KEY_PATH="$HOME/.config/indiebuild/app.private-key.pem"
export INDIEBUILD_GITHUB_WEBHOOK_SECRET='...'
export INDIEBUILD_WORKER_AUTH_SECRET='...'
export INDIEBUILD_CLOUDFLARE_TUNNEL_TOKEN='...'
```

`INDIEBUILD_WORK_ROOT` must be an absolute, operator-owned persistent directory outside the materialized monorepo checkout. The worker stores build logs and durable authoritative-report intents there so a source refresh or worker restart cannot erase reconciliation state.

The private-key binding is a **path**, not PEM contents. `gha-indie-worker.rs` reads that file once at startup and never passes its contents into a tested job.

## Required code pins

The production `.ores-compose.yaml` is intentionally reproducible and currently pins:

- the monorepo source adapter from `gha-indie-worker/gha-indie-worker-monorepo#9`;
- split worker commit `be8f6aac3eb6e1d1f76d613e3082ca2114ceb2bf`;
- provenance workspace commit `ORESoftware/k8s-cluster@5cfac43c6900898f36f588d044ca34083da1c726`.

When a dependency PR merges with a different SHA, advance the pin explicitly. Do not replace an immutable pin with a branch name.

The compose executable must include the executor half of `ORESoftware/ores-compose#154`: service environment admission before source side effects plus `env_clear()` for build, service and healthcheck commands.

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
4. a declared-but-missing secret fails before source materialization and before process side effects;
5. the production manifest uses App-required reporting and an external durable state path;
6. the Cloudflare edge policy exposes only POST `/webhooks/github`.

## Start the local stack

From this infra repository:

```sh
ores-compose check .ores-compose.yaml
ores-compose plan .ores-compose.yaml
ores-compose up .ores-compose.yaml
```

The trusted monorepo bootstrap reconstructs the split worker in its immutable source-provenance workspace and builds `dd-build-server` at the pinned SHA. The worker binds only `127.0.0.1:8100`; `cloudflared` connects outward from the same laptop.

For an operator shutdown:

```sh
ores-compose down .ores-compose.yaml
```

## Cloudflare provisioning

The Terraform resource is opt-in. In the production Cloudflare platform root, set `enable_laptop_ci_tunnel = true` only after the isolation test passes and the App/webhook configuration is ready.

Terraform owns the remotely managed tunnel and `ci-laptop.indiebuild.dev` DNS record. `cloudflared` consumes the generated tunnel token at runtime; the token is not stored in the compose manifest or placed on its command line.

## Evidence promotion

The worker runs in `app-required` mode and writes the authoritative context `indiebuild.dev/ci`. A result is not merge-authoritative merely because that context exists.

Promotion remains closed until all of these are demonstrated end-to-end:

- exact current PR head was the checked commit;
- Check Run is completed/success;
- Check Run is owned by the dedicated IndieBuild GitHub App ID;
- context is exactly `indiebuild.dev/ci`;
- crash/restart reconciliation either recovers the correct terminal evidence or refuses success;
- the operator-owned #47 cohort has run observationally across its 30 PRs / 16 orgs and receipts reconcile against native stepful CI where available;
- `ores-gh-bots` independently authenticates the current-head App Check Run before counting it.

PAT Commit Status remains advisory under the distinct `indiebuild.dev/ci-advisory` context and must never satisfy the trusted predicate.
