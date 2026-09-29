#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tunnel_script="$repo_root/scripts/dev/tunnel"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_count() {
    local expected="$1"
    local pattern="$2"
    local file="$3"
    local actual
    actual="$(grep -c -F "$pattern" "$file" 2>/dev/null || true)"
    if [[ "$actual" != "$expected" ]]; then
        fail "expected $expected occurrences of $pattern in $file, got $actual"
    fi
}

run_case() {
    local name="$1"
    shift

    local root
    root="$(mktemp -d "${TMPDIR:-/tmp}/giw-tunnel-test.XXXXXX")"
    local home="$root/home"
    local bin="$root/bin"
    local state="$root/state"
    local log="$root/calls.log"
    local credentials="$root/tunnel.json"
    local config="$root/cloudflared.yml"
    mkdir -p "$home" "$bin" "$state"
    : > "$log"
    printf '{}\n' > "$credentials"
    chmod 600 "$credentials"

    cat > "$config" <<EOF
tunnel: 00000000-0000-0000-0000-000000000000
credentials-file: $credentials
ingress:
  - hostname: local.indiebuild.dev
    service: http://127.0.0.1:8080
  - service: http_status:404
EOF

    cat > "$bin/cargo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'cargo %s\n' "$*" >> "$FAKE_CALL_LOG"

for arg in "$@"; do
    if [[ "$arg" == "doctor" ]]; then
        count_file="$FAKE_STATE_DIR/doctor-count"
        count=0
        if [[ -f "$count_file" ]]; then
            count="$(cat "$count_file")"
        fi
        count=$((count + 1))
        printf '%s\n' "$count" > "$count_file"
        if [[ -n "${FAKE_DOCTOR_FAIL_AFTER:-}" ]] && (( count > FAKE_DOCTOR_FAIL_AFTER )); then
            exit "${FAKE_DOCTOR_LATE_STATUS:-27}"
        fi
        exit "${FAKE_DOCTOR_STATUS:-0}"
    fi
    if [[ "$arg" == "tunnel" ]]; then
        count_file="$FAKE_STATE_DIR/tunnel-count"
        count=0
        if [[ -f "$count_file" ]]; then
            count="$(cat "$count_file")"
        fi
        count=$((count + 1))
        printf '%s\n' "$count" > "$count_file"
        exit "${FAKE_TUNNEL_STATUS:-0}"
    fi
done

exit 99
EOF
    chmod +x "$bin/cargo"

    cat > "$bin/cloudflared" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'cloudflared %s\n' "$*" >> "$FAKE_CALL_LOG"

joined=" $* "
if [[ "$joined" == *" ingress validate "* ]]; then
    exit "${FAKE_INGRESS_VALIDATE_STATUS:-0}"
fi
if [[ "$joined" == *" ingress rule "* ]]; then
    url="${!#}"
    if [[ "$url" == "https://local.indiebuild.dev/" ]]; then
        printf 'Matched rule #1\nhostname: local.indiebuild.dev\n'
        if [[ "${FAKE_BAD_ROUTE:-0}" == "1" ]]; then
            printf 'service: http://127.0.0.1:9999\n'
        else
            printf 'service: http://127.0.0.1:8080\n'
        fi
        exit 0
    fi
    printf 'Matched rule #2\nservice: http_status:404\n'
    exit 0
fi

exit 98
EOF
    chmod +x "$bin/cloudflared"

    cat > "$bin/oresc" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'oresc %s\n' "$*" >> "$FAKE_CALL_LOG"
exit "${FAKE_ORESC_STATUS:-2}"
EOF
    chmod +x "$bin/oresc"

    set +e
    env \
        HOME="$home" \
        PATH="$bin:/usr/bin:/bin" \
        FAKE_CALL_LOG="$log" \
        FAKE_STATE_DIR="$state" \
        "$@" \
        "$tunnel_script" laptop "$config"
    local status="$?"
    set -e

    CASE_ROOT="$root"
    CASE_LOG="$log"
    CASE_CONFIG="$config"
    CASE_CREDENTIALS="$credentials"
    CASE_STATUS="$status"
    echo "PASS setup: $name status=$status"
}

run_case clean-exit
[[ "$CASE_STATUS" == "0" ]] || fail "clean connector exit should return 0"
assert_count 1 ' doctor' "$CASE_LOG"
assert_count 1 ' tunnel laptop ' "$CASE_LOG"

run_case doctor-fails FAKE_DOCTOR_STATUS=23
[[ "$CASE_STATUS" == "23" ]] || fail "doctor failure should be returned unchanged"
assert_count 0 ' tunnel laptop ' "$CASE_LOG"

run_case bad-route FAKE_BAD_ROUTE=1
[[ "$CASE_STATUS" != "0" ]] || fail "bad ingress route must fail admission"
assert_count 0 ' tunnel laptop ' "$CASE_LOG"

run_case bounded-restarts \
    FAKE_TUNNEL_STATUS=42 \
    GHA_INDIE_WORKER_TUNNEL_MAX_RESTARTS=2 \
    GHA_INDIE_WORKER_TUNNEL_STABLE_SECONDS=999 \
    GHA_INDIE_WORKER_TUNNEL_BACKOFF_CAP_SECONDS=0
[[ "$CASE_STATUS" == "42" ]] || fail "restart exhaustion must preserve connector exit status"
assert_count 3 ' tunnel laptop ' "$CASE_LOG"

run_case admission-drift \
    FAKE_TUNNEL_STATUS=42 \
    FAKE_DOCTOR_FAIL_AFTER=1 \
    FAKE_DOCTOR_LATE_STATUS=27 \
    GHA_INDIE_WORKER_TUNNEL_MAX_RESTARTS=8 \
    GHA_INDIE_WORKER_TUNNEL_BACKOFF_CAP_SECONDS=0
[[ "$CASE_STATUS" == "27" ]] || fail "post-failure admission drift must stop with admission status"
assert_count 1 ' tunnel laptop ' "$CASE_LOG"

run_case invalid-restart-setting GHA_INDIE_WORKER_TUNNEL_MAX_RESTARTS=banana
[[ "$CASE_STATUS" == "64" ]] || fail "invalid restart setting must fail before launch"
assert_count 0 ' tunnel laptop ' "$CASE_LOG"

run_case credentials-permissions
chmod 644 "$CASE_CREDENTIALS"
set +e
env \
    HOME="$CASE_ROOT/home" \
    PATH="$CASE_ROOT/bin:/usr/bin:/bin" \
    FAKE_CALL_LOG="$CASE_LOG" \
    FAKE_STATE_DIR="$CASE_ROOT/state" \
    "$tunnel_script" laptop "$CASE_CONFIG"
status="$?"
set -e
[[ "$status" == "66" ]] || fail "group/world-readable credentials must fail with 66"

run_case symlink-config
ln -s "$CASE_CONFIG" "$CASE_ROOT/cloudflared-link.yml"
set +e
env \
    HOME="$CASE_ROOT/home" \
    PATH="$CASE_ROOT/bin:/usr/bin:/bin" \
    FAKE_CALL_LOG="$CASE_LOG" \
    FAKE_STATE_DIR="$CASE_ROOT/state" \
    "$tunnel_script" laptop "$CASE_ROOT/cloudflared-link.yml"
status="$?"
set -e
[[ "$status" == "66" ]] || fail "symlink config must fail with 66"

echo 'dev tunnel supervisor regression suite passed'
