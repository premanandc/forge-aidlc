#!/usr/bin/env bash
# ticket.sh <TICKET> [from-stage]
#
# The autonomous half of the chain. Everything before it is a human's: a person opened the issue,
# accepted the intent, accepted the spec and accepted the failing tests, each with bin/accept.sh,
# each recorded as an Accepted-By trailer that bin/chain-check.sh verifies. This script refuses to
# start until those gates are in the history.
#
# From there the fleet works on the ticket branch, one headless session per role:
#   4 implementer (plan draft) -> 5 architect (boundary review, by policy) -> 6 implementer (impl:)
#   -> 7 bin/review.sh (verdict) -> 8 bin/release.sh (evidence:)
# then it pushes, fills in the pull request and marks it ready for the human. It never merges: the
# merge is the release, and that is the human's act.
#
# Stage 5 runs only when bin/policy.sh says the ticket needs an architect's boundary review (risk
# high, or a Contract that names an event or crosses a module). When it does not, ticket.sh
# commits the plan itself with an Architecture-Review: skipped (policy) trailer, which chain-check
# accepts only while the policy agrees.
#
# from-stage (4-8) resumes a chain whose earlier stages are already committed (a dead session, a
# machine that slept). Wall time, session count, diff size, review and mutation results are
# appended to metrics/runs.jsonl as the harnessed run to read beside the baseline.
#
# FORGE_TICKET_DRY_RUN=1 runs the preconditions, prints what the chain would do, and stops before
# the first session. Use it to test the gates: a script that exercises the refusals must not be
# able to spend a plan's worth of model time when one of its own cases is wrong, which is how
# bin/ticket-preconditions found itself running a real chain on a probe ticket.
# Compatible with bash 3.2.
set -uo pipefail
TICKET=${1:-}; FROM=${2:-4}
[ -n "$TICKET" ] || { echo "usage: bin/ticket.sh <TICKET> [from-stage 4-8]" >&2; exit 2; }
ROOT=$(git rev-parse --show-toplevel); cd "$ROOT"
BRANCH="ticket/$TICKET"
die() { echo "ticket: $*" >&2; exit 2; }

# --- the human gates must already be in the history ---------------------------------
for a in architect implementer release-manager; do
  [ -f ".claude/agents/$a.md" ] || die "$a is not admitted; run bin/admit.sh $a"
done
bin/fleet-check.sh >/dev/null || die "fleet-check failed; the fleet does not match its admissions"
[ "$(git branch --show-current)" = "$BRANCH" ] || die "the chain for $TICKET lives on $BRANCH; git switch $BRANCH"
[ -z "$(git status --porcelain)" ] || die "working tree not clean"
ls work/*/.drafting-* >/dev/null 2>&1 && die "an artifact is still being drafted ($(ls work/*/.drafting-* | paste -sd, -)); a human accepts it with bin/accept.sh first"
TESTS_COMMIT=$(git log --format=%H --grep="^tests: $TICKET" | tail -1)
[ -n "$TESTS_COMMIT" ] || die "no tests: commit for $TICKET; the chain starts with /forge:intent, /forge:spec, /forge:tests and a human's bin/accept.sh"
NEED_TESTS_ACCEPT=$(bin/policy.sh "$TICKET" acceptance.tests)
ACCEPTED=$(git log -1 --format='%(trailers:key=Accepted-By,valueonly)' "$TESTS_COMMIT")
if [ -z "$ACCEPTED" ] && [ "$NEED_TESTS_ACCEPT" = required ]; then
  die "the tests: commit carries no Accepted-By trailer and policy acceptance.tests=required; a human accepts with bin/accept.sh $TICKET tests"
fi
bin/chain-check.sh "$TICKET" >/dev/null 2>&1 || { bin/chain-check.sh "$TICKET" | grep FAIL; die "chain-check fails before the fleet starts"; }
REVIEW_NEEDED=$(bin/policy.sh "$TICKET" architectureReview)
RISK=$(bin/policy.sh "$TICKET" risk)

if [ "${FORGE_TICKET_DRY_RUN:-0}" = 1 ]; then
  echo "ticket: preconditions pass for $TICKET on $BRANCH"
  echo "ticket: risk $RISK; tests accepted by ${ACCEPTED:-nobody (policy $NEED_TESTS_ACCEPT)}; architecture review $REVIEW_NEEDED"
  echo "ticket: would run stages ${FROM}-8: plan, $([ "$REVIEW_NEEDED" = required ] && echo "architect boundary review" || echo "plan committed with Architecture-Review: skipped (policy)"), impl, review, evidence, push, PR ready"
  echo "ticket: dry run, no sessions started"
  exit 0
fi

STAMP=$(date -u +%Y%m%dT%H%M%SZ); RUN="$ROOT/evals/.runs/ticket/$TICKET-$STAMP"; mkdir -p "$RUN"
mkdir -p "work/$TICKET"; echo "$TICKET" >|work/.current-ticket
T0=$(date +%s); SESSIONS=0; MODELS=""
log() { echo "ticket: $(date -u +%H:%M:%SZ) $*" | tee -a "$RUN/timeline.log"; }
log "$TICKET on $BRANCH: risk $RISK, tests accepted by ${ACCEPTED:-nobody (policy $NEED_TESTS_ACCEPT)}, architecture review $REVIEW_NEEDED"

role() {  # role <agent> <label> <prompt>   (label starts with the stage number)
  local agent=$1 label=$2 prompt=$3 out="$RUN/$2" s e m
  if [ "${label%%-*}" -lt "$FROM" ]; then log "$label skipped (resuming from stage $FROM)"; return 0; fi
  mkdir -p "$out"; ALLOWED_TOOLS=""; DISALLOWED_TOOLS=""; . "evals/$agent/policy.sh"
  log "$label ($agent) start"; s=$(date +%s)
  claude -p "$prompt" --agent "$agent" --output-format json --max-turns 100 --permission-mode acceptEdits \
    ${ALLOWED_TOOLS:+--allowedTools "$ALLOWED_TOOLS"} ${DISALLOWED_TOOLS:+--disallowedTools "$DISALLOWED_TOOLS"} \
    >"$out/claude.json" 2>"$out/claude.stderr"
  e=$(( $(date +%s) - s )); SESSIONS=$((SESSIONS+1))
  jq -r '.result // ""' "$out/claude.json" >"$out/claude-result.txt" 2>/dev/null
  m=$(jq -r '(.modelUsage // {}) | keys | join("+")' "$out/claude.json" 2>/dev/null); MODELS="$MODELS,$m"
  log "$label done in ${e}s; HEAD $(git rev-parse --short HEAD); chain: $(bin/chain-check.sh "$TICKET" 2>&1 | tail -1)"
}

role implementer 4-plan "Ticket $TICKET is active (work/.current-ticket). A human has accepted its intent, its spec and its failing tests; the tests are locked.

Draft work/$TICKET/plan.md following CLAUDE.md and your role: sections # $TICKET, ## Steps, ## Files, ## Risks. This invocation is the plan only: do NOT commit plan.md and do NOT change any production code yet. Stop after plan.md is written and report it."

if [ "$REVIEW_NEEDED" = required ]; then
  role architect 5-architect-plan "Ticket $TICKET is active (work/.current-ticket). intent:, spec: and tests: are committed and accepted by a human, the tests are locked, and the implementer has drafted work/$TICKET/plan.md (uncommitted).

Review the plan for boundary fit, append the Boundary review, and commit plan: $TICKET <title> with the trailer Reviewed-By: architect, following CLAUDE.md and your role."
elif [ "$FROM" -le 5 ]; then
  # No architect this time: the policy resolved the review optional for this ticket, and the plan
  # commit says so in a trailer that chain-check re-checks against the policy.
  log "5-architect-plan skipped: policy architectureReview=$REVIEW_NEEDED at risk $RISK"
  if [ -f "work/$TICKET/plan.md" ]; then
    printf '\n## Boundary review\nSkipped by policy: architectureReview resolved optional (risk %s, Contract inside one module and adding no event). The implementer works inside the Contract the architect wrote in the spec.\n' "$RISK" >>"work/$TICKET/plan.md"
    TITLE=$(git log --format=%s --grep="^tests: $TICKET" -1 | sed -E "s/^tests:[[:space:]]*$TICKET[[:space:]]*//")
    git add "work/$TICKET/plan.md"
    git -c user.name="forge fleet" -c user.email=fleet@forge.demo commit -q -m "plan: $TICKET $TITLE" \
      --trailer "Architecture-Review: skipped (policy)" && log "5 plan committed without a boundary review $(git rev-parse --short HEAD)"
  else log "5 no plan.md to commit; stage 4 must have failed"; fi
fi

role implementer 6-impl "Ticket $TICKET is active (work/.current-ticket). plan: is committed; the tests are locked and were accepted by a human.

Implement $TICKET per work/$TICKET/plan.md following CLAUDE.md and your role: make the locked tests pass with the smallest change that keeps mvn (clean verify) green, then commit impl: $TICKET <title>. Do not commit plan.md again."

if [ "$FROM" -le 7 ]; then
  log "7-review start"; s=$(date +%s)
  bin/review.sh "$TICKET" | tee -a "$RUN/timeline.log"
  SESSIONS=$((SESSIONS+1)); log "7-review done in $(( $(date +%s) - s ))s"
else log "7-review skipped (resuming from stage $FROM)"; fi
DISP=$(jq -r .disposition "work/$TICKET/review-verdict.json" 2>/dev/null)
FINDINGS=$(jq -r '.findings | length' "work/$TICKET/review-verdict.json" 2>/dev/null)
if [ "$DISP" != "auto-pass" ]; then
  log "review disposition is $DISP: a human must resolve it in work/$TICKET/review-verdict.json (add humanResolution {by, decision, note}) and commit with FORGE_REVIEWER=1 before bin/release.sh $TICKET"
fi

if [ "$DISP" = "auto-pass" ]; then
  log "8-release start"; s=$(date +%s)
  bin/release.sh "$TICKET" | tee -a "$RUN/timeline.log"
  SESSIONS=$((SESSIONS+1)); log "8-release done in $(( $(date +%s) - s ))s"
fi

# --- hand the pull request to the human ---------------------------------------------
EV="work/$TICKET/evidence.json"
PR=""
if git remote get-url origin >/dev/null 2>&1; then
  if git push -q -u origin "$BRANCH"; then log "pushed $BRANCH"; else log "push failed; push $BRANCH by hand"; fi
  PR=$(bin/issue.sh pr "$TICKET" 2>/dev/null || true)
  if [ -n "$PR" ] && [ -f "$EV" ]; then
    BODY="$(jq -r '"**Gates**  tier 1 \(.gates.tier1.status), tier 2 \(.gates.tier2.status), mutation \(.gates.tier2.mutationScorePercent)%, coverage \(.coverage.linePercent)%, vulnerable dependencies \(.gates.tier2.vulnerableDependencies)."' "$EV" 2>/dev/null)

**Review**  ${DISP:-none}, ${FINDINGS:-0} finding(s)$(jq -r 'if (.findings | length) > 0 then "\n" + ([.findings[] | "- \(.severity): `\(.path)` \(.note)"] | join("\n")) else "" end' "work/$TICKET/review-verdict.json" 2>/dev/null)

**Human gates**  intent, spec and tests accepted by ${ACCEPTED:-nobody: policy acceptance.tests=$NEED_TESTS_ACCEPT}. Boundary review: $REVIEW_NEEDED (risk $RISK).

**Chain**  $(bin/chain-check.sh "$TICKET" --complete 2>&1 | tail -1)

Merging this pull request is the release:
\`\`\`
gh pr merge $PR --merge --subject \"release: $TICKET $(jq -r '.title // ""' "work/$TICKET/ticket.json" 2>/dev/null)\"
\`\`\`

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
    gh pr edit "$PR" --body "$BODY" >/dev/null 2>&1 && log "PR #$PR body updated with the evidence"
    if [ "$DISP" = "auto-pass" ] && [ "$(jq -r '.readyForRelease // false' "$EV")" = true ]; then
      gh pr ready "$PR" >/dev/null 2>&1 && log "PR #$PR marked ready for review"
      bin/issue.sh stage "$TICKET" review >/dev/null 2>&1 || true
      bin/issue.sh comment "$TICKET" "**Ready for release.** The fleet finished on \`$BRANCH\`: review **${DISP:-none}**, gates recorded in \`work/$TICKET/evidence.json\`. Merging [#$PR]($(gh repo view --json url -q .url)/pull/$PR) releases it." >/dev/null 2>&1 || true
      bin/issue.sh render "$TICKET" >/dev/null 2>&1 || log "could not update the chain comment"
    else
      log "PR #$PR left as a draft: disposition $DISP, readyForRelease $(jq -r '.readyForRelease // false' "$EV" 2>/dev/null)"
    fi
  fi
fi

WALL=$(( $(date +%s) - T0 ))
# sed -n 1p rather than head -1: head exits on its first line and git dies writing into a closed
# pipe. IMPL_LAST wants the most recent, which git can answer on its own without a pipe at all.
IMPL_FIRST=$(git log --reverse --topo-order --format=%H --grep="^impl: $TICKET" | sed -n 1p)
IMPL_LAST=$(git log -1 --format=%H --grep="^impl: $TICKET")
STAT=$([ -n "$IMPL_FIRST" ] && git diff --shortstat "$IMPL_FIRST^" "$IMPL_LAST" -- src || echo "")
FILES=$(echo "$STAT" | grep -oE '[0-9]+ files? changed' | grep -oE '^[0-9]+' || echo 0)
INS=$(echo "$STAT" | grep -oE '[0-9]+ insertions?' | grep -oE '^[0-9]+' || echo 0)
DEL=$(echo "$STAT" | grep -oE '[0-9]+ deletions?' | grep -oE '^[0-9]+' || echo 0)
T1=$(jq -r '.gates.tier1.status // "-"' "$EV" 2>/dev/null); T2=$(jq -r '.gates.tier2.status // "-"' "$EV" 2>/dev/null)
MUT=$(jq -r '.gates.tier2.mutationScorePercent // "-"' "$EV" 2>/dev/null)
FIRST_PASS=$(grep -c "impl: gate FAIL" "$RUN/timeline.log" 2>/dev/null | awk '{print ($1==0)?"true":"false"}')
MODEL_LIST=$(printf '%s' "$MODELS" | tr ',' '\n' | grep -v '^$' | sort -u | paste -sd, -)
HUMAN_GATES=$(git log --format='%H' --grep="^\(intent\|spec\|tests\): $TICKET" | while read -r h; do git log -1 --format='%(trailers:key=Accepted-By,valueonly)' "$h"; done | grep -c . || echo 0)
bin/metrics.sh append "$(jq -n --arg ticket "$TICKET" --arg started "$STAMP" --argjson wall "$WALL" --argjson sessions "$SESSIONS" \
  --arg model "${MODEL_LIST:-unknown}" --arg t1 "${T1:--}" --arg t2 "${T2:--}" --argjson fp "${FIRST_PASS:-true}" \
  --argjson files "${FILES:-0}" --argjson ins "${INS:-0}" --argjson del "${DEL:-0}" --arg disp "${DISP:-none}" --argjson findings "${FINDINGS:-0}" \
  --arg mut "${MUT:--}" --arg branch "$BRANCH" --arg pr "${PR:-}" --argjson gates "${HUMAN_GATES:-0}" --arg review "$REVIEW_NEEDED" --arg risk "$RISK" \
  --arg notes "autonomous half only: $SESSIONS sessions from the accepted tests to the evidence pack$([ "$FROM" -gt 4 ] && echo " (resumed from stage $FROM; wall time covers the resumed stages only)"); $HUMAN_GATES human acceptance gates preceded it; boundary review $REVIEW_NEEDED at risk $RISK; timeline in evals/.runs/ticket/$TICKET-$STAMP" \
  '{ticket:$ticket, mode:"harnessed", startedAt:$started, wallSeconds:$wall, sessions:$sessions, model:$model,
    gate:{tier1:$t1, tier1FirstPass:$fp, tier2:$t2}, diff:{files:$files, insertions:$ins, deletions:$del},
    review:{disposition:$disp, findings:$findings}, mutationScorePercent:($mut|tonumber? // $mut),
    branch:$branch, pr:$pr, humanGates:$gates, architectureReview:$review, risk:$risk, notes:$notes}')"
# --complete only when the chain actually reached the end. It requires the evidence pack, so
# running it after a stop for a human prints FAILED over a run that did exactly what it should,
# and a red line nobody should act on is how people learn to ignore red lines.
if [ -f "$EV" ]; then
  log "chain finished in ${WALL}s over $SESSIONS sessions; $(bin/chain-check.sh "$TICKET" --complete 2>&1 | tail -1)"
else
  log "chain stopped for a human in ${WALL}s over $SESSIONS sessions; $(bin/chain-check.sh "$TICKET" 2>&1 | tail -1) (no evidence pack yet, which is correct)"
fi
echo
echo "ticket: STOP. ${PR:+Pull request #$PR is }the human's to read and merge; the merge is the release."
