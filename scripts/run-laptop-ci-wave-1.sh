#!/usr/bin/env bash
set -euo pipefail
umask 077

# Operator-side driver for cohorts/laptop-ci-wave-1.json.
#
# Trust boundary:
# - this script never executes repository commands on the host;
# - GitHub is queried immediately before submission for one coherent PR state;
# - only same-repository, open, non-draft heads are admitted;
# - the exact head SHA is recorded before `giw verify` submits work;
# - the PR head is re-read after the job; a moved or unreadable head makes the
#   receipt stale and therefore unusable as current-head evidence;
# - hosted Actions evidence is queried for that exact same SHA and distinguishes
#   stepful runs from zero-step runner/admission failures;
# - the cohort chooses only fixed worker profiles; PRs cannot supply commands;
# - Wave 1 is advisory until the worker publishes App-owned authoritative checks.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COHORT_FILE="${COHORT_FILE:-$ROOT_DIR/cohorts/laptop-ci-wave-1.json}"
RECEIPT_DIR="${RECEIPT_DIR:-$ROOT_DIR/.indiebuild/receipts}"
GIW_BIN="${GIW_BIN:-giw}"
GH_BIN="${GH_BIN:-gh}"
JQ_BIN="${JQ_BIN:-jq}"
HOSTED_RUN_LIMIT="${HOSTED_RUN_LIMIT:-10}"

usage() {
  cat <<'EOF'
usage: scripts/run-laptop-ci-wave-1.sh [--dry-run] [--entry REPO#PR] [--continue-on-failure]

Environment:
  COHORT_FILE       cohort JSON (default: cohorts/laptop-ci-wave-1.json)
  RECEIPT_DIR       output directory (default: .indiebuild/receipts)
  GIW_BIN           giw executable (default: giw)
  GH_BIN            GitHub CLI executable (default: gh)
  JQ_BIN            jq executable (default: jq)
  HOSTED_RUN_LIMIT  max same-SHA hosted runs inspected per PR (default: 10; max: 20)

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
[[ "$HOSTED_RUN_LIMIT" =~ ^[0-9]+$ ]] && (( HOSTED_RUN_LIMIT >= 1 && HOSTED_RUN_LIMIT <= 20 )) || {
  echo "HOSTED_RUN_LIMIT must be an integer from 1 to 20" >&2
  exit 2
}

[[ -f "$COHORT_FILE" ]] || { echo "cohort not found: $COHORT_FILE" >&2; exit 2; }
[[ ! -L "$COHORT_FILE" ]] || { echo "refusing symlinked cohort: $COHORT_FILE" >&2; exit 2; }
if [[ -e "$RECEIPT_DIR" && -L "$RECEIPT_DIR" ]]; then
  echo "refusing symlinked receipt directory: $RECEIPT_DIR" >&2
  exit 2
fi
mkdir -p "$RECEIPT_DIR"
[[ -d "$RECEIPT_DIR" && ! -L "$RECEIPT_DIR" ]] || {
  echo "receipt path is not a real directory: $RECEIPT_DIR" >&2
  exit 2
}
chmod 700 "$RECEIPT_DIR" 2>/dev/null || true

# Snapshot the operator-owned cohort exactly once. Every admission decision and
# the digest below is made from these same bytes, so an editor/process cannot
# swap entries between the initial validation and later submission.
COHORT_INPUT="$(mktemp "$RECEIPT_DIR/.cohort-snapshot.XXXXXX")"
cleanup() { rm -f "$COHORT_INPUT"; }
trap cleanup EXIT HUP INT TERM
cp -- "$COHORT_FILE" "$COHORT_INPUT"
chmod 600 "$COHORT_INPUT" 2>/dev/null || true

schema="$($JQ_BIN -r '.schemaVersion // empty' "$COHORT_INPUT")"
[[ "$schema" == "indiebuild.cohort.v1" ]] || {
  echo "unsupported cohort schema: ${schema:-<missing>}" >&2
  exit 2
}
mode="$($JQ_BIN -r '.mode // empty' "$COHORT_INPUT")"
[[ "$mode" == "advisory" ]] || {
  echo "wave runner currently refuses non-advisory cohort mode: ${mode:-<missing>}" >&2
  exit 2
}

# Keep the profile authority here as an independent operator-side check. The
# worker performs its own fixed-profile allowlist admission too.
allowed_profiles='["rust-verify","node-verify","python-verify","flutter-verify","playwright","puppeteer","browser-e2e"]'

$JQ_BIN -e '
  (.entries | type) == "array" and
  (.allowedOwners | type) == "array" and
  all(.entries[];
    ((.repo | type) == "string") and
    (.repo | test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")) and
    ((.pullRequest | type) == "number") and
    (.pullRequest >= 1) and (.pullRequest == floor) and
    ((.profile | type) == "string")) and
  all(.allowedOwners[]; (type == "string") and test("^[A-Za-z0-9_.-]+$"))
' "$COHORT_INPUT" >/dev/null || {
  echo "cohort contains malformed owner/repository/PR/profile fields" >&2
  exit 2
}

entry_count="$($JQ_BIN '.entries | length' "$COHORT_INPUT")"
(( entry_count > 0 && entry_count <= 100 )) || {
  echo "cohort entry count is outside 1..100: $entry_count" >&2
  exit 2
}

# Duplicate repo+PR entries are ambiguous evidence and therefore rejected.
duplicate="$($JQ_BIN -r '
  [.entries[] | (.repo + "#" + (.pullRequest|tostring))]
  | group_by(.)[] | select(length > 1) | .[0]
' "$COHORT_INPUT" | head -n1)"
[[ -z "$duplicate" ]] || { echo "duplicate cohort entry: $duplicate" >&2; exit 2; }

run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
receipt="$RECEIPT_DIR/laptop-ci-wave-1-$run_id.ndjson"
if ! ( set -o noclobber; : >"$receipt" ) 2>/dev/null; then
  echo "refusing to overwrite existing receipt path: $receipt" >&2
  exit 2
fi
chmod 600 "$receipt" 2>/dev/null || true

cohort_digest="$(sha256sum "$COHORT_INPUT" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$COHORT_INPUT" | awk '{print $1}')"
$JQ_BIN -cn \
  --arg event "cohort_started" \
  --arg runId "$run_id" \
  --arg cohort "$COHORT_FILE" \
  --arg cohortSha256 "$cohort_digest" \
  --arg mode "$mode" \
  --argjson entryCount "$entry_count" \
  '{event:$event,runId:$runId,cohort:$cohort,cohortSha256:$cohortSha256,mode:$mode,entryCount:$entryCount}' \
  >>"$receipt"

record_refusal() {
  local repo="$1"
  local pr="$2"
  local profile="$3"
  local head_sha="$4"
  local reason="$5"
  echo "$repo#$pr: refused ($reason)" >&2
  $JQ_BIN -cn \
    --arg event "entry_refused" --arg runId "$run_id" --arg repo "$repo" \
    --argjson pullRequest "$pr" --arg profile "$profile" --arg headSha "$head_sha" \
    --arg reason "$reason" \
    '{event:$event,runId:$runId,repo:$repo,pullRequest:$pullRequest,profile:$profile,headSha:$headSha,reason:$reason}' \
    >>"$receipt"
}

# Summarize GitHub-hosted pull-request workflow runs for one immutable head.
# A red run with zero executable steps is deliberately kept separate from a
# stepful non-success run; the former is runner/admission/infrastructure
# evidence and must never be presented as a code-test failure.
hosted_actions_summary() {
  local repo="$1"
  local head_sha="$2"
  local runs_json query_status total_matching tmp

  set +e
  runs_json="$($GH_BIN api "repos/$repo/actions/runs?head_sha=$head_sha&event=pull_request&per_page=$HOSTED_RUN_LIMIT" 2>/dev/null)"
  query_status=$?
  set -e
  if (( query_status != 0 )); then
    $JQ_BIN -cn '{
      available:false,
      queryError:"workflow-runs-query-failed",
      totalMatchingRuns:0,
      inspectedRuns:0,
      stepfulRuns:0,
      zeroStepRuns:0,
      jobsUnavailableRuns:0,
      completedStepfulRuns:0,
      successfulStepfulRuns:0,
      nonSuccessStepfulRuns:0,
      truncated:false,
      runs:[]
    }'
    return 0
  fi

  total_matching="$($JQ_BIN -r '.total_count // 0' <<<"$runs_json")"
  tmp="$(mktemp "$RECEIPT_DIR/.hosted-actions.XXXXXX")"

  while IFS=$'\t' read -r workflow_id workflow_name workflow_status workflow_conclusion workflow_head; do
    [[ -n "$workflow_id" ]] || continue
    # Do not trust query filtering alone: independently bind every retained run
    # to the immutable SHA admitted for this cohort entry.
    [[ "$workflow_head" == "$head_sha" ]] || continue

    local jobs_json jobs_status jobs_available stepful jobs_total jobs_seen
    set +e
    jobs_json="$($GH_BIN api "repos/$repo/actions/runs/$workflow_id/jobs?per_page=100" 2>/dev/null)"
    jobs_status=$?
    set -e
    if (( jobs_status == 0 )); then
      jobs_total="$($JQ_BIN -r '.total_count // (.jobs | length)' <<<"$jobs_json")"
      jobs_seen="$($JQ_BIN -r '(.jobs // []) | length' <<<"$jobs_json")"
      if [[ "$jobs_total" =~ ^[0-9]+$ && "$jobs_seen" =~ ^[0-9]+$ ]] && (( jobs_total == jobs_seen )); then
        jobs_available=true
        stepful="$($JQ_BIN -r 'any(.jobs[]?; ((.steps // []) | length) > 0)' <<<"$jobs_json")"
      else
        # Incomplete pagination is unavailable evidence; never classify a run
        # from only the first subset of its jobs.
        jobs_available=false
        stepful=null
      fi
    else
      jobs_available=false
      stepful=null
    fi

    $JQ_BIN -cn \
      --argjson id "$workflow_id" \
      --arg name "$workflow_name" \
      --arg status "$workflow_status" \
      --arg conclusion "$workflow_conclusion" \
      --arg headSha "$workflow_head" \
      --argjson jobsAvailable "$jobs_available" \
      --argjson stepful "$stepful" \
      '{
        id:$id,
        name:$name,
        status:$status,
        conclusion:(if $conclusion == "" then null else $conclusion end),
        headSha:$headSha,
        jobsAvailable:$jobsAvailable,
        stepful:$stepful
      }' >>"$tmp"
  done < <($JQ_BIN -r --argjson limit "$HOSTED_RUN_LIMIT" '
    .workflow_runs[:$limit][]?
    | [(.id|tostring), (.name // ""), (.status // ""), (.conclusion // ""), (.head_sha // "")]
    | @tsv
  ' <<<"$runs_json")

  $JQ_BIN -sc --argjson totalMatchingRuns "$total_matching" --argjson limit "$HOSTED_RUN_LIMIT" '
    . as $runs
    | {
        available:true,
        queryError:null,
        totalMatchingRuns:$totalMatchingRuns,
        inspectedRuns:($runs|length),
        stepfulRuns:([$runs[] | select(.jobsAvailable == true and .stepful == true)]|length),
        zeroStepRuns:([$runs[] | select(.jobsAvailable == true and .stepful == false)]|length),
        jobsUnavailableRuns:([$runs[] | select(.jobsAvailable == false)]|length),
        completedStepfulRuns:([$runs[] | select(.jobsAvailable == true and .stepful == true and .status == "completed")]|length),
        successfulStepfulRuns:([$runs[] | select(.jobsAvailable == true and .stepful == true and .status == "completed" and .conclusion == "success")]|length),
        nonSuccessStepfulRuns:([$runs[] | select(.jobsAvailable == true and .stepful == true and .status == "completed" and .conclusion != "success")]|length),
        truncated:($totalMatchingRuns > $limit),
        runs:$runs
      }
  ' "$tmp"
  rm -f "$tmp"
}

failures=0
ran=0

while IFS=$'\t' read -r repo pr profile; do
  key="$repo#$pr"
  if [[ -n "$ONLY_ENTRY" && "$ONLY_ENTRY" != "$key" ]]; then
    continue
  fi
  ran=$((ran + 1))

  if ! $JQ_BIN -e --arg p "$profile" --argjson allowed "$allowed_profiles" '$allowed | index($p) != null' <<< '{}' >/dev/null; then
    record_refusal "$repo" "$pr" "$profile" "" "profile-not-operator-approved:$profile"
    failures=$((failures + 1))
    (( CONTINUE_ON_FAILURE )) || break
    continue
  fi

  owner="${repo%%/*}"
  if ! $JQ_BIN -e --arg owner "$owner" '.allowedOwners | index($owner) != null' "$COHORT_INPUT" >/dev/null; then
    record_refusal "$repo" "$pr" "$profile" "" "owner-not-allowed:$owner"
    failures=$((failures + 1))
    (( CONTINUE_ON_FAILURE )) || break
    continue
  fi

  # Fetch all admission facts in one API response so SHA/fork/state/draft are
  # observations of the same PR state. Read failures are attributable refusals,
  # not reasons to abort the remainder of a --continue-on-failure cohort.
  set +e
  pr_json="$($GH_BIN api "repos/$repo/pulls/$pr" 2>/dev/null)"
  pr_query_status=$?
  set -e
  if (( pr_query_status != 0 )); then
    record_refusal "$repo" "$pr" "$profile" "" "pr-query-failed"
    failures=$((failures + 1))
    (( CONTINUE_ON_FAILURE )) || break
    continue
  fi

  set +e
  observed="$($JQ_BIN -r '[.head.sha, (.head.repo.full_name // ""), .state, (.draft|tostring)] | @tsv' <<<"$pr_json" 2>/dev/null)"
  observed_status=$?
  set -e
  if (( observed_status != 0 )); then
    record_refusal "$repo" "$pr" "$profile" "" "invalid-pr-response"
    failures=$((failures + 1))
    (( CONTINUE_ON_FAILURE )) || break
    continue
  fi
  IFS=$'\t' read -r head_sha head_repo state draft <<<"$observed"

  reason=""
  [[ "$state" == "open" ]] || reason="not-open:$state"
  [[ "$head_repo" == "$repo" ]] || reason="fork-or-repo-mismatch:$head_repo"
  [[ "$draft" == "false" ]] || reason="draft"
  [[ "$head_sha" =~ ^[0-9a-f]{40}$ ]] || reason="invalid-head-sha"

  if [[ -n "$reason" ]]; then
    safe_head="$head_sha"
    [[ "$safe_head" =~ ^[0-9a-f]{40}$ ]] || safe_head=""
    record_refusal "$repo" "$pr" "$profile" "$safe_head" "$reason"
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

  # Verify the CLI's own receipt is pinned to the SHA we admitted and carries a
  # bounded terminal status. A syntactically valid `status: failed` is still a
  # cohort failure even if a buggy CLI exits zero.
  emitted_head="$($JQ_BIN -r '.headSha // empty' <<<"$verify_json" 2>/dev/null || true)"
  emitted_job="$($JQ_BIN -r '.jobId // empty' <<<"$verify_json" 2>/dev/null || true)"
  emitted_status="$($JQ_BIN -r '.status // empty' <<<"$verify_json" 2>/dev/null || true)"
  receipt_job="$emitted_job"
  receipt_status="$emitted_status"
  worker_receipt_valid=true
  [[ "$emitted_head" == "$head_sha" ]] || worker_receipt_valid=false
  [[ -n "$emitted_job" && ${#emitted_job} -le 256 ]] || worker_receipt_valid=false
  case "$emitted_status" in
    succeeded|failed|error|cancelled|timeout) ;;
    *) worker_receipt_valid=false ;;
  esac
  if [[ "$worker_receipt_valid" != true ]]; then
    verify_status=1
    receipt_job="invalid-worker-receipt"
    receipt_status="error"
  elif [[ "$emitted_status" != "succeeded" ]]; then
    verify_status=1
  fi

  # A force-push or an unreadable PR after execution makes the result historical
  # / unverifiable evidence only. Never fabricate an after-head from the old SHA.
  after_head=""
  after_head_query_error=""
  stale=true
  set +e
  after_json="$($GH_BIN api "repos/$repo/pulls/$pr" 2>/dev/null)"
  after_query_status=$?
  set -e
  if (( after_query_status == 0 )); then
    after_head="$($JQ_BIN -r '.head.sha // empty' <<<"$after_json" 2>/dev/null || true)"
    if [[ "$after_head" =~ ^[0-9a-f]{40}$ ]]; then
      if [[ "$after_head" == "$head_sha" ]]; then
        stale=false
      fi
    else
      after_head_query_error="invalid-after-head-sha"
      after_head=""
    fi
  else
    after_head_query_error="pr-recheck-failed"
  fi

  # Compare only with hosted runs that GitHub itself binds to the exact SHA we
  # admitted. Query failure is evidence-unavailable, not a local job failure.
  native_github_actions="$(hosted_actions_summary "$repo" "$head_sha")"

  $JQ_BIN -cn \
    --arg event "entry_finished" --arg runId "$run_id" --arg repo "$repo" \
    --argjson pullRequest "$pr" --arg profile "$profile" --arg headSha "$head_sha" \
    --arg jobId "$receipt_job" --arg status "$receipt_status" \
    --arg afterHeadSha "$after_head" --arg afterHeadQueryError "$after_head_query_error" \
    --argjson cliExit "$verify_status" --argjson stale "$stale" \
    --argjson nativeGitHubActions "$native_github_actions" \
    '{
      event:$event,
      runId:$runId,
      repo:$repo,
      pullRequest:$pullRequest,
      profile:$profile,
      headSha:$headSha,
      jobId:$jobId,
      status:$status,
      afterHeadSha:(if $afterHeadSha == "" then null else $afterHeadSha end),
      afterHeadQueryError:(if $afterHeadQueryError == "" then null else $afterHeadQueryError end),
      cliExit:$cliExit,
      stale:$stale,
      nativeGitHubActions:$nativeGitHubActions
    }' >>"$receipt"

  if (( verify_status != 0 )) || [[ "$stale" == true ]]; then
    failures=$((failures + 1))
    (( CONTINUE_ON_FAILURE )) || break
  fi
done < <($JQ_BIN -r '.entries[] | [.repo, (.pullRequest|tostring), .profile] | @tsv' "$COHORT_INPUT")

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