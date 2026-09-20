#!/usr/bin/env bash
# policy.sh <TICKET> <key>
#
# The effective chain policy for one ticket. Repo defaults live in .forge/policy.json; a ticket may
# override the relaxable keys in work/<T>/policy.json. Both files are edited by humans only
# (bin/guard.sh refuses agent writes). Keys:
#   acceptance.intent | acceptance.spec   always "required"; no setting relaxes them. A ticket
#                                          whose policy carries grandfathered.reason (it predates
#                                          the gate) resolves to "optional".
#   acceptance.tests                       required | by-risk  -> required | optional
#   architectureReview                     required | by-risk | optional -> required | optional
#   risk                                   the ticket's risk (work/<T>/ticket.json, else defaultRisk)
#   mergeMethod                            how the human releases (merge)
#   grandfathered                          yes | no
#   show                                   the repo and ticket policy JSON side by side
# by-risk: required when risk is high; for architectureReview also when the spec's Contract names
# an event type or more than one module (a boundary is in play). Unknown values resolve to
# required: the policy fails closed. Compatible with bash 3.2; needs jq.
set -uo pipefail
T=${1:-}; KEY=${2:-}
[ -n "$T" ] && [ -n "$KEY" ] || { echo "usage: bin/policy.sh <TICKET> <acceptance.intent|acceptance.spec|acceptance.tests|architectureReview|risk|mergeMethod|grandfathered|show>" >&2; exit 2; }
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd); cd "$ROOT"
DEFAULTS='{"humanAcceptance":{"tests":"required"},"architectureReview":"by-risk","defaultRisk":"medium","mergeMethod":"merge"}'
REPO_JSON=$([ -f .forge/policy.json ] && jq -c . .forge/policy.json 2>/dev/null || echo "$DEFAULTS")
TICKET_JSON=$([ -f "work/$T/policy.json" ] && jq -c . "work/$T/policy.json" 2>/dev/null || echo '{}')

get() {  # $1 = jq path; ticket wins over repo over built-in defaults
  local v
  v=$(printf '%s' "$TICKET_JSON" | jq -r "$1 // empty"); [ -n "$v" ] && { echo "$v"; return; }
  v=$(printf '%s' "$REPO_JSON" | jq -r "$1 // empty");   [ -n "$v" ] && { echo "$v"; return; }
  printf '%s' "$DEFAULTS" | jq -r "$1 // empty"
}
risk() {
  local r; r=$(jq -r '.risk // empty' "work/$T/ticket.json" 2>/dev/null)
  case "$r" in low|medium|high) echo "$r";; *) get '.defaultRisk';; esac
}
resolve() {  # $1 = required|optional|by-risk
  case "$1" in
    required|optional) echo "$1";;
    by-risk) [ "$(risk)" = high ] && echo required || echo optional;;
    *) echo "policy: unknown value '$1' for $KEY; resolving to required" >&2; echo required;;
  esac
}
grandfathered() { printf '%s' "$TICKET_JSON" | jq -e '.grandfathered.reason | strings | length > 0' >/dev/null 2>&1; }

case "$KEY" in
  acceptance.intent|acceptance.spec)
    if grandfathered; then echo optional; else echo required; fi;;
  acceptance.tests)
    if grandfathered; then echo optional; else resolve "$(get '.humanAcceptance.tests')"; fi;;
  architectureReview)
    v=$(get '.architectureReview')
    if [ "$v" = by-risk ] && [ -f "work/$T/spec.md" ]; then
      contract=$(awk '/^## Contract/{f=1; next} /^## /{f=0} f' "work/$T/spec.md")
      # template: module names of this codebase; the copier template renders them from its answers
      mods=$(printf '%s' "$contract" | grep -oE 'enrollment|screening|decision|registry|correspondence' | sort -u | wc -l | tr -d ' ')
      if printf '%s' "$contract" | grep -qE 'shared\.events|ForgeEvent|allowedDependencies' || [ "$mods" -ge 2 ]; then
        echo required; exit 0
      fi
    fi
    resolve "$v";;
  risk) risk;;
  mergeMethod) get '.mergeMethod';;
  grandfathered) if grandfathered; then echo yes; else echo no; fi;;
  show) jq -n --argjson r "$REPO_JSON" --argjson t "$TICKET_JSON" '{repo:$r, ticket:$t}';;
  *) echo "policy: unknown key '$KEY'" >&2; exit 2;;
esac
