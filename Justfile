set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# Lifecycle behavior belongs to ORESoftware/ores-cli; these are intentionally thin wrappers.
codespace-edge-up:
    @command -v oresc >/dev/null 2>&1 || { echo >&2 "oresc is required; install/update ORESoftware/ores-cli first"; exit 127; }
    oresc --no-json codespace edge up

codespace-edge-status:
    @command -v oresc >/dev/null 2>&1 || { echo >&2 "oresc is required; install/update ORESoftware/ores-cli first"; exit 127; }
    oresc --no-json codespace edge status

codespace-edge-down:
    @command -v oresc >/dev/null 2>&1 || { echo >&2 "oresc is required; install/update ORESoftware/ores-cli first"; exit 127; }
    oresc --no-json codespace edge down

# Read-only smoke check for a provisioned Codespace. Exit 2 means the edge runtime is installed but stopped.
codespace-edge-check:
    @command -v cloudflared >/dev/null 2>&1 || { echo >&2 "cloudflared is required; rebuild the Codespace"; exit 127; }
    @command -v oresc >/dev/null 2>&1 || { echo >&2 "oresc is required; rebuild the Codespace with ORES_CLI_READ_TOKEN available"; exit 127; }
    @oresc --no-json codespace edge status >/dev/null || test $? -eq 2
    @echo "Codespace edge tooling is ready"
