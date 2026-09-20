#!/usr/bin/env bash
# fleet-render.sh: print FLEET.md from its two sources of truth, the fleet catalog
# (.forge/fleet-catalog.json: family, purpose, owner, ladder) and the admissions log
# (evals/admissions.log: when each agent was admitted, on what score, against which tasks).
#
# FLEET.md is therefore derived, never hand-written: bin/admit.sh rewrites it after an admission
# or a retirement, and bin/fleet-check.sh fails when the committed file differs from this output.
# That removes the one place where the registry could quietly disagree with the record.
# Compatible with bash 3.2; needs jq.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd); cd "$ROOT"
CAT=.forge/fleet-catalog.json
LOG=evals/admissions.log
[ -f "$CAT" ] || { echo "fleet-render: $CAT missing" >&2; exit 1; }

cat <<'HEADER'
# Fleet registry

Derived from `.forge/fleet-catalog.json` and `evals/admissions.log` by `bin/fleet-render.sh`.
Never edit it by hand: `bin/admit.sh` rewrites it after an admission or a retirement, and
`bin/fleet-check.sh` fails when it differs from what the sources render.

Every agent belongs to one family with a narrow purpose, a human owner accountable for its
output, and a rung on the autonomy ladder:

| rung | meaning |
|---|---|
HEADER
jq -r '.ladder | to_entries[] | "| \(.key) | \(.value) |"' "$CAT"
cat <<'MID'

Families and where their human decides:

| family | owner | checkpoint |
|---|---|---|
MID
jq -r '.families | to_entries[] | "| \(.key) | \(.value.owner) | \(.value.checkpoint) |"' "$CAT"
cat <<'AGENTS'

Admitted agents, in the order a ticket meets them. A row appears only after `bin/admit.sh` passed
the agent's golden tasks:

| step | agent | family | ladder | since | provenance | score | purpose |
|---|---|---|---|---|---|---|---|
AGENTS
# Chain order, not alphabetical: the registry should show how the work moves, not who exists.
# The order lives here rather than in the catalog because it is a rendering choice, not a fact
# about accountability. The catalog records who owns an agent and what it is for, and it is
# human-written; the guards refuse it to an agent session, which is how this ended up here.
# An agent not named below sorts last rather than disappearing.
chain_order() {  # template: the stages of this project's chain, in order
  case "$1" in
    intent-drafter) echo 1;; spec-drafter) echo 2;; architect) echo 3;;
    test-designer) echo 4;; implementer) echo 5;; release-manager) echo 6;;
    *) echo 99;;
  esac
}
for a in $(for f in .claude/agents/*.md; do
             [ -e "$f" ] || continue
             n=$(basename "$f" .md)
             printf '%s %s\n' "$(chain_order "$n")" "$n"
           done | sort -n | awk '{print $2}'); do
  f=".claude/agents/$a.md"
  # An agent that came with the suite has an "installed" line naming the suite and version; one
  # that earned its place here has an "admitted" line naming a local run. The table shows which,
  # because a vendor's score and a local score are not the same claim.
  line=$(grep -E "^[0-9TZ]+  $a  [0-9]+/[0-9]+  (admitted|installed)  candidate=" "$LOG" 2>/dev/null | tail -1)
  [ -n "$line" ] || { echo "| $a | (not in $LOG) | | | | |"; continue; }
  origin=$(printf '%s' "$line" | awk '{print $4}')
  suite=$(printf '%s' "$line" | sed -nE 's/.*[[:space:]]suite=([^[:space:]]+).*/\1/p')
  case "$origin" in
    installed) provenance="${suite:-suite}";;
    *)         provenance="admitted here";;
  esac
  when=$(printf '%s' "$line" | awk '{print $1}' | cut -c1-8 | sed -E 's/(....)(..)(..)/\1-\2-\3/')
  score=$(printf '%s' "$line" | awk '{print $3}')
  # Who authorised it. Admissions made before bin/admit.sh recorded that show "-", which is the
  # truth: nobody signed them, and back-filling a name would be inventing the record this table
  # exists to keep.
  by=$(printf '%s' "$line" | sed -nE 's/.*[[:space:]]by=(.*[)]).*/\1/p')
  # An amendment after the last admission means the installed text is not the text that scored.
  amended=$(grep -E "^[0-9TZ]+  $a  -/-  amended  candidate=" "$LOG" 2>/dev/null | tail -1)
  mark=""; [ -n "$amended" ] && mark=" ¹"
  step=$(chain_order "$a"); [ "$step" = 99 ] && step="-"
  # An agent admitted here shows who authorised it; one that came with the suite shows the suite
  # and version it came from. Both answer "why should I trust this text", with different evidence.
  [ "$origin" = installed ] || provenance="${by:-admitted here}"
  jq -r --arg a "$a" --arg when "$when" --arg score "$score" --arg prov "$provenance" --arg step "$step" --arg mark "$mark" \
    '.agents[$a] as $x | "| \($step) | \($a)\($mark) | \($x.family // "?") | \($x.ladder // "?") | \($when) | \($prov) | \($score) | \($x.purpose // "?") |"' "$CAT"
done
# Amendments, if any. The score above belongs to the text that passed; an amended definition is
# text a human corrected afterwards without re-running the tasks, and saying so is the point.
AMENDED=$(grep -E "^[0-9TZ]+  [a-z-]+  -/-  amended  candidate=" "$LOG" 2>/dev/null \
  | while IFS= read -r line; do
      agent=$(printf '%s' "$line" | awk '{print $2}')
      [ -f ".claude/agents/$agent.md" ] || continue
      # Everything after the parenthesised by= field is the reason.
      printf '| %s | %s | %s |\n' "$agent" \
        "$(printf '%s' "$line" | awk '{print $1}' | cut -c1-8 | sed -E 's/(....)(..)(..)/\1-\2-\3/')" \
        "$(printf '%s' "$line" | sed -E 's/.*[[:space:]]by=[^)]*\)[[:space:]]*//')"
    done)
if [ -n "$AMENDED" ]; then
  printf '\n¹ Amended after admission: the text changed, the golden tasks did not re-run, and the\n'
  printf 'score above therefore describes the text as it was. Re-admit to earn a score for the text\n'
  printf 'as it is.\n\n'
  printf '| agent | amended | why |\n|---|---|---|\n%s\n' "$AMENDED"
fi
RETIRED=$(jq -r '.agents | to_entries[] | select(.value.retired == true) | "| \(.key) | \(.value.family) | \(.value.purpose) |"' "$CAT")
if [ -n "$RETIRED" ]; then
  printf '\nRetired. The definition is gone from `.claude/agents/`; the admissions log keeps its history:\n\n'
  printf '| agent | family | why |\n|---|---|---|\n%s\n' "$RETIRED"
fi
