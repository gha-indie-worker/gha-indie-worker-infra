#!/usr/bin/env bash
set -euo pipefail

provider="${1:-}"
environment="${TF_ENVIRONMENT:-production}"
case "$provider" in gcp|cloudflare|neon|supabase) ;; *) echo "usage: $0 {gcp|cloudflare|neon|supabase}" >&2; exit 2;; esac
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/environments/${environment}/${provider}"
[[ -d "$root" ]] || { echo "missing environment root: $root" >&2; exit 2; }
cd "$root"
command -v terraform >/dev/null || { echo "terraform is not installed" >&2; exit 127; }
terraform init -input=false
mapfile -t addresses < <(terraform state list)
for address in "${addresses[@]}"; do
  case "$address" in module.*|data.*) continue ;; esac
  echo "terraform state mv '$address' 'module.${provider}.${address}'"
done
cat <<EOF

Dry-run only. Review the commands above. To execute them intentionally:
  $0 $provider --apply
EOF
if [[ "${2:-}" == "--apply" ]]; then
  for address in "${addresses[@]}"; do
    case "$address" in module.*|data.*) continue ;; esac
    terraform state mv "$address" "module.${provider}.${address}"
  done
fi
