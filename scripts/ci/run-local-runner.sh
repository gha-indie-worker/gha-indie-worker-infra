#!/usr/bin/env bash
# A foreground, one-job runner inside the MacBook's rootless Linux VM.
set -Eeuo pipefail
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
repo="${1:?usage: run-local-runner.sh OWNER/REPO [jobs]}"
jobs="${2:-1}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
jq -e --arg repo "$repo" 'index($repo) != null' "$root/config/macbook-ci-repositories.json" >/dev/null \
  || { echo 'Repository is not admitted for this rollout.' >&2; exit 2; }
[[ "$jobs" =~ ^[1-4]$ ]] || { echo 'jobs must be 1..4' >&2; exit 2; }
image=indiebuild-runner:2.338.2-ready
expected=indiebuild-runner@sha256:6c241aa7944a536aaf0117ea7ecfb6e1973177330bd8976f11a819bc5f46b3cd
actual="$(limactl shell atto-ci -- nerdctl image inspect "$image" --format '{{index .RepoDigests 0}}')"
[[ "$actual" == "$expected" ]] || { echo 'Runner image digest differs from the admitted image.' >&2; exit 2; }
for ((job=1; job<=jobs; job++)); do
  name="indiebuild-${repo##*/}-$job"
  # The host login stays on the host. Only a short-lived repository registration
  # token crosses stdin into this disposable container; never enable xtrace.
  token="$(gh api --method POST "repos/$repo/actions/runners/registration-token" --jq .token)"
  printf '%s\n' "$token" | limactl shell atto-ci -- nerdctl run --pull=never \
    --rm -i --name "$name" --cpus=2 --memory=4g --pids-limit=1024 \
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
    '
  unset token
done
