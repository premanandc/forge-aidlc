#!/usr/bin/env bash
# accept.sh <TICKET> <intent|spec|tests> [--defer "<reason>"]
#
# A human accepts a drafted artifact. This is the only way an intent:, spec: or tests: commit is
# made, and the only way the test lock is created. It refuses to run without a terminal: agents'
# shells have none, so acceptance cannot be scripted by the fleet. The commit carries
#   Accepted-By: <git user.name> (<GitHub login>)
# which bin/chain-check.sh requires before the next stage may exist. The ticket branch is pushed,
# a draft pull request is opened on the first acceptance, and the issue is labelled with the stage.
#
# intent  commits work/<T>/intent.md (+ ticket.json, policy.json if present)
# spec    commits work/<T>/spec.md (+ docs/adr/ changes)
# tests   commits src/test/ changes, then creates work/<T>/.tests-locked
# --defer lets an artifact with unchecked "## Open questions" be accepted anyway; the reason is
#         recorded as a Deferred-Questions trailer. Compatible with bash 3.2.
set -uo pipefail
usage() { echo "usage: bin/accept.sh <TICKET> <intent|spec|tests> [--defer \"<reason>\"]" >&2; exit 2; }
T=${1:-}; STAGE=${2:-}
[ -n "$T" ] || usage
case "$STAGE" in intent|spec|tests) ;; *) usage;; esac
shift 2; DEFER=""
while [ $# -gt 0 ]; do
  case "$1" in --defer) DEFER=${2:-}; shift;; *) echo "accept: unknown option $1" >&2; usage;; esac
  shift
done
die() { echo "accept: $*" >&2; exit 1; }
# Undo only what this script staged, never the human's other staged work.
unstage() { [ -n "${FILES:-}" ] && git reset -q -- $FILES 2>/dev/null; return 0; }
if [ ! -t 0 ] || [ ! -t 1 ]; then die "acceptance is a human act at a terminal; stdin/stdout is not a TTY"; fi
ROOT=$(git rev-parse --show-toplevel) || die "not a git repository"; cd "$ROOT"
W="work/$T"; BRANCH="ticket/$T"

# --- where are we in the chain ------------------------------------------------------
CUR=$(git branch --show-current)
if [ "$CUR" != "$BRANCH" ]; then
  if [ "$STAGE" = intent ] && ! git show-ref --verify -q "refs/heads/$BRANCH"; then
    git switch -q -c "$BRANCH" || die "could not create $BRANCH"
    echo "accept: created branch $BRANCH from $CUR"
  elif [ "$STAGE" = intent ]; then
    git switch -q "$BRANCH" || die "could not switch to $BRANCH"
  else
    die "on branch $CUR; the chain for $T lives on $BRANCH (git switch $BRANCH)"
  fi
fi
# No -q, deliberately. `grep -q` exits on its first match, git keeps writing into a closed pipe and
# dies with SIGPIPE, and under `pipefail` the pipeline reports 141 rather than 0: a commit that is
# plainly there reads as absent. It only bites when the commit exists, so the intent gate, where
# this is expected to find nothing, passed while every later gate refused. Same bug as the one
# bin/chain-check.sh carries a comment about; a reader that stops early is the shape to avoid.
has_commit() { git log --format=%s | grep -E "^$1:[[:space:]]*$T([^A-Za-z0-9-]|$)" >/dev/null; }
case "$STAGE" in
  intent) has_commit intent && die "intent: $T is already committed";;
  spec)   has_commit intent || die "no intent: commit for $T yet; accept intent first"
          has_commit spec && die "spec: $T is already committed";;
  tests)  has_commit spec || die "no spec: commit for $T yet; accept spec first"
          has_commit tests && die "tests: $T is already committed";;
esac

# --- what is being accepted ---------------------------------------------------------
case "$STAGE" in
  intent) [ -f "$W/intent.md" ] || die "$W/intent.md does not exist; run /forge:intent $T first"
          FILES="$W/intent.md"; for f in "$W/ticket.json" "$W/policy.json"; do [ -f "$f" ] && FILES="$FILES $f"; done;;
  spec)   [ -f "$W/spec.md" ] || die "$W/spec.md does not exist; run /forge:spec $T first"
          grep -Eq '^## Contract' "$W/spec.md" || die "$W/spec.md has no '## Contract' section; the architect drafts it before you accept"
          FILES="$W/spec.md"; [ -d docs/adr ] && FILES="$FILES docs/adr";;
  tests)  FILES="src/test";;
esac
if [ "$STAGE" != tests ]; then
  OPEN=$(awk '/^## Open questions/{f=1; next} /^## /{f=0} f' "$W/$STAGE.md" | grep -E '^[[:space:]]*- \[ \]' || true)
  if [ -n "$OPEN" ] && [ -z "$DEFER" ]; then
    echo "accept: $W/$STAGE.md still has open questions:"; echo "$OPEN" | sed 's/^/    /'
    die "answer them in the file (tick the boxes), or accept anyway with --defer \"<reason>\""
  fi
fi
# Stage and inspect only this artifact's paths: the human may have other work in the tree, and it
# is neither accepted nor disturbed here.
# shellcheck disable=SC2086
git add -A -- $FILES 2>/dev/null
# shellcheck disable=SC2086
if git diff --cached --quiet -- $FILES; then die "nothing to accept: no changes under $FILES"; fi
if [ "$STAGE" = tests ]; then
  [ -f "$W/.tests-locked" ] && die "$W/.tests-locked already exists"
  # The test-designer may not write production code. The guards refuse it live; this catches a
  # draft produced some other way before it is frozen as the oracle.
  if ! git diff --quiet HEAD -- src/main || [ -n "$(git ls-files --others --exclude-standard src/main)" ]; then
    echo "accept: src/main has uncommitted changes:"; git status --short src/main | sed 's/^/    /'
    die "the tests are the oracle and must fail against today's production code; revert src/main before accepting"
  fi
fi

TITLE=$(jq -r '.title // empty' "$W/ticket.json" 2>/dev/null)
[ -z "$TITLE" ] && TITLE=$(grep -m1 -E "^# *$T:" "$W/intent.md" 2>/dev/null | sed -E "s/^# *$T:[[:space:]]*//")
[ -z "$TITLE" ] && TITLE=$(git log --format=%s --grep="^intent: $T" -1 | sed -E "s/^intent:[[:space:]]*$T[[:space:]]*//")
[ -n "$TITLE" ] || { unstage; die "no title: work/$T/ticket.json or a '# $T: <title>' heading in intent.md is needed"; }

# --- the human ----------------------------------------------------------------------
LOGIN=$(gh api user --jq .login 2>/dev/null) || { unstage; die "gh api user failed; log in with gh auth login (acceptance is recorded under your GitHub login)"; }
NAME=$(git config user.name); [ -n "$NAME" ] || { unstage; die "git config user.name is empty"; }
echo
echo "accept: $STAGE for $T: $TITLE"
echo "accept: branch $BRANCH; policy acceptance.$STAGE=$(bin/policy.sh "$T" "acceptance.$STAGE"), risk $(bin/policy.sh "$T" risk)"
echo "accept: you are $NAME ($LOGIN). Accepting:"
# shellcheck disable=SC2086
git diff --cached --stat -- $FILES | sed 's/^/    /'
[ -n "$DEFER" ] && echo "accept: open questions deferred: $DEFER"
printf 'accept: type your GitHub login to accept, anything else to abort: '
read -r ANSWER
[ "$ANSWER" = "$LOGIN" ] || { unstage; die "aborted; nothing committed (staging undone)"; }

# --- the artifact stops being a draft here, before the commit rather than after ------
# work/<T>/.drafting-<stage> means "drafted and unaccepted", and the line above is where that
# stops being true. It used to be removed after the commit, four lines too late: the pre-commit
# layer refuses any commit carrying a drafted artifact and cannot tell this script from any other
# caller, so this script was refused by the very rule that names it as the exception. Clearing the
# marker first makes that rule true by construction. By the time git runs there is no draft, there
# is an artifact a human accepted.
#
# It goes back if anything below fails. A ticket with neither a marker nor an accepted commit is a
# ticket nothing is guarding, and that is a worse state than the one we started in.
DRAFTED="$W/.drafting-$STAGE"
STASH=""
if [ -f "$DRAFTED" ]; then
  STASH=${TMPDIR:-/tmp}/accept-$T-$STAGE.$$
  cp "$DRAFTED" "$STASH" || die "could not set aside $DRAFTED"
  trap 'if [ -n "${STASH:-}" ] && [ -f "$STASH" ]; then cp "$STASH" "$DRAFTED"; rm -f "$STASH"; echo "accept: $DRAFTED restored; $T is still drafting" >&2; fi' EXIT INT TERM
  rm -f "$DRAFTED"
fi

# --- commit, lock, push, PR ---------------------------------------------------------
TRAILERS=(--trailer "Accepted-By: $NAME ($LOGIN)")
[ -n "$DEFER" ] && TRAILERS+=(--trailer "Deferred-Questions: $DEFER")
# --only with the artifact's own paths: an acceptance commit contains the artifact and nothing
# else, whatever the human happened to have staged. (The message precedes --, or git reads it as
# a pathspec.)
# shellcheck disable=SC2086
git commit -q -m "$STAGE: $T $TITLE" "${TRAILERS[@]}" --only -- $FILES || die "commit refused"
# Committed. The draft is now an accepted artifact in the history, so the marker must not come back.
trap - EXIT INT TERM
if [ -n "$STASH" ]; then rm -f "$STASH"; STASH=""; fi
SHA=$(git rev-parse --short HEAD)
echo "accept: committed $SHA  $STAGE: $T $TITLE  (Accepted-By: $NAME ($LOGIN))"
if [ "$STAGE" = tests ]; then touch "$W/.tests-locked"; echo "accept: tests locked ($W/.tests-locked); src/test is frozen for $T until evidence:"; fi
mkdir -p work; echo "$T" >|work/.current-ticket

if git remote get-url origin >/dev/null 2>&1; then
  if git push -q -u origin "$BRANCH"; then echo "accept: pushed $BRANCH"; else echo "accept: push failed; push $BRANCH by hand"; fi
  N=$(bin/issue.sh number "$T" 2>/dev/null || true)
  PR=$(bin/issue.sh pr "$T" 2>/dev/null || true)
  if [ -z "$PR" ]; then
    BODY="Chain for $T on \`$BRANCH\`. Human gates: intent, spec and tests carry \`Accepted-By\` trailers from bin/accept.sh; the fleet takes over from \`plan:\` (bin/ticket.sh). Merging this PR is the release."
    [ -n "$N" ] && BODY="$BODY

Closes #$N"
    BODY="$BODY

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
    if URL=$(gh pr create --draft --head "$BRANCH" --base main --title "$T: $TITLE" --body "$BODY" --label ticket 2>&1); then
      echo "accept: draft PR $URL"
    else echo "accept: PR not created: $URL"; fi
  fi
  if [ -n "$N" ]; then
    bin/issue.sh stage "$T" "$STAGE" >/dev/null 2>&1 || true
    # Two things, deliberately. The short comment is new, so GitHub notifies everyone watching;
    # editing the chain comment in place notifies nobody. The chain comment is the record.
    bin/issue.sh comment "$T" "**$STAGE accepted** by $NAME ($LOGIN) in $SHA on \`$BRANCH\`.${DEFER:+ Open questions deferred: $DEFER} The chain comment above has the detail." >/dev/null 2>&1 || true
    bin/issue.sh render "$T" >/dev/null 2>&1 || echo "accept: could not update the chain comment on #$N"
    echo "accept: issue #$N labelled stage:$STAGE, chain comment updated"
  fi
fi
case "$STAGE" in
  intent) echo "accept: next: /forge:spec $T (spec-drafter and architect draft; you accept)";;
  spec)   echo "accept: next: /forge:tests $T (test-designer drafts failing tests; you accept and they lock)";;
  tests)  echo "accept: next: bin/ticket.sh $T (the fleet plans, implements, reviews and assembles evidence on $BRANCH, then marks the PR ready)";;
esac
bin/chain-check.sh "$T" | tail -1
