#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

path="_apps/gha-monorepo"
git submodule update --init -- "$path"
old="$(git ls-tree HEAD "$path" | awk '{print $3}')"

git -C "$path" fetch --prune origin main
git -C "$path" checkout --detach FETCH_HEAD
new="$(git -C "$path" rev-parse HEAD)"

printf 'gha-monorepo pin: %s -> %s\n' "$old" "$new"
if [[ "$old" == "$new" ]]; then
  echo 'already pinned to origin/main'
  exit 0
fi

cat <<EOF
Pin updated in the working tree only. Review the monorepo change, then record it deliberately:
  git add $path
  git diff --cached --submodule=log -- $path
No commit, merge, rebase, reset, or force-push was performed.
EOF
