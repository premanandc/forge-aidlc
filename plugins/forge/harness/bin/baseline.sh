#!/usr/bin/env bash
# baseline.sh <TICKET> "<one-line story>"
#
# The un-harnessed number (S5.3): one headless session, no chain, no roles, no hooks, no
# CLAUDE.md (`--bare`), told to implement the story and make the tests pass. Runs in a throwaway
# worktree so nothing lands on main. Afterwards the gate is run once, exactly as it would be on
# a pull request, and the result is recorded with wall time and diff size in metrics/runs.jsonl.
# The worktree is kept under evals/.runs/baseline/<stamp>/worktree for inspection and removed by
# the next run. Compatible with bash 3.2.
set -uo pipefail
TICKET=${1:-}; STORY=${2:-}
[ -n "$TICKET" ] && [ -n "$STORY" ] || { echo "usage: bin/baseline.sh <TICKET> \"<story>\"" >&2; exit 2; }
ROOT=$(git rev-parse --show-toplevel); cd "$ROOT"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$ROOT/evals/.runs/baseline/$STAMP"; mkdir -p "$OUT"
WT=$(mktemp -d "${TMPDIR:-/tmp}/baseline-$TICKET.XXXXXX"); rmdir "$WT"
git worktree add --detach -q "$WT" HEAD
BASE=$(git -C "$WT" rev-parse HEAD)

PROMPT="Implement $TICKET in this Spring Boot / Spring Modulith codebase: $STORY

Write whatever production code and tests you judge necessary, run the tests you touched, and commit your work with a clear message. Work directly; there is no process to follow."

# Un-harness the worktree: no hooks, no guards, no constitution, no agents. (`--bare` would do
# this too but also skips the user's login, so the session is refused.) The git pre-commit hook
# is shared with the main checkout, so it is disabled for this session only through git's
# environment override, never through the shared repository config.
( cd "$WT" && rm -rf .claude CLAUDE.md FLEET.md .forge templates )
echo "baseline: $TICKET in $WT (no hooks, no guards, no CLAUDE.md, no policy, no templates)"
START=$(date +%s)
( cd "$WT" && GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null \
    claude -p "$PROMPT" --output-format json --max-turns 80 --permission-mode acceptEdits \
    --allowedTools "Read,Grep,Glob,Edit,Write,Bash(mvn *),Bash(git *),Bash(ls *),Bash(cat *),Bash(find *),Bash(grep *),Bash(mkdir *)" \
    >"$OUT/claude.json" 2>"$OUT/claude.stderr" )
WALL=$(( $(date +%s) - START ))
MODEL=$(jq -r '(.modelUsage // {}) | keys | join("+")' "$OUT/claude.json" 2>/dev/null)
TURNS=$(jq -r '.num_turns // 0' "$OUT/claude.json" 2>/dev/null)
jq -r '.result // ""' "$OUT/claude.json" >"$OUT/claude-result.txt" 2>/dev/null
echo "baseline: session finished in ${WALL}s, $TURNS turns, model $MODEL"

# Diff size: everything the session changed, committed or not, over source paths only (the
# harness files this script removed are not the agent's work).
( cd "$WT" && git add -A >/dev/null 2>&1; git diff --cached --shortstat "$BASE" -- src pom.xml ) >"$OUT/diffstat.txt" 2>/dev/null
FILES=$(grep -oE '[0-9]+ files? changed' "$OUT/diffstat.txt" | grep -oE '^[0-9]+' || echo 0)
INS=$(grep -oE '[0-9]+ insertions?' "$OUT/diffstat.txt" | grep -oE '^[0-9]+' || echo 0)
DEL=$(grep -oE '[0-9]+ deletions?' "$OUT/diffstat.txt" | grep -oE '^[0-9]+' || echo 0)
( cd "$WT" && git diff --cached "$BASE" ) >"$OUT/diff.patch" 2>/dev/null
( cd "$WT" && git log --oneline "$BASE"..HEAD ) >"$OUT/commits.txt" 2>/dev/null

# Now the gate, once, as a pull request would see it.
echo "baseline: running the tier 1 gate on the result"
if ( cd "$WT" && mvn -B clean verify ) >"$OUT/gate.log" 2>&1; then T1=pass; else T1=fail; fi
GATE_FAILS=$(grep -E "ERROR\] Failed to execute goal" "$OUT/gate.log" | sed -E 's/.*goal ([^ ]+) .*/\1/' | head -3 | paste -sd, -)
echo "baseline: tier 1 $T1 ${GATE_FAILS:+($GATE_FAILS)}"

bin/metrics.sh append "$(jq -n \
  --arg ticket "$TICKET" --arg started "$STAMP" --argjson wall "$WALL" --arg model "${MODEL:-unknown}" \
  --arg t1 "$T1" --argjson files "${FILES:-0}" --argjson ins "${INS:-0}" --argjson del "${DEL:-0}" \
  --arg notes "bare session, $TURNS turns, no chain; gate run once afterwards${GATE_FAILS:+; failed: $GATE_FAILS}" \
  '{ticket:$ticket, mode:"baseline", startedAt:$started, wallSeconds:$wall, sessions:1, model:$model,
    gate:{tier1:$t1, tier1FirstPass:($t1=="pass"), tier2:"skipped"},
    diff:{files:$files, insertions:$ins, deletions:$del},
    review:{disposition:"none", findings:0}, notes:$notes}')"

# Keep the worktree for inspection; remove any older baseline worktree registration.
mv "$WT" "$OUT/worktree" 2>/dev/null && git worktree repair >/dev/null 2>&1 || true
git worktree prune
echo "baseline: artifacts in $OUT"
