#!/usr/bin/env bash
# chain-check.sh <TICKET> [--complete]
#
# The commit-chain gate. Reads git history for one ticket and verifies:
#   - the six typed commits appear in order: intent, spec, tests, plan, impl, evidence
#   - no impl: commit exists before the ticket's tests: commit; tests: implies intent: and spec:
#   - intent: and spec: carry "Accepted-By: <name> (<login>)", written only by bin/accept.sh
#     (a human at a terminal); tests: carries it when bin/policy.sh acceptance.tests resolves
#     required. A grandfathered ticket (work/<T>/policy.json) is exempt and says so.
#   - plan: carries "Reviewed-By: architect", or "Architecture-Review: skipped (policy)" when
#     bin/policy.sh architectureReview resolves optional for the ticket
#   - between tests: and evidence: (or HEAD), no commit touches src/test/ unless it is
#     a tests-amend: commit for the ticket carrying an Approved-By: trailer
#   - work/<TICKET>/ holds intent.md, spec.md (with "## Contract"), plan.md (with
#     "## Boundary review"), and the plan: commit carries "Reviewed-By: architect"
#   - the verdict was produced by the reviewer: review-verdict.json declares
#     reviewer.tool == "bin/review.sh" and the commit that added it carries
#     "Reviewed-By: bin/review.sh"
#   - with --complete: all six stages exist, the disposition is auto-pass or has a
#     humanResolution, and evidence.json records tier1 and tier2 gates as "pass"
#
# Without --complete the script validates whatever stages exist so far (the Stop hook
# runs it mid-ticket). Exit 0 on pass, 1 on any failure, 2 on usage error.
#
# Commit subject convention: "<prefix>: <TICKET> <summary>" (a space after the colon is
# optional). Compatible with bash 3.2.

set -euo pipefail

TICKET=${1:-}
MODE=partial
if [ -z "$TICKET" ]; then
  echo "usage: bin/chain-check.sh <TICKET> [--complete]" >&2
  exit 2
fi
if [ "${2:-}" = "--complete" ]; then MODE=complete; fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "chain-check: not a git repository" >&2; exit 2; }
cd "$ROOT"
WORK="work/$TICKET"
FAILED=0

fail() { echo "chain-check: FAIL  $*"; FAILED=1; }
ok()   { echo "chain-check: ok    $*"; }

# --- collect the ticket's typed commits, oldest first -------------------------------
# subject regex: prefix, colon, optional space, ticket id, then a non-identifier char or end
subject_re="^(intent|spec|tests|plan|impl|evidence|tests-amend):[[:space:]]*${TICKET}([^A-Za-z0-9-]|$)"

# Neither awk exits on its first match, and that is deliberate. `git log | awk '...{exit}'` leaves
# git writing to a closed pipe: git dies of SIGPIPE, the pipeline reports 141, and `set -o
# pipefail` turns a correct answer into a failed gate. It is a race, so it passed locally and on
# one CI run before failing on the next. Reading the whole stream costs a few milliseconds on a
# history this size and cannot lose that race.
first_hash_for() {  # $1 = prefix ; prints hash of the earliest matching commit
  git log --reverse --topo-order --format='%H %s' \
    | awk -v re="^[0-9a-f]+ $1:[[:space:]]*${TICKET}([^A-Za-z0-9-]|\$)" '$0 ~ re && !seen {print $1; seen=1}'
}
position_of() {  # $1 = hash ; prints 1-based position in oldest-first history
  git log --reverse --topo-order --format='%H' | awk -v h="$1" '$1 == h && !seen {print NR; seen=1}'
}
trailer_of() {   # $1 = hash, $2 = key ; prints trailer values
  git log -1 --format="%(trailers:key=$2,valueonly)" "$1"
}

INTENT=$(first_hash_for intent);     SPEC=$(first_hash_for spec)
TESTS=$(first_hash_for tests);       PLAN=$(first_hash_for plan)
IMPL=$(first_hash_for impl);         EVIDENCE=$(first_hash_for evidence)

echo "chain-check: ticket $TICKET ($MODE)"
for stage in intent spec tests plan impl evidence; do
  case $stage in
    intent) h=$INTENT;; spec) h=$SPEC;; tests) h=$TESTS;;
    plan) h=$PLAN;; impl) h=$IMPL;; evidence) h=$EVIDENCE;;
  esac
  if [ -n "$h" ]; then printf 'chain-check: stage %-9s %s\n' "$stage" "$(git log -1 --format='%h %s' "$h")"
  else printf 'chain-check: stage %-9s (absent)\n' "$stage"; fi
done

# --- order --------------------------------------------------------------------------
prev_pos=0; prev_name=""
for stage in intent spec tests plan impl evidence; do
  case $stage in
    intent) h=$INTENT;; spec) h=$SPEC;; tests) h=$TESTS;;
    plan) h=$PLAN;; impl) h=$IMPL;; evidence) h=$EVIDENCE;;
  esac
  [ -z "$h" ] && continue
  pos=$(position_of "$h")
  if [ "$pos" -le "$prev_pos" ]; then
    fail "order: $stage: commit precedes $prev_name: commit"
  fi
  prev_pos=$pos; prev_name=$stage
done
if [ -n "$IMPL" ] && [ -z "$TESTS" ]; then fail "impl: commit exists but no tests: commit for $TICKET"; fi
if [ "$MODE" = complete ]; then
  for stage in intent spec tests plan impl evidence; do
    case $stage in
      intent) h=$INTENT;; spec) h=$SPEC;; tests) h=$TESTS;;
      plan) h=$PLAN;; impl) h=$IMPL;; evidence) h=$EVIDENCE;;
    esac
    [ -z "$h" ] && fail "complete: missing $stage: commit"
  done
fi
[ "$FAILED" -eq 0 ] && ok "commit order"

# --- presence: a later stage implies the earlier ones -------------------------------
if [ -n "$TESTS" ]; then
  [ -n "$INTENT" ] || fail "tests: commit exists but no intent: commit for $TICKET"
  [ -n "$SPEC" ]   || fail "tests: commit exists but no spec: commit for $TICKET"
fi
if [ -n "$PLAN" ] && [ -z "$TESTS" ]; then fail "plan: commit exists but no tests: commit for $TICKET"; fi

# --- human acceptance ---------------------------------------------------------------
# intent: and spec: always, tests: by policy, carry "Accepted-By: <name> (<login>)". Only
# bin/accept.sh writes that trailer, and only for a human at a terminal. A grandfathered ticket
# predates the gate; work/<T>/policy.json says why, and the waiver is printed, never silent.
POLICY_SH="$(cd "$(dirname "$0")" && pwd)/policy.sh"
policy() {  # $1 = key ; fails closed to "required" when policy.sh is missing or errors
  local v=""
  if [ -x "$POLICY_SH" ]; then v=$("$POLICY_SH" "$TICKET" "$1" 2>/dev/null) || v=""; fi
  case "$1" in risk) echo "${v:-medium}";; grandfathered) echo "${v:-no}";; *) echo "${v:-required}";; esac
}
if [ "$(policy grandfathered)" = yes ]; then
  ok "acceptance waived: grandfathered ($(jq -r '.grandfathered.reason // ""' "$WORK/policy.json" 2>/dev/null | cut -c1-90)...)"
fi
accepted_by() { trailer_of "$1" Accepted-By | grep -Eq '^.+ \(.+\)$'; }
for stage in intent spec tests; do
  case $stage in intent) h=$INTENT;; spec) h=$SPEC;; tests) h=$TESTS;; esac
  [ -z "$h" ] && continue
  need=$(policy "acceptance.$stage")
  if accepted_by "$h"; then ok "$stage: accepted by $(trailer_of "$h" Accepted-By | head -1)"
  elif [ "$need" = required ]; then fail "$stage: commit lacks an Accepted-By trailer; a human accepts $stage with bin/accept.sh (policy acceptance.$stage=required)"
  else ok "$stage: no human acceptance; policy acceptance.$stage=$need (risk $(policy risk))"; fi
done

# --- test lock ----------------------------------------------------------------------
if [ -n "$TESTS" ]; then
  end=${EVIDENCE:-HEAD}
  lock_ok=1
  for c in $(git rev-list --reverse "$TESTS".."$end"); do
    if git diff-tree --no-commit-id --name-only -r "$c" | grep -q '^src/test/'; then
      subj=$(git log -1 --format='%s' "$c")
      if ! echo "$subj" | grep -Eq "^tests-amend:[[:space:]]*${TICKET}([^A-Za-z0-9-]|$)"; then
        fail "test lock: $(git log -1 --format='%h' "$c") touches src/test after tests: without a tests-amend: commit ($subj)"
        lock_ok=0
      elif [ -z "$(trailer_of "$c" Approved-By)" ]; then
        fail "test lock: tests-amend $(git log -1 --format='%h' "$c") lacks an Approved-By: trailer"
        lock_ok=0
      fi
    fi
  done
  [ "$lock_ok" -eq 1 ] && ok "test lock held since tests: commit"
fi

# --- artifacts ----------------------------------------------------------------------
if [ -n "$INTENT" ] || [ "$MODE" = complete ]; then
  [ -f "$WORK/intent.md" ] && ok "intent.md present" || fail "$WORK/intent.md missing"
fi
if [ -n "$SPEC" ] || [ "$MODE" = complete ]; then
  if [ -f "$WORK/spec.md" ]; then
    grep -Eq '^## Contract' "$WORK/spec.md" && ok "spec.md has a Contract section" || fail "spec.md lacks a '## Contract' heading"
  else fail "$WORK/spec.md missing"; fi
fi
if [ -n "$PLAN" ] || [ "$MODE" = complete ]; then
  if [ -f "$WORK/plan.md" ]; then
    grep -Eq '^## Boundary review' "$WORK/plan.md" && ok "plan.md has a Boundary review section" || fail "plan.md lacks a '## Boundary review' heading"
  else fail "$WORK/plan.md missing"; fi
  if [ -n "$PLAN" ]; then
    if trailer_of "$PLAN" Reviewed-By | grep -q '^architect$'; then ok "plan: commit carries Reviewed-By: architect"
    elif trailer_of "$PLAN" Architecture-Review | grep -q '^skipped (policy)$'; then
      if [ "$(policy architectureReview)" = optional ]; then ok "plan: boundary review skipped; policy architectureReview resolves optional (risk $(policy risk))"
      else fail "plan: commit skips the boundary review but policy architectureReview resolves required (risk $(policy risk), or the Contract names an event or a second module)"; fi
    else fail "plan: commit lacks 'Reviewed-By: architect' (or 'Architecture-Review: skipped (policy)' where policy allows it)"; fi
  fi
fi

# --- verdict ------------------------------------------------------------------------
VERDICT="$WORK/review-verdict.json"
if [ -f "$VERDICT" ]; then
  if ! jq -e . "$VERDICT" >/dev/null 2>&1; then fail "review-verdict.json is not valid JSON"
  else
    tool=$(jq -r '.reviewer.tool // empty' "$VERDICT")
    disp=$(jq -r '.disposition // empty' "$VERDICT")
    [ "$tool" = "bin/review.sh" ] && ok "verdict declares reviewer.tool bin/review.sh" || fail "verdict lacks reviewer marker (reviewer.tool != bin/review.sh)"
    case "$disp" in
      auto-pass|block|needs-human) ok "verdict disposition: $disp";;
      *) fail "verdict disposition invalid: '${disp}'";;
    esac
    added=$(git log --format='%H' --diff-filter=A -- "$VERDICT" | tail -1)
    if [ -z "$added" ]; then fail "review-verdict.json is not committed"
    elif trailer_of "$added" Reviewed-By | grep -q '^bin/review.sh$'; then ok "verdict commit carries Reviewed-By: bin/review.sh"
    else fail "commit adding review-verdict.json lacks 'Reviewed-By: bin/review.sh' trailer"; fi
    if [ "$MODE" = complete ]; then
      if [ "$disp" = "auto-pass" ]; then ok "disposition auto-pass"
      elif jq -e '.humanResolution.by and .humanResolution.decision' "$VERDICT" >/dev/null 2>&1; then ok "disposition $disp resolved by human"
      else fail "disposition $disp without a humanResolution {by, decision}"; fi
    fi
  fi
elif [ "$MODE" = complete ]; then
  fail "$VERDICT missing"
fi

# --- evidence -----------------------------------------------------------------------
if [ "$MODE" = complete ]; then
  EV="$WORK/evidence.json"
  if [ -f "$EV" ] && jq -e . "$EV" >/dev/null 2>&1; then
    t1=$(jq -r '.gates.tier1.status // empty' "$EV")
    t2=$(jq -r '.gates.tier2.status // empty' "$EV")
    [ "$t1" = "pass" ] && ok "evidence: tier1 pass" || fail "evidence: gates.tier1.status is '${t1}', not pass"
    [ "$t2" = "pass" ] && ok "evidence: tier2 pass" || fail "evidence: gates.tier2.status is '${t2}', not pass"
  else
    fail "$EV missing or invalid JSON"
  fi
fi

if [ "$FAILED" -eq 0 ]; then echo "chain-check: PASS $TICKET"; exit 0; fi
echo "chain-check: FAILED $TICKET"; exit 1
