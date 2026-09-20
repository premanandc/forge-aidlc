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
) | while IFS= read -r l; do echo "$l"; case "$l" in *WRONG*) echo "$l" >>"$STAGE_PROBE.fail";; esac; done
[ -f "$STAGE_PROBE.fail" ] && WRONG=$((WRONG+2)) || PASSED=$((PASSED+2))
rm -f "$STAGE_PROBE.fail"
git worktree remove --force "$STAGE_PROBE" >/dev/null 2>&1; git worktree prune >/dev/null 2>&1
rm -rf work/PF-777
O=$(echo '{"tool_input":{"command":"ls"}}' | bin/hooks/pretooluse-bash.sh); RC=$?
if [ -z "$O" ] && [ "$RC" -eq 0 ]; then echo "guard-selftest: ok    (0) adapter is silent on an unguarded command"; PASSED=$((PASSED+1))
else echo "guard-selftest: WRONG adapter spoke on an unguarded command: $O"; WRONG=$((WRONG+1)); fi

echo "guard-selftest: $PASSED ok, $WRONG wrong"
[ "$WRONG" -eq 0 ]
