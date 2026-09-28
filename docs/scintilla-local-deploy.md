# GIW on Scintilla: build, deploy, and local dev

`scintilla-run/scintilla-cli` uses authored `.scintilla-endpoint.toml` files and one deterministic project manifest for build, deployed control-plane execution, and local development.

## Install the CLI from source

The CLI depends on private Scintilla repositories, so Git/Cargo credentials must have read access.

```sh
export CARGO_NET_GIT_FETCH_WITH_CLI=true
cargo install \
  --git https://github.com/scintilla-run/scintilla-cli.git \
  --locked \
  scintilla-cli

scintilla --help
```

## Build once, use the same artifact everywhere

From the application/project root containing `.scintilla-endpoint.toml` endpoint contracts:

```sh
scintilla build --project . --out-dir .scintilla
scintilla deploy --project . --out-dir .scintilla --dry-run
```

After reviewing the dry-run, deploy to the configured Scintilla control plane:

```sh
export SCINTILLA_BASE_URL="https://api.scintilla.run"
export SCINTILLA_TOKEN="$(security find-generic-password -w -s scintilla-token)"
scintilla deploy --project . --out-dir .scintilla
```

`SCINTILLA_TOKEN` is environment-only and must not be placed on argv, committed, or written into `.scintilla-endpoint.toml`.

## Local development / standalone path

The same project contract can be synchronized to a loopback control plane:

```sh
export SCINTILLA_BASE_URL="http://127.0.0.1:8080"
scintilla dev --project .
```

For the desktop appliance used by GIW, run the exact Scintilla desktop substrate pinned by `giw-desktop-infra/appliance.json`. The Rust-first local daemon path is the repository's ORES Compose contract:

```sh
cd "$HOME/src/scintilla-desktop-infra"
ores-compose check .ores-compose.yaml
ores-compose plan .ores-compose.yaml
ores-compose up .ores-compose.yaml
```

That keeps the Scintilla machine-control API on `127.0.0.1:8765`. GIW's `giw-desktop-daemon` remains a separate loopback adapter on `127.0.0.1:8770`.

For the fuller standalone Scintilla appliance (BEAM ingress, worker pools, persistent OS service, and optional substrate-managed Cloudflare connector), use the Scintilla repository's audited bootstrap/service lifecycle and its current reviewed runtime manifest. GIW deliberately does not duplicate or extend the legacy Python manifest renderer; that tooling remains migration debt until Scintilla replaces it with the Rust-first equivalent.

To install the audited persistent OS service after the Scintilla runtime manifest is prepared:

```sh
./scripts/install-service.sh
./scripts/status.sh
```

The machine-local control APIs remain loopback-only. A Cloudflare Tunnel may publish only an explicitly allow-listed product origin; it must never expose `127.0.0.1:8765` or `127.0.0.1:8770`.
