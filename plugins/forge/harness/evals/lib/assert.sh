#!/usr/bin/env bash
# Assertion helpers for golden tasks. Sourced by evals/<agent>/<task>/assert.sh, which runs inside
# the scratch worktree after the candidate agent has finished. Every check is mechanical: files,
# sections, diffs, compile, test outcome, commit subjects. No LLM judging.
#
# Each helper prints "assert: ok <what>" or "assert: FAIL <what>" and records the failure; the
# task's assert.sh ends with `finish`, which exits 1 if anything failed. Compatible with bash 3.2.

ASSERT_FAILED=0
ok()   { echo "assert: ok    $*"; }
fail() { echo "assert: FAIL  $*"; ASSERT_FAILED=1; }
finish() {
  if [ "$ASSERT_FAILED" -eq 0 ]; then echo "assert: PASS"; exit 0; fi
  echo "assert: FAILED"; exit 1
}

# Files the candidate added or modified relative to the baseline commit (committed or not).
changed_files() {
  { git diff --name-only "$BASELINE"; git diff --name-only --cached "$BASELINE"; git ls-files --others --exclude-standard; } | sort -u
}

# assert_only_under <prefix>... : every changed file starts with one of the prefixes.
assert_only_under() {
  local bad=0 f p match
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    match=0
    for p in "$@"; do case "$f" in "$p"*) match=1;; esac; done
    if [ "$match" -eq 0 ]; then fail "changed file outside allowed paths: $f"; bad=1; fi
  done <<EOF
$(changed_files)
EOF
  [ "$bad" -eq 0 ] && ok "all changes under: $*"
}

# assert_none_under <prefix>... : no changed file starts with any of the prefixes.
assert_none_under() {
  local bad=0 f p
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    for p in "$@"; do case "$f" in "$p"*) fail "forbidden path changed: $f"; bad=1;; esac; done
  done <<EOF
$(changed_files)
EOF
  [ "$bad" -eq 0 ] && ok "nothing changed under: $*"
}

assert_file()      { [ -f "$1" ] && ok "file present: $1" || fail "file missing: $1"; }
assert_no_file()   { [ ! -e "$1" ] && ok "file absent: $1" || fail "file should not exist: $1"; }
assert_contains()  { grep -Eq -- "$2" "$1" 2>/dev/null && ok "$1 matches /$2/" || fail "$1 lacks /$2/"; }
assert_not_contains() { grep -Eq -- "$2" "$1" 2>/dev/null && fail "$1 must not match /$2/" || ok "$1 free of /$2/"; }

# assert_commit <regex> : some commit after BASELINE has a subject matching the regex.
assert_commit() {
  git log --format='%s' "$BASELINE"..HEAD | grep -Eq -- "$1" && ok "commit subject /$1/" || fail "no commit subject matching /$1/"
}
assert_no_commit() {
  git log --format='%s' "$BASELINE"..HEAD | grep -Eq -- "$1" && fail "unexpected commit subject /$1/" || ok "no commit subject /$1/"
}

# assert_test_compiles : test sources compile against production sources (the Contract holds).
# Always `clean`: the candidate has usually run Maven already, and the incremental compiler can
# report "up to date" and succeed without compiling anything.
assert_test_compiles() {
  if mvn -B -q clean test-compile -Dspotless.check.skip=true -Denforcer.skip=true >"$EVAL_OUT/test-compile.log" 2>&1; then
    ok "test sources compile"
  else fail "test sources do not compile (see test-compile.log)"; fi
}

# new_test_classes : fully qualified names of test classes added under src/test since BASELINE.
new_test_classes() {
  changed_files | grep -E '^src/test/java/.*Tests?\.java$' \
    | sed -E 's#^src/test/java/##; s#\.java$##; s#/#.#g'
}

# assert_new_tests_fail : the tests the candidate wrote run and fail (red before green).
assert_new_tests_fail() {
  local classes; classes=$(new_test_classes | paste -sd, -)
  if [ -z "$classes" ]; then fail "no new test classes under src/test"; return; fi
  if mvn -B -q test -Dtest="$classes" -Dsurefire.failIfNoSpecifiedTests=true -Djacoco.skip=true -Dspotless.check.skip=true -Denforcer.skip=true >"$EVAL_OUT/new-tests.log" 2>&1; then
    fail "new tests pass against the current code; tests-first means they must fail: $classes"
  else
    if grep -Eq "Tests run: [0-9]+, Failures: [1-9]|Tests run: [0-9]+, Failures: [0-9]+, Errors: [1-9]" "$EVAL_OUT/new-tests.log"; then
      ok "new tests fail red: $classes"
    else fail "new tests did not run to a failing result (see new-tests.log)"; fi
  fi
}

# assert_gate_green : the tier 1 gate passes.
assert_gate_green() {
  if mvn -B -q clean verify >"$EVAL_OUT/gate.log" 2>&1; then ok "mvn clean verify green"
  else fail "mvn clean verify failed (see gate.log)"; fi
}
