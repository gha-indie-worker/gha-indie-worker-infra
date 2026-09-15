#!/usr/bin/env bash
set -euo pipefail

provider="${1:-}"
apply="${2:-}"
environment="${TF_ENVIRONMENT:-production}"

case "$provider" in
  gcp|cloudflare|neon|supabase) ;;
  *) echo "usage: $0 {gcp|cloudflare|neon|supabase} [--apply]" >&2; exit 2 ;;
esac

if [[ -n "$apply" && "$apply" != "--apply" ]]; then
  echo "unknown argument: $apply" >&2
  exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/environments/${environment}/${provider}"
[[ -d "$root" ]] || { echo "missing environment root: $root" >&2; exit 2; }
command -v terraform >/dev/null || { echo "terraform is not installed" >&2; exit 127; }

cd "$root"
terraform init -input=false

echo "State-address migration for ${environment}/${provider}:"
terraform state list | while IFS= read -r address; do
  case "$address" in
    module.*|data.*) continue ;;
  esac
  printf "terraform state mv %q %q\n" "$address" "module.${provider}.${address}"
done

if [[ "$apply" != "--apply" ]]; then
  cat <<EOF

Dry-run only. Review the commands above. To execute them intentionally:
  $0 $provider --apply
EOF
  exit 0
fi

terraform state list | while IFS= read -r address; do
  case "$address" in
    module.*|data.*) continue ;;
  esac
  terraform state mv "$address" "module.${provider}.${address}"
done
