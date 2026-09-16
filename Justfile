set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# Full GHA Codespace lifecycle: application backends first, shared Rust edge
# second, Cloudflare connector last. Only `up` refreshes the shared checkout.
codespace-edge-up:
    repo="$PWD"; root="${ORES_CODESPACE_CLUSTER_DIR:-$HOME/.cache/ores/codespaces-cluster}"; mkdir -p "$(dirname "$root")"; if [[ -d "$root/.git" ]]; then git -C "$root" fetch --prune origin main && git -C "$root" checkout -q main && git -C "$root" merge --ff-only origin/main; else command -v gh >/dev/null; gh repo clone ORESoftware/codespaces-cluster "$root"; fi; (cd "$root" && just codespace-edge-bootstrap); ORES_CODESPACES_CLUSTER_MANIFEST=.ores-compose.yaml ORES_CODESPACES_CLUSTER_STATE_DIR=.ores/codespaces-cluster-app ORES_CODESPACES_CLUSTER_READY_PORT=18091 ORES_CODESPACES_CLUSTER_SERVICE=gha-indie-worker-app "$root/target/debug/codespaces-cluster-ctl" up; if ! (cd "$root" && CODESPACES_CLUSTER_CONFIG="$repo/config/codespaces-cluster.toml" just codespace-edge-up); then ORES_CODESPACES_CLUSTER_MANIFEST=.ores-compose.yaml ORES_CODESPACES_CLUSTER_STATE_DIR=.ores/codespaces-cluster-app ORES_CODESPACES_CLUSTER_READY_PORT=18091 ORES_CODESPACES_CLUSTER_SERVICE=gha-indie-worker-app "$root/target/debug/codespaces-cluster-ctl" down || true; exit 1; fi

# Status/down deliberately do not fetch. They inspect or stop the exact shared
# checkout/controller binary that owns the running supervisors.
codespace-edge-status:
    repo="$PWD"; root="${ORES_CODESPACE_CLUSTER_DIR:-$HOME/.cache/ores/codespaces-cluster}"; test -x "$root/target/debug/codespaces-cluster-ctl" || { echo >&2 "codespaces-cluster controller is missing; run just codespace-edge-up first"; exit 2; }; ORES_CODESPACES_CLUSTER_MANIFEST=.ores-compose.yaml ORES_CODESPACES_CLUSTER_STATE_DIR=.ores/codespaces-cluster-app ORES_CODESPACES_CLUSTER_READY_PORT=18091 ORES_CODESPACES_CLUSTER_SERVICE=gha-indie-worker-app "$root/target/debug/codespaces-cluster-ctl" status; (cd "$root" && CODESPACES_CLUSTER_CONFIG="$repo/config/codespaces-cluster.toml" just codespace-edge-status); curl --fail --silent --show-error --max-time 2 http://127.0.0.1:8080/api/readyz >/dev/null

codespace-edge-down:
    repo="$PWD"; root="${ORES_CODESPACE_CLUSTER_DIR:-$HOME/.cache/ores/codespaces-cluster}"; test -x "$root/target/debug/codespaces-cluster-ctl" || { echo >&2 "codespaces-cluster controller is missing; cannot prove ownership of a running app supervisor"; exit 2; }; set +e; (cd "$root" && CODESPACES_CLUSTER_CONFIG="$repo/config/codespaces-cluster.toml" just codespace-edge-down); edge_rc=$?; ORES_CODESPACES_CLUSTER_MANIFEST=.ores-compose.yaml ORES_CODESPACES_CLUSTER_STATE_DIR=.ores/codespaces-cluster-app ORES_CODESPACES_CLUSTER_READY_PORT=18091 ORES_CODESPACES_CLUSTER_SERVICE=gha-indie-worker-app "$root/target/debug/codespaces-cluster-ctl" down; app_rc=$?; set -e; if (( edge_rc != 0 || app_rc != 0 )); then exit 1; fi

codespace-edge-check:
    command -v just >/dev/null
    command -v gh >/dev/null
    command -v cargo >/dev/null
    command -v curl >/dev/null
    command -v cloudflared >/dev/null || { echo >&2 "cloudflared is required"; exit 127; }
    cargo run --locked --manifest-path tools/dev-runtime/Cargo.toml -- validate
    @echo "GHA Indie Worker application + shared Codespace edge contracts are ready"
