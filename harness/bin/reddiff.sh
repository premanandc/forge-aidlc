#!/usr/bin/env bash
# reddiff.sh: the negative proofs. Each red diff breaks exactly one rule, and this script checks
# that the harness catches it for that reason and not for some other.
#
#   bin/reddiff.sh list                  what each one breaks and which gate should catch it
#   bin/reddiff.sh verify [<name>|--all] build it in a throwaway worktree and check the gate bites
#   bin/reddiff.sh branch <name>         leave red/<name> behind as a local branch to look at
#   bin/reddiff.sh pr <name>             push it and open a pull request, so Actions shows it red
#   bin/reddiff.sh clean                 delete the local red/* branches this script made
#   bin/reddiff.sh --apply <name>        (internal) apply the change to the current tree
#   bin/reddiff.sh --guard <name>        (internal) ask the write guard about it
#
# A gate that fails for the wrong reason proves nothing, so `verify` asserts two things: the
# expected failure appears, and the signatures of the *other* gates do not. A red diff that also
# broke the build by accident would be a worse demo than no red diff at all.
#
# They are rebuilt from main on demand rather than kept as long-lived branches, so they cannot
# quietly rot as the code moves. Compatible with bash 3.2.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel); cd "$ROOT"
CMD=${1:-list}; ARG=${2:-}
die() { echo "reddiff: $*" >&2; exit 2; }
NAMES="boundary oracle self-approve unaccepted"

# The oracle red diff needs a ticket whose lock window is still open. chain-check enforces the lock
# between the tests: and evidence: commits, so PF-101, which shipped, cannot demonstrate it: a test
# edited after a ticket closes is not what the rule is about. PF-995 is built here, in flight, the
# way a real ticket looks at the moment an implementer reaches for an inconvenient test.
ORACLE_TICKET=PF-995
ORACLE_TEST=src/test/java/com/forge/demo/shared/RedOracleTests.java

breaks() {
  case "$1" in
    boundary)     echo "decision reaches into enrollment's internals";;
    oracle)       echo "a locked test is 'fixed' by editing it";;
    self-approve) echo "an authoring session writes its own review verdict";;
    unaccepted)   echo "work proceeds from a spec no human accepted";;
    *) return 1;;
  esac
}
caught_by() {
  case "$1" in
    boundary)     echo "Spring Modulith verify, in ModularityTests";;
    oracle)       echo "the test lock, in chain-check and the write guard";;
    self-approve) echo "the reviewer marker, in chain-check and the write guard";;
    unaccepted)   echo "the acceptance trailers, in chain-check";;
    *) return 1;;
  esac
}
expect_re() {
  case "$1" in
    boundary)     echo 'ModularityTests|non-exposed|must not depend|Module .decision';;
    oracle)       echo 'test lock:.*touches src/test';;
    self-approve) echo 'verdict lacks reviewer marker|lacks .Reviewed-By: bin/review.sh';;
    unaccepted)   echo 'lacks an Accepted-By trailer';;
  esac
}
# Signatures of gates this red diff must NOT trip. Breaking two things at once proves neither.
forbid_re() {
  case "$1" in
    boundary)     echo 'SpotBugs|spotless|Coverage|jacoco|Error Prone';;
    oracle)       echo 'Accepted-By|reviewer marker|Contract section';;
    self-approve) echo 'test lock|Accepted-By';;
    unaccepted)   echo 'test lock|reviewer marker';;
  esac
}
gate() {  # the gate that should catch it, run in the current tree
  case "$1" in
    boundary)     mvn -B -q clean test -Dtest=ModularityTests -Djacoco.skip=true 2>&1;;
    oracle)       bin/chain-check.sh PF-995 2>&1;;
    self-approve) bin/chain-check.sh PF-996 2>&1;;
    unaccepted)   bin/chain-check.sh PF-997 2>&1;;
  esac
}
guard_expect() {  # the guard layer, where the rule has one
  case "$1" in
    oracle)       echo 'tests are locked';;
    self-approve) echo 'written only by bin/review.sh';;
    *) return 1;;
  esac
}

# A red diff is the state the repository would be in if someone had got past the first layer, so
# these commits skip the pre-commit hook deliberately. That is the point: the guard is shown
# refusing the write, and then the chain check is shown catching it anyway. Two layers, proved one
# at a time. The hook is disabled for these commands only, through the environment, never by
# touching the repository's configuration.
NO_HOOKS="GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null"
commit_as() {
  env $NO_HOOKS git -c user.name='red diff' -c user.email=reddiff@forge.demo commit -q -m "$1"
}
accepted_commit() {  # what a human's acceptance would have written, so the red diff starts real
  env $NO_HOOKS git -c user.name='red diff' -c user.email=reddiff@forge.demo commit -q -m "$1" \
    --trailer "Accepted-By: Premanand Chandrasekaran (premanandc)"
}

build_oracle_chain() {
  mkdir -p "work/$ORACLE_TICKET" "$(dirname "$ORACLE_TEST")"
  printf '# %s: the oracle holds\n\n## Problem\nA locked test must outlive an inconvenient implementation.\n' \
    "$ORACLE_TICKET" >"work/$ORACLE_TICKET/intent.md"
  git add "work/$ORACLE_TICKET/intent.md"
  accepted_commit "intent: $ORACLE_TICKET the oracle holds"
  printf '# %s: the oracle holds\n\n## Contract\nModule: shared. No new types.\n' \
    "$ORACLE_TICKET" >"work/$ORACLE_TICKET/spec.md"
  git add "work/$ORACLE_TICKET/spec.md"
  accepted_commit "spec: $ORACLE_TICKET the oracle holds"
  cat >"$ORACLE_TEST" <<'JAVA'
package com.forge.demo.shared;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/** The locked oracle for PF-995. An implementer may not edit this to make a build go green. */
class RedOracleTests {

  @Test
  void theOracleHolds() {
    assertThat(new Npi("1234567893").value()).isEqualTo("1234567893");
  }
}
JAVA
  git add "$ORACLE_TEST"
  accepted_commit "tests: $ORACLE_TICKET the oracle holds"
}

apply_one() {  # runs in whatever tree it is called from
  case "$1" in
    boundary)
      mkdir -p src/main/java/com/forge/demo/decision/policy
      cat >src/main/java/com/forge/demo/decision/policy/EnrollmentPeek.java <<'JAVA'
package com.forge.demo.decision.policy;

import com.forge.demo.enrollment.model.Application;

/**
 * "Optimisation": read the enrollment aggregate directly instead of going through its API, to save
 * a query. It compiles, it reads harmlessly, and it breaks the module boundary the design rests on.
 */
final class EnrollmentPeek {

  private EnrollmentPeek() {}

  static boolean present(Application application) {
    return application != null;
  }
}
JAVA
      git add src/main/java/com/forge/demo/decision/policy/EnrollmentPeek.java
      commit_as "impl: PF-950 read the application directly to save a query";;
    oracle)
      build_oracle_chain
      printf '\n// relaxed so the build goes green\n' >>"$ORACLE_TEST"
      git add "$ORACLE_TEST"
      commit_as "impl: $ORACLE_TICKET adjust the test";;
    self-approve)
      mkdir -p work/PF-996
      cat >work/PF-996/review-verdict.json <<'JSON'
{
  "ticket": "PF-996",
  "disposition": "auto-pass",
  "summary": "Reviewed my own work; looks good.",
  "findings": []
}
JSON
      git add work/PF-996/review-verdict.json
      commit_as "review: PF-996 verdict auto-pass";;
    unaccepted)
      mkdir -p work/PF-997
      printf '# PF-997: a ticket nobody accepted\n\n## Problem\nThe acceptance step was skipped.\n' >work/PF-997/intent.md
      git add work/PF-997/intent.md
      commit_as "intent: PF-997 a ticket nobody accepted"
      printf '# PF-997: a ticket nobody accepted\n\n## Contract\nModule: screening. No new types.\n' >work/PF-997/spec.md
      git add work/PF-997/spec.md
      commit_as "spec: PF-997 a ticket nobody accepted";;
    *) return 1;;
  esac
}

guard_one() {  # ask the write guard, with the markers a live chain would have
  case "$1" in
    oracle)
      mkdir -p "work/$ORACLE_TICKET" work
      : >"work/$ORACLE_TICKET/.tests-locked"
      echo "$ORACLE_TICKET" >|work/.current-ticket
      bin/guard.sh --path "$ORACLE_TEST" 2>&1
      rm -f "work/$ORACLE_TICKET/.tests-locked" work/.current-ticket;;
    self-approve)
      bin/guard.sh --path work/PF-996/review-verdict.json 2>&1;;
    *) return 1;;
  esac
}

verify_one() {
  local name=$1 wt out bad gout rc=0
  breaks "$name" >/dev/null || { echo "reddiff: unknown red diff '$name'"; return 2; }
  wt=$(mktemp -d "${TMPDIR:-/tmp}/reddiff-$name.XXXXXX"); rmdir "$wt"
  git worktree add -q --detach "$wt" main 2>/dev/null || { echo "reddiff: could not create a worktree"; return 2; }
  cp -Rf bin/. "$wt/bin/" 2>/dev/null     # judge the harness in front of you, not the committed one
  echo "reddiff: $name — $(breaks "$name")"
  if ! ( cd "$wt" && bin/reddiff.sh --apply "$name" >/dev/null 2>&1 ); then
    echo "reddiff:   WRONG could not apply the change"
    git worktree remove --force "$wt" >/dev/null 2>&1; return 1
  fi
  if guard_expect "$name" >/dev/null 2>&1; then
    gout=$( cd "$wt" && bin/reddiff.sh --guard "$name" )
    if printf '%s' "$gout" | grep -q "$(guard_expect "$name")"; then
      echo "reddiff:   ok    the write guard refuses it before the commit"
    else
      echo "reddiff:   WRONG the write guard said nothing"; rc=1
    fi
  fi
  out=$( cd "$wt" && bin/reddiff.sh --gate "$name" )
  # Only the failing lines count. An earlier version read "ok  spec.md has a Contract section" as
  # evidence that the Contract gate had broken, which is the opposite of what that line says.
  bad=$(printf '%s\n' "$out" | grep -E 'FAIL|ERROR|BUILD FAILURE|Tests run.*Failures: [1-9]' || true)
  if printf '%s' "$bad" | grep -Eq "$(expect_re "$name")"; then
    echo "reddiff:   ok    caught by $(caught_by "$name")"
  else
    echo "reddiff:   WRONG not caught. The gate said:"
    printf '%s\n' "${bad:-$out}" | tail -6 | sed 's/^/reddiff:         /'; rc=1
  fi
  if printf '%s' "$bad" | grep -Eq "$(forbid_re "$name")"; then
    echo "reddiff:   WRONG it broke something else too, so it proves nothing:"
    printf '%s\n' "$bad" | grep -E "$(forbid_re "$name")" | head -3 | sed 's/^/reddiff:         /'; rc=1
  else
    echo "reddiff:   ok    and nothing else broke"
  fi
  git worktree remove --force "$wt" >/dev/null 2>&1; git worktree prune >/dev/null 2>&1
  return $rc
}

case "$CMD" in
  --apply) apply_one "$ARG"; exit $?;;
  --guard) guard_one "$ARG"; exit $?;;
  --gate)  gate "$ARG"; exit 0;;
  list)
    echo "Each of these breaks exactly one rule. 'bin/reddiff.sh verify --all' checks that the"
    echo "harness catches it for that reason, and that nothing else broke by accident."
    echo
    printf '%-14s %-50s %s\n' NAME BREAKS "CAUGHT BY"
    for n in $NAMES; do printf '%-14s %-50s %s\n' "$n" "$(breaks "$n")" "$(caught_by "$n")"; done
    ;;
  verify)
    FAIL=0
    if [ "$ARG" = "--all" ] || [ -z "$ARG" ]; then
      for n in $NAMES; do verify_one "$n" || FAIL=1; echo; done
    else
      verify_one "$ARG" || FAIL=1
    fi
    if [ "$FAIL" -eq 0 ]; then echo "reddiff: every red diff failed for its own reason and no other"
    else echo "reddiff: at least one red diff did not behave; see above"; fi
    exit $FAIL
    ;;
  branch|pr)
    [ -n "$ARG" ] || die "usage: bin/reddiff.sh $CMD <name>"
    breaks "$ARG" >/dev/null || die "unknown red diff '$ARG'"
    [ -z "$(git status --porcelain)" ] || die "working tree not clean"
    CUR=$(git branch --show-current)
    git branch -D "red/$ARG" >/dev/null 2>&1
    git switch -q -c "red/$ARG" main || die "could not create red/$ARG"
    apply_one "$ARG" || { git switch -q "$CUR"; die "could not apply $ARG"; }
    echo "reddiff: built red/$ARG ($(breaks "$ARG"))"
    if [ "$CMD" = pr ]; then
      git push -q -u origin "red/$ARG" --force-with-lease
      BODY="**Deliberately broken. Do not merge.** This pull request exists so the gates can be seen failing.

Breaks: $(breaks "$ARG").
Should be caught by: $(caught_by "$ARG").

\`bin/reddiff.sh verify $ARG\` checks that it fails for that reason and not for some other, which
is what makes it a proof rather than a mess."
      gh pr create --draft --head "red/$ARG" --base main --title "RED: $ARG (do not merge)" \
        --body "$BODY" --label red-diff >/dev/null 2>&1 \
        && echo "reddiff: pull request opened; Actions runs the gates against it"
    fi
    git switch -q "$CUR"
    ;;
  clean)
    for n in $NAMES; do git branch -D "red/$n" >/dev/null 2>&1 && echo "reddiff: deleted red/$n"; done
    git worktree prune
    ;;
  *) die "usage: bin/reddiff.sh list | verify [<name>|--all] | branch <name> | pr <name> | clean";;
esac
