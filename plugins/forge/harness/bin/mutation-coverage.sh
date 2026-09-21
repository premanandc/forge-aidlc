#!/usr/bin/env bash
# mutation-coverage.sh <TICKET>
#
# Did mutation testing touch the code this ticket actually wrote?
#
# PF-103 came out of tier 2 with a mutation score of 81.25% against a threshold of 75, and the
# number described no line the ticket had written. PIT mutates the pure-logic classes and excludes
# the model, command, query and api packages, because those are reached only through Spring-context
# tests that would be re-run per mutant. Every class PF-103 added lives in model or command. So the
# score passed honestly and proved nothing, and nothing in the evidence pack said so.
#
# A number that looks like evidence and is not is worse than no number. This prints which of the
# ticket's own classes were mutated and which were not, so the evidence can say which it is.
#
# Reads target/pit-reports/mutations.xml, so run it after `mvn verify -Pfull-quality`.
# Exit 0 always: this reports, it does not gate. Whether an uncovered class is acceptable is a
# judgement about the ticket, and the release-manager and the human make it with this in hand.
# Compatible with bash 3.2.
set -uo pipefail
TICKET=${1:-}
[ -n "$TICKET" ] || { echo "usage: bin/mutation-coverage.sh <TICKET>" >&2; exit 2; }
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd); cd "$ROOT"
REPORT=target/pit-reports/mutations.xml

# The ticket's own production classes: the paths its impl commits touched, still present, under
# src/main/java. Deleted files are not classes any more, and a merge from main brings files the
# ticket never wrote, so the commits decide rather than the diff range.
IMPL=$(git log --reverse --format=%H --grep="^impl: $TICKET")
[ -n "$IMPL" ] || { echo "mutation-coverage: no impl: commits for $TICKET" >&2; exit 2; }
CHANGED=$(for c in $IMPL; do git diff-tree --no-commit-id --name-only -r "$c"; done \
  | sort -u | grep '^src/main/java/.*\.java$' || true)

CLASSES=""
for f in $CHANGED; do
  [ -f "$f" ] || continue                       # deleted by the ticket; nothing left to mutate
  case "$(basename "$f")" in package-info.java) continue;; esac
  CLASSES="$CLASSES $(printf '%s' "${f#src/main/java/}" | sed 's/\.java$//; s#/#.#g')"
done
CLASSES=$(printf '%s\n' $CLASSES | grep -v '^$' | sort -u || true)

if [ -z "$CLASSES" ]; then
  echo "mutation-coverage: $TICKET changed no production classes that survive; nothing to mutate"
  exit 0
fi
if [ ! -f "$REPORT" ]; then
  echo "mutation-coverage: $REPORT is missing; run 'mvn verify -Pfull-quality' first" >&2
  echo "mutation-coverage: $TICKET has $(printf '%s\n' "$CLASSES" | grep -c .) production class(es) to account for"
  exit 0
fi

MUTATED=$(grep -o '<mutatedClass>[^<]*' "$REPORT" | sed 's/<mutatedClass>//' | sort -u)
COVERED=0; UNCOVERED=0
echo "mutation-coverage: $TICKET, against $REPORT"
for c in $CLASSES; do
  n=$(printf '%s\n' "$MUTATED" | grep -cx "$c" || true)
  if [ "${n:-0}" -gt 0 ]; then
    k=$(grep -c "<mutatedClass>$c</mutatedClass>" "$REPORT" || true)
    echo "  mutated      $c ($k mutant(s))"; COVERED=$((COVERED+1))
  else
    echo "  NOT mutated  $c"; UNCOVERED=$((UNCOVERED+1))
  fi
done
TOTAL=$((COVERED+UNCOVERED))
echo "mutation-coverage: $COVERED of $TOTAL class(es) this ticket wrote were mutated"
if [ "$COVERED" -eq 0 ]; then
  echo "mutation-coverage: the suite's mutation score says nothing about $TICKET. Every class it"
  echo "mutation-coverage: wrote sits in a package PIT excludes (model, command, query, api), so"
  echo "mutation-coverage: report the score as pre-existing coverage, not as evidence for this work."
fi
exit 0
