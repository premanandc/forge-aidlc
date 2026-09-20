#!/usr/bin/env bash
# Builds throwaway repositories with one good and several bad histories and asserts
# that bin/chain-check.sh passes or fails each one as intended. Never touches this repo.
# The scratch repositories carry no .forge/policy.json, so bin/policy.sh applies its built-in
# defaults (tests acceptance required, architecture review by risk, default risk medium); the
# scenarios that need a different policy write work/<T>/policy.json or ticket.json.
set -euo pipefail

CHECK="$(cd "$(dirname "$0")" && pwd)/chain-check.sh"
T=PF-999
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/chain-selftest.XXXXXX")
trap 'rm -rf "$SCRATCH"' EXIT
PASSED=0; FAILED=0
ACCEPT="Accepted-By: selftest human (selftest)"

new_repo() {  # $1 = name ; cds into a fresh repo
  local d="$SCRATCH/$1"; mkdir -p "$d"; cd "$d"
  git init -q -b main .
  # Safe here, unlike in the other selftests: this is a standalone repository created by git init
  # above, with its own .git/config. A linked worktree would share the real repository's config,
  # and configuring an identity in one rewrote this project's for eleven commits.
  git config user.email selftest@example.com; git config user.name selftest
  git config commit.gpgsign false
  mkdir -p "work/$T" src/main/java src/test/java
  echo "# seed" > README.md; git add -A; git commit -q -m "chore: seed"
}
commit() {  # $1 = subject, $2 = optional body (trailers go here)
  git add -A
  if [ -n "${2:-}" ]; then git commit -q --allow-empty -m "$1" -m "$2"; else git commit -q --allow-empty -m "$1"; fi
}
intent()   { echo "# Intent" > "work/$T/intent.md"; commit "intent: $T why" "$ACCEPT"; }
intent_unaccepted() { echo "# Intent" > "work/$T/intent.md"; commit "intent: $T why"; }
spec()     { printf '# Spec\n\n## Contract\nmodule: screening\n' > "work/$T/spec.md"; commit "spec: $T what" "$ACCEPT"; }
spec_unaccepted() { printf '# Spec\n\n## Contract\nmodule: screening\n' > "work/$T/spec.md"; commit "spec: $T what"; }
spec_nocontract() { printf '# Spec\n\nno contract here\n' > "work/$T/spec.md"; commit "spec: $T what" "$ACCEPT"; }
spec_events() { printf '# Spec\n\n## Contract\nmodule: screening\npublishes shared.events.ScreeningCompleted\n' > "work/$T/spec.md"; commit "spec: $T what" "$ACCEPT"; }
tests()    { echo "class T {}" > src/test/java/T.java; commit "tests: $T failing tests" "$ACCEPT"; }
tests_unaccepted() { echo "class T {}" > src/test/java/T.java; commit "tests: $T failing tests"; }
plan()     { printf '# Plan\n\n## Steps\n1.\n\n## Boundary review\nfits.\n' > "work/$T/plan.md"; commit "plan: $T how" "Reviewed-By: architect"; }
plan_notrailer() { printf '# Plan\n\n## Boundary review\nfits.\n' > "work/$T/plan.md"; commit "plan: $T how"; }
plan_skipped() { printf '# Plan\n\n## Steps\n1.\n\n## Boundary review\nSkipped by policy.\n' > "work/$T/plan.md"; commit "plan: $T how" "Architecture-Review: skipped (policy)"; }
impl()     { echo "class M {}" > src/main/java/M.java; commit "impl: $T make green"; }
verdict()  {
  printf '{"disposition":"auto-pass","findings":[],"reviewer":{"tool":"bin/review.sh","session":"abc"}}\n' > "work/$T/review-verdict.json"
  commit "review: $T verdict" "Reviewed-By: bin/review.sh"
}
verdict_forged() {
  printf '{"disposition":"auto-pass","findings":[]}\n' > "work/$T/review-verdict.json"
  commit "review: $T verdict"
}
evidence() {
  printf '{"ticket":"%s","gates":{"tier1":{"status":"pass"},"tier2":{"status":"pass"}},"review":{"disposition":"auto-pass"}}\n' "$T" > "work/$T/evidence.json"
  commit "evidence: $T pack"
}
ticket_policy() { printf '%s\n' "$1" > "work/$T/policy.json"; }   # human-written, committed with intent
ticket_risk()   { printf '{"ticket":"%s","risk":"%s"}\n' "$T" "$1" > "work/$T/ticket.json"; }

expect() {  # $1 = pass|fail, $2 = name, rest = chain-check args
  local want=$1 name=$2; shift 2
  local out rc=0
  out=$("$CHECK" "$@" 2>&1) || rc=$?
  if { [ "$want" = pass ] && [ $rc -eq 0 ]; } || { [ "$want" = fail ] && [ $rc -eq 1 ]; }; then
    echo "selftest: ok    $name (expected $want, rc=$rc)"; PASSED=$((PASSED+1))
  else
    echo "selftest: WRONG $name (expected $want, rc=$rc)"; echo "$out" | sed 's/^/    /'; FAILED=$((FAILED+1))
  fi
}

# 1. good history, complete
new_repo good; intent; spec; tests; plan; impl; verdict; evidence
expect pass "good complete chain" "$T" --complete

# 2. good history mid-ticket (no evidence yet), partial mode
new_repo partial; intent; spec; tests; plan; impl
expect pass "partial chain through impl" "$T"
expect fail "partial chain rejected by --complete" "$T" --complete

# 3. impl before tests
new_repo impl-first; intent; spec; impl; tests; plan
expect fail "impl before tests" "$T"

# 4. test edited after lock without tests-amend
new_repo oracle; intent; spec; tests; plan
echo "class T { void softened() {} }" > src/test/java/T.java; commit "impl: $T fix test"
expect fail "src/test edited after lock" "$T"

# 5. tests-amend without approval fails, with approval passes
new_repo amend; intent; spec; tests; plan
echo "class T { void amended() {} }" > src/test/java/T.java; commit "tests-amend: $T clarify"
expect fail "tests-amend without Approved-By" "$T"
new_repo amend-ok; intent; spec; tests; plan
echo "class T { void amended() {} }" > src/test/java/T.java; commit "tests-amend: $T clarify" "Approved-By: human@example.com"
expect pass "tests-amend with Approved-By" "$T"

# 6. spec without Contract
new_repo nocontract; intent; spec_nocontract; tests
expect fail "spec.md without Contract" "$T"

# 7. plan without Reviewed-By trailer
new_repo notrailer; intent; spec; tests; plan_notrailer
expect fail "plan without Reviewed-By: architect" "$T"

# 8. forged verdict
new_repo forged; intent; spec; tests; plan; impl; verdict_forged; evidence
expect fail "hand-crafted verdict without reviewer marker" "$T" --complete

# 9. human acceptance: intent and spec are non-negotiable
new_repo unaccepted-intent; intent_unaccepted
expect fail "intent without Accepted-By" "$T"
new_repo unaccepted-spec; intent; spec_unaccepted; tests
expect fail "tests after a spec nobody accepted" "$T"
new_repo relax-intent; ticket_policy '{"humanAcceptance":{"intent":"optional","spec":"optional"}}'; intent_unaccepted; spec_unaccepted
expect fail "ticket policy cannot relax intent/spec acceptance" "$T"

# 10. tests acceptance: required by default, relaxable by risk
new_repo unaccepted-tests; intent; spec; tests_unaccepted; plan; impl
expect fail "impl after tests nobody accepted (policy required)" "$T"
new_repo byrisk-low; ticket_policy '{"humanAcceptance":{"tests":"by-risk"}}'; ticket_risk low; intent; spec; tests_unaccepted; plan; impl
expect pass "unaccepted tests allowed: tests by-risk, risk low" "$T"
new_repo byrisk-high; ticket_policy '{"humanAcceptance":{"tests":"by-risk"}}'; ticket_risk high; intent; spec; tests_unaccepted
expect fail "unaccepted tests refused: tests by-risk, risk high" "$T"

# 11. grandfathered ticket: no trailers anywhere, waiver printed
new_repo grandfathered; ticket_policy '{"grandfathered":{"reason":"predates the acceptance gate","by":"selftest"}}'
intent_unaccepted; spec_unaccepted; tests_unaccepted; plan; impl; verdict; evidence
expect pass "grandfathered chain without acceptance trailers" "$T" --complete

# 12. architecture review by policy
new_repo skip-medium; intent; spec; tests; plan_skipped; impl
expect pass "boundary review skipped: by-risk, medium, single module" "$T"
new_repo skip-required; ticket_policy '{"architectureReview":"required"}'; intent; spec; tests; plan_skipped
expect fail "boundary review skipped under architectureReview=required" "$T"
new_repo skip-high; ticket_risk high; intent; spec; tests; plan_skipped
expect fail "boundary review skipped at risk high" "$T"
new_repo skip-events; intent; spec_events; tests; plan_skipped
expect fail "boundary review skipped when the Contract names an event" "$T"

# 13. presence: a later stage implies the earlier ones
new_repo no-intent; spec; tests
expect fail "tests without an intent commit" "$T"

echo "selftest: $PASSED ok, $FAILED wrong"
[ "$FAILED" -eq 0 ]
