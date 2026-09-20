#!/usr/bin/env bash
# Claude Code Stop hook. If a ticket is active (work/.current-ticket), runs bin/chain-check.sh
# for it. A failing chain blocks the stop once with the findings as the reason, so the agent
# has to address them; stop_hook_active=true means the hook already fired and we allow the
# stop to avoid a loop. Contract per https://code.claude.com/docs/en/hooks.md (2026-09-18).
set -uo pipefail
INPUT=$(cat)
ROOT=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
cd "$ROOT" || exit 0

# A role marker says "a fleet session is running right now". Each agent creates one at session
# start and, until this hook did it, nothing ever removed one: the file outlived the session that
# made it. That is not only untidy. A left-behind .role-implementer blocks every later write under
# src/test for that ticket, including the human-approved tests-amend the guard deliberately leaves
# open, because that rule has no approval escape. So the marker's life ends where the session does.
#
# Only on the paths that let the stop proceed. A block means the session keeps working, and a
# session carrying on without its own role marker would have run with its guard switched off.
# Scoped to the active ticket: markers belong to the ticket whose chain this session is in.
clear_role_markers() {
  [ -f work/.current-ticket ] || return 0
  local t; t=$(tr -d '[:space:]' < work/.current-ticket)
  [ -n "$t" ] && [ -d "work/$t" ] || return 0
  find "work/$t" -maxdepth 1 -name '.role-*' -delete 2>/dev/null
  return 0
}

if [ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')" = "true" ]; then
  clear_role_markers; exit 0
fi

# The fleet must match its admissions before any session ends, ticket or not.
if [ -x bin/fleet-check.sh ] && ! FLEET_OUT=$(bin/fleet-check.sh 2>&1); then
  # pipeline-ok: the pipeline is fed by echo of a shell variable, which is bounded and finishes
  # writing before head can exit. The jq on this line is a separate command, not its reader.
  jq -n --arg r "fleet-check failed:"$'\n'"$(echo "$FLEET_OUT" | grep FAIL | head -5)" \
    '{hookSpecificOutput:{hookEventName:"Stop",decision:"block",reason:$r}}'
  exit 0
fi

[ -f work/.current-ticket ] || exit 0
TICKET=$(tr -d '[:space:]' < work/.current-ticket)
[ -z "$TICKET" ] && exit 0

OUT=$(bin/chain-check.sh "$TICKET" 2>&1); RC=$?
if [ $RC -eq 0 ]; then
  clear_role_markers
  echo "$OUT" | tail -1
  exit 0
fi
FAILS=$(echo "$OUT" | grep 'FAIL' | head -8)
jq -n --arg r "chain-check failed for $TICKET:"$'\n'"$FAILS" \
  '{hookSpecificOutput:{hookEventName:"Stop",decision:"block",reason:$r}}'
