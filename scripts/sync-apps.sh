#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
git submodule sync --recursive
git submodule update --init --recursive _apps/gha-monorepo
echo "gha monorepo ready at $repo_root/_apps/gha-monorepo"
