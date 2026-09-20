#!/usr/bin/env bash
set -euo pipefail

role="${1:?role required}"
phase="${2:?phase required}"
out="${PROBE_OUTPUT_DIR:?PROBE_OUTPUT_DIR required}"
mkdir -p "$out"

require_var() {
  local key="$1"
  if [[ -z "${!key+x}" ]]; then
    echo "$role/$phase missing required $key" >&2
    exit 20
  fi
}

forbid_var() {
  local key="$1"
  if [[ -n "${!key+x}" ]]; then
    echo "$role/$phase unexpectedly inherited $key" >&2
    exit 21
  fi
}

case "$role" in
  worker)
    require_var WORKER_APP
    require_var WORKER_WEBHOOK
    require_var WORKER_AUTH
    forbid_var TUNNEL_TOKEN
    forbid_var UNRELATED_SENTINEL
    ;;
  tunnel)
    require_var TUNNEL_TOKEN
    forbid_var WORKER_APP
    forbid_var WORKER_WEBHOOK
    forbid_var WORKER_AUTH
    forbid_var UNRELATED_SENTINEL
    ;;
  sibling)
    forbid_var WORKER_APP
    forbid_var WORKER_WEBHOOK
    forbid_var WORKER_AUTH
    forbid_var TUNNEL_TOKEN
    forbid_var UNRELATED_SENTINEL
    ;;
  *)
    echo "unknown probe role: $role" >&2
    exit 22
    ;;
esac

# Record only names, never values. The sentinel values are intentionally not
# persisted even though they are fake test credentials.
printf '%s\n' "$role/$phase" > "$out/$role.$phase.ok"

action="${3:-return}"
if [[ "$action" == "serve" ]]; then
  while true; do sleep 1; done
fi
