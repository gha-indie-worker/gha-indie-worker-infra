set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# Start only the application backends plus the shared Rust edge. This is the
# recovery/development path when a Cloudflare connector is already supervised
# elsewhere on the laptop.
codespace-origin-up:
    bash scripts/dev/codespace-origin-up

# Full GHA Codespace lifecycle: application backends first, shared Rust edge
# second, Cloudflare connector last. The connector contract is intentionally a
# remotely managed Cloudflare Tunnel: require its token before starting any
# local layer so a missing secret cannot cause a start-then-rollback cycle.
# Cargo installs only executable bytes, so bind oresc to the exact package-owned
# flags contract materialized by the reviewed codespaces-cluster bootstrap.
codespace-edge-up:
    token="${TUNNEL_TOKEN:-${CF_TUNNEL_TOKEN:-}}"; [[ -n "${token//[[:space:]]/}" ]] || { echo >&2 "TUNNEL_TOKEN (preferred) or CF_TUNNEL_TOKEN is required for the remotely managed Cloudflare Tunnel"; exit 78; }; unset token; repo="$PWD"; bash scripts/dev/codespace-origin-up; root="${ORES_CODESPACE_CLUSTER_DIR:-$HOME/.cache/ores/codespaces-cluster}"; flags="${ORES_TOOL_PIN_RECEIPT_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/ores/tool-pins/codespaces-cluster}/oresc.contract"; test -s "$flags" || { echo >&2 "missing pinned oresc flag contract: $flags"; exit 66; }; export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"; if ! FLAGS2ENV_CONFIG="$flags" oresc --no-json codespace edge up; then set +e; (cd "$root" && CODESPACES_CLUSTER_CONFIG="$repo/config/codespaces-cluster.toml" just local-cluster-down); ORES_CODESPACES_CLUSTER_MANIFEST=.ores-compose.yaml ORES_CODESPACES_CLUSTER_STATE_DIR=.ores/codespaces-cluster-app ORES_CODESPACES_CLUSTER_READY_PORT=18091 ORES_CODESPACES_CLUSTER_SERVICE=gha-indie-worker-app "$root/target/debug/codespaces-cluster-ctl" down; exit 1; fi

# Status/down deliberately do not fetch. They inspect or stop the exact shared
# checkout/controller binary that owns the running supervisors.
codespace-origin-status:
    repo="$PWD"; root="${ORES_CODESPACE_CLUSTER_DIR:-$HOME/.cache/ores/codespaces-cluster}"; test -x "$root/target/debug/codespaces-cluster-ctl" || { echo >&2 "codespaces-cluster controller is missing; run just codespace-origin-up first"; exit 2; }; ORES_CODESPACES_CLUSTER_MANIFEST=.ores-compose.yaml ORES_CODESPACES_CLUSTER_STATE_DIR=.ores/codespaces-cluster-app ORES_CODESPACES_CLUSTER_READY_PORT=18091 ORES_CODESPACES_CLUSTER_SERVICE=gha-indie-worker-app "$root/target/debug/codespaces-cluster-ctl" status; (cd "$root" && CODESPACES_CLUSTER_CONFIG="$repo/config/codespaces-cluster.toml" just local-cluster-status); curl --fail --silent --show-error --max-time 2 http://127.0.0.1:8080/api/readyz >/dev/null

codespace-edge-status:
    just codespace-origin-status
    flags="${ORES_TOOL_PIN_RECEIPT_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/ores/tool-pins/codespaces-cluster}/oresc.contract"; test -s "$flags" || { echo >&2 "missing pinned oresc flag contract: $flags"; exit 66; }; export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"; FLAGS2ENV_CONFIG="$flags" oresc --no-json codespace edge status

# Teardown is deliberately best-effort across independent ownership layers.
# Missing/tampered connector evidence must not prevent the Rust edge/app from
# being stopped, and a missing controller must not prevent connector teardown.
codespace-edge-down:
    repo="$PWD"; root="${ORES_CODESPACE_CLUSTER_DIR:-$HOME/.cache/ores/codespaces-cluster}"; controller="$root/target/debug/codespaces-cluster-ctl"; flags="${ORES_TOOL_PIN_RECEIPT_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/ores/tool-pins/codespaces-cluster}/oresc.contract"; export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"; set +e; if [[ -s "$flags" ]]; then FLAGS2ENV_CONFIG="$flags" oresc --no-json codespace edge down; connector_rc=$?; else echo >&2 "missing pinned oresc flag contract: $flags"; connector_rc=66; fi; if [[ -x "$controller" ]]; then (cd "$root" && CODESPACES_CLUSTER_CONFIG="$repo/config/codespaces-cluster.toml" just local-cluster-down); edge_rc=$?; ORES_CODESPACES_CLUSTER_MANIFEST=.ores-compose.yaml ORES_CODESPACES_CLUSTER_STATE_DIR=.ores/codespaces-cluster-app ORES_CODESPACES_CLUSTER_READY_PORT=18091 ORES_CODESPACES_CLUSTER_SERVICE=gha-indie-worker-app "$controller" down; app_rc=$?; else echo >&2 "codespaces-cluster controller is missing; Rust edge/app teardown cannot be proven"; edge_rc=2; app_rc=2; fi; set -e; if (( connector_rc != 0 || edge_rc != 0 || app_rc != 0 )); then exit 1; fi

codespace-edge-check:
    command -v just >/dev/null
    command -v gh >/dev/null
    command -v cargo >/dev/null
    command -v curl >/dev/null
    command -v cloudflared >/dev/null || { echo >&2 "cloudflared is required"; exit 127; }
    rev="$(tr -d '[:space:]' < config/codespaces-cluster.rev)"; [[ "$rev" =~ ^[0-9a-f]{40}$ ]] || { echo >&2 "invalid config/codespaces-cluster.rev"; exit 2; }
    cargo run --locked --manifest-path tools/dev-runtime/Cargo.toml -- validate
    bash -n scripts/dev/codespace-origin-up
    grep -Fq 'cleanup_started_layers() (' scripts/dev/codespace-origin-up
    grep -Fq 'bootstrap did not materialize controller' scripts/dev/codespace-origin-up
    grep -Fq 'TUNNEL_TOKEN (preferred) or CF_TUNNEL_TOKEN is required' Justfile
    grep -Fq 'FLAGS2ENV_CONFIG="$flags" oresc --no-json codespace edge up' Justfile
    @echo "GHA Indie Worker application + shared Codespace edge contracts are ready"
