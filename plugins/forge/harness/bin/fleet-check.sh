#!/usr/bin/env bash
# fleet-check.sh: the fleet is what it was admitted to be, and no more.
#
#   - every admitted definition under .claude/agents/ is byte-identical to the text that passed
#     admission (the content hash recorded in evals/admissions.log)
#   - every admitted agent is named in .forge/fleet-catalog.json with a family, a purpose, a
#     ladder rung and a family owner, so a human is accountable for it
#   - no agent still installed is marked retired
#   - FLEET.md is exactly what bin/fleet-render.sh renders from those two sources, so the
#     registry cannot quietly disagree with the record
#
# Run by the Stop hook, by bin/admit.sh after a run, by CI, and by hand. Exit 0 clean, 1 drift.
# Compatible with bash 3.2.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd); cd "$ROOT"
LOG=evals/admissions.log
CAT=.forge/fleet-catalog.json
FAILED=0
fail() { echo "fleet-check: FAIL  $*"; FAILED=1; }
ok()   { echo "fleet-check: ok    $*"; }

[ -f "$CAT" ] || fail "$CAT is missing; the fleet has no catalog"

for f in .claude/agents/*.md; do
  [ -e "$f" ] || continue
  agent=$(basename "$f" .md)
  actual=$(git hash-object "$f")
  # The newest line that installed text for this agent, whether a passing run or a recorded
  # amendment. An amendment is text a human changed without re-running the tasks; it sits in the
  # log as "amended" precisely so it can never be mistaken for a score.
  # Three ways text legitimately arrives: it passed golden tasks here (admitted), a human corrected
  # its prose without re-running them (amended), or it came with the suite and the installer
  # recorded where from (installed). All three are provenance; what is refused is text with none.
  admitted=$(grep -E "^[0-9TZ]+  $agent  ([0-9]+/[0-9]+|-/-)  (admitted|amended|installed)  candidate=" "$LOG" 2>/dev/null | tail -1 | sed -E 's/.*candidate=([0-9a-f]+).*/\1/')
  if [ -z "$admitted" ]; then
    fail "$agent: present in .claude/agents/ but $LOG records no admission, amendment or install for it"
  elif [ "$actual" != "$admitted" ]; then
    fail "$agent: definition drifted from its admitted text (admitted $admitted, now $actual); edit the candidate and re-run bin/admit.sh $agent"
  else
    ok "$agent matches admitted hash ${admitted:0:12}"
  fi
  if [ -f "$CAT" ]; then
    entry=$(jq -c --arg a "$agent" '.agents[$a] // empty' "$CAT" 2>/dev/null)
    if [ -z "$entry" ]; then
      fail "$agent: not in $CAT; every agent needs a family, a purpose, a rung and an owner"
    else
      fam=$(printf '%s' "$entry" | jq -r '.family // empty')
      rung=$(printf '%s' "$entry" | jq -r '.ladder // empty')
      owner=$(jq -r --arg f "$fam" '.families[$f].owner // empty' "$CAT")
      retired=$(printf '%s' "$entry" | jq -r '.retired // false')
      if [ "$retired" = true ]; then fail "$agent: marked retired in $CAT but still installed; run bin/admit.sh --retire $agent \"<reason>\""
      elif [ -z "$fam" ] || [ -z "$rung" ] || [ -z "$owner" ]; then
        fail "$agent: catalog entry incomplete (family='$fam' ladder='$rung' owner='$owner')"
      else ok "$agent is $fam family, $rung rung, owned by $owner"; fi
    fi
  fi
done

# FLEET.md is derived, so it must equal what its sources render.
if [ -x bin/fleet-render.sh ]; then
  if diff -q <(bin/fleet-render.sh) FLEET.md >/dev/null 2>&1; then
    ok "FLEET.md matches bin/fleet-render.sh"
  else
    fail "FLEET.md differs from what the catalog and the admissions log render; it is not edited by hand:"
    diff <(bin/fleet-render.sh) FLEET.md | head -10 | sed 's/^/fleet-check:       /'
  fi
fi

if [ "$FAILED" -eq 0 ]; then echo "fleet-check: PASS"; exit 0; fi
echo "fleet-check: FAILED"; exit 1
