#!/usr/bin/env bash
set -euo pipefail

# Operator-side driver for cohorts/laptop-ci-wave-1.json.
#
# Trust boundary:
# - this script never executes repository commands on the host;
# - GitHub is queried immediately before submission for one coherent PR state;
# - only same-repository, open, non-draft heads are admitted;
# - the exact head SHA is recorded before `giw verify` submits work;
# - the PR head is re-read after the job; a moved head makes the receipt stale;
# - the cohort chooses only fixed worker profiles; PRs cannot supply commands;
# - Wave 1 is advisory until the worker publishes App-owned authoritative checks.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COHORT_FILE="${COHORT_FILE:-$ROOT_DIR/cohorts/laptop-ci-wave-1.json}"
RECEIPT_DIR="${RECEIPT_DIR:-$ROOT_DIR/.indiebuild/receipts}"
GIW_BIN="${GIW_BIN:-giw}"
GH_BIN="${GH_BIN:-gh}"
JQ_BIN="${JQ_BIN:-jq}"

usage() {
  cat <<'EOF'
usage: scripts/run-laptop-ci-wave-1.sh [--dry-run] [--entry REPO#PR] [--continue-on-failure]

Environment:
  COHORT_FILE   cohort JSON (default: cohorts/laptop-ci-wave-1.json)
  RECEIPT_DIR   output directory (default: .indiebuild/receipts)
  GIW_BIN       giw executable (default: giw)
  GH_BIN        GitHub CLI executable (default: gh)
  JQ_BIN        jq executable (default: jq)

This command intentionally runs entries serially. Parallel execution belongs in
the worker scheduler, where resource limits and queue evidence are authoritative.
EOF
}

DRY_RUN=0
CONTINUE_ON_FAILURE=0
ONLY_ENTRY=""
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --continue-on-failure) CONTINUE_ON_FAILURE=1 ;;
    --entry)
      shift
      (($#)) || { echo "--entry requires REPO#PR" >&2; exit 2; }
      ONLY_ENTRY="$1"
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

for tool in "$GH_BIN" "$JQ_BIN"; do
  command -v "$tool" >/dev/null 2>&1 || { echo "required tool not found: $tool" >&2; exit 2; }
done
if (( ! DRY_RUN )); then
  command -v "$GIW_BIN" >/dev/null 2>&1 || { echo "required tool not found: $GIW_BIN" >&2; exit 2; }
fi

[[ -f "$COHORT_FILE" ]] || { echo "cohort not found: $COHORT_FILE" >&2; exit 2; }

schema="$($JQ_BIN -r '.schemaVersion // empty' "$COHORT_FILE")"
[[ "$schema" == "indiebuild.cohort.v1" ]] || {
  echo "unsupported cohort schema: ${schema:-<missing>}" >&2
  exit 2
}
mode="$($JQ_BIN -r '.mode // empty' "$COHORT_FILE")"
[[ "$mode" == "advisory" ]] || {
  echo "wave runner currently refuses non-advisory cohort mode: ${mode:-<missing>}" >&2
  exit 2
}

# Keep the profile authority here as an independent operator-side check. The
# worker performs its own fixed-profile allowlist admission too.
allowed_profiles='["rust-verify","node-verify","python-verify","flutter-verify","playwright","puppeteer","browser-e2e"]'

entry_count="$($JQ_BIN '.entries | length' "$COHORT_FILE")"
(( entry_count > 0 && entry_count <= 100 )) || {
  echo "cohort entry count is outside 1..100: $entry_count" >&2
  exit 2
}

# Duplicate repo+PR entries are ambiguous evidence and therefore rejected.
duplicate="$($JQ_BIN -r '
  [.entries[] | (.repo + "#" + (.pullRequest|tostring))]
  | group_by(.)[] | select(length > 1) | .[0]
' "$COHORT_FILE" | head -n1)"
[[ -z "$duplicate" ]] || { echo "duplicate cohort entry: $duplicate" >&2; exit 2; }

mkdir -p "$RECEIPT_DIR"
chmod 700 "$RECEIPT_DIR" 2>/dev/null || true
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
receipt="$RECEIPT_DIR/laptop-ci-wave-1-$run_id.ndjson"
: >"$receipt"
chmod 600 "$receipt" 2>/dev/null || true

cohort_digest="$(sha256sum "$COHORT_FILE" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$COHORT_FILE" | awk '{print $1}')"
$JQ_BIN -cn \
  --arg event "cohort_started" \
  --arg runId "$run_id" \
  --arg cohort "$COHORT_FILE" \
  --arg cohortSha256 "$cohort_digest" \
  --arg mode "$mode" \
  --argjson entryCount "$entry_count" \
  '{event:$event,runId:$runId,cohort:$cohort,cohortSha256:$cohortSha256,mode:$mode,entryCount:$entryCount}' \
  >>"$receipt"

failures=0
ran=0

while IFS=$'\t' read -r repo pr profile; do
  key="$repo#$pr"
  if [[ -n "$ONLY_ENTRY" && "$ONLY_ENTRY" != "$key" ]]; then
    continue
  fi
  ran=$((ran + 1))

  if ! $JQ_BIN -e --arg p "$profile" --argjson allowed "$allowed_profiles" '$allowed | index($p) != null' <<< '{}' >/dev/null; then
    echo "$key: profile $profile is not operator-approved" >&2
    failures=$((failures + 1))
    (( CONTINUE_ON_FAILURE )) || break
    continue
  fi

  owner="${repo%%/*}"
  if ! $JQ_BIN -e --arg owner "$owner" '.allowedOwners | index($owner) != null' "$COHORT_FILE" >/dev/null; then
    echo "$key: owner $owner is not in allowedOwners" >&2
    failures=$((failures + 1))
    (( CONTINUE_ON_FAILURE )) || break
    continue
  fi

  # Fetch all admission facts in one API response so SHA/fork/state/draft are
  # observations of the same PR state.
  pr_json="$($GH_BIN api "repos/$repo/pulls/$pr")"
  observed="$($JQ_BIN -r '[.head.sha, (.head.repo.full_name // ""), .state, (.draft|tostring)] | @tsv' <<<"$pr_json")"
  IFS=$'\t' read -r head_sha head_repo state draft <<<"$observed"

  reason=""
  [[ "$state" == "open" ]] || reason="not-open:$state"
  [[ "$head_repo" == "$repo" ]] || reason="fork-or-repo-mismatch:$head_repo"
  [[ "$draft" == "false" ]] || reason="draft"
  [[ "$head_sha" =~ ^[0-9a-f]{40}$ ]] || reason="invalid-head-sha"

  if [[ -n "$reason" ]]; then
    echo "$key: refused ($reason)" >&2
    $JQ_BIN -cn \
      --arg event "entry_refused" --arg runId "$run_id" --arg repo "$repo" \
      --argjson pullRequest "$pr" --arg profile "$profile" --arg headSha "$head_sha" \
      --arg reason "$reason" \
      '{event:$event,runId:$runId,repo:$repo,pullRequest:$pullRequest,profile:$profile,headSha:$headSha,reason:$reason}' \
      >>"$receipt"
    failures=$((failures + 1))
    (( CONTINUE_ON_FAILURE )) || break
    continue
  fi

  echo "==> $key  $profile  $head_sha"
  $JQ_BIN -cn \
    --arg event "entry_admitted" --arg runId "$run_id" --arg repo "$repo" \
    --argjson pullRequest "$pr" --arg profile "$profile" --arg headSha "$head_sha" \
    '{event:$event,runId:$runId,repo:$repo,pullRequest:$pullRequest,profile:$profile,headSha:$headSha}' \
    >>"$receipt"

  if (( DRY_RUN )); then
    continue
  fi

  set +e
  verify_json="$($GIW_BIN --json verify --repo="$repo#$pr" --profile="$profile" 2> >(tee /dev/stderr))"
  verify_status=$?
  set -e

  # Verify the CLI's own receipt is pinned to the SHA we admitted. If it emits
  # malformed/non-JSON output, that is a failed evidence event even if the
  # process exit code happened to be zero.
  emitted_head="$($JQ_BIN -r '.headSha // empty' <<<"$verify_json" 2>/dev/null || true)"
  emitted_job="$($JQ_BIN -r '.jobId // empty' <<<"$verify_json" 2>/dev/null || true)"
  emitted_status="$($JQ_BIN -r '.status // empty' <<<"$verify_json" 2>/dev/null || true)"
  if [[ "$emitted_head" != "$head_sha" || -z "$emitted_job" || -z "$emitted_status" ]]; then
    verify_status=1
  fi

  # A force-push during execution makes the result historical evidence only.
  # It must never be confused with a verdict for the PR's new head.
  after_json="$($GH_BIN api "repos/$repo/pulls/$pr")"
  after_head="$($JQ_BIN -r '.head.sha // empty' <<<"$after_json")"
  stale=false
  [[ "$after_head" == "$head_sha" ]] || stale=true

  $JQ_BIN -cn \
    --arg event "entry_finished" --arg runId "$run_id" --arg repo "$repo" \
    --argjson pullRequest "$pr" --arg profile "$profile" --arg headSha "$head_sha" \
    --arg jobId "$emitted_job" --arg status "$emitted_status" --arg afterHeadSha "$after_head" \
    --argjson cliExit "$verify_status" --argjson stale "$stale" \
    '{event:$event,runId:$runId,repo:$repo,pullRequest:$pullRequest,profile:$profile,headSha:$headSha,jobId:$jobId,status:$status,afterHeadSha:$afterHeadSha,cliExit:$cliExit,stale:$stale}' \
    >>"$receipt"

  if (( verify_status != 0 )) || [[ "$stale" == true ]]; then
    failures=$((failures + 1))
    (( CONTINUE_ON_FAILURE )) || break
  fi
done < <($JQ_BIN -r '.entries[] | [.repo, (.pullRequest|tostring), .profile] | @tsv' "$COHORT_FILE")

if [[ -n "$ONLY_ENTRY" && "$ran" -eq 0 ]]; then
  echo "entry not found in cohort: $ONLY_ENTRY" >&2
  exit 2
fi

$JQ_BIN -cn \
  --arg event "cohort_finished" --arg runId "$run_id" \
  --argjson attempted "$ran" --argjson failures "$failures" \
  '{event:$event,runId:$runId,attempted:$attempted,failures:$failures,success:($failures == 0)}' \
  >>"$receipt"

echo "receipt: $receipt"
(( failures == 0 ))
