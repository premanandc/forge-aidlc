#!/usr/bin/env bash
# issue.sh: the one place GitHub Issues and pull requests meet the chain. Everything else in the
# harness knows a ticket only by its id (PF-NNN); the issue number is metadata recorded here.
#
#   new "<story>" [opts]      file one request: allocates the next PF-NNN, labels it, posts it
#   list [stage]              open tickets, oldest first: id, risk, stage, title; a stage narrows
#                             it (filed, intent, spec, tests, impl, review, released)
#   fetch <T>                 write work/<T>/ticket.json {ticket, issue, url, title, story, risk, labels}
#   number <T>                print the issue number for the ticket
#   comment <T> "<text>"      comment on the ticket's issue
#   stage <T> <stage>         set the stage:<stage> label, removing any other stage label
#   render <T>                rewrite the machine-owned chain comment on the issue (see below)
#   reconcile <T>             make the labels agree with the issue body and give it a stage
#   pr <T>                    print the PR number for branch ticket/<T>, if one exists
#   seed                      create an issue for every backlog row in the functional brief that
#                             has none; PF-101 (already shipped) is created closed
#
# ## The chain comment, and why it is safe to copy the chain into the tracker
#
# Plenty of people follow the work in Issues and never open the repository. `render` gives them
# the whole chain in one comment that is rewritten in place at every transition: what was asked,
# what was agreed, who agreed to it, and how the gates ended.
#
# It is a projection, not a second original, and the rule that keeps it honest is that every fact
# it states carries the identifier that makes the fact checkable. "Premanand accepted this" is an
# assertion. "Accepted in 4b50afb", linked, is falsifiable: that commit either carries the
# Accepted-By trailer or it does not, and GitHub renders the trailer in its own commit view, so a
# reader verifies it without cloning anything. The strongest line in the comment is the link to
# the pull request's checks, where bin/chain-check.sh computes over the commits rather than
# claiming anything about them.
#
# The artifacts are read at the sha that was accepted (git show <sha>:<path>), never from the
# working tree, so the comment shows what a human accepted rather than what someone edited after.
#
# A ticket's issue is the one whose title starts with "<T>:". Needs gh (authenticated) and jq.
# Compatible with bash 3.2.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd); cd "$ROOT"
MARKER='<!-- forge:chain -->'
PROJECT=.forge/project.json
CMD=${1:-}; shift || true
die() { echo "issue: $*" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || die "gh is not installed"
command -v jq >/dev/null 2>&1 || die "jq is not installed"

# How a ticket id looks and where the backlog table lives are facts about this codebase, not about
# the harness, so they are read rather than edited in. bin/ is vendor code: re-installing the suite
# replaces every script in it, and anything tuned in here would go without a word. Fail closed and
# name the file, because a guessed ticket pattern would silently match the wrong issues.
[ -f "$PROJECT" ] || die "$PROJECT is missing; it holds this project's ticket pattern and backlog source"
TICKET_RE=$(jq -r '.ticket.pattern // empty' "$PROJECT")
BRIEF=$(jq -r '.ticket.backlogSource // empty' "$PROJECT")
[ -n "$TICKET_RE" ] || die "$PROJECT has no .ticket.pattern"

all_issues() { gh issue list --state all --label ticket --limit 200 --json number,title,url,state,body,labels,createdAt; }
issue_json() {  # $1 = ticket ; the issue object or nothing
  all_issues | jq -c --arg t "$1" '[.[] | select(.title | test("^" + $t + ":"))] | sort_by(.number) | .[0] // empty'
}
slug() { gh repo view --json nameWithOwner -q .nameWithOwner; }

# --- reading the chain out of git ----------------------------------------------------
# No pipeline here closes its reader early: `git log | head` leaves git writing to a closed pipe,
# which under pipefail reports 141 and turns a correct answer into a failure. Capture, then slice.
stage_sha() {  # $1 = prefix, $2 = ticket ; earliest matching commit, or nothing
  local all; all=$(git log --reverse --topo-order --format='%H %s' 2>/dev/null \
    | awk -v re="^[0-9a-f]+ $1:[[:space:]]*$2([^A-Za-z0-9-]|\$)" '$0 ~ re && !seen {print $1; seen=1}')
  printf '%s' "$all"
}
trailer_of() { git log -1 --format="%(trailers:key=$2,valueonly)" "$1" 2>/dev/null | sed -n 1p; }
file_at() { git show "$1:$2" 2>/dev/null; }            # the artifact as accepted, not as it is now
section() {  # stdin = markdown, $1 = heading regex ; prints the section body
  awk -v re="^## $1" '$0 ~ re {f=1; next} /^## /{f=0} f'
}
short() { git rev-parse --short "$1" 2>/dev/null; }

# sections_of <sha> <path> <heading>... : the first heading that yields anything. Artifacts
# written before the current templates use different headings (PF-101's intent has "Why" and
# "Out of scope" where today's has "Scope"), and a projection that silently renders nothing is
# worse than one that finds the older heading.
sections_of() {
  local sha=$1 path=$2; shift 2
  local h out
  for h in "$@"; do
    out=$(file_at "$sha" "$path" | section "$h" | sed '/^[[:space:]]*$/d')
    if [ -n "$out" ]; then printf '%s\n' "$out"; return 0; fi
  done
  return 1
}

# fold <lines> <title> <link> : long artifact text goes in a collapsed block, clipped, with a link
# to the file at the sha it was accepted at. An issue comment nobody scrolls is not a projection.
fold() {
  local max=$1 title=$2 link=$3 body total
  body=$(cat); total=$(printf '%s\n' "$body" | grep -c '' )
  printf '<details><summary>%s</summary>\n\n' "$title"
  printf '%s\n' "$body" | sed -n "1,${max}p"
  [ "$total" -gt "$max" ] && printf '\n_… %s more lines; read the file as accepted: %s_\n' "$(( total - max ))" "$link"
  printf '\n</details>\n'
}
blob() { printf 'https://github.com/%s/blob/%s/%s' "$(slug)" "$1" "$2"; }

render_body() {  # $1 = ticket ; prints the whole comment
  local T=$1 url="https://github.com/$(slug)" n pr line
  local i s t p im ev
  i=$(stage_sha intent "$T"); s=$(stage_sha spec "$T"); t=$(stage_sha tests "$T")
  p=$(stage_sha plan "$T");  im=$(stage_sha impl "$T"); ev=$(stage_sha evidence "$T")
  pr=$(gh pr list --state all --head "ticket/$T" --json number -q '.[0].number // empty' 2>/dev/null)

  printf '%s\n' "$MARKER"
  printf '### %s — chain\n\n' "$T"
  printf 'Rewritten by `bin/issue.sh render` at every stage. **Do not edit**: your changes are overwritten.\n'
  printf 'This is a projection. The governing copies are the files in `work/%s/`, and the proof of each\n' "$T"
  printf 'decision is the trailer on the commit it links to, which GitHub renders in its own commit view.\n\n'

  printf '| stage | decided by | commit |\n|---|---|---|\n'
  for pair in "intent:$i" "spec:$s" "tests:$t" "plan:$p" "impl:$im" "evidence:$ev"; do
    local name=${pair%%:*} sha=${pair#*:} who=""
    [ -z "$sha" ] && { printf '| %s | | _not yet_ |\n' "$name"; continue; }
    case "$name" in
      intent|spec|tests) who=$(trailer_of "$sha" Accepted-By); who=${who:-_policy waiver_};;
      plan) who=$(trailer_of "$sha" Reviewed-By); [ -z "$who" ] && who="_review skipped by policy_";;
      *) who="the fleet";;
    esac
    printf '| %s | %s | [`%s`](%s/commit/%s) |\n' "$name" "$who" "$(short "$sha")" "$url" "$sha"
  done
  printf '\n'

  if [ -n "$i" ]; then
    local scope; scope=$(sections_of "$i" "work/$T/intent.md" 'Scope' 'Why' 'Problem')
    if [ -n "$scope" ]; then
      printf '#### Scope, as accepted\n\n'
      printf '%s\n' "$scope" | fold 25 'scope in and out' "$(blob "$i" "work/$T/intent.md")"
      printf '\n'
    fi
    local qs asked open
    qs=$(file_at "$i" "work/$T/intent.md" | section 'Open questions')
    asked=$(printf '%s\n' "$qs" | grep -cE '^[[:space:]]*- \[[ xX]\]')
    open=$(printf '%s\n' "$qs" | grep -cE '^[[:space:]]*- \[ \]')
    [ "${asked:-0}" -gt 0 ] && printf '%s question(s) raised by the drafter, %s answered before acceptance.\n\n' "${asked:-0}" "$(( ${asked:-0} - ${open:-0} ))"
    local defer; defer=$(trailer_of "$i" Deferred-Questions)
    [ -n "$defer" ] && printf 'Deferred on acceptance: _%s_\n\n' "$defer"
  fi

  if [ -n "$s" ]; then
    local crit; crit=$(sections_of "$s" "work/$T/spec.md" 'Acceptance criteria')
    if [ -n "$crit" ]; then
      printf '#### Acceptance criteria, as accepted\n\n'
      printf '%s\n' "$crit" | fold 40 'acceptance criteria' "$(blob "$s" "work/$T/spec.md")"
      printf '\n'
    fi
  fi

  if [ -n "$ev" ]; then
    printf '#### Gates\n\n'
    file_at "$ev" "work/$T/evidence.json" \
      | jq -r '"- tier 1 **\(.gates.tier1.status)**, tier 2 **\(.gates.tier2.status)**\n- mutation \(.gates.tier2.mutationScorePercent)%, line coverage \(.coverage.linePercent)%, vulnerable dependencies \(.gates.tier2.vulnerableDependencies)\n- review **\(.review.disposition)**"' 2>/dev/null
    printf '\n'
  fi

  printf '#### How to check any of this\n\n'
  printf -- '- Open a commit above: the `Accepted-By` trailer is rendered by GitHub from the commit itself.\n'
  if [ -n "$pr" ]; then
    printf -- '- Pull request [#%s](%s/pull/%s) lists the whole chain, and its checks run `bin/chain-check.sh`,\n' "$pr" "$url" "$pr"
    printf -- '  which verifies the trailers are present, in order, and permitted by `.forge/policy.json`.\n'
  else
    printf -- '- No pull request yet; one opens at the first acceptance.\n'
  fi
}

upsert_comment() {  # $1 = issue number, $2 = body
  local n=$1 body=$2 ids id
  ids=$(gh api "repos/$(slug)/issues/$n/comments" --paginate -q '.[] | select(.body | contains("'"$MARKER"'")) | .id' 2>/dev/null)
  id=$(printf '%s\n' "$ids" | sed -n 1p)
  if [ -n "$id" ]; then
    printf '%s' "$body" | gh api --method PATCH "repos/$(slug)/issues/comments/$id" -F body=@- >/dev/null \
      && echo "issue: #$n chain comment updated"
  else
    printf '%s' "$body" | gh issue comment "$n" --body-file - >/dev/null \
      && echo "issue: #$n chain comment posted"
  fi
}

case "$CMD" in
  list)
    # An optional stage narrows the list: `list filed` is the queue waiting for someone to work
    # out what the request actually means, which is the question people ask of a backlog most often.
    WANT=${1:-}
    ROWS=$(all_issues | jq -r --arg want "$WANT" '
        .[] | select(.state == "OPEN")
        | (([.labels[].name | select(startswith("stage:"))][0] // "stage:-") | sub("stage:";"")) as $stage
        | select($want == "" or $stage == $want)
        | [.number, .title, (([.labels[].name | select(startswith("risk:"))][0] // "risk:medium") | sub("risk:";"")), $stage] | @tsv' \
      | sort -n)
    if [ -z "$ROWS" ]; then
      echo "issue: no open tickets${WANT:+ at stage $WANT}"
      [ -n "$WANT" ] && echo "issue: stages are filed, intent, spec, tests, impl, review, released"
      exit 0
    fi
    printf '%s\n' "$ROWS" | while IFS=$'\t' read -r n title risk stage; do
      printf '%-8s %-7s %-10s %s  (#%s)\n' "${title%%:*}" "$risk" "$stage" "${title#*: }" "$n"
    done
    ;;
  fetch)
    T=${1:-}; [ -n "$T" ] || die "usage: bin/issue.sh fetch <TICKET>"
    bin/issue.sh reconcile "$T" || true      # labels first: the chain reads risk from the label
    J=$(issue_json "$T"); [ -n "$J" ] || die "no issue titled '$T: ...' (run bin/issue.sh list, or bin/issue.sh seed)"
    mkdir -p "work/$T"
    printf '%s' "$J" | jq --arg t "$T" '{ticket:$t, issue:.number, url:.url, state:.state,
        title:(.title | sub("^" + $t + ":[[:space:]]*"; "")),
        story:((.body // "") | split("\n") | map(select(length > 0 and (startswith("**") | not) and (startswith("#") | not) and (startswith("<!--") | not))) | .[0] // ""),
        risk:([.labels[].name | select(startswith("risk:"))][0] // "risk:medium" | sub("risk:";"")),
        labels:[.labels[].name], fetchedAt:(now | todate)}' >"work/$T/ticket.json"
    echo "issue: wrote work/$T/ticket.json ($(jq -r '"#\(.issue) \(.title) risk=\(.risk)"' "work/$T/ticket.json"))"
    ;;
  reconcile)
    # The issue form asks for risk in a dropdown, which lands in the body; the chain reads risk
    # from the label, and the form can only apply a fixed one. Left alone, a ticket filed as high
    # risk screens as medium and the policy quietly relaxes the gates that risk was meant to
    # tighten. Reconcile at the point of use, loudly, and give an unstarted issue a stage.
    T=${1:-}; [ -n "$T" ] || die "usage: bin/issue.sh reconcile <TICKET>"
    J=$(issue_json "$T"); [ -n "$J" ] || die "no issue for $T"
    N=$(printf '%s' "$J" | jq -r .number)
    LABEL_RISK=$(printf '%s' "$J" | jq -r '[.labels[].name | select(startswith("risk:"))][0] // "" | sub("risk:";"")')
    BODY_RISK=$(printf '%s' "$J" | jq -r '.body // ""' | awk '/^###[[:space:]]*Risk/{f=1; next} f && NF && !seen {print tolower($0); seen=1}' | tr -d '[:space:]')
    case "$BODY_RISK" in
      low|medium|high)
        if [ "$BODY_RISK" != "$LABEL_RISK" ]; then
          [ -n "$LABEL_RISK" ] && gh issue edit "$N" --remove-label "risk:$LABEL_RISK" >/dev/null 2>&1
          gh issue edit "$N" --add-label "risk:$BODY_RISK" >/dev/null \
            && echo "issue: #$N risk label corrected to $BODY_RISK (the form said $BODY_RISK, the label said ${LABEL_RISK:-none})"
        fi;;
    esac
    HAS_STAGE=$(printf '%s' "$J" | jq -r '[.labels[].name | select(startswith("stage:"))] | length')
    if [ "$HAS_STAGE" = "0" ]; then
      gh issue edit "$N" --add-label "stage:filed" >/dev/null && echo "issue: #$N labelled stage:filed"
    fi
    ;;
  number)
    T=${1:-}; J=$(issue_json "$T"); [ -n "$J" ] || die "no issue for $T"; printf '%s' "$J" | jq -r .number
    ;;
  comment)
    T=${1:-}; TEXT=${2:-}; [ -n "$T" ] && [ -n "$TEXT" ] || die "usage: bin/issue.sh comment <TICKET> \"<text>\""
    N=$(bin/issue.sh number "$T") || exit 1
    gh issue comment "$N" --body "$TEXT" >/dev/null && echo "issue: commented on #$N"
    ;;
  render)
    T=${1:-}; [ -n "$T" ] || die "usage: bin/issue.sh render <TICKET>"
    # Nothing accepted yet means nothing to project: the stage:filed label already says that, and
    # a table of six "not yet" rows is noise on someone's issue.
    if [ -z "$(stage_sha intent "$T")" ]; then
      echo "issue: $T has no accepted stage yet; nothing to render"; exit 0
    fi
    N=$(bin/issue.sh number "$T") || exit 1
    upsert_comment "$N" "$(render_body "$T")"
    ;;
  stage)
    T=${1:-}; S=${2:-}; [ -n "$T" ] && [ -n "$S" ] || die "usage: bin/issue.sh stage <TICKET> <filed|intent|spec|tests|impl|review|released>"
    N=$(bin/issue.sh number "$T") || exit 1
    OTHERS=$(gh issue view "$N" --json labels -q '[.labels[].name | select(startswith("stage:") and . != "stage:'"$S"'")] | join(",")')
    gh issue edit "$N" ${OTHERS:+--remove-label "$OTHERS"} --add-label "stage:$S" >/dev/null && echo "issue: #$N now stage:$S"
    ;;
  pr)
    T=${1:-}; [ -n "$T" ] || die "usage: bin/issue.sh pr <TICKET>"
    gh pr list --state all --head "ticket/$T" --json number -q '.[0].number // empty'
    ;;
  new)
    # File one request. The value here is not the typing it saves, it is the identifier: PF-NNN is
    # the key the whole chain hangs off, from the branch name to the work directory to every commit
    # subject, and a web form cannot allocate one. Left to people, two of them file on the same
    # afternoon and pick the same number.
    STORY=${1:-}; shift || true
    [ -n "$STORY" ] || die "usage: bin/issue.sh new \"<story>\" [--risk low|medium|high] [--modules \"a, b\"] [--title \"...\"] [--notes \"...\"]"
    RISK=""; MODULES=""; TITLE=""; NOTES=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --risk) RISK=${2:-}; shift;;
        --modules) MODULES=${2:-}; shift;;
        --title) TITLE=${2:-}; shift;;
        --notes) NOTES=${2:-}; shift;;
        *) die "unknown option $1";;
      esac
      shift
    done
    case "${RISK:-medium}" in low|medium|high) ;; *) die "risk must be low, medium or high";; esac
    # Next free id. Synthetic ids from PF-900 up are reserved for golden tasks, so a stray one on
    # the board must not push real tickets into the 900s.
    MAX=$(all_issues | jq -r '.[].title' | grep -oE "^$TICKET_RE" | sed 's/PF-//' \
          | awk '$1 < 900 {print $1}' | sort -n | tail -1)
    NEXT=$(( ${MAX:-100} + 1 ))
    T="PF-$NEXT"
    if [ -z "$TITLE" ]; then
      # First sentence, or a word-boundary trim of it. A title cut mid-word reads as a mistake,
      # and this one goes on the board where everyone sees it; pass --title for anything better.
      TITLE=$(printf '%s' "$STORY" | sed -E 's/([.!?])[[:space:]].*/\1/; s/[.[:space:]]*$//')
      if [ ${#TITLE} -gt 72 ]; then
        TITLE="$(printf '%s' "$TITLE" | cut -c1-72 | sed -E 's/[[:space:]][^[:space:]]*$//')…"
      fi
    fi
    if [ -z "$RISK" ]; then
      # The same rule bin/issue.sh seed applied to the brief's backlog: more than one module means
      # a boundary is in play, and the policy should tighten rather than relax. Say so, because a
      # guess that silently sets a gate is the bug this harness already shipped once.
      NMOD=$(printf '%s' "$MODULES" | tr ',' '\n' | grep -c '[^[:space:]]' || true)
      if [ "${NMOD:-0}" -ge 2 ]; then RISK=high; else RISK=medium; fi
      echo "issue: risk not given; inferred $RISK from ${NMOD:-0} module(s). Override with --risk."
    fi
    BODY="$STORY"
    [ -n "$MODULES" ] && BODY="$BODY

**Modules:** $MODULES"
    [ -n "$NOTES" ] && BODY="$BODY

**Notes for the drafters:** $NOTES"
    BODY="$BODY

Chain: \`/forge:intent $T\` → accept → \`/forge:spec $T\` → accept → \`/forge:tests $T\` → accept → \`bin/ticket.sh $T\` → review the PR → merge to release."
    URL=$(gh issue create --title "$T: $TITLE" --body "$BODY" --label "ticket,risk:$RISK,stage:filed" 2>&1) \
      || die "create failed: $URL"
    echo "issue: filed $T ($RISK) $URL"
    echo "issue: next, work out what it means: /forge:intent $T"
    ;;
  seed)
    [ -f "$BRIEF" ] || die "$BRIEF not found"
    EXISTING=$(all_issues | jq -r '.[].title' | grep -oE "^$TICKET_RE" | sort -u)
    grep -E "^\| $TICKET_RE \|" "$BRIEF" | while IFS='|' read -r _ id story modules value _; do
      id=$(echo "$id" | tr -d ' '); story=$(echo "$story" | sed 's/^ *//; s/ *$//'); modules=$(echo "$modules" | sed 's/^ *//; s/ *$//'); value=$(echo "$value" | sed 's/^ *//; s/ *$//')
      if echo "$EXISTING" | grep -qx "$id"; then echo "issue: $id exists, skipping"; continue; fi
      nmods=$(echo "$modules" | tr ',' '\n' | grep -c .)
      risk=medium; [ "$nmods" -ge 2 ] && risk=high
      body="$story

**Modules:** $modules
**Demo value:** $value
**Source:** $BRIEF, Section 9

Chain: \`/forge:intent $id\` → accept → \`/forge:spec $id\` → accept → \`/forge:tests $id\` → accept → \`bin/ticket.sh $id\` → review the PR → merge to release."
      url=$(gh issue create --title "$id: $story" --body "$body" --label "ticket,risk:$risk,stage:filed" 2>&1) || { echo "issue: create failed for $id: $url"; continue; }
      echo "issue: created $id ($risk) $url"
      # A ticket that shipped before the backlog moved to Issues is filed and then closed with the
      # note that says so, rather than left looking like open work. Which tickets those are, and
      # what each note says, are facts about this project and live in .forge/project.json.
      note=$(jq -r --arg id "$id" '.ticket.alreadyReleased[$id] // empty' "$PROJECT")
      if [ -n "$note" ]; then
        n=${url##*/}
        gh issue comment "$n" --body "$note" >/dev/null
        gh issue edit "$n" --remove-label "stage:filed" --add-label "stage:released" >/dev/null
        gh issue close "$n" --reason completed >/dev/null && echo "issue: closed $id as already released"
      fi
    done
    ;;
  *) echo "usage: bin/issue.sh new \"<story>\" [--risk r] [--modules m] [--title t] [--notes n] | list [stage] | fetch <T> | number <T> | comment <T> \"<text>\" | render <T> | reconcile <T> | stage <T> <stage> | pr <T> | seed" >&2; exit 2;;
esac
