#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

path="_apps/gha-monorepo"
expected="$(git ls-tree HEAD "$path" | awk '{print $3}')"
[[ -n "$expected" ]] || { echo "tracked gitlink missing: $path" >&2; exit 1; }

git submodule sync -- "$path"
git submodule update --init --recursive -- "$path"
actual="$(git -C "$path" rev-parse HEAD)"

if [[ "$actual" != "$expected" ]]; then
  echo "submodule pin mismatch: expected $expected, got $actual" >&2
  exit 1
fi

printf 'gha-monorepo pinned at %s\n' "$actual"
