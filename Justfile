set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# `up` refreshes the shared implementation before launching it. The checkout is
# outside this repository so ephemeral runtime code/state never pollutes git.
codespace-edge-up:
    root="${ORES_CODESPACE_CLUSTER_DIR:-$HOME/.cache/ores/codespaces-cluster}"; mkdir -p "$(dirname "$root")"; if [[ -d "$root/.git" ]]; then git -C "$root" fetch --prune origin main && git -C "$root" checkout -q main && git -C "$root" merge --ff-only origin/main; else command -v gh >/dev/null; gh repo clone ORESoftware/codespaces-cluster "$root"; fi; cd "$root"; just codespace-edge-up

# Status and down deliberately do not fetch: they inspect/stop the exact checkout
# that owns the running local compose supervisor.
codespace-edge-status:
    root="${ORES_CODESPACE_CLUSTER_DIR:-$HOME/.cache/ores/codespaces-cluster}"; test -f "$root/Justfile" || { echo >&2 "codespaces-cluster checkout is missing; run just codespace-edge-up first"; exit 2; }; cd "$root"; just codespace-edge-status

codespace-edge-down:
    root="${ORES_CODESPACE_CLUSTER_DIR:-$HOME/.cache/ores/codespaces-cluster}"; test -f "$root/Justfile" || { echo >&2 "codespaces-cluster checkout is missing; edge is already locally stopped"; exit 0; }; cd "$root"; just codespace-edge-down

codespace-edge-check:
    command -v just >/dev/null
    command -v gh >/dev/null
    command -v cargo >/dev/null
    command -v cloudflared >/dev/null || { echo >&2 "cloudflared is required"; exit 127; }
    @echo "Codespace edge wrapper prerequisites are ready"
