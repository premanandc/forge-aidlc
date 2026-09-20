#!/usr/bin/env bash
# guard.sh: the repo's write guards, shared by the git pre-commit hook and the Claude Code
# PreToolUse hooks so every layer enforces the same rules from the same file-based signals.
#
#   bin/guard.sh --path <file> [<file>...]   check paths about to be written (PreToolUse Edit|Write)
#   bin/guard.sh --command "<shell>"         check a shell command about to run (PreToolUse Bash)
#   bin/guard.sh --staged                    check the files staged for commit (pre-commit)
#
# Exit codes: 0 allow, 1 block, 3 needs human confirmation (pom.xml dependency edit).
# Reasons go to stdout, one per line, prefixed "guard:".
#
# Signals (all plain files, all created by the fleet or the human):
#   work/.current-ticket                  active ticket id
#   work/<T>/.role-<name>                 session role marker (implementer, test-designer, ...)
#   work/<T>/.drafting-<stage>            an agent is drafting intent|spec|tests. While one exists
#                                         no commit or push may happen at all. /forge:intent, /forge:spec and
#                                         /forge:tests create them; only bin/accept.sh (a human at a
#                                         terminal) removes one, which is what acceptance is.
#   work/<T>/.tests-locked                created by bin/accept.sh when a human accepts the tests
#   work/<T>/.tests-amend-approved        created by the human to open a tests-amend flow
#   work/.pom-approved                    created by the human to approve a pom.xml dependency edit
#   FORGE_REVIEWER=1 (environment)        set only by bin/review.sh, the sole writer of verdicts
#   FORGE_ADMIT=1 (environment)           set only by bin/admit.sh, the sole writer of the fleet
#
# Policy (.forge/policy.json, work/<T>/policy.json) is edited by humans in an editor and committed
# from a terminal; agents never write it and no marker opens it. Compatible with bash 3.2.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT"
MODE=${1:-}
shift || true

TICKET=""
[ -f work/.current-ticket ] && TICKET=$(tr -d '[:space:]' < work/.current-ticket)
# A chain is in flight when a ticket is active (work/.current-ticket, set by /forge:intent and
# bin/ticket.sh), a fleet role has announced itself (work/<T>/.role-<name>), or an artifact is
# being drafted. The signal rules below exist to protect that chain, so they apply exactly then.
# Outside one, a human maintaining the harness writes policy, catalog and fixture files that name
# these markers; matching on the names alone blocked ordinary work, three times, before this.
AGENT_SESSION=0
[ -n "$TICKET" ] && AGENT_SESSION=1
ls work/*/.role-* >/dev/null 2>&1 && AGENT_SESSION=1
CHAIN_ACTIVE=$AGENT_SESSION
ls work/*/.drafting-* >/dev/null 2>&1 && CHAIN_ACTIVE=1
BLOCK=0; ASK=0
block() { echo "guard: BLOCK $*"; BLOCK=1; }
ask()   { echo "guard: ASK   $*"; ASK=1; }
drafting() {  # prints the drafting markers that exist, if any
  ls work/*/.drafting-* 2>/dev/null
}
drafting_tickets() {  # the ticket ids with an artifact open, one per line
  drafting | sed -E 's#^work/([^/]+)/\.drafting-.*#\1#' | sort -u
}
# Is the ticket being drafted the one this session is working on? The commit that must be stopped
# is the drafting agent's own; a commit on another branch, by someone maintaining the harness
# while a colleague has a draft open, is not that commit. The first version of this rule blocked
# every commit anywhere while any marker existed, which is the fourth over-broad rule in this file
# and the only one that blocked a person rather than an agent.
drafting_here() {
  [ -n "$TICKET" ] || return 1
  drafting_tickets | grep -qx "$TICKET"
}

check_path() {  # $1 = repo-relative path
  local p=$1
  case "$p" in
    src/test/*)
      if [ -n "$TICKET" ] && [ -f "work/$TICKET/.role-implementer" ]; then
        block "$p: the implementer role never writes under src/test (ticket $TICKET)"
      elif [ -n "$TICKET" ] && [ -f "work/$TICKET/.tests-locked" ] && [ ! -f "work/$TICKET/.tests-amend-approved" ]; then
        block "$p: tests are locked for $TICKET; a human must create work/$TICKET/.tests-amend-approved to open a tests-amend flow"
      fi
      ;;
    work/*/review-verdict.json)
      if [ "${FORGE_REVIEWER:-}" != "1" ]; then
        block "$p: review-verdict.json is written only by bin/review.sh (the independent reviewer)"
      fi
      ;;
    work/*/.tests-locked)
      if [ "$CHAIN_ACTIVE" -eq 1 ]; then
        block "$p: the test lock is created only by bin/accept.sh when a human accepts the tests"
      fi
      ;;
    work/*/policy.json|.forge/*)
      if [ "$AGENT_SESSION" -eq 1 ]; then
        block "$p: policy and the fleet catalog are edited by a human outside a ticket, never by an agent"
      fi
      ;;
    .claude/agents/*|FLEET.md|evals/admissions.log)
      # The fleet changes only through admission. Edit the candidate copy and re-run
      # bin/admit.sh; a definition that drifts from its admitted text fails bin/fleet-check.sh.
      if [ "${FORGE_ADMIT:-}" != "1" ]; then
        block "$p: the fleet is written only by bin/admit.sh; edit .claude/agents-candidates/ and re-admit"
      fi
      ;;
    pom.xml)
      if [ "$MODE" = "--path" ]; then
        ask "pom.xml: dependency changes need human approval before commit (create work/.pom-approved)"
      fi
      ;;
  esac
}

check_command() {  # $1 = shell command text; text rules, deliberately narrow
  local c=$1 m
  # "git [options] commit|push" anywhere in the command, options included (git -C dir commit ...)
  if printf '%s' "$c" | grep -Eq '(^|[[:space:];&|(])git[[:space:]]+([^|;&]*[[:space:]])?(commit|push)([[:space:]]|$)'; then
    if drafting_here; then
      m=$(ls "work/$TICKET"/.drafting-* 2>/dev/null | paste -sd, -)
      block "git commit/push while $TICKET's artifact is being drafted ($m); only bin/accept.sh, run by a human at a terminal, commits an accepted artifact"
    fi
    printf '%s' "$c" | grep -Eq 'Accepted-By' && block "a commit carrying Accepted-By is made only by bin/accept.sh"
    # --no-verify, or its short form -n as a flag of this git invocation (not the -n of a test
    # expression elsewhere in the command, which an earlier version matched by mistake).
    printf '%s' "$c" | grep -Eq -- '--no-verify' && block "commits run with the pre-commit hook; --no-verify is not available to agents"
    printf '%s' "$c" | grep -Eq '(commit|push)[^;|&]*[[:space:]]-n([[:space:]]|$)' && block "commits run with the pre-commit hook; -n (--no-verify) is not available to agents"
  fi
  # Writes to a guarded path. The verb and the path must be adjacent: naming a guarded path in a
  # read, a test or a string is not a write, and an earlier version that matched the two anywhere
  # in the command blocked ordinary scripting.
  creates() {  # $1 = path regex ; true when the command brings that path into being
    printf '%s' "$c" | grep -Eq "(touch|tee|install|ln|chmod|truncate)[^;|&]*$1" && return 0
    printf '%s' "$c" | grep -Eq "(cp|sed[[:space:]]+-i[^;|&]*)[[:space:]][^;|&]*$1" && return 0
    printf '%s' "$c" | grep -Eq ">>?[[:space:]]*[^[:space:];|&]*$1" && return 0
    return 1
  }
  removes() {  # $1 = path regex ; true when the command takes that path away
    printf '%s' "$c" | grep -Eq "(rm|unlink|mv)[[:space:]][^;|&]*$1" && return 0
    printf '%s' "$c" | grep -Eq "find[^;|&]*$1[^;|&]*-delete" && return 0
    return 1
  }
  writes_to() { creates "$1" || removes "$1"; }
  # What actually disables the pre-commit hook: pointing git at a different hooks directory, or
  # writing over the installed copy under .git/hooks. The repository's own tracked copy is ordinary
  # content and changing it is a visible diff. Matching that path anywhere in a command blocked
  # copying it into a plugin payload, which makes this the fifth rule here to confuse naming a
  # path with writing to it.
  printf '%s' "$c" | grep -Eq 'core\.hooksPath' && block "the pre-commit hook is not disabled by agents"
  writes_to '\.git/hooks/' && block "the installed git hooks are not rewritten by agents"
  if [ "$CHAIN_ACTIVE" -eq 1 ]; then
    # The lock freezes the oracle and unfreezing it is worse: both directions are bin/accept.sh's.
    writes_to '\.tests-locked' && block "the test lock is created and removed only by bin/accept.sh"
    # A drafting marker only ever adds restriction, so creating one is the chain's own business
    # (the drafting commands each open their window that way). Removing one lifts the block on
    # committing, which is precisely the human's acceptance, so only bin/accept.sh may do it.
    removes '\.drafting-' && block "a drafting marker is removed only by bin/accept.sh, when a human accepts the artifact"
  fi
  if [ "$AGENT_SESSION" -eq 1 ] && { writes_to 'policy\.json' || writes_to 'fleet-catalog\.json'; }; then
    block "policy and the fleet catalog are edited by a human outside a ticket, never by an agent"
  fi
  if printf '%s' "$c" | grep -Eq 'gh[[:space:]]+pr[[:space:]]+merge|gh[[:space:]]+api.*merge'; then
    block "merging a pull request is the human's release act"
  fi
}

case "$MODE" in
  --path)
    for p in "$@"; do
      # normalise absolute paths inside the repo to repo-relative
      case "$p" in "$ROOT"/*) p=${p#"$ROOT"/};; esac
      check_path "$p"
    done
    ;;
  --command)
    check_command "${1:-}"
    ;;
  --staged)
    staged=$(git diff --cached --name-only --diff-filter=ACMRD)
    for p in $staged; do check_path "$p"; done
    # At commit time the staged set is known exactly, so this rule can be precise rather than
    # conservative: a commit is refused only when it carries the artifact of a ticket that is
    # still being drafted. Anything else may commit, whatever else is open elsewhere.
    for dt in $(drafting_tickets); do
      if echo "$staged" | grep -Eq "^work/$dt/|^src/test/"; then
        block "this commit carries $dt's work while $(ls "work/$dt"/.drafting-* 2>/dev/null | paste -sd, -) is open; only bin/accept.sh commits a drafted artifact"
      fi
    done
    if echo "$staged" | grep -Eq '^(\.forge/policy\.json|work/[^/]+/policy\.json)$' && [ ! -t 0 ]; then
      block "policy files are committed by a human at a terminal (stdin is not a TTY)"
    fi
    if echo "$staged" | grep -qx 'pom.xml'; then
      # New build inputs need human approval: direct dependencies and plugins (which execute at
      # build time), in the main build or any profile. dependencyManagement pins and exclusions
      # re-version code already present and pass. Parsed with an XML parser, and the guard fails
      # closed if parsing or python itself fails.
      if ! command -v python3 >/dev/null 2>&1; then
        block "pom.xml changed but python3 is unavailable to inspect it"
      elif added=$(python3 "$ROOT/bin/pom-additions.py" 2>"${TMPDIR:-/tmp}/guard-pom.err"); then
        if [ -n "$added" ]; then
          if [ -f work/.pom-approved ]; then
            echo "guard: ok    pom.xml adds build inputs ($added); work/.pom-approved present (consumed)"
            rm -f work/.pom-approved
          else
            block "pom.xml adds build inputs ($added); a human must create work/.pom-approved first"
          fi
        fi
      else
        block "pom.xml could not be inspected ($(head -1 "${TMPDIR:-/tmp}/guard-pom.err" 2>/dev/null)); refusing rather than guessing"
      fi
    fi
    ;;
  *)
    echo "usage: bin/guard.sh --path <file>... | --command \"<shell>\" | --staged" >&2; exit 2;;
esac

[ "$BLOCK" -eq 1 ] && exit 1
[ "$ASK" -eq 1 ] && exit 3
exit 0
