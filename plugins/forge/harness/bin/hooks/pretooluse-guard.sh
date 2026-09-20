#!/usr/bin/env bash
# Claude Code PreToolUse hook for Edit|Write. Reads the hook JSON on stdin, extracts the
# target path, and asks bin/guard.sh. Maps guard exit codes to hook decisions:
#   1 -> deny (test lock, verdict ownership)   3 -> ask (pom.xml dependency edit)   0 -> no opinion
# Contract per https://code.claude.com/docs/en/hooks.md (checked 2026-09-18).
set -uo pipefail
INPUT=$(cat)
ROOT=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE" ] && exit 0

cd "$ROOT" || exit 0
REASON=$(bin/guard.sh --path "$FILE"); RC=$?
case $RC in
  1) jq -n --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}';;
  3) jq -n --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}';;
  *) exit 0;;
esac
