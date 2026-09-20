#!/usr/bin/env bash
# Claude Code Stop hook. If a ticket is active (work/.current-ticket), runs bin/chain-check.sh
# for it. A failing chain blocks the stop once with the findings as the reason, so the agent
# has to address them; stop_hook_active=true means the hook already fired and we allow the
# stop to avoid a loop. Contract per https://code.claude.com/docs/en/hooks.md (2026-09-18).
set -uo pipefail
INPUT=$(cat)
ROOT=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
cd "$ROOT" || exit 0

if [ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')" = "true" ]; then exit 0; fi

# The fleet must match its admissions before any session ends, ticket or not.
if [ -x bin/fleet-check.sh ] && ! FLEET_OUT=$(bin/fleet-check.sh 2>&1); then
  jq -n --arg r "fleet-check failed:"$'\n'"$(echo "$FLEET_OUT" | grep FAIL | head -5)" \
    '{hookSpecificOutput:{hookEventName:"Stop",decision:"block",reason:$r}}'
  exit 0
fi

[ -f work/.current-ticket ] || exit 0
TICKET=$(tr -d '[:space:]' < work/.current-ticket)
[ -z "$TICKET" ] && exit 0

OUT=$(bin/chain-check.sh "$TICKET" 2>&1); RC=$?
if [ $RC -eq 0 ]; then
  echo "$OUT" | tail -1
  exit 0
fi
FAILS=$(echo "$OUT" | grep 'FAIL' | head -8)
jq -n --arg r "chain-check failed for $TICKET:"$'\n'"$FAILS" \
  '{hookSpecificOutput:{hookEventName:"Stop",decision:"block",reason:$r}}'
