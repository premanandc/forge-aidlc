#!/usr/bin/env bash
# admit.sh <agent> [--selftest] [--task <name>]
# admit.sh --retire <agent> "<reason>"
#
# Eval-gated admission of a candidate agent into the fleet. For each golden task under
# evals/<agent>/, creates a throwaway git worktree at HEAD, overlays the task's fixture, runs the
# candidate headlessly with the task prompt, then runs the task's assert.sh. On 3/3 the definition
# moves from .claude/agents-candidates/ to .claude/agents/ and FLEET.md is re-rendered.
# Every run's transcript, assertion output and score land under evals/.runs/<agent>/<timestamp>/.
#
# An agent must be listed in .forge/fleet-catalog.json first: family, purpose, owner, ladder.
# No agent joins the fleet without a human accountable for it, so admission refuses a candidate
# the catalog does not name.
#
# --retire removes an admitted agent's definition, records the reason in the catalog's entry and
# in the log, and re-renders FLEET.md. The admissions history is never rewritten.
#
# Every commit this script makes names its paths (`git commit --only -- ...`), so an admission
# carries the fleet change and nothing else. An earlier version used a bare `git commit`, which
# swept up whatever happened to be staged in the caller's tree: commit 90afd97 says "re-render
# FLEET.md" and contains 67 unrelated files. A fleet commit that can quietly carry other work is
# not the audit record this harness claims to keep. (-m comes before --, or git reads the
# message as a pathspec.)
#
# --selftest runs no model. It proves the assertions bite: each task's assert.sh must FAIL on the
# bare fixture and, when the task ships an expected/ overlay, PASS with it applied.
#
# Worktrees are scratch: created under $TMPDIR, removed at the end of each task. Compatible with
# bash 3.2.
set -uo pipefail

AGENT=${1:-}
[ -z "$AGENT" ] && { echo "usage: bin/admit.sh <agent> [--selftest] [--task <name>] | bin/admit.sh --retire <agent> \"<reason>\"" >&2; exit 2; }

# Who authorised this change to the fleet. Which agents may act is the most consequential decision
# in the harness: it decides who writes the code that the rest of the gates then judge. It used to
# be recorded only as the git author of the commit, which is exactly the provenance that turned out
# to be wrong for twelve commits when a selftest rewrote this repository's identity.
#
# So a fleet change is a human act at a terminal, like accepting an artifact: bin/admit.sh will not
# admit, reject or retire an agent from an agent's shell, and the decision is signed with an
# Authorised-By trailer and named in evals/admissions.log. Re-rendering FLEET.md is exempt: it
# derives a file from records that already exist and grants nobody anything.
AUTHORISED_BY=""
authorise() {  # $1 = what is being decided, for the prompt
  local login name answer
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo "admit: changing the fleet is a human act at a terminal; stdin/stdout is not a TTY" >&2
    echo "admit: to $1, run bin/admit.sh yourself in a terminal" >&2
    exit 1
  fi
  login=$(gh api user --jq .login 2>/dev/null) || { echo "admit: gh api user failed; log in with gh auth login" >&2; exit 1; }
  name=$(git config user.name); [ -n "$name" ] || { echo "admit: git config user.name is empty" >&2; exit 1; }
  echo
  echo "admit: you are about to $1."
  echo "admit: you are $name ($login), and you will be recorded as having authorised it."
  printf 'admit: type your GitHub login to continue, anything else to abort: '
  read -r answer
  [ "$answer" = "$login" ] || { echo "admit: aborted; the fleet is unchanged" >&2; exit 1; }
  AUTHORISED_BY="$name ($login)"
}

if [ "$AGENT" = "--render" ]; then
  # Re-render FLEET.md from the catalog and the admissions log. The only way that file is written
  # outside an admission, so the guards' rule (bin/admit.sh alone writes the fleet) holds as
  # stated. Used when the catalog's families, purposes or the rendering itself change.
  ROOT=$(git rev-parse --show-toplevel); cd "$ROOT"
  WHY=${2:-}; [ -n "$WHY" ] || { echo "usage: bin/admit.sh --render \"<why>\"" >&2; exit 2; }
  bin/fleet-render.sh >|FLEET.md
  if git diff --quiet -- FLEET.md; then echo "admit: FLEET.md already matches its sources"; exit 0; fi
  FORGE_ADMIT=1 git commit -q -m "fleet: re-render FLEET.md

$WHY" --only -- FLEET.md && echo "admit: FLEET.md re-rendered; committed $(git rev-parse --short HEAD)"
  bin/fleet-check.sh | tail -1
  exit 0
fi

if [ "$AGENT" = "--amend" ]; then
  # Replace an admitted definition's text WITHOUT re-running its golden tasks.
  #
  # This is an escape hatch and it is shaped like the other one in this repo: a tests-amend commit
  # carries an Approved-By trailer, and an amendment carries a reason and is logged as `amended`
  # rather than `admitted`, so nobody reading the record can mistake it for a passing run. The
  # alternative, editing the installed file directly, leaves bin/fleet-check.sh failing until a
  # re-admission; the worse alternative, editing the file and the recorded hash together, makes the
  # check pass while the log claims a score the text never earned. That is forgery, and this script
  # will not do it.
  #
  # Use it for text that cannot change behaviour: a renamed command in prose, a typo, a stale path
  # in a comment. Anything that changes what the agent does needs bin/admit.sh and three fresh
  # runs, because the score is a claim about the text and this leaves the old score standing.
  ROOT=$(git rev-parse --show-toplevel); cd "$ROOT"
  AA=${2:-}; REASON=${3:-}
  [ -n "$AA" ] && [ -n "$REASON" ] || { echo "usage: bin/admit.sh --amend <agent> \"<reason>\"" >&2; exit 2; }
  [ -f ".claude/agents/$AA.md" ] || { echo "admit: $AA is not an admitted agent" >&2; exit 2; }
  CAND=".claude/agents-candidates/$AA.md"
  [ -f "$CAND" ] || { echo "admit: put the corrected text in $CAND first" >&2; exit 2; }
  if diff -q ".claude/agents/$AA.md" "$CAND" >/dev/null 2>&1; then
    echo "admit: $CAND is identical to the installed definition; nothing to amend"; exit 0
  fi
  echo "admit: amending $AA without re-running its golden tasks. The diff:"
  diff -u ".claude/agents/$AA.md" "$CAND" | sed 's/^/    /'
  CHANGED=$(diff ".claude/agents/$AA.md" "$CAND" | grep -c '^[<>]')
  WHO=$(git config user.name); [ -n "$WHO" ] || { echo "admit: git config user.name is empty" >&2; exit 1; }
  # Parenthesised like the admitted lines, so "by=" ends at a ")" and a multi-word name cannot run
  # into the reason that follows it. The first version of this line rendered as
  # "Chandrasekaran Rename /intent to ..." in FLEET.md.
  WHO="$WHO ($(git config user.email))"
  # A candidate is usually untracked, and naming an untracked path in a commit's pathspec fails
  # the whole commit rather than being ignored. Only mention it when git knows about it.
  CAND_PATHSPEC=""
  git ls-files --error-unmatch "$CAND" >/dev/null 2>&1 && CAND_PATHSPEC="$CAND"
  cp "$CAND" ".claude/agents/$AA.md"
  rm -f "$CAND"
  printf '%s  %s  -/-  amended  candidate=%s  model=-  by=%s %s\n' \
    "$(date -u +%Y%m%dT%H%M%SZ)" "$AA" "$(git hash-object ".claude/agents/$AA.md")" "$WHO" \
    "$REASON ($CHANGED changed lines; text only, golden tasks NOT re-run)" >>evals/admissions.log
  bin/fleet-render.sh >|FLEET.md
  FORGE_ADMIT=1 git commit -q -m "fleet: amend $AA without re-running its tasks

$REASON

$CHANGED changed lines. The golden tasks were not re-run, so the score in
FLEET.md still refers to the previous text. Recorded as 'amended' in
evals/admissions.log so the difference is visible." \
    --trailer "Amended-By: $WHO" --only -- ".claude/agents/$AA.md" $CAND_PATHSPEC FLEET.md evals/admissions.log \
    && echo "admit: $AA amended; committed $(git rev-parse --short HEAD)"
  echo "admit: NOTE the recorded score still describes the previous text. Re-admit when convenient."
  bin/fleet-check.sh | tail -1
  exit 0
fi

if [ "$AGENT" = "--check" ]; then
  # Everything that can be known about a candidate without deciding anything: is it there, is
  # somebody accountable for it, does it have enough golden tasks, and where does it stand today.
  # Commits nothing, needs no terminal, spends no model time, so a session can run it and hand the
  # human a decision that is already prepared. The decision itself stays theirs.
  ROOT=$(git rev-parse --show-toplevel); cd "$ROOT"
  CA=${2:-}; [ -n "$CA" ] || { echo "usage: bin/admit.sh --check <agent>" >&2; exit 2; }
  CAT=.forge/fleet-catalog.json
  READY=1
  say() { printf 'admit: %-4s %s\n' "$1" "$2"; }
  if [ -f ".claude/agents-candidates/$CA.md" ]; then
    say ok "candidate present: .claude/agents-candidates/$CA.md ($(grep -c '' ".claude/agents-candidates/$CA.md") lines)"
  else
    say no "no candidate at .claude/agents-candidates/$CA.md"; READY=0
  fi
  ENTRY=$(jq -c --arg a "$CA" '.agents[$a] // empty' "$CAT" 2>/dev/null)
  if [ -n "$ENTRY" ]; then
    FAM=$(printf '%s' "$ENTRY" | jq -r '.family // ""'); RUNG=$(printf '%s' "$ENTRY" | jq -r '.ladder // ""')
    OWN=$(jq -r --arg f "$FAM" '.families[$f].owner // ""' "$CAT")
    if [ -n "$FAM" ] && [ -n "$RUNG" ] && [ -n "$OWN" ]; then
      say ok "catalogued: $FAM family, $RUNG rung, owned by $OWN"
    else
      say no "catalog entry incomplete (family='$FAM' ladder='$RUNG' owner='$OWN')"; READY=0
    fi
  else
    say no "not in $CAT; a human adds family, purpose and ladder before it can be admitted"; READY=0
  fi
  TASKS=$(ls -d "evals/$CA"/*/ 2>/dev/null | while read -r d; do [ -f "$d/assert.sh" ] && echo "$d"; done | grep -c . )
  if [ "${TASKS:-0}" -ge 3 ]; then say ok "$TASKS golden tasks with assertions"
  else say no "${TASKS:-0} golden tasks with an assert.sh; three are required"; READY=0; fi
  if [ -f ".claude/agents/$CA.md" ]; then
    NOW=$(git hash-object ".claude/agents/$CA.md")
    WAS=$(grep -E "^[0-9TZ]+  $CA  [0-9]+/[0-9]+  admitted  candidate=" evals/admissions.log 2>/dev/null | tail -1 | sed -E 's/.*candidate=([0-9a-f]+).*/\1/')
    [ "$NOW" = "$WAS" ] && say ok "already admitted, definition unchanged since admission" \
                        || say note "already admitted, but the installed text has drifted"
    if [ -f ".claude/agents-candidates/$CA.md" ]; then
      if diff -q ".claude/agents/$CA.md" ".claude/agents-candidates/$CA.md" >/dev/null 2>&1; then
        say note "the candidate is identical to what is already admitted; nothing would change"
      else
        say note "re-admission would replace the installed definition ($(diff ".claude/agents/$CA.md" ".claude/agents-candidates/$CA.md" | grep -c '^[<>]') changed lines)"
      fi
    fi
  else
    say note "not currently in the fleet"
  fi
  echo
  if [ "$READY" -eq 1 ]; then
    echo "admit: ready. Prove the assertions bite, then decide, both in your terminal:"
    echo "    bin/admit.sh $CA --selftest"
    echo "    bin/admit.sh $CA"
    exit 0
  fi
  echo "admit: not ready; fix what is marked 'no' above first"
  exit 1
fi

if [ "$AGENT" = "--retire" ]; then
  ROOT=$(git rev-parse --show-toplevel); cd "$ROOT"
  RA=${2:-}; REASON=${3:-}
  [ -n "$RA" ] && [ -n "$REASON" ] || { echo "usage: bin/admit.sh --retire <agent> \"<reason>\"" >&2; exit 2; }
  [ -f ".claude/agents/$RA.md" ] || { echo "admit: $RA is not an admitted agent" >&2; exit 2; }
  jq -e --arg a "$RA" '.agents[$a]' .forge/fleet-catalog.json >/dev/null 2>&1 \
    || { echo "admit: $RA is not in .forge/fleet-catalog.json" >&2; exit 2; }
  jq -e --arg a "$RA" '.agents[$a].retired == true' .forge/fleet-catalog.json >/dev/null 2>&1 \
    || { echo "admit: mark $RA retired in .forge/fleet-catalog.json first (a human decides that)" >&2; exit 2; }
  authorise "retire the agent $RA, removing it from the fleet"
  RHASH=$(git hash-object ".claude/agents/$RA.md")   # the text being retired, same hash space as admissions
  git rm -q ".claude/agents/$RA.md"
  [ -d "evals/$RA" ] && git rm -rq "evals/$RA"
  printf '%s  %s  -/-  retired  candidate=%s  model=-  by=%s %s\n' "$(date -u +%Y%m%dT%H%M%SZ)" "$RA" "$RHASH" "$AUTHORISED_BY" "$REASON" >>evals/admissions.log
  bin/fleet-render.sh >|FLEET.md
  FORGE_ADMIT=1 git commit -q -m "fleet: retire $RA

$REASON" --trailer "Authorised-By: $AUTHORISED_BY" --only -- FLEET.md evals/admissions.log ".claude/agents/$RA.md" "evals/$RA" && echo "admit: $RA RETIRED; committed $(git rev-parse --short HEAD)"
  bin/fleet-check.sh | tail -1
  exit 0
fi
shift
SELFTEST=0; ONLY_TASK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) SELFTEST=1;;
    --task) ONLY_TASK=$2; shift;;
    *) echo "unknown option $1" >&2; exit 2;;
  esac
  shift
done

ROOT=$(git rev-parse --show-toplevel); cd "$ROOT"
export EVAL_LIB="$ROOT/evals/lib"
CANDIDATE=".claude/agents-candidates/$AGENT.md"
EVALS="evals/$AGENT"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
RUNS="$ROOT/evals/.runs/$AGENT/$STAMP"
mkdir -p "$RUNS"

[ -d "$EVALS" ] || { echo "admit: no golden tasks under $EVALS" >&2; exit 2; }
if [ "$SELFTEST" -eq 0 ] && [ ! -f "$CANDIDATE" ]; then
  echo "admit: no candidate definition at $CANDIDATE" >&2; exit 2
fi
# No agent joins the fleet without a family, a purpose, a rung and a human owner.
CATALOG=.forge/fleet-catalog.json
if [ "$SELFTEST" -eq 0 ]; then
  ENTRY=$(jq -c --arg a "$AGENT" '.agents[$a] // empty' "$CATALOG" 2>/dev/null)
  [ -n "$ENTRY" ] || { echo "admit: $AGENT is not in $CATALOG; a human adds it there (family, purpose, ladder) before it can be admitted" >&2; exit 2; }
  FAM=$(printf '%s' "$ENTRY" | jq -r '.family // empty')
  LADDER=$(printf '%s' "$ENTRY" | jq -r '.ladder // empty')
  OWNER=$(jq -r --arg f "$FAM" '.families[$f].owner // empty' "$CATALOG")
  [ -n "$FAM" ] && [ -n "$LADDER" ] && [ -n "$OWNER" ] \
    || { echo "admit: $AGENT's catalog entry needs a family with a known owner and a ladder rung (family='$FAM' ladder='$LADDER' owner='$OWNER')" >&2; exit 2; }
  echo "admit: $AGENT is $FAM family, $LADDER rung, owned by $OWNER"
  # Before the golden tasks, not after: a run that ends in a commit nobody may make has spent a
  # plan's worth of model time for nothing.
  authorise "put $AGENT through its golden tasks and, on a pass, admit it to the fleet"
fi

# run_candidate <worktree> <task-dir> <run-dir> : runs the candidate headlessly in the worktree.
# The headless invocation is isolated here so that CLI drift touches one function. Wired against
# code.claude.com/docs/en/headless.md and cli-reference.md as of 2026-09-19:
#   --agents '<json>' defines the candidate for this session only; --agent <name> runs the whole
#   session as it; hooks and CLAUDE.md load as in an interactive session; tool rules restrict paths.
# Returns 75 when the run was refused (rate limit, auth) so the caller does not score it.
run_candidate() {
  local wt=$1 task=$2 out=$3
  local prompt agents_json rc
  prompt=$(cat "$task/task.md")
  agents_json=$(python3 "$ROOT/bin/agent-json.py" "$ROOT/$CANDIDATE") || return 1
  ALLOWED_TOOLS=""; DISALLOWED_TOOLS=""
  [ -f "$ROOT/$EVALS/policy.sh" ] && . "$ROOT/$EVALS/policy.sh"
  (
    cd "$wt" && claude -p "$prompt" \
      --agents "$agents_json" --agent "$AGENT" \
      --output-format json \
      --max-turns "${ADMIT_MAX_TURNS:-80}" \
      --permission-mode acceptEdits \
      ${ALLOWED_TOOLS:+--allowedTools "$ALLOWED_TOOLS"} \
      ${DISALLOWED_TOOLS:+--disallowedTools "$DISALLOWED_TOOLS"} \
      >"$out/claude.json" 2>"$out/claude.stderr"
  )
  rc=$?
  python3 - "$out/claude.json" >"$out/claude-result.txt" 2>/dev/null <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"(no JSON result: {e})"); sys.exit(0)
print(d.get("result", ""))
print(f"\n--- is_error={d.get('is_error')} num_turns={d.get('num_turns')} duration_ms={d.get('duration_ms')} session_id={d.get('session_id')}")
PY
  # Which model(s) produced this run: part of the admission record, since the proof covers the
  # definition text under a given model.
  jq -r '(.modelUsage // {}) | keys | join("+")' "$out/claude.json" 2>/dev/null >"$out/model.txt" || true
  # A refusal means the run never happened: a transport, quota or auth failure. Read the envelope,
  # never the model's prose. This once grepped the result text for "authentication", so an
  # intent-drafter answer that correctly called authentication a non-goal was scored as a refusal
  # and the candidate was rejected 2/2 on two passes and a phantom (evals/admissions.log,
  # 20260919T194338Z). An agent must not be able to fail admission by writing about the right
  # subject.
  refusal_re="rate.?limit|usage limit|overloaded|quota|not logged in|authentication_error|invalid_api_key|invalid api key|credit balance|Connection error|ECONNRESET"
  if grep -qiE "$refusal_re" "$out/claude.stderr" 2>/dev/null; then return 75; fi
  if [ ! -s "$out/claude.json" ]; then return 75; fi
  # No -q on the second grep: a model result can be long, and -q exits on the first match, leaving
  # jq writing into a closed pipe. Under pipefail the pipeline then reports 141 and the run reads
  # as "not a refusal", so a rate-limited or unauthenticated run would be scored against the
  # candidate instead of reported. A refusal must never cost an agent its admission.
  if [ "$(jq -r '.is_error // false' "$out/claude.json" 2>/dev/null)" = "true" ] \
     && jq -r '.result // ""' "$out/claude.json" 2>/dev/null | grep -iE "$refusal_re" >/dev/null; then
    return 75
  fi
  [ "$rc" -ne 0 ] && echo "admit: claude exited $rc (assertions still decide)" >>"$out/claude.stderr"
  return 0
}

# apply_overlay <worktree> <dir> : copies a fixture or expected overlay into the worktree
# (shell scripts in the overlay root are helpers, not fixture files).
apply_overlay() {
  local wt=$1 dir=$2
  [ -d "$dir" ] || return 0
  (cd "$dir" && find . -type f ! -name '*.sh' | while IFS= read -r f; do
    mkdir -p "$wt/$(dirname "$f")"; cp "$f" "$wt/$f"; done)
}

# prepare_worktree <worktree> <task-dir> <ticket> : shared overlay, task fixture, current ticket,
# then the task's fixture.sh (which builds chain history the candidate should find in place).
prepare_worktree() {
  local wt=$1 task=$2 ticket=$3
  apply_overlay "$wt" "$ROOT/$EVALS/common"
  apply_overlay "$wt" "$task/fixture"
  [ -n "$ticket" ] && mkdir -p "$wt/work" && echo "$ticket" >"$wt/work/.current-ticket"
  if [ -f "$task/fixture.sh" ]; then
    ( cd "$wt" && EVAL_ROOT="$ROOT" EVAL_TASK_DIR="$task" bash "$task/fixture.sh" ) >"$EVAL_OUT/fixture.log" 2>&1 \
      || { echo "admit: fixture.sh failed for $(basename "$task") (see $EVAL_OUT/fixture.log)"; return 1; }
  fi
}

ticket_of() {  # $1 = task dir ; the ticket id its fixture declares, if any
  ls "$1/fixture/work" 2>/dev/null | grep -E '^PF-[0-9]+$' | sed -n 1p
}

PASS=0; FAIL=0; SUMMARY=""
for TASK_DIR in "$EVALS"/*/; do
  TASK=$(basename "$TASK_DIR")
  [ -n "$ONLY_TASK" ] && [ "$TASK" != "$ONLY_TASK" ] && continue
  [ "$TASK" = "common" ] && continue
  [ -f "$TASK_DIR/assert.sh" ] || { echo "admit: $TASK has no assert.sh, skipping"; continue; }
  OUT="$RUNS/$TASK"; mkdir -p "$OUT"; export EVAL_OUT="$OUT"
  WT=$(mktemp -d "${TMPDIR:-/tmp}/admit-$AGENT-$TASK.XXXXXX")
  rmdir "$WT"
  git worktree add --detach -q "$WT" HEAD
  TICKET=$(ticket_of "$TASK_DIR")

  run_task() {  # $1 = label ; runs assert.sh in the worktree, returns its exit code
    ( cd "$WT" && bash "$ROOT/$TASK_DIR/assert.sh" ) >"$OUT/assert-$1.log" 2>&1
  }

  # Fixture first, baseline second: assertions judge only what the candidate did, not the chain
  # history the fixture laid down for it.
  prepare_worktree "$WT" "$ROOT/$TASK_DIR" "$TICKET" || { FAIL=$((FAIL+1)); SUMMARY="$SUMMARY $TASK=fixture-error"; git worktree remove --force "$WT" >/dev/null 2>&1; continue; }
  export BASELINE; BASELINE=$(git -C "$WT" rev-parse HEAD)

  if [ "$SELFTEST" -eq 1 ]; then
    if run_task bare; then echo "admit: $TASK  WRONG  assertions pass on the bare fixture"; FAIL=$((FAIL+1))
    else echo "admit: $TASK  ok     assertions fail on the bare fixture"; PASS=$((PASS+1)); fi
    if [ -d "$ROOT/$TASK_DIR/expected" ]; then
      apply_overlay "$WT" "$ROOT/$TASK_DIR/expected"
      ( cd "$WT" && [ -f "$ROOT/$TASK_DIR/expected.sh" ] && bash "$ROOT/$TASK_DIR/expected.sh" ) >"$OUT/expected-setup.log" 2>&1 || true
      if run_task expected; then echo "admit: $TASK  ok     assertions pass with expected/ applied"; PASS=$((PASS+1))
      else echo "admit: $TASK  WRONG  assertions fail with expected/ applied (see $OUT/assert-expected.log)"; FAIL=$((FAIL+1)); fi
    fi
  else
    START=$(date +%s)
    if run_candidate "$WT" "$ROOT/$TASK_DIR" "$OUT"; then RUN_RC=0; else RUN_RC=$?; fi
    ELAPSED=$(( $(date +%s) - START ))
    m=$(cat "$OUT/model.txt" 2>/dev/null); [ -n "$m" ] && MODELS="${MODELS:-}${MODELS:+,}$m"
    if [ "$RUN_RC" -eq 75 ]; then
      echo "admit: $TASK  REFUSED  the run was rate limited or refused; not counted against the candidate"
      SUMMARY="$SUMMARY $TASK=refused"
    elif run_task result; then
      echo "admit: $TASK  PASS  (${ELAPSED}s)"; PASS=$((PASS+1)); SUMMARY="$SUMMARY $TASK=pass"
    else
      echo "admit: $TASK  FAIL  (${ELAPSED}s)  first failure: $(grep -m1 'assert: FAIL' "$OUT/assert-result.log" | sed 's/assert: FAIL *//')"
      FAIL=$((FAIL+1)); SUMMARY="$SUMMARY $TASK=fail"
    fi
  fi

  git worktree remove --force "$WT" >/dev/null 2>&1 || rm -rf "$WT"
done
git worktree prune

TOTAL=$((PASS+FAIL))
echo "admit: $AGENT  $PASS/$TOTAL passed  (runs in $RUNS)"
if [ "$SELFTEST" -eq 1 ]; then [ "$FAIL" -eq 0 ]; exit $?; fi

# Every real run is on the record, admitted or not: the demo shows a rejection before a success.
# The record names the candidate's content hash and the model(s) the run used; fleet-check
# compares the hash, and a model change is visible in the log.
OUTCOME=$([ "$FAIL" -eq 0 ] && [ "$PASS" -ge 3 ] && echo admitted || echo rejected)
MODEL_LIST=$(printf '%s' "${MODELS:-unknown}" | tr ',' '\n' | sort -u | paste -sd, -)
printf '%s  %s  %s/%s  %s  candidate=%s  model=%s  by=%s %s\n' "$STAMP" "$AGENT" "$PASS" "$TOTAL" "$OUTCOME" \
  "$(git hash-object "$CANDIDATE")" "$MODEL_LIST" "$AUTHORISED_BY" "$SUMMARY" >>evals/admissions.log

# The admission (or rejection) commit is made here, under the marker the guards require, so no
# later commit can carry an unmarked fleet change by accident.
if [ "$OUTCOME" = admitted ]; then
  mkdir -p .claude/agents
  git mv -f "$CANDIDATE" ".claude/agents/$AGENT.md" 2>/dev/null || mv "$CANDIDATE" ".claude/agents/$AGENT.md"
  bin/fleet-render.sh >|FLEET.md
  FORGE_ADMIT=1 git commit -q -m "fleet: admit $AGENT ($PASS/$TOTAL)

Family: $FAM, $LADDER rung, owned by $OWNER
Golden tasks:$SUMMARY
Model: $MODEL_LIST
Runs: evals/.runs/$AGENT/$STAMP" \
    --trailer "Authorised-By: $AUTHORISED_BY" \
    --only -- ".claude/agents/$AGENT.md" "$CANDIDATE" FLEET.md evals/admissions.log \
    && echo "admit: $AGENT ADMITTED -> .claude/agents/$AGENT.md; committed $(git rev-parse --short HEAD)" \
    || echo "admit: $AGENT ADMITTED but the commit failed; fleet files are staged"
  bin/fleet-check.sh | tail -1
  exit 0
fi
FORGE_ADMIT=1 git commit -q -m "fleet: reject $AGENT ($PASS/$TOTAL)

Golden tasks:$SUMMARY
Model: $MODEL_LIST
Runs: evals/.runs/$AGENT/$STAMP" \
  --trailer "Authorised-By: $AUTHORISED_BY" \
  --only -- evals/admissions.log \
  && echo "admit: $AGENT NOT ADMITTED; rejection committed $(git rev-parse --short HEAD)" \
  || echo "admit: $AGENT NOT ADMITTED; rejection is staged but the commit failed"
exit 1
