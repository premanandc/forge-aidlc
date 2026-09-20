#!/usr/bin/env bash
# guard-selftest.sh: proves bin/guard.sh blocks what it must and allows what it must, and that
# the Bash PreToolUse adapter turns a block into a deny. Run it whenever a guard rule changes; CI
# runs it beside bin/chain-check-selftest.sh.
#
# Every rule here has failed open or closed at least once during development: "-n" in a test
# expression read as --no-verify, a grep for a marker name read as a write to it. The vectors
# below are those regressions. They live in a file, not in a tool call, because a command naming
# them would itself be guarded.
#
# Exit 0 when every case behaves; 1 otherwise. Compatible with bash 3.2.
cd "$(git rev-parse --show-toplevel)" || exit 1

# Several cases below assert what the guard does with no chain in flight, and bin/guard.sh derives
# that from the branch: on ticket/<T> you are inside a ticket whatever work/.current-ticket says,
# which is the point of deriving it. Run from a ticket branch those cases would assert the opposite
# of the truth, and run from main they would pass, so the suite's answer would depend on where it
# happened to be run. Re-run the whole thing in a detached worktree, where no branch claims a
# ticket and the pointer file decides, as the cases expect. CI checks out detached already.
# Any named branch, not just ticket/*. On a ticket branch the derivation claims that ticket; on
# main it ignores the pointer entirely. Either way the cases below, which steer the guard by
# writing work/.current-ticket, are not testing what they think. Only a detached HEAD leaves the
# pointer in charge, which is the state they were written for and the one CI checks out.
case "$(git branch --show-current 2>/dev/null)" in
  "") ;;
  *)
    [ -z "${FORGE_SELFTEST_DETACHED:-}" ] || { echo "guard-selftest: still on a ticket branch inside the worktree"; exit 1; }
    SELF_WT=$(mktemp -d "${TMPDIR:-/tmp}/guardself.XXXXXX"); rmdir "$SELF_WT"
    git worktree add -q --detach "$SELF_WT" HEAD || { echo "guard-selftest: could not create the worktree"; exit 1; }
    cp -Rf bin/. "$SELF_WT/bin/"
    mkdir -p "$SELF_WT/.forge"; cp -Rf .forge/. "$SELF_WT/.forge/"
    ( cd "$SELF_WT" && FORGE_SELFTEST_DETACHED=1 bin/guard-selftest.sh ); SELF_RC=$?
    git worktree remove --force "$SELF_WT" >/dev/null 2>&1; git worktree prune >/dev/null 2>&1
    exit $SELF_RC;;
esac
PASSED=0; WRONG=0
# The cases below set work/.current-ticket to steer the guard, and this script runs in a real
# checkout. Put back whatever was there, or a selftest would quietly hijack the ticket someone is
# in the middle of.
SAVED_TICKET_FILE=$(mktemp "${TMPDIR:-/tmp}/guardselftest.XXXXXX")
HAD_TICKET=0
[ -f work/.current-ticket ] && { cp work/.current-ticket "$SAVED_TICKET_FILE"; HAD_TICKET=1; }
restore_ticket() {
  if [ "$HAD_TICKET" -eq 1 ]; then cp "$SAVED_TICKET_FILE" work/.current-ticket
  else rm -f work/.current-ticket; fi
  rm -f "$SAVED_TICKET_FILE"
}
trap 'restore_ticket; rm -rf work/PF-777' EXIT
# Start from a known state: the early cases assert what the guard does with no session in flight,
# and a ticket left active by whoever ran this would silently change their meaning.
rm -f work/.current-ticket
LOCK='.tests-locked'; DRAFT='.drafting-spec'; POL='policy.json'
t() { # $1 expected rc, $2 label, $3 command text
  out=$(bin/guard.sh --command "$3"); rc=$?
  if [ "$rc" -eq "$1" ]; then echo "guard-selftest: ok    ($rc) $2"; PASSED=$((PASSED+1))
  else echo "guard-selftest: WRONG (rc=$rc, want $1) $2"; echo "$out" | sed 's/^/      /'; WRONG=$((WRONG+1)); fi
}
expect_path() {  # $1 expected rc, $2 label, $3 path
  bin/guard.sh --path "$3" >/dev/null; local rc=$?
  if [ "$rc" -eq "$1" ]; then echo "guard-selftest: ok    ($rc) $2"; PASSED=$((PASSED+1))
  else echo "guard-selftest: WRONG (rc=$rc, want $1) $2"; WRONG=$((WRONG+1)); fi
}
echo "=== commits and pushes"
t 1 "commit with Accepted-By trailer"        'git commit -m x --trailer "Accepted-By: me (me)"'
t 1 "commit --no-verify"                     'git commit --no-verify -m x'
t 1 "commit -n"                              'git commit -n -m x'
t 0 "-n in a test expression"                'if [ -n "$d" ]; then git status; fi'
t 0 "plain commit, nothing drafting"         'git commit -m "impl: PF-102 x"'
t 1 "gh pr merge"                            'gh pr merge 3 --merge'
t 1 "git config hooksPath"                   'git config core.hooksPath /dev/null'
# Naming the tracked hook file is not disabling it. Matching the path anywhere blocked copying it
# into a plugin payload; what matters is the installed copy and where git looks for it.
t 0 "copy the tracked hook somewhere else"   'cp hooks/pre-commit /tmp/payload/'
t 0 "read the tracked hook"                  'cat hooks/pre-commit'
t 1 "overwrite the installed hook"           'echo "" > .git/hooks/pre-commit'
t 1 "delete the installed hook"              'rm .git/hooks/pre-commit'
t 0 "git status"                             'git status'
t 0 "git log grep commit"                    'git log --grep=commit --oneline'

echo "=== the chain's signals: protected while a chain is in flight"
mkdir -p work/PF-777
t 0 "touch the lock, no chain in flight"     "touch work/PF-102/$LOCK"
t 0 "rm a marker, no chain in flight"        "rm work/PF-102/$DRAFT"
touch work/PF-777/.role-test-designer        # a fleet role has announced itself: a chain is live
t 1 "touch the lock"                         "touch work/PF-102/$LOCK"
t 1 "redirect into the lock"                 "echo x > work/PF-102/$LOCK"
t 0 "cat the lock"                           "cat work/PF-102/$LOCK"
t 0 "test for the lock, redirect elsewhere"  "assert_no_file work/PF-901/$LOCK > out.log"
t 0 "grep for the lock name"                 "grep -r ${LOCK#.} evals/ > /tmp/x"
t 1 "rm a drafting marker"                   "rm work/PF-102/$DRAFT"
t 0 "ls a drafting marker"                   "ls work/PF-102/$DRAFT"
# Creating a marker only ever adds restriction, and it is how the drafting commands open their
# window. Blocking it broke the first step of the chain.
t 0 "touch a drafting marker"                "touch work/PF-102/$DRAFT"
t 0 "mkdir and touch a marker, as /forge:intent does" "mkdir -p work/PF-102 && touch work/PF-102/$DRAFT"
t 1 "mv a drafting marker away"              "mv work/PF-102/$DRAFT /tmp/x"
rm -f work/PF-777/.role-test-designer

echo "=== policy and catalog: closed to agent sessions only"
t 0 "write policy, no agent session"         "echo {} > .forge/$POL"
expect_path 0 "--path catalog, no agent session" ".forge/fleet-catalog.json"
mkdir -p work/PF-777 && touch work/PF-777/.role-implementer
t 1 "write policy, agent session"            "echo {} > .forge/$POL"
t 1 "sed -i the policy, agent session"       "sed -i '' s/a/b/ .forge/$POL"
t 0 "jq read of the policy, agent session"   "jq . .forge/$POL"
expect_path 1 "--path catalog, agent session" ".forge/fleet-catalog.json"
rm -f work/PF-777/.role-implementer

echo "=== drafting blocks the drafting agent's commits, and only those"
mkdir -p work && echo PF-777 >|work/.current-ticket    # this session is working PF-777
touch "work/PF-777/$DRAFT"
t 1 "git commit while drafting this ticket"  'git commit -m "intent: PF-777"'
t 1 "git -C . commit while drafting"         'git -C . commit -m x'
t 1 "cd && git push while drafting"          'cd /tmp && git push origin main'
t 0 "git add while drafting"                 'git add work/PF-777/intent.md'
# Someone else's draft must not stop unrelated work. Blocking every commit anywhere while any
# marker existed is what stopped a person maintaining the harness on another branch.
echo PF-778 >|work/.current-ticket                     # this session is working a different one
t 0 "commit on another ticket while PF-777 drafts" 'git commit -m "impl: PF-778 unrelated"'
rm -f work/.current-ticket
t 0 "commit with no active ticket while PF-777 drafts" 'git commit -m "docs: harness note"'
echo PF-777 >|work/.current-ticket                     # back on the drafting ticket for the adapter check
echo "=== the hook adapter turns a block into a deny"
D=$(echo '{"tool_input":{"command":"git commit -m x"}}' | bin/hooks/pretooluse-bash.sh | jq -r '.hookSpecificOutput.permissionDecision // "none"')
if [ "$D" = deny ]; then echo "guard-selftest: ok    (deny) adapter denies a commit while drafting"; PASSED=$((PASSED+1))
else echo "guard-selftest: WRONG adapter returned '$D' for a commit while drafting"; WRONG=$((WRONG+1)); fi
echo "=== --staged refuses the drafted artifact, and passes everything else"
# The pre-commit layer knows exactly what is about to be committed, so it judges the staged set
# rather than the existence of a marker anywhere.
STAGE_PROBE=$(mktemp -d "${TMPDIR:-/tmp}/guardstaged.XXXXXX"); rmdir "$STAGE_PROBE"
git worktree add -q --detach "$STAGE_PROBE" HEAD 2>/dev/null
cp -Rf bin/. "$STAGE_PROBE/bin/" 2>/dev/null
(
  cd "$STAGE_PROBE" || exit 0
  # Environment, not `git config`: a linked worktree shares .git/config with the primary checkout,
  # so configuring an identity here would rewrite the real repository's.
  export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@example.com
  export GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@example.com
  mkdir -p work/PF-777 && touch "work/PF-777/$DRAFT"
  mkdir -p docs && echo "note" >docs/unrelated.md && git add docs/unrelated.md
  bin/guard.sh --staged >/dev/null; rc=$?
  [ "$rc" -eq 0 ] && echo "guard-selftest: ok    (0) --staged passes a commit that carries no drafted artifact" \
                  || echo "guard-selftest: WRONG --staged blocked an unrelated commit (rc=$rc)"
  mkdir -p work/PF-777 && echo "# intent" >work/PF-777/intent.md && git add work/PF-777/intent.md
  bin/guard.sh --staged >/dev/null; rc=$?
  [ "$rc" -eq 1 ] && echo "guard-selftest: ok    (1) --staged refuses the drafted artifact itself" \
                  || echo "guard-selftest: WRONG --staged allowed the drafted artifact (rc=$rc)"
  # The other half of the same rule, and the half whose absence let a real bug ship. A rule that
  # only ever blocks is untested: bin/accept.sh clears the marker when a human accepts and commits
  # after, so the identical staged set must pass once there is no draft. Without this case the
  # guard refused every acceptance commit for as long as the harness existed and every check
  # stayed green, because nothing ever asked the rule to let go.
  rm -f "work/PF-777/$DRAFT"
  bin/guard.sh --staged >/dev/null; rc=$?
  [ "$rc" -eq 0 ] && echo "guard-selftest: ok    (0) --staged passes that same artifact once the marker is cleared" \
                  || echo "guard-selftest: WRONG --staged still refused the artifact with no marker open (rc=$rc)"
) | while IFS= read -r l; do echo "$l"; case "$l" in *WRONG*) echo "$l" >>"$STAGE_PROBE.fail";; esac; done
[ -f "$STAGE_PROBE.fail" ] && WRONG=$((WRONG+3)) || PASSED=$((PASSED+3))
rm -f "$STAGE_PROBE.fail"
git worktree remove --force "$STAGE_PROBE" >/dev/null 2>&1; git worktree prune >/dev/null 2>&1
rm -rf work/PF-777

echo "=== the Stop hook ends the session's role markers, and only on an allowed stop"
# A role marker says "a fleet session is running right now". Nothing removed one until the Stop
# hook did, so every finished session left one behind, and a left-behind .role-implementer blocks
# the human-approved tests-amend for that ticket, because that rule has no approval escape. These
# three cases are that lifecycle: cleared when the session ends, scoped to its own ticket, and
# kept when the stop is refused, because then the session is still running.
STOP_PROBE=$(mktemp -d "${TMPDIR:-/tmp}/guardstop.XXXXXX"); rmdir "$STOP_PROBE"
git worktree add -q --detach "$STOP_PROBE" HEAD 2>/dev/null
cp -Rf bin/. "$STOP_PROBE/bin/" 2>/dev/null
(
  cd "$STOP_PROBE" || exit 0
  export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@example.com
  export GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@example.com
  mkdir -p work/PF-777 work/PF-778
  echo PF-777 >work/.current-ticket
  : >work/PF-777/.role-implementer
  : >work/PF-778/.role-architect
  echo '{"stop_hook_active":true}' | bin/hooks/stop-chain-check.sh >/dev/null 2>&1
  [ -f work/PF-777/.role-implementer ] \
    && echo "guard-selftest: WRONG the Stop hook left the active ticket's role marker behind" \
    || echo "guard-selftest: ok    (0) the Stop hook clears the active ticket's role markers"
  [ -f work/PF-778/.role-architect ] \
    && echo "guard-selftest: ok    (0) and leaves another ticket's role marker alone" \
    || echo "guard-selftest: WRONG the Stop hook cleared a marker belonging to another ticket"
  # A refused stop means the session keeps working. Clearing there would let it run on with the
  # role guard switched off, so the marker must survive exactly the refusal.
  : >work/PF-777/.role-implementer
  git commit -q --allow-empty -m "impl: PF-777 an impl with no tests before it"
  D=$(echo '{"stop_hook_active":false}' | bin/hooks/stop-chain-check.sh | jq -r '.hookSpecificOutput.decision // "none"')
  if [ "$D" = block ] && [ -f work/PF-777/.role-implementer ]; then
    echo "guard-selftest: ok    (block) a refused stop keeps the role marker"
  else
    echo "guard-selftest: WRONG refused stop: decision=$D, marker kept=$([ -f work/PF-777/.role-implementer ] && echo yes || echo no)"
  fi
) | while IFS= read -r l; do echo "$l"; case "$l" in *WRONG*) echo "$l" >>"$STOP_PROBE.fail";; esac; done
[ -f "$STOP_PROBE.fail" ] && WRONG=$((WRONG+3)) || PASSED=$((PASSED+3))
rm -f "$STOP_PROBE.fail"
git worktree remove --force "$STOP_PROBE" >/dev/null 2>&1; git worktree prune >/dev/null 2>&1
echo "=== the branch decides whether you are inside a ticket, not the pointer file"
# work/.current-ticket is written by /forge:intent and bin/accept.sh and nothing ever clears it,
# so it outlives the work it describes. While the guard trusted it alone, the only way to do
# harness work was to move it aside, and moving it is exactly what switched off the rule
# protecting .forge/. These two cases are the derivation: a plain branch is outside a ticket
# however stale the pointer, and a ticket branch is inside one with no pointer at all, so deleting
# the file no longer disarms anything.
BR_PROBE=$(mktemp -d "${TMPDIR:-/tmp}/guardbranch.XXXXXX"); rmdir "$BR_PROBE"
BR_PLAIN="forge-selftest-plain-$$"; BR_TICKET="ticket/forge-selftest-$$"
git worktree add -q -b "$BR_PLAIN" "$BR_PROBE" HEAD 2>/dev/null
cp -Rf bin/. "$BR_PROBE/bin/" 2>/dev/null
mkdir -p "$BR_PROBE/.forge"; cp -Rf .forge/. "$BR_PROBE/.forge/" 2>/dev/null
(
  cd "$BR_PROBE" || exit 0
  mkdir -p work; echo PF-777 >work/.current-ticket   # the stale pointer every finished ticket leaves
  bin/guard.sh --path .forge/policy.json >/dev/null; rc=$?
  [ "$rc" -eq 0 ] && echo "guard-selftest: ok    (0) a plain branch is outside a ticket, stale pointer and all" \
                  || echo "guard-selftest: WRONG a plain branch still counted as inside a ticket (rc=$rc)"
  git switch -q -c "$BR_TICKET" 2>/dev/null
  rm -f work/.current-ticket                         # deleting it used to be enough to disarm this
  bin/guard.sh --path .forge/policy.json >/dev/null; rc=$?
  [ "$rc" -eq 1 ] && echo "guard-selftest: ok    (1) a ticket branch is inside a ticket with no pointer at all" \
                  || echo "guard-selftest: WRONG deleting the pointer on a ticket branch disarmed the rule (rc=$rc)"
) | while IFS= read -r l; do echo "$l"; case "$l" in *WRONG*) echo "$l" >>"$BR_PROBE.fail";; esac; done
[ -f "$BR_PROBE.fail" ] && WRONG=$((WRONG+2)) || PASSED=$((PASSED+2))
rm -f "$BR_PROBE.fail"
git worktree remove --force "$BR_PROBE" >/dev/null 2>&1; git worktree prune >/dev/null 2>&1
git branch -D "$BR_PLAIN" "$BR_TICKET" >/dev/null 2>&1

O=$(echo '{"tool_input":{"command":"ls"}}' | bin/hooks/pretooluse-bash.sh); RC=$?
if [ -z "$O" ] && [ "$RC" -eq 0 ]; then echo "guard-selftest: ok    (0) adapter is silent on an unguarded command"; PASSED=$((PASSED+1))
else echo "guard-selftest: WRONG adapter spoke on an unguarded command: $O"; WRONG=$((WRONG+1)); fi

echo "guard-selftest: $PASSED ok, $WRONG wrong"
[ "$WRONG" -eq 0 ]
