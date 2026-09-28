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

For the desktop appliance used by GIW, run the Scintilla desktop substrate at `127.0.0.1:8765` and GIW's adapter at `127.0.0.1:8770` as documented in `local-desktop-cloudflare-bringup.md`. The standalone Scintilla appliance bootstrap is:

```sh
cd "$HOME/src/scintilla-desktop-infra"
./scripts/bootstrap.sh
python3 scripts/render_runtime_manifest.py \
  --ingress-bin /absolute/path/to/scintilla-ingress \
  --ingress-root /absolute/path/to/runtime \
  --cloudflared-credentials /absolute/path/to/.cloudflared/TUNNEL-ID.json
./scripts/doctor.sh
./scripts/up.sh
./scripts/status.sh
```

To install the audited persistent OS service instead of keeping a foreground terminal open:

```sh
./scripts/install-service.sh
./scripts/status.sh
```

The machine-local control APIs remain loopback-only. A Cloudflare Tunnel may publish only an explicitly allow-listed product origin; it must never expose `127.0.0.1:8765` or `127.0.0.1:8770`.
