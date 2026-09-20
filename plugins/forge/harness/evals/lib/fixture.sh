#!/usr/bin/env bash
# Fixture helpers for golden tasks. Sourced by evals/<agent>/<task>/fixture.sh, which runs inside
# the scratch worktree before the candidate starts, to lay down the chain history the candidate
# should find in place.
#
# The chain the real factory produces carries human acceptance on intent:, spec: and tests:
# (bin/accept.sh writes the Accepted-By trailer) and the architect's trailer on plan:. Fixtures
# reproduce that, so bin/chain-check.sh inside a task judges the candidate's work rather than the
# fixture's shortcuts. Compatible with bash 3.2.

FIXTURE_AUTHOR_ARGS="-c user.email=harness@forge.demo -c user.name=harness"
FIXTURE_ACCEPTED_BY="harness human (harness)"

# fixture_commit <prefix> <ticket> <summary> [extra trailer]...
# Commits whatever is staged. intent:, spec: and tests: get the acceptance trailer a human's
# bin/accept.sh run would have written.
fixture_commit() {
  local prefix=$1 ticket=$2 summary=$3; shift 3
  local trailers=()
  case "$prefix" in intent|spec|tests) trailers+=(--trailer "Accepted-By: $FIXTURE_ACCEPTED_BY");; esac
  while [ $# -gt 0 ]; do trailers+=(--trailer "$1"); shift; done
  # shellcheck disable=SC2086
  git $FIXTURE_AUTHOR_ARGS commit -q -m "$prefix: $ticket $summary" "${trailers[@]}"
}

# fixture_stage_commit <prefix> <ticket> <summary> <path>... : stage the paths, then commit.
fixture_stage_commit() {
  local prefix=$1 ticket=$2 summary=$3; shift 3
  git add "$@"
  fixture_commit "$prefix" "$ticket" "$summary"
}

# fixture_accepted_spec <ticket> <summary> : the usual "intent and spec are accepted" starting
# point, from work/<ticket>/intent.md and spec.md already overlaid by the task's fixture/.
fixture_accepted_spec() {
  local t=$1 s=$2
  fixture_stage_commit intent "$t" "$s" "work/$t/intent.md"
  fixture_stage_commit spec   "$t" "$s" "work/$t/spec.md"
}

# fixture_locked_tests <ticket> <summary> : intent and spec accepted, tests accepted and locked,
# as the chain stands when the implementer starts.
fixture_locked_tests() {
  local t=$1 s=$2
  fixture_accepted_spec "$t" "$s"
  fixture_stage_commit tests "$t" "$s" src/test
  touch "work/$t/.tests-locked"
}

# fixture_drafting <ticket> <stage> : mark an artifact as drafted but not yet accepted. While the
# marker exists the guards refuse the drafting session's commits, as in a real drafting run.
fixture_drafting() { mkdir -p "work/$1"; touch "work/$1/.drafting-$2"; }
