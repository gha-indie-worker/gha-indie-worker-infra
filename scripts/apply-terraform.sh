#!/usr/bin/env bash
# Plan (and, only when explicitly asked, apply) one Terraform environment root.
#
#   scripts/apply-terraform.sh production/gcp-platform
#   scripts/apply-terraform.sh production/cloudflare-platform --apply
#
# Backward-compatible aliases `gcp` and `cloudflare` resolve to the production
# platform roots. CI never runs an apply.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: scripts/apply-terraform.sh <environment/root> [--apply] [--auto-approve] [-- <extra terraform args>]

examples:
  scripts/apply-terraform.sh production/gcp-platform
  scripts/apply-terraform.sh production/gcp-cloudrun
  scripts/apply-terraform.sh production/cloudflare-platform
  scripts/apply-terraform.sh production/cloudflare-dns
  scripts/apply-terraform.sh production/neon

legacy aliases:
  gcp         -> production/gcp-platform
  cloudflare  -> production/cloudflare-platform

--apply         apply the saved reviewed plan
--auto-approve  skip the prompt; requires --apply and TF_APPLY_I_MEAN_IT=1
EOF
  exit 2
}

[[ $# -ge 1 ]] || usage

ROOT=""
APPLY=0
AUTO=0
EXTRA=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --auto-approve) AUTO=1; shift ;;
    --plan-only) APPLY=0; shift ;;
    -h|--help) usage ;;
    --) shift; EXTRA=("$@"); break ;;
    -*) echo "unknown flag: $1" >&2; usage ;;
    *) [[ -z "$ROOT" ]] || usage; ROOT="$1"; shift ;;
  esac
done
[[ -n "$ROOT" ]] || usage

case "$ROOT" in
  gcp) ROOT="production/gcp-platform" ;;
  cloudflare) ROOT="production/cloudflare-platform" ;;
esac

[[ "$ROOT" != /* && "$ROOT" != *".."* ]] || { echo "root must be a relative path under environments/" >&2; exit 2; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ENV_ROOT="$REPO_ROOT/environments"
DIR="$ENV_ROOT/$ROOT"
[[ -d "$DIR" && -f "$DIR/main.tf" ]] || {
  echo "no such Terraform environment root: environments/$ROOT" >&2
  echo "available roots:" >&2
  find "$ENV_ROOT" -mindepth 3 -maxdepth 3 -name main.tf -print 2>/dev/null \
    | sed "s#^$ENV_ROOT/##; s#/main.tf\$##" | sort | sed 's/^/  /' >&2
  exit 2
}
DIR="$(cd "$DIR" && pwd -P)"
case "$DIR/" in "$ENV_ROOT/"*) ;; *) echo "root escapes environments/: $ROOT" >&2; exit 2 ;; esac

command -v terraform >/dev/null || { echo "terraform is not installed" >&2; exit 127; }

ROOT_NAME="$(basename "$DIR")"
case "$ROOT_NAME" in
  cloudflare-*)
    : "${CLOUDFLARE_API_TOKEN:?export CLOUDFLARE_API_TOKEN first}"
    ;;
  gcp-*)
    command -v gcloud >/dev/null || { echo "gcloud is not installed" >&2; exit 127; }
    gcloud auth application-default print-access-token >/dev/null 2>&1 \
      || { echo "no application-default credentials: run 'gcloud auth application-default login'" >&2; exit 1; }
    ;;
  neon)
    : "${NEON_API_KEY:?export NEON_API_KEY first}"
    ;;
  *)
    echo "unsupported Terraform root provider: $ROOT_NAME" >&2
    exit 2
    ;;
esac

cd "$DIR"
PLAN_FILE="$(mktemp -t "tfplan-${ROOT_NAME}-XXXXXX")"
cleanup() { rm -f "$PLAN_FILE"; }
trap cleanup EXIT

echo "==> terraform fmt -check   (environments/$ROOT)"
terraform fmt -check -diff -recursive

echo "==> terraform init        (environments/$ROOT)"
terraform init -input=false

echo "==> terraform validate    (environments/$ROOT)"
terraform validate

echo "==> terraform plan        (environments/$ROOT)"
set +e
if [[ ${#EXTRA[@]} -gt 0 ]]; then
  terraform plan -input=false -detailed-exitcode -out="$PLAN_FILE" "${EXTRA[@]}"
else
  terraform plan -input=false -detailed-exitcode -out="$PLAN_FILE"
fi
PLAN_STATUS=$?
set -e

case "$PLAN_STATUS" in
  0) echo "==> no changes. Infrastructure matches the configuration."; exit 0 ;;
  1) echo "==> plan failed." >&2; exit 1 ;;
  2) : ;;
  *) echo "==> unexpected plan exit code $PLAN_STATUS" >&2; exit 1 ;;
esac

if [[ "$APPLY" -ne 1 ]]; then
  cat <<EOF

==> PLAN ONLY. Nothing has been applied.
Re-run with:
  scripts/apply-terraform.sh $ROOT --apply
EOF
  exit 0
fi

echo
echo "==> the saved plan above will be APPLIED to environments/$ROOT"
if [[ "$AUTO" -eq 1 ]]; then
  [[ "${TF_APPLY_I_MEAN_IT:-}" == "1" ]] || { echo "--auto-approve also requires TF_APPLY_I_MEAN_IT=1" >&2; exit 2; }
else
  read -r -p "Type the root path ('$ROOT') to apply, anything else to abort: " CONFIRM
  [[ "$CONFIRM" == "$ROOT" ]] || { echo "==> aborted. Nothing applied."; exit 1; }
fi

terraform apply -input=false "$PLAN_FILE"
echo
echo "==> applied. Outputs:"
terraform output
