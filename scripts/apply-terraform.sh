#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: scripts/apply-terraform.sh <gcp|cloudflare|neon|supabase> [--environment NAME] [--apply] [--auto-approve] [-- <extra terraform args>]

Default environment: production. Default behavior: plan only. CI never calls this script.
EOF
  exit 2
}

[[ $# -ge 1 ]] || usage
ROOT="$1"; shift
case "$ROOT" in gcp|cloudflare|neon|supabase) ;; *) usage ;; esac
ENVIRONMENT="production"; APPLY=0; AUTO=0; EXTRA=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --environment) [[ $# -ge 2 ]] || usage; ENVIRONMENT="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --auto-approve) AUTO=1; shift ;;
    --plan-only) APPLY=0; shift ;;
    --) shift; EXTRA=("$@"); break ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$REPO_ROOT/environments/$ENVIRONMENT/$ROOT"
[[ -d "$DIR" ]] || { echo "no environment root: environments/$ENVIRONMENT/$ROOT" >&2; exit 2; }
command -v terraform >/dev/null || { echo "terraform is not installed" >&2; exit 127; }
case "$ROOT" in
  cloudflare) : "${CLOUDFLARE_API_TOKEN:?export CLOUDFLARE_API_TOKEN first}" ;;
  gcp) command -v gcloud >/dev/null || { echo "gcloud is not installed" >&2; exit 127; }; gcloud auth application-default print-access-token >/dev/null 2>&1 || { echo "no application-default credentials" >&2; exit 1; } ;;
  neon) : "${NEON_API_KEY:?export NEON_API_KEY first}" ;;
  supabase) : "${SUPABASE_ACCESS_TOKEN:?export SUPABASE_ACCESS_TOKEN first}" ;;
esac
cd "$DIR"
PLAN_FILE="$(mktemp -t "tfplan-${ENVIRONMENT}-${ROOT}-XXXXXX")"
trap 'rm -f "$PLAN_FILE"' EXIT
terraform fmt -check -diff -recursive
terraform init -input=false
terraform validate
set +e
terraform plan -input=false -detailed-exitcode -out="$PLAN_FILE" "${EXTRA[@]+"${EXTRA[@]}"}"
status=$?
set -e
case "$status" in 0) echo "no changes"; exit 0;; 1) echo "plan failed" >&2; exit 1;; 2) ;; *) exit 1;; esac
[[ "$APPLY" -eq 1 ]] || { echo "PLAN ONLY. Re-run with --apply after review."; exit 0; }
if [[ "$AUTO" -eq 1 ]]; then
  [[ "${TF_APPLY_I_MEAN_IT:-}" == "1" ]] || { echo "--auto-approve requires TF_APPLY_I_MEAN_IT=1" >&2; exit 2; }
else
  read -r -p "Type '$ENVIRONMENT/$ROOT' to apply: " confirm
  [[ "$confirm" == "$ENVIRONMENT/$ROOT" ]] || { echo "aborted"; exit 1; }
fi
terraform apply -input=false "$PLAN_FILE"
terraform output
