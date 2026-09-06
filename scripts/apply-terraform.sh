#!/usr/bin/env bash
# Plan (and, only when explicitly asked, apply) one Terraform root.
#
#   scripts/apply-terraform.sh gcp                 # plan only — the default
#   scripts/apply-terraform.sh cloudflare          # plan only
#   scripts/apply-terraform.sh gcp --apply         # plan, show it, ask, apply
#
# THE DEFAULT IS PLAN-ONLY, AND --apply IS THE ONLY WAY PAST IT. CI never runs
# this script; an apply is always a person who has read the plan.
#
# The apply path applies the saved plan file, not a fresh one. That is the whole
# point of `-out`: what you approved is what runs, even if something changed
# underneath in the meantime.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: scripts/apply-terraform.sh <root> [--apply] [--auto-approve] [-- <extra terraform args>]

  <root>          cloudflare | gcp   (a directory under terraform/)
  --apply         actually apply after showing the plan and prompting
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
    --apply)        APPLY=1; shift ;;
    --auto-approve) AUTO=1; shift ;;
    --plan-only)    APPLY=0; shift ;;
    -h|--help)      usage ;;
    --)             shift; EXTRA=("$@"); break ;;
    -*)             echo "unknown flag: $1" >&2; usage ;;
    *)              [[ -z "$ROOT" ]] || usage; ROOT="$1"; shift ;;
  esac
done

[[ -n "$ROOT" ]] || usage

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$REPO_ROOT/terraform/$ROOT"

if [[ ! -d "$DIR" ]]; then
  echo "no such terraform root: terraform/$ROOT" >&2
  echo "available: $(cd "$REPO_ROOT/terraform" && ls -d */ | tr -d /  | tr '\n' ' ')" >&2
  exit 2
fi

command -v terraform >/dev/null || { echo "terraform is not installed" >&2; exit 127; }

# Fail before touching a provider if the credentials for this root are absent,
# so the error names the missing variable instead of being a 401 forty seconds
# later.
case "$ROOT" in
  cloudflare)
    : "${CLOUDFLARE_API_TOKEN:?export CLOUDFLARE_API_TOKEN first — see terraform/cloudflare/README.md for the scopes}"
    ;;
  gcp)
    command -v gcloud >/dev/null || { echo "gcloud is not installed" >&2; exit 127; }
    gcloud auth application-default print-access-token >/dev/null 2>&1 \
      || { echo "no application-default credentials: run 'gcloud auth application-default login'" >&2; exit 1; }
    ;;
esac

cd "$DIR"

PLAN_FILE="$(mktemp -t "tfplan-${ROOT}-XXXXXX")"
cleanup() { rm -f "$PLAN_FILE"; }
trap cleanup EXIT

echo "==> terraform fmt -check   (terraform/$ROOT)"
terraform fmt -check -diff -recursive

echo "==> terraform init        (terraform/$ROOT)"
terraform init -input=false

echo "==> terraform validate    (terraform/$ROOT)"
terraform validate

echo "==> terraform plan        (terraform/$ROOT)"
set +e
terraform plan -input=false -detailed-exitcode -out="$PLAN_FILE" "${EXTRA[@]+"${EXTRA[@]}"}"
PLAN_STATUS=$?
set -e

# -detailed-exitcode: 0 = no changes, 1 = error, 2 = changes present.
case "$PLAN_STATUS" in
  0) echo "==> no changes. Infrastructure matches the configuration."; exit 0 ;;
  1) echo "==> plan failed." >&2; exit 1 ;;
  2) : ;;
  *) echo "==> unexpected plan exit code $PLAN_STATUS" >&2; exit 1 ;;
esac

if [[ "$APPLY" -ne 1 ]]; then
  cat <<EOF

==> PLAN ONLY. Nothing has been applied.

    Re-run with --apply to apply exactly this change:

        scripts/apply-terraform.sh $ROOT --apply

EOF
  exit 0
fi

echo
echo "==> the plan above will now be APPLIED to terraform/$ROOT"
if [[ "$ROOT" == "gcp" ]]; then
  echo "    project: $(terraform output -raw project_id 2>/dev/null || echo 'gha-indie-worker')"
fi
echo

if [[ "$AUTO" -eq 1 ]]; then
  if [[ "${TF_APPLY_I_MEAN_IT:-}" != "1" ]]; then
    echo "--auto-approve also requires TF_APPLY_I_MEAN_IT=1 in the environment." >&2
    exit 2
  fi
  echo "==> --auto-approve: applying without a prompt"
else
  read -r -p "Type the root name ('$ROOT') to apply, anything else to abort: " CONFIRM
  if [[ "$CONFIRM" != "$ROOT" ]]; then
    echo "==> aborted. Nothing applied."
    exit 1
  fi
fi

echo "==> terraform apply       (terraform/$ROOT)"
# The SAVED plan, not a fresh one: what was approved is what runs.
terraform apply -input=false "$PLAN_FILE"

echo
echo "==> applied. Outputs:"
terraform output

if [[ "$ROOT" == "gcp" ]]; then
  cat <<'EOF'

==> Next:
    * check `ingress_posture`: admin-web and admin-api must be
      INGRESS_TRAFFIC_INTERNAL_ONLY, and only web and api may have allUsers.
    * copy `cloud_run_hosts` into terraform/cloudflare's tfvars and into
      cloudflare/edge-router/router.config.json, then re-render wrangler.toml.
EOF
fi
