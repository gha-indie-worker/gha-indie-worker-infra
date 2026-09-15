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
