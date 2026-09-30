# Laptop and Codespaces development contract

The infra repository owns one application `.ores-compose.yaml`. Laptop and Codespaces use that same manifest and exact application source commit; environment-specific application service graphs are forbidden.

## Current application readiness

The pinned application monorepo contains long-lived API and web server revisions. The application compose contract binds them only on loopback:

- API: `127.0.0.1:18090` with `/healthz` and `/readyz`;
- web: `127.0.0.1:18091` with `/healthz` and `/readyz`;
- web reaches the API through `GHA_INDIE_WORKER_API_HTTP_BASE=http://127.0.0.1:18090`.

Port `8080` is reserved exclusively for the shared `ORESoftware/codespaces-cluster` Rust edge. The application compose manifest must not claim it.

`config/codespaces-cluster.toml` is this repository's trusted edge route table:

- `/api/*` -> API on `127.0.0.1:18090`, with the `/api` prefix stripped;
- all other application paths -> web on `127.0.0.1:18091`.

The edge's own `/healthz`, `/readyz`, and `/routes` endpoints remain control-plane endpoints and are not shadowed by the web root route.

## Workflow

1. `scripts/dev/bootstrap` initializes `_apps/gha-monorepo` and its tracked nested gitlinks at the recorded revisions. It uses checkout semantics only; it does not rebase/reset/force-push.
2. `scripts/dev/doctor` verifies the infra gitlink, application compose source pin, required tools, initialized source, and real application server pins.
3. `just codespace-origin-up` materializes the exact reviewed shared edge revision from `config/codespaces-cluster.rev`, verifies the reviewed `ores-compose`/`oresc` toolchain, starts this repository's application compose stack, then starts the shared Rust edge on `127.0.0.1:8080`. Use this when a Cloudflare connector is already supervised separately on the laptop.
4. `just codespace-edge-up` is the managed public lifecycle. It requires `TUNNEL_TOKEN` (preferred) or compatibility `CF_TUNNEL_TOKEN` **before starting any local layer**, performs origin startup, then asks `oresc` to start the remotely managed Cloudflare connector only after edge `/readyz` passes.
5. `just codespace-origin-status` reports the application supervisor and shared edge state without requiring a Cloudflare connector. `just codespace-edge-status` additionally reports the connector state.
6. `just codespace-edge-down` attempts every owned layer even if connector evidence, the Rust edge, or one supervisor reports an error. Teardown must not rebuild/fetch simply to stop already-owned processes.
7. `status` and `down` deliberately do not fetch or mutate the shared checkout while it owns running supervisors.
8. `cloudflare/laptop-ingress/config.example.yml` and `scripts/dev/tunnel laptop ...` are a manual/legacy locally-managed alternative only. The managed `just`/`oresc` lifecycle does not read that YAML.

`local.indiebuild.dev` and `codespace.indiebuild.dev` are Access-protected interactive surfaces. `hooks.indiebuild.dev` / `ci-laptop.indiebuild.dev` remain separate signed-machine/webhook surfaces; never weaken Access to make automation work.

For `local.indiebuild.dev`, DNS alone is insufficient: the remotely managed tunnel must also contain an ingress rule mapping the hostname to `http://127.0.0.1:8080` and a fail-closed catch-all. When the tunnel is dedicated to this laptop ingress, production Cloudflare Terraform can own that complete rule set with `laptop_manage_dedicated_tunnel_config = true`. Leave that false for a shared tunnel rather than letting Terraform overwrite unrelated ingress rules.

## Codespace bootstrap

A fresh/rebuilt devcontainer provisions the reviewed private tools needed by this lifecycle:

- `ORESoftware/ores-cli@d37aa4c1a0b79a292a31e2f16db8622144b0831f`, with the reviewed revision recorded in `config/ores-cli.rev`;
- `ORESoftware/ores-compose@a9758b8a48c2a264c4bff38f1dc166cba0e9caa1`, with the reviewed revision recorded in `config/ores-compose.rev`;
- the shared `ORESoftware/codespaces-cluster` source is materialized later at exact commit `72149bd4889a62814ca630f2cbf4d05cf97a620e`, recorded in `config/codespaces-cluster.rev`.

The three `config/*.rev` files are review authorities for private bootstrap/runtime tooling. They must contain exactly one full 40-hex commit SHA. The Rust dev-runtime validator, contract tests, devcontainer install commands, and Codespace edge workflow cross-check those values so a pin cannot move in only one surface.

The shared cluster intentionally uses the same reviewed `ores-compose@a9758b8...` authority as this consumer. This prevents shared bootstrap from silently replacing a consumer-reviewed `ores-compose` executable with a different revision in the same Cargo bin namespace.

The pinned `ores-compose` revision preserves exact source materialization while adding pre-network runtime/replica admission, checkout-path lifetime locking, dependency-safe reverse shutdown waves, partial-start cleanup, shared trusted-path normalization, and non-destructive dirty managed-cache recovery even when optional pre-sync is skipped. A pin advance must point at a reviewed immutable commit and retain those invariants.

The pinned `oresc` revision independently sanitizes child command environments. Before its `cloudflared --version` preflight, detached supervisor, and connector spawn, it removes `ORES_CLI_READ_TOKEN`, `GH_TOKEN`, `GITHUB_TOKEN`, `TUNNEL_TOKEN`, and `CF_TUNNEL_TOKEN`, then restores only canonical `TUNNEL_TOKEN` and the per-run ownership marker at the child boundaries that require them. The pinned shared cluster revision applies the same control-plane/tunnel-secret removal before both the `ores-compose --help` preflight and long-running `ores-compose up`, so bootstrap and tunnel credentials do not flow into the application process tree.

The shared cluster bootstrap does not treat `command -v` as proof. It binds installed executables to the exact Git repository, exact revision, Cargo package, binary SHA-256, and—where required—the exact package-owned flags contract. Those authority receipts live outside the managed Git checkout, reject symlink aliases, and are repaired/verified to owner-only permissions before reuse. Revision authority files are parsed as exactly one line rather than whitespace-normalized input. The flags contract is materialized before executable replacement, carries its own exact revision/hash, and lifecycle invocations bind it with `FLAGS2ENV_CONFIG`; a caller repository's `.cli-flags.toml` is never accidental authority.

Controller builds force the managed checkout's own `target/` directory, preventing a global Cargo target-dir from moving `codespaces-cluster-ctl` away from its ownership state. Shared-cluster `status`/`down` are build-independent. The pinned shared-edge head contains the resolver-generated Cargo v4 lockfile required for `cargo build --locked`; both local `just rust-check` and CI require locked check, Clippy, and tests.

The exact shared-cluster head `72149bd4889a62814ca630f2cbf4d05cf97a620e` was stepfully certified on Rust 1.88 by funded evidence carrier run `36619392577`, including bootstrap security regressions, resolver-stable lock verification, rustfmt, locked Rust check, strict locked Clippy, locked Rust tests, lifecycle contract checks, and final immutable clean-head verification.

All three repositories are private and cross-owner from `gha-indie-worker`. `ORES_CLI_READ_TOKEN` remains supported as a fine-grained bootstrap secret with **read-only Contents access limited to exactly those three repositories**. On an interactive laptop, `scripts/dev/codespace-origin-up` may instead use the credential already available through `gh auth token`. Private Git authentication is injected through command-scoped Git config; bootstrap does not mutate the user's global Git credential-helper configuration. Credentials are scoped to private clone/fetch/tool-install operations and are not exported to the long-running application controller, shared Rust edge, `oresc` connector supervisor, or `cloudflared`.

The devcontainer also performs a read-only `gh repo view ORESoftware/codespaces-cluster` preflight so insufficient repository scope fails during rebuild rather than during first traffic activation.

Port 8080 stays private to the Codespace and is marked `onAutoForward: ignore`; Cloudflare connects to loopback from `cloudflared` inside the same Codespace rather than proxying a `*.app.github.dev` URL.

## Secret boundary

No tunnel token, GitHub bootstrap token, or credential JSON belongs in Git, `.ores-compose.yaml`, `config/codespaces-cluster.toml`, process arguments, Terraform variables committed to the repository, or devcontainer configuration. Real connector tokens live only in the approved secret mechanism/environment. Manual locally-managed tunnel configs/credential files, when intentionally used, live outside the checkout. `.runtime/` and `.ores/` are transient runtime state and must not become credential stores.
