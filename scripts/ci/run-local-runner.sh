#!/usr/bin/env bash
# A foreground, one-job runner inside the MacBook's rootless Linux VM.
set +x
set -Eeuo pipefail
umask 077
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
repo="${1:?usage: run-local-runner.sh OWNER/REPO [jobs]}"
jobs="${2:-1}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# A malformed/string-valued policy document must not admit substring matches.
# Require a JSON array of string slugs with a literal, exact member match.
jq -e --arg repo "$repo" 'type == "array" and all(.[]; type == "string") and any(.[]; . == $repo)' "$root/config/macbook-ci-repositories.json" >/dev/null \
  || { echo 'Repository is not admitted for this rollout.' >&2; exit 2; }
[[ "$jobs" =~ ^[1-4]$ ]] || { echo 'jobs must be 1..4' >&2; exit 2; }
[[ "$(uname -s)" == Darwin ]] || { echo 'MacBook runner broker requires macOS.' >&2; exit 2; }
[[ "$(id -u)" != 0 ]] || { echo 'Do not run this broker as root.' >&2; exit 2; }
# Serialize broker invocations for this macOS login. SIGKILL leaves a
# fail-closed stale lock, which the operator must inspect before clearing.
lock_root="${HOME:?}/.cache/indiebuild-runner"
[[ ! -L "$lock_root" ]] || { echo 'Runner lock directory must not be a symlink.' >&2; exit 2; }
mkdir -p -m 700 "$lock_root"
[[ -O "$lock_root" && ! -L "$lock_root" ]] || { echo 'Runner lock directory is not owned by this user.' >&2; exit 2; }
[[ "$(stat -f %Lp "$lock_root")" == 700 ]] || { echo 'Runner lock directory must be owner-only (0700).' >&2; exit 2; }
lock="$lock_root/active.lock"
mkdir -m 700 "$lock" 2>/dev/null || { echo 'Runner broker is busy or a stale lock needs manual inspection.' >&2; exit 2; }
active_name=''
client_pid=''
cleanup() {
  local status="$?"
  trap - EXIT INT TERM HUP
  if [[ -n "$client_pid" ]]; then
    kill -TERM "$client_pid" 2>/dev/null || true
  fi
  if [[ -n "$active_name" ]]; then
    # An attached client can die while its VM container survives.
    # On cleanup failure keep the lock for manual intervention.
    if ! limactl shell atto-ci -- nerdctl rm -f "$active_name" >/dev/null 2>&1; then
      echo "CRITICAL: could not remove VM runner $active_name; inspect the guest before clearing $lock" >&2
      exit 1
    fi
  fi
  if ! rmdir "$lock"; then
    echo "CRITICAL: could not release runner lock $lock" >&2
    exit 1
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
image=indiebuild-runner:2.338.2-ready
expected=indiebuild-runner@sha256:6c241aa7944a536aaf0117ea7ecfb6e1973177330bd8976f11a819bc5f46b3cd
# No registration token is requested until the exact local image has passed
# provenance verification. The VM user must be non-root as a minimum guard;
# rootless containerd configuration still requires physical acceptance.
vm_uid="$(limactl shell atto-ci -- id -u)"
[[ "$vm_uid" =~ ^[1-9][0-9]*$ ]] || { echo 'Lima VM session must be unprivileged.' >&2; exit 2; }
actual="$(limactl shell atto-ci -- nerdctl image inspect "$image" --format '{{index .RepoDigests 0}}')"
[[ "$actual" == "$expected" ]] || { echo 'Runner image digest differs from the admitted image.' >&2; exit 2; }
for ((job=1; job<=jobs; job++)); do
  name="indiebuild-${repo##*/}-$job-$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-')"
  # The host login stays on the host. Only a short-lived repository registration
  # token crosses stdin into this disposable container; never enable xtrace.
  token="$(gh api --method POST "repos/$repo/actions/runners/registration-token" --jq .token)"
  [[ "$token" =~ ^[A-Za-z0-9_-]+$ ]] || { echo 'Registration token response is invalid.' >&2; exit 2; }
  active_name="$name"
  printf '%s\n' "$token" | limactl shell atto-ci -- nerdctl run --pull=never \
    --rm -i --name "$name" --cpus=2 --memory=4g --pids-limit=1024 \
    --cap-drop=ALL --security-opt no-new-privileges \
    --env "INDIEBUILD_REPOSITORY=$repo" --env "INDIEBUILD_RUNNER_NAME=$name" \
    "$image" /bin/bash -lc '
      set -Eeuo pipefail
      unset RUNNER_PRINT_LOG_TO_STDOUT ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT
      read -r ACTIONS_RUNNER_INPUT_TOKEN
      export ACTIONS_RUNNER_INPUT_TOKEN
      ./config.sh --unattended --ephemeral --disableupdate \
        --url "https://github.com/$INDIEBUILD_REPOSITORY" \
        --name "$INDIEBUILD_RUNNER_NAME" --no-default-labels \
        --labels indiebuild-linux-arm64 --work _work
      unset ACTIONS_RUNNER_INPUT_TOKEN
      exec ./run.sh
    ' &
  client_pid="$!"
  unset token
  # macOS Bash 3.2 supports interruptible wait; traps can force-remove
  # the VM container instead of leaving an attached job alive.
  wait "$client_pid"
  client_pid=''
  active_name=''
done
