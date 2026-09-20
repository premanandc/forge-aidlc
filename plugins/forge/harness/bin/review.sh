#!/usr/bin/env bash
# review.sh <TICKET>
#
# The independent reviewer: a fresh headless session with no CLAUDE.md, no hooks, no agents and
# no tools, whose entire world is the spec, the locked tests and the diff of the impl: commits.
# It returns one of auto-pass | needs-human | block with findings. A mechanical risk floor then
# raises the disposition to at least needs-human when the diff touches pom.xml, Liquibase
# changelogs, security configuration, prompts, the hooks, the fleet, the policy, the templates or
# the workflows. The verdict is written to
# work/<TICKET>/review-verdict.json under the reviewer marker and committed with the trailer
# chain-check requires. This script is the only writer of that file.
set -uo pipefail
TICKET=${1:-}; [ -n "$TICKET" ] || { echo "usage: bin/review.sh <TICKET>" >&2; exit 2; }
ROOT=$(git rev-parse --show-toplevel); cd "$ROOT"
W="work/$TICKET"; [ -f "$W/spec.md" ] || { echo "review: $W/spec.md missing" >&2; exit 2; }
STAMP=$(date -u +%Y%m%dT%H%M%SZ); OUT="$ROOT/evals/.runs/review/$TICKET-$STAMP"; mkdir -p "$OUT"

TESTS_COMMIT=$(git log --format=%H --grep="^tests: $TICKET" | tail -1)
IMPL_COMMITS=$(git log --reverse --format=%H --grep="^impl: $TICKET")
[ -n "$IMPL_COMMITS" ] || { echo "review: no impl: commits for $TICKET" >&2; exit 2; }
FIRST_IMPL=$(echo "$IMPL_COMMITS" | head -1); LAST_IMPL=$(echo "$IMPL_COMMITS" | tail -1)
# The range FIRST_IMPL^..LAST_IMPL is the ticket's span, not the ticket's work. Anything merged
# into the branch from main while the ticket was open sits inside it, and the reviewer, seeing
# only the spec, the tests and this diff, reasonably reads it as the implementer's doing. On
# PF-103 that put 82 lines of bin/ticket.sh in front of the reviewer, which blocked the ticket for
# harness commits nobody on the ticket had made. So the diff is restricted to the paths the impl
# commits themselves touched: a merge from main brings files the implementer never wrote, and
# those drop out. The net state of those paths is what gets reviewed, not each round separately.
IMPL_PATHS=$(for c in $IMPL_COMMITS; do git diff-tree --no-commit-id --name-only -r "$c"; done | sort -u | grep -v '^work/' || true)
[ -n "$IMPL_PATHS" ] || { echo "review: the impl: commits for $TICKET touch no files outside work/" >&2; exit 2; }
# shellcheck disable=SC2086
DIFF=$(git diff "$FIRST_IMPL^" "$LAST_IMPL" -- $IMPL_PATHS)
# shellcheck disable=SC2086
TOUCHED=$(git diff --name-only "$FIRST_IMPL^" "$LAST_IMPL" -- $IMPL_PATHS)
TEST_FILES=$([ -n "$TESTS_COMMIT" ] && git diff-tree --no-commit-id --name-only -r "$TESTS_COMMIT" | grep '^src/test/' || true)
TESTS_TEXT=$(for f in $TEST_FILES; do echo "=== $f"; git show "$LAST_IMPL:$f" 2>/dev/null || git show "$TESTS_COMMIT:$f"; done)

# Mechanical risk floor.
FLOOR_PATHS=$(echo "$TOUCHED" | grep -E '^(pom\.xml|src/main/resources/db/changelog/|.*[Ss]ecurity.*|src/main/java/com/forge/demo/decision/advisor/embabel/DeterminationPrompt\.java|src/test/resources/prompts/|\.claude/|\.forge/|\.github/|bin/|hooks/|evals/|templates/)' || true)

PROMPT="You are the independent reviewer in a software factory. You are given a ticket's spec, the tests written before the implementation, and the implementation diff. You have no other context and no tools; judge only what is in front of you.

Decide one disposition:
- auto-pass: the diff satisfies the spec's acceptance criteria and Contract, the tests cover them, and nothing in the diff is risky or outside the Contract.
- needs-human: acceptable but something a human should look at (scope creep, an unstated assumption, a weak test, a design smell).
- block: the diff does not satisfy the spec, contradicts the Contract, weakens a test, adds an unapproved dependency, or changes behaviour the spec did not ask for.

List findings with severity (info|low|medium|high), the file path, and one sentence each. Be specific and terse. Respond with JSON only, no prose before or after, in this exact shape:
{\"disposition\":\"auto-pass|needs-human|block\",\"summary\":\"one sentence\",\"findings\":[{\"severity\":\"info|low|medium|high\",\"path\":\"file\",\"note\":\"one sentence\"}]}

## Spec
$(cat "$W/spec.md")

## Tests (written before the implementation, locked)
$TESTS_TEXT

## Implementation diff ($(echo "$IMPL_COMMITS" | wc -l | tr -d ' ') impl commit(s))
$DIFF"

echo "review: $TICKET, $(echo "$TOUCHED" | wc -l | tr -d ' ') files in the diff, reviewer sees spec + tests + diff only"
# Fresh context: run from an empty scratch directory so no CLAUDE.md, hooks or agents load, and
# with every tool denied so the prompt is the reviewer's whole world.
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/review-$TICKET.XXXXXX")
START=$(date +%s)
( cd "$SCRATCH" && claude -p "$PROMPT" --output-format json --max-turns 3 --permission-mode dontAsk \
  --disallowedTools "Read,Edit,Write,Bash,Grep,Glob,WebFetch,WebSearch,Agent,NotebookEdit" \
  >"$OUT/claude.json" 2>"$OUT/claude.stderr" )
rm -rf "$SCRATCH"
WALL=$(( $(date +%s) - START ))
MODEL=$(jq -r '(.modelUsage // {}) | keys | join("+")' "$OUT/claude.json" 2>/dev/null)
SESSION=$(jq -r '.session_id // "unknown"' "$OUT/claude.json" 2>/dev/null)
RAW=$(jq -r '.result // ""' "$OUT/claude.json" 2>/dev/null)
echo "$RAW" >"$OUT/raw-result.txt"
# The model was told JSON only; tolerate a fenced block.
VERDICT_JSON=$(printf '%s' "$RAW" | sed -n '/{/,$p' | sed 's/^```json//; s/^```//' | jq -c . 2>/dev/null)
if [ -z "$VERDICT_JSON" ]; then
  echo "review: reviewer did not return parseable JSON (see $OUT/raw-result.txt); recording needs-human" >&2
  VERDICT_JSON='{"disposition":"needs-human","summary":"reviewer output was not parseable","findings":[]}'
fi
DISP=$(echo "$VERDICT_JSON" | jq -r '.disposition')
case "$DISP" in auto-pass|needs-human|block) ;; *) DISP=needs-human;; esac

FLOOR_TRIGGERED=false
if [ -n "$FLOOR_PATHS" ] && [ "$DISP" = "auto-pass" ]; then DISP=needs-human; FLOOR_TRIGGERED=true; fi
[ -n "$FLOOR_PATHS" ] && FLOOR_TRIGGERED=true

jq -n --arg ticket "$TICKET" --arg disp "$DISP" --argjson v "$VERDICT_JSON" \
   --argjson floor "$FLOOR_TRIGGERED" --arg paths "$FLOOR_PATHS" \
   --arg tool "bin/review.sh" --arg session "$SESSION" --arg model "${MODEL:-unknown}" \
   --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg first "$FIRST_IMPL" --arg last "$LAST_IMPL" --argjson wall "$WALL" \
   '{ticket:$ticket, disposition:$disp, summary:($v.summary // ""), findings:($v.findings // []),
     riskFloor:{triggered:$floor, paths:($paths | split("\n") | map(select(length>0)))},
     reviewed:{implCommits:{first:$first,last:$last}},
     reviewer:{tool:$tool, session:$session, model:$model, wallSeconds:$wall}, reviewedAt:$at}' >"$W/review-verdict.json"

echo "review: disposition $DISP${FLOOR_TRIGGERED:+ (risk floor: $(echo "$FLOOR_PATHS" | paste -sd, -))}; $(echo "$VERDICT_JSON" | jq -r '.findings | length') finding(s); ${WALL}s; model $MODEL"
git add "$W/review-verdict.json"
FORGE_REVIEWER=1 git commit -q -m "review: $TICKET verdict $DISP" --trailer "Reviewed-By: bin/review.sh" \
  && echo "review: verdict committed $(git rev-parse --short HEAD)"
[ "$DISP" = "block" ] && exit 1 || exit 0
