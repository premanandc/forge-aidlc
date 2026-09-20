#!/usr/bin/env bash
# ticket-preconditions-selftest.sh: proves bin/ticket.sh refuses to start the autonomous half
# until the human gates are in the history, and accepts it once they are.
#
# Runs in a throwaway worktree, and always with FORGE_TICKET_DRY_RUN=1, so no case can reach a
# model. An earlier version of this script ran bin/ticket.sh for real: one of its own cases was
# wrong (a linked worktree cannot switch to a branch the primary worktree has checked out, so the
# "wrong branch" case never left the ticket branch), the preconditions passed, and the chain ran
# three live sessions on a probe ticket before it was killed. A test of a gate must not be able to
# spend what the gate protects.
#
# Exit 0 when every case behaves; 1 otherwise. Compatible with bash 3.2.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel); cd "$ROOT"
T=PF-996
WT=$(mktemp -d "${TMPDIR:-/tmp}/ticketpre.XXXXXX"); rmdir "$WT"
cleanup() {
  cd "$ROOT"
  git worktree remove --force "$WT" >/dev/null 2>&1
  git branch -D "ticket/$T" >/dev/null 2>&1
  git worktree prune >/dev/null 2>&1
}
trap cleanup EXIT
# HEAD, not main: in CI the checkout is often detached or on a pull-request merge ref, and a
# local `main` need not exist.
git worktree add -q -b "ticket/$T" "$WT" HEAD || { echo "ticket-preconditions: could not create the worktree"; exit 1; }
# A worktree checks out committed files, so it would otherwise run the last committed harness
# rather than the one being edited. Copy the working tree's scripts in: this test exists to check
# the code in front of you. The same goes for .forge/, which the scripts now read this project's
# facts from; without it fleet-render cannot order the registry, fleet-check fails, and every case
# here fails for that reason instead of the one it is testing.
cp -Rf "$ROOT/bin/." "$WT/bin/"
mkdir -p "$WT/.forge"; cp -Rf "$ROOT/.forge/." "$WT/.forge/"
cd "$WT"
# Identity through the environment, never `git config`. A linked worktree shares .git/config with
# the primary checkout, so `git config user.name selftest` here rewrote the whole repository's
# identity, and eleven commits went out authored "selftest" before anyone noticed. A selftest must
# not be able to change the repository it is run in.
export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@example.com
export GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@example.com
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
# Commit them, or the copy itself is the unclean tree the last case is meant to detect. Both
# directories: .forge/project.json is often newer than HEAD in the tree being worked on, and left
# untracked here it made every case fail as "working tree not clean".
git add -A bin .forge >/dev/null 2>&1 && git commit -q -m "chore: the harness under test" >/dev/null 2>&1
export FORGE_TICKET_DRY_RUN=1
# Refuse to run at all unless the script under test honours the dry run. Without this check a
# missing flag does not fail the test, it starts live sessions; that has happened twice.
grep -q 'FORGE_TICKET_DRY_RUN' bin/ticket.sh || {
  echo "ticket-preconditions: bin/ticket.sh has no FORGE_TICKET_DRY_RUN support; refusing to run, every case would start real sessions"
  exit 1
}
PASSED=0; WRONG=0
accepted() { git commit -q --allow-empty -m "$1" --trailer "Accepted-By: selftest human (selftest)"; }

refuses() {  # $1 = label, $2 = substring expected in the refusal
  local out rc
  out=$(bin/ticket.sh "$T" 2>&1); rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q -- "$2"; then
    echo "ticket-preconditions: ok    refused: $1"; PASSED=$((PASSED+1))
  else
    echo "ticket-preconditions: WRONG $1 (rc=$rc, wanted /$2/)"; printf '%s\n' "$out" | tail -3 | sed 's/^/      /'; WRONG=$((WRONG+1))
  fi
}
accepts() {  # $1 = label
  local out rc
  out=$(bin/ticket.sh "$T" 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "preconditions pass"; then
    echo "ticket-preconditions: ok    accepted: $1"; PASSED=$((PASSED+1))
  else
    echo "ticket-preconditions: WRONG $1 (rc=$rc)"; printf '%s\n' "$out" | tail -3 | sed 's/^/      /'; WRONG=$((WRONG+1))
  fi
}

mkdir -p "work/$T"; echo "$T" >|work/.current-ticket
refuses "no chain at all" "no tests: commit"

printf '# %s: probe\n' "$T" >"work/$T/intent.md"
git add "work/$T/intent.md"; accepted "intent: $T probe"
printf '# %s: probe\n\n## Contract\nModule: screening. No new types.\n' "$T" >"work/$T/spec.md"
git add "work/$T/spec.md"; accepted "spec: $T probe"
mkdir -p src/test/java/probe; echo "class Probe {}" >src/test/java/probe/Probe.java
git add src/test; git commit -q -m "tests: $T probe"          # deliberately unaccepted
refuses "tests nobody accepted" "no Accepted-By trailer"

git commit -q --amend --no-edit --trailer "Accepted-By: selftest human (selftest)" >/dev/null
touch "work/$T/.tests-locked"
accepts "intent, spec and tests all accepted"

touch "work/$T/.drafting-tests"
refuses "an artifact still drafting" "still being drafted"
rm -f "work/$T/.drafting-tests"

echo "dirty" >src/main/java/Probe.java 2>/dev/null || { mkdir -p src/main/java; echo "dirty" >src/main/java/Probe.java; }
refuses "working tree not clean" "not clean"
rm -f src/main/java/Probe.java

echo "ticket-preconditions: $PASSED ok, $WRONG wrong"
[ "$WRONG" -eq 0 ]
