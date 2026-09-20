#!/usr/bin/env bash
# release.sh <TICKET>
#
# Runs the admitted release-manager headlessly to assemble work/<TICKET>/evidence.json and commit
# `evidence:`, then stops. It prints the evidence summary and points at the pull request whose
# merge is the release, naming the human whose act that is. This script never merges or tags.
set -uo pipefail
TICKET=${1:-}; [ -n "$TICKET" ] || { echo "usage: bin/release.sh <TICKET>" >&2; exit 2; }
ROOT=$(git rev-parse --show-toplevel); cd "$ROOT"
[ -f .claude/agents/release-manager.md ] || { echo "release: release-manager is not an admitted agent" >&2; exit 2; }
bin/fleet-check.sh >/dev/null || { echo "release: fleet-check failed; fix the fleet before releasing" >&2; exit 1; }
echo "$TICKET" >work/.current-ticket
STAMP=$(date -u +%Y%m%dT%H%M%SZ); OUT="$ROOT/evals/.runs/release/$TICKET-$STAMP"; mkdir -p "$OUT"
. evals/release-manager/policy.sh
START=$(date +%s)
claude -p "Ticket $TICKET is active (work/.current-ticket). The chain is committed through the review verdict. Assemble the evidence pack for $TICKET following CLAUDE.md and your role, commit evidence:, then stop and name the human who makes the release commit." \
  --agent release-manager --output-format json --max-turns 80 --permission-mode acceptEdits \
  --allowedTools "$ALLOWED_TOOLS" --disallowedTools "$DISALLOWED_TOOLS" >"$OUT/claude.json" 2>"$OUT/claude.stderr"
WALL=$(( $(date +%s) - START ))
jq -r '.result // ""' "$OUT/claude.json" >"$OUT/claude-result.txt" 2>/dev/null
echo "release: release-manager finished in ${WALL}s"
EV="work/$TICKET/evidence.json"
if [ -f "$EV" ] && jq -e . "$EV" >/dev/null 2>&1; then
  jq '{ticket, gates:{tier1:.gates.tier1.status, tier2:.gates.tier2.status, mutation:.gates.tier2.mutationScorePercent}, chainCheck:.chainCheck.status, review:.review.disposition, readyForRelease, releaseCommitBy}' "$EV"
else
  echo "release: no valid evidence.json was written (see $OUT)"; exit 1
fi
bin/chain-check.sh "$TICKET" --complete | tail -1
echo
PR=$(bin/issue.sh pr "$TICKET" 2>/dev/null || true)
TITLE=$(jq -r '.title // ""' "work/$TICKET/ticket.json" 2>/dev/null)
echo "release: STOP. The release is $(jq -r .releaseCommitBy "$EV")'s to make, by hand, after reading $EV."
if [ -n "$PR" ]; then
  printf 'release: it is the merge of pull request #%s:\n    gh pr %s %s --merge --subject "release: %s %s"\n' "$PR" merge "$PR" "$TICKET" "$TITLE"
else
  echo "release: no pull request for $TICKET yet; push $(git branch --show-current) and open one."
fi
