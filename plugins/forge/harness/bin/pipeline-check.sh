#!/usr/bin/env bash
# pipeline-check.sh: refuse a pipe from a producer with no small ceiling into a reader that stops
# early.
#
# `producer | grep -q` exits on the first match. The producer is still writing, gets SIGPIPE, and
# under `set -o pipefail` the pipeline reports 141. Every caller in this harness then reads 141 as
# the negative answer, and the negative answer is always the permissive one: a stage that was
# committed reads as missing, a commit that touched src/test reads as clean, a refused model run
# reads as one worth scoring.
#
# It has now happened four times. Twice the fix was a comment above the line, and the comment did
# not stop the next two, because a rule nobody re-reads is not a rule. So it is mechanical now, in
# the same spirit as every other check here: the harness's own source is code, and code is tested.
#
# What it flags: a line where a producer whose output has no small ceiling feeds a pipeline that
# contains a reader which stops early.
#
# What it does not flag, deliberately, because a guard that blocks too much is as broken as one
# that blocks too little:
#   - grep on a file. There is no pipe and nothing to close.
#   - a producer whose whole output fits in the pipe buffer, such as one commit's trailers or a
#     single subject line. It finishes writing before the reader can exit, every time.
#
# A line that is genuinely fine carries `# pipeline-ok: <why>` and is skipped, so an exception has
# to be argued in the diff rather than left silent.
#
#   bin/pipeline-check.sh             scan bin/ and hooks/
#   bin/pipeline-check.sh --selftest  prove it catches the four real bugs and spares the safe shapes
#
# Compatible with bash 3.2.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd); cd "$ROOT"

# Producers with no small ceiling: a repository's history, a commit's file list, a model's answer,
# a directory, a search. Not `echo` or `printf` of a variable, which is where most of this
# harness's greps get their input and why they are safe.
PRODUCER='(git[[:space:]]+[a-z-]*(log|diff|diff-tree|rev-list|show|ls-files|ls-tree|for-each-ref|blame)|jq[[:space:]]|ls[[:space:]]|find[[:space:]]|cat[[:space:]]|seq[[:space:]]|curl[[:space:]]|gh[[:space:]])'
# Readers that stop before end of input.
READER='(grep[[:space:]]+-[a-zA-Z]*q|head([[:space:]]|$)|awk[^|]*exit|sed[[:space:]]+-n[^|]*[0-9]q)'

scan() {  # $1.. = files ; prints one finding per line, returns 1 if any
  local found=0 f n line
  for f in "$@"; do
    [ -f "$f" ] || continue
    n=0; ok_next=0
    while IFS= read -r line; do
      n=$((n + 1))
      bare=${line#"${line%%[![:space:]]*}"}     # the line without its indentation
      is_comment=0; case "$bare" in \#*) is_comment=1;; esac
      # The exception marker may sit on the line itself or on a comment above it, because the
      # lines worth excusing are usually already long. Either way it carries a reason.
      case "$line" in *"# pipeline-ok:"*) ok_next=1;; esac
      [ "$is_comment" -eq 1 ] && continue       # a comment describing the bug is not the bug
      if [ "$ok_next" -eq 1 ]; then ok_next=0; continue; fi
      printf '%s' "$line" | grep -Eq "$PRODUCER" || continue
      printf '%s' "$line" | grep -Eq "\|" || continue
      printf '%s' "$line" | grep -Eq "$PRODUCER.*\|.*$READER" || continue
      echo "pipeline-check: $f:$n reader stops early on a producer with no ceiling"
      echo "pipeline-check:     $(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-110)"
      found=1
    done <"$f"
  done
  return $found
}

if [ "${1:-}" = "--selftest" ]; then
  # The four real bugs, and the shapes that must not be flagged. Written as text rather than run,
  # because running them is what the fix prevents.
  T=$(mktemp -d "${TMPDIR:-/tmp}/pipelineself.XXXXXX"); trap 'rm -rf "$T"' EXIT
  cat >"$T/bad.sh" <<'BAD'
has_commit() { git log --format=%s | grep -Eq "^$1:"; }
if git diff-tree --no-commit-id --name-only -r "$c" | grep -q '^src/test/'; then :; fi
jq -r '.result // ""' "$out/claude.json" | grep -qiE "$refusal_re"
FIRST=$(git log --reverse --format=%H --grep="^impl:" | head -1)
BAD
  cat >"$T/good.sh" <<'GOOD'
has_commit() { git log --format=%s | grep -E "^$1:" >/dev/null; }
grep -Eq '^## Contract' "$W/spec.md" || die "no Contract"
trailer_of "$1" Accepted-By | grep -Eq '^.+ \(.+\)$'
echo "$subj" | grep -Eq "^tests-amend:"
printf '%s' "$c" | grep -Eq 'core\.hooksPath'
# git log --format=%s | grep -q something   (a comment about the bug, not the bug)
git log --format=%H | head -1   # pipeline-ok: caller ignores the status and wants the value only
GOOD
  BAD_HITS=$(scan "$T/bad.sh" | grep -c 'reader stops early')
  GOOD_HITS=$(scan "$T/good.sh" | grep -c 'reader stops early')
  rc=0
  if [ "$BAD_HITS" -eq 4 ]; then echo "pipeline-check: ok    catches all 4 known-bad shapes"
  else echo "pipeline-check: WRONG caught $BAD_HITS of 4 known-bad shapes"; rc=1; fi
  if [ "$GOOD_HITS" -eq 0 ]; then echo "pipeline-check: ok    spares all 7 safe shapes"
  else echo "pipeline-check: WRONG flagged $GOOD_HITS safe shapes"; scan "$T/good.sh"; rc=1; fi
  exit $rc
fi

# This script is left out of its own scan. Its --selftest fixtures are the four real bugs written
# out verbatim, so scanning itself reports them every time; they are the test, not the defect. It
# is covered by `bin/pipeline-check.sh --selftest` instead, which is the stronger check anyway
# because it proves what the scanner catches rather than what it happens not to contain.
FILES=$(ls bin/*.sh bin/hooks/*.sh hooks/pre-commit 2>/dev/null | grep -v '^bin/pipeline-check\.sh$')
# shellcheck disable=SC2086
OUT=$(scan $FILES)
if [ -n "$OUT" ]; then
  printf '%s\n' "$OUT"
  echo "pipeline-check: FAIL  $(printf '%s' "$OUT" | grep -c 'reader stops early') pipeline(s) that would read SIGPIPE as an answer"
  echo "pipeline-check:       let the reader run to the end (drop -q, use 'sed -n 1p' for a first line),"
  echo "pipeline-check:       or mark the line '# pipeline-ok: <why>' if the producer really is bounded."
  exit 1
fi
echo "pipeline-check: PASS  $(printf '%s\n' "$FILES" | grep -c .) scripts, no reader stops early on an unbounded producer"
