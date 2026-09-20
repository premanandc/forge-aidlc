#!/usr/bin/env bash
# forge-install.sh: vendor the Forge harness into a project and record where its agents came from.
#
#   forge-install.sh --from <plugin-root> [--owner "<name> (<login>)"] [--dry-run]
#
# Run from the root of the project being equipped. It copies the scripts, the git hook, the
# templates, the workflows and the default policy into place, then seeds the two records that
# FLEET.md is rendered from.
#
# ## Why the agents arrive with a record and not just a file
#
# bin/fleet-check.sh refuses an agent that is present in .claude/agents/ with no line in
# evals/admissions.log, on the grounds that it sneaked in. A pre-installed agent is not unadmitted:
# it passed the suite's tasks upstream, and what is missing locally is the *record* of that. So the
# install writes one line per agent:
#
#   <stamp>  <agent>  <score>  installed  candidate=<hash>  suite=forge@<version>  by=<installer>
#
# "installed" rather than "admitted", naming the suite and version instead of a local run, so the
# registry can say plainly which agents came with the suite and which earned their place here.
# Recording the hash keeps drift detection working: editing a suite agent afterwards is caught
# exactly as any other drift is.
#
# The agents are vendored into .claude/agents/ rather than loaded from the plugin, and that is
# not an accident of packaging. bin/fleet-check.sh hashes the files there against the record, and
# FLEET.md is rendered from what is there. An agent that lived only in the plugin's cache could
# not be hash-locked, could not carry provenance, and would not appear in the registry at all.
# Being a governed file in your repository is the point of it.
#
# What the suite cannot supply is accountability. Every family in the catalog needs a named human
# who answers for what those agents produce, and no installer can know who your QA lead is, so it
# asks. Compatible with bash 3.2.
set -uo pipefail
PLUGIN=""; OWNER=""; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --from) PLUGIN=${2:-}; shift;;
    --owner) OWNER=${2:-}; shift;;
    --dry-run) DRY=1;;
    *) echo "forge-install: unknown option $1" >&2; exit 2;;
  esac
  shift
done
die() { echo "forge-install: $*" >&2; exit 1; }
[ -n "$PLUGIN" ] || die "usage: forge-install.sh --from <plugin-root> [--owner \"<name> (<login>)\"]"
[ -d "$PLUGIN/harness" ] || die "$PLUGIN does not look like the Forge plugin (no harness/)"

# Everything missing, reported at once, before anything is written. Each of these is load-bearing,
# and without this check the first sign of an absent tool is a script failing three commands into
# a chain with an error that names the script rather than what is missing.
MISSING=""
need() {  # $1 = command, $2 = what stops working without it
  command -v "$1" >/dev/null 2>&1 || MISSING="$MISSING
    $1 — $2"
}
need git     "everything: the chain is git history"
need jq      "the policy, the catalog, the review verdict and the evidence pack are all JSON"
need gh      "issues and pull requests: the backlog, the chain comment, the release"
need python3 "the pom guard and the agent definition parser"
[ -z "$MISSING" ] || {
  echo "forge-install: not installing, because these are missing:$MISSING" >&2
  echo "forge-install: on macOS: brew install git jq gh python" >&2
  exit 1
}
# gh present but not logged in is the same problem, one step later.
gh auth status >/dev/null 2>&1 || die "gh is installed but not authenticated. Run 'gh auth login' first: the harness files issues, opens pull requests, and records your login when you accept an artifact."
git rev-parse --show-toplevel >/dev/null 2>&1 || die "run this from inside the git repository you are equipping"
ROOT=$(git rev-parse --show-toplevel); cd "$ROOT"
VERSION=$(jq -r '.version // "unknown"' "$PLUGIN/.claude-plugin/plugin.json" 2>/dev/null)
NAME=$(jq -r '.name // "forge"' "$PLUGIN/.claude-plugin/plugin.json" 2>/dev/null)

say() { [ "$DRY" -eq 1 ] && echo "forge-install: would $*" || echo "forge-install: $*"; }
run() { [ "$DRY" -eq 1 ] || eval "$@"; }

# --- 1. the scripts, which must exist in the project because CI runs them too --------
say "vendor bin/ (the gates, the guards, the chain check)"
run "mkdir -p bin/hooks hooks templates evals/lib .forge .github/workflows work"
run "cp '$PLUGIN'/harness/bin/*.sh '$PLUGIN'/harness/bin/*.py bin/"
run "cp '$PLUGIN'/harness/bin/hooks/*.sh bin/hooks/"
run "cp '$PLUGIN'/harness/githooks/pre-commit hooks/"
run "cp '$PLUGIN'/harness/templates/*.md templates/"
run "cp '$PLUGIN'/harness/evals/lib/*.sh evals/lib/"
run "cp '$PLUGIN'/harness/evals/README.md evals/"
run "cp '$PLUGIN'/harness/.github/workflows/*.yml .github/workflows/"
run "cp -r '$PLUGIN'/harness/.github/ISSUE_TEMPLATE .github/"
run "chmod +x bin/*.sh bin/hooks/*.sh hooks/pre-commit"

# --- 2. policy and catalog, if the project has none ---------------------------------
if [ -f .forge/policy.json ]; then
  say "keep the existing .forge/policy.json"
else
  say "install the default .forge/policy.json"
  run "cp '$PLUGIN'/harness/.forge/policy.json .forge/"
fi
if [ -f .forge/fleet-catalog.json ]; then
  say "keep the existing .forge/fleet-catalog.json"
else
  say "install .forge/fleet-catalog.json"
  run "cp '$PLUGIN'/harness/.forge/fleet-catalog.json .forge/"
fi
# The facts about the project being equipped: ticket id pattern, backlog source, chain order,
# module names. They used to be edited into bin/ at five places marked "# template:", which made
# this install a silent overwrite of work somebody had done. Keeping them here is what lets the
# step above replace every script without asking: nothing in bin/ is yours to keep.
if [ -f .forge/project.json ]; then
  say "keep the existing .forge/project.json"
else
  say "install .forge/project.json (ticket pattern, chain order, module names)"
  run "cp '$PLUGIN'/harness/.forge/project.json .forge/"
fi

# --- 3. accountability, which the suite cannot ship ---------------------------------
if [ "$DRY" -eq 0 ] && grep -q 'UNASSIGNED' .forge/fleet-catalog.json 2>/dev/null; then
  if [ -z "$OWNER" ]; then
    if [ -t 0 ]; then
      echo
      echo "forge-install: every family needs a human who answers for what its agents produce."
      echo "forge-install: one name now covers all six; edit .forge/fleet-catalog.json to split them later."
      printf 'forge-install: owner, as "Name (login)": '
      read -r OWNER
    fi
  fi
  [ -n "$OWNER" ] || die "no owner given; pass --owner \"Name (login)\" or answer the prompt. The catalog cannot say UNASSIGNED and mean anything."
  tmp=$(mktemp); jq --arg o "$OWNER" '.families |= with_entries(.value.owner = $o)' .forge/fleet-catalog.json >"$tmp" && mv "$tmp" .forge/fleet-catalog.json
  echo "forge-install: every family is owned by $OWNER"
fi

# --- 4. the agents, and the record of where they came from --------------------------
say "install the fleet and record its provenance"
run "mkdir -p .claude/agents .claude/agents-candidates"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
INSTALLER=$(git config user.name 2>/dev/null); INSTALLER=${INSTALLER:-unknown}
for a in "$PLUGIN"/harness/agents/*.md; do
  [ -e "$a" ] || continue
  n=$(basename "$a" .md)
  if [ "$DRY" -eq 1 ]; then echo "forge-install: would install agent $n"; continue; fi
  cp "$a" ".claude/agents/$n.md"
  # The score belongs to the suite's own tasks, upstream. Saying so is the point of the line.
  printf '%s  %s  3/3  installed  candidate=%s  suite=%s@%s  by=%s (installed, not run here)\n' \
    "$STAMP" "$n" "$(git hash-object ".claude/agents/$n.md")" "$NAME" "$VERSION" "$INSTALLER" \
    >>evals/admissions.log
done

# --- 5. render the registry from those records --------------------------------------
if [ "$DRY" -eq 0 ]; then
  bin/fleet-render.sh >|FLEET.md || die "could not render FLEET.md"
  echo "forge-install: FLEET.md rendered from the catalog and the log"
  bin/fleet-check.sh | tail -1
fi

echo
echo "forge-install: done. Still yours to do:"
echo "  1. Write the architecture and prohibitions sections of CLAUDE.md for this codebase."
echo "  2. Fill in .forge/project.json: the ticket id pattern, the backlog source if you have one,"
echo "     and your module names. Until the modules are named the architect's boundary review is"
echo "     required on every ticket, because an unknown module count fails closed."
echo "  3. Add golden tasks under evals/<agent>/ as you learn what your agents get wrong,"
echo "     then bin/admit.sh <agent> to earn a local score instead of the suite's."
echo
echo "forge-install: nothing under bin/ is yours to edit. It is replaced wholesale on the next"
echo "forge-install: install; everything that varies by project lives in .forge/, which is kept."
