#!/usr/bin/env bash
# Claude Code PreToolUse hook for Bash. Reads the hook JSON on stdin, extracts the command text,
# and asks bin/guard.sh --command. Exit 1 from the guard becomes a deny with the reasons.
# Contract per https://code.claude.com/docs/en/hooks.md (checked 2026-09-19): tool_input.command;
# the same hooks fire for subagents' tool calls.
set -uo pipefail
INPUT=$(cat)
ROOT=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0
cd "$ROOT" || exit 0
REASON=$(bin/guard.sh --command "$CMD"); RC=$?
case $RC in
  1) jq -n --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}';;
  *) exit 0;;
esac
