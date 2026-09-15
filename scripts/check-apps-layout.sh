#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

path="_apps/gha-monorepo"
test -f .gitmodules
[[ "$(git config -f .gitmodules --get submodule._apps/gha-monorepo.path)" == "$path" ]]
[[ "$(git config -f .gitmodules --get submodule._apps/gha-monorepo.url)" == "https://github.com/gha-indie-worker/gha-indie-worker-monorepo.git" ]]
[[ "$(git config -f .gitmodules --get submodule._apps/gha-monorepo.branch)" == "main" ]]

mode="$(git ls-files --stage "$path" | awk '{print $1}')"
[[ "$mode" == "160000" ]] || { echo "$path must be a gitlink (mode 160000), got ${mode:-missing}" >&2; exit 1; }

git check-ignore -q --no-index dist/.probe || { echo 'dist/ must be ignored' >&2; exit 1; }
git check-ignore -q --no-index _apps/other-app/.probe || { echo '_apps/* must be ignored by default' >&2; exit 1; }
if git check-ignore -q --no-index "$path"; then
  echo "$path must be explicitly unignored so its gitlink is trackable" >&2
  exit 1
fi

if grep -R -n -E 'source[[:space:]]*=[[:space:]]*"[^"]*(_apps|dist)/' modules environments --include='*.tf'; then
  echo 'Terraform modules/environments must not source code from _apps/ or dist/' >&2
  exit 1
fi

echo 'application checkout contract: ok'
