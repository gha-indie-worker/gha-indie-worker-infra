#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ORES_COMPOSE_BIN="${ORES_COMPOSE_BIN:-ores-compose}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/indiebuild-isolation.XXXXXX")"
PROBE_OUTPUT_DIR="$TMP/probes"
UP_LOG="$TMP/up.log"
MISSING_LOG="$TMP/missing.log"
UP_PID=""

cleanup() {
  if [[ -n "$UP_PID" ]] && kill -0 "$UP_PID" 2>/dev/null; then
    kill -INT "$UP_PID" 2>/dev/null || true
    wait "$UP_PID" 2>/dev/null || true
  fi
  "$ORES_COMPOSE_BIN" down "$ROOT/laptop-ci-secret-isolation.ores-compose.yaml" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

fail() {
  echo "laptop CI isolation acceptance: FAIL: $*" >&2
  if [[ -s "$UP_LOG" ]]; then
    echo "--- isolation up log ---" >&2
    tail -n 120 "$UP_LOG" >&2 || true
  fi
  exit 1
}

service_block() {
  local service="$1" file="$2"
  awk -v wanted="  ${service}:" '
    $0 == wanted { inside=1; print; next }
    inside && /^  [A-Za-z0-9_-]+:$/ { exit }
    inside { print }
  ' "$file"
}

command -v "$ORES_COMPOSE_BIN" >/dev/null 2>&1 || fail "ores-compose executable not found: $ORES_COMPOSE_BIN"
mkdir -p "$PROBE_OUTPUT_DIR"
export PROBE_OUTPUT_DIR

# Fake values model the parent shell holding every control-plane credential at
# once. Child probes inspect *presence*, not values, and never persist them.
export WORKER_APP_SENTINEL='fake-app-sentinel'
export WORKER_WEBHOOK_SENTINEL='fake-webhook-sentinel'
export WORKER_AUTH_SENTINEL='fake-worker-auth-sentinel'
export TUNNEL_SENTINEL='fake-tunnel-sentinel'
export UNRELATED_SENTINEL='fake-unrelated-operator-sentinel'
unset INTENTIONALLY_MISSING_SECRET || true

# Static assertions bind this executable fixture to the production manifest and
# prove the two credential families are not merely present somewhere in YAML —
# they are present only in the intended service block.
PROD="$ROOT/.ores-compose.yaml"
RULES="$ROOT/modules/cloudflare/platform/rulesets.tf"
worker_block="$(service_block ci-worker "$PROD")"
tunnel_block="$(service_block cloudflare-tunnel "$PROD")"
api_block="$(service_block api "$PROD")"
web_block="$(service_block web "$PROD")"

grep -Fq 'commit: b599977c766a9b9209a8d554d506f8639be5a08b' "$PROD" || fail "production monorepo source pin drifted from reviewed #9 head"
[[ "$worker_block" == *'BUILD_SERVER_REPORTING_MODE: "app-required"'* ]] || fail "production worker is not app-required"
[[ "$worker_block" == *'HOST: "127.0.0.1"'* ]] || fail "production worker is not loopback-bound"
[[ "$worker_block" == *'BUILD_SERVER_WORK_ROOT: INDIEBUILD_WORK_ROOT'* ]] || fail "durable worker work root is not an explicit required binding"
[[ "$worker_block" == *'BUILD_SERVER_GITHUB_APP_PRIVATE_KEY_PATH: INDIEBUILD_GITHUB_APP_PRIVATE_KEY_PATH'* ]] || fail "worker App key binding missing"
[[ "$worker_block" == *'BUILD_SERVER_GITHUB_WEBHOOK_SECRET: INDIEBUILD_GITHUB_WEBHOOK_SECRET'* ]] || fail "worker webhook binding missing"
[[ "$worker_block" == *'scripts/bootstrap-ci-worker.sh'* ]] || fail "worker build does not use the trusted bootstrap"
[[ "$worker_block" == *'scripts/run-ci-worker.sh'* ]] || fail "worker start does not use the provenance-checking launcher"
[[ "$worker_block" == *'scripts/ci-worker-healthcheck.sh'* ]] || fail "worker readiness does not use the secret-scrubbing wrapper"
[[ "$worker_block" != *'INDIEBUILD_CLOUDFLARE_TUNNEL_TOKEN'* ]] || fail "worker block can see the tunnel token source"

[[ "$tunnel_block" == *'TUNNEL_TOKEN: INDIEBUILD_CLOUDFLARE_TUNNEL_TOKEN'* ]] || fail "tunnel token binding missing"
[[ "$tunnel_block" == *'scripts/cloudflared-healthcheck.sh'* ]] || fail "tunnel readiness does not use the token-scrubbing wrapper"
[[ "$tunnel_block" != *'INDIEBUILD_GITHUB_APP_'* ]] || fail "tunnel block can see App bindings"
[[ "$tunnel_block" != *'INDIEBUILD_GITHUB_WEBHOOK_SECRET'* ]] || fail "tunnel block can see webhook binding"
[[ "$tunnel_block" != *'INDIEBUILD_WORKER_AUTH_SECRET'* ]] || fail "tunnel block can see worker auth binding"

for sibling in "$api_block" "$web_block"; do
  [[ "$sibling" != *'INDIEBUILD_GITHUB_APP_'* ]] || fail "ordinary sibling can see App bindings"
  [[ "$sibling" != *'INDIEBUILD_GITHUB_WEBHOOK_SECRET'* ]] || fail "ordinary sibling can see webhook binding"
  [[ "$sibling" != *'INDIEBUILD_WORKER_AUTH_SECRET'* ]] || fail "ordinary sibling can see worker auth binding"
  [[ "$sibling" != *'INDIEBUILD_CLOUDFLARE_TUNNEL_TOKEN'* ]] || fail "ordinary sibling can see tunnel binding"
done

if grep -Eq -- '--token([ =]|$)' "$PROD"; then
  fail "production manifest puts a tunnel token on argv"
fi
grep -Fq 'http.request.uri.path ne \"/webhooks/github\"' "$RULES" || fail "Cloudflare webhook-only path guard missing"
grep -Fq 'http.request.method ne \"POST\"' "$RULES" || fail "Cloudflare webhook-only method guard missing"

# Runtime assertion: build, long-running service and healthcheck each receive
# only the service's admitted environment. `UNRELATED_SENTINEL` must disappear
# everywhere despite being present in this parent process.
(
  cd "$ROOT"
  "$ORES_COMPOSE_BIN" up "$ROOT/laptop-ci-secret-isolation.ores-compose.yaml"
) >"$UP_LOG" 2>&1 &
UP_PID=$!

expected=(
  worker.build.ok worker.service.ok worker.healthcheck.ok
  tunnel.build.ok tunnel.service.ok tunnel.healthcheck.ok
  sibling.build.ok sibling.service.ok sibling.healthcheck.ok
)

deadline=$((SECONDS + 30))
while (( SECONDS < deadline )); do
  all=1
  for marker in "${expected[@]}"; do
    [[ -f "$PROBE_OUTPUT_DIR/$marker" ]] || { all=0; break; }
  done
  (( all == 1 )) && break
  if ! kill -0 "$UP_PID" 2>/dev/null; then
    wait "$UP_PID" || true
    UP_PID=""
    fail "ores-compose up exited before all build/service/healthcheck probes succeeded"
  fi
  sleep 0.1
done

for marker in "${expected[@]}"; do
  [[ -f "$PROBE_OUTPUT_DIR/$marker" ]] || fail "missing runtime probe marker: $marker"
done

kill -INT "$UP_PID" 2>/dev/null || true
wait "$UP_PID" 2>/dev/null || true
UP_PID=""
"$ORES_COMPOSE_BIN" down "$ROOT/laptop-ci-secret-isolation.ores-compose.yaml" >/dev/null 2>&1 || true

# Admission-order assertion: a missing declared secret must stop before the
# source checkout boundary and before either build/start command can touch disk.
rm -f "$PROBE_OUTPUT_DIR/build-side-effect" "$PROBE_OUTPUT_DIR/process-side-effect"
set +e
(
  cd "$ROOT"
  "$ORES_COMPOSE_BIN" up "$ROOT/laptop-ci-missing-secret.ores-compose.yaml"
) >"$MISSING_LOG" 2>&1
missing_status=$?
set -e

(( missing_status != 0 )) || fail "missing secret unexpectedly admitted"
if grep -Fq 'source_materialization_started' "$MISSING_LOG"; then
  fail "missing secret crossed the source-materialization boundary"
fi
[[ ! -e "$PROBE_OUTPUT_DIR/build-side-effect" ]] || fail "missing secret allowed a build side effect"
[[ ! -e "$PROBE_OUTPUT_DIR/process-side-effect" ]] || fail "missing secret allowed a service side effect"

echo "laptop CI isolation acceptance: PASS"
echo "- production source pin and trusted phase-scrub wrappers are fixed"
echo "- production credential families are scoped to the intended service blocks"
echo "- worker/tunnel/sibling environments isolated across build, service and healthcheck"
echo "- undeclared parent sentinel absent"
echo "- missing secret rejected before source/process side effects"
echo "- production manifest uses App-required checks and durable external report state"
echo "- Cloudflare exposes only POST /webhooks/github on the laptop CI hostname"
