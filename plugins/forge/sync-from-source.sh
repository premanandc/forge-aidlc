#!/usr/bin/env bash
# sync-from-source.sh <source-repo>
#
# Copy the canonical harness out of the repository it is developed in and into this plugin's
# payload. Until the harness is extracted for good, provider-services is where it lives and gets
# exercised, and this plugin is a packaging of it; running this keeps the two honest.
#
# `command cp -f` deliberately: an interactive `cp -i` alias prompts, answers no, and leaves a
# silently stale payload, which is exactly the failure this script exists to prevent.
set -euo pipefail
SRC=${1:-}
[ -n "$SRC" ] || { echo "usage: ./sync-from-source.sh <source-repo>" >&2; exit 2; }
[ -d "$SRC/bin" ] || { echo "sync: $SRC has no bin/; is that the harness repository?" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd); cd "$HERE"   # the plugin root, under plugins/

mkdir -p harness/bin/hooks harness/githooks harness/templates harness/evals/lib \
         harness/.github/workflows harness/agents commands

command cp -f "$SRC"/bin/*.sh "$SRC"/bin/*.py harness/bin/
command cp -f "$SRC"/bin/hooks/*.sh harness/bin/hooks/
command cp -f "$SRC"/hooks/pre-commit harness/githooks/
command cp -f "$SRC"/templates/*.md harness/templates/
command cp -f "$SRC"/evals/lib/*.sh harness/evals/lib/
command cp -f "$SRC"/evals/README.md harness/evals/
command cp -f "$SRC"/.github/workflows/*.yml harness/.github/workflows/
command cp -Rf "$SRC"/.github/ISSUE_TEMPLATE harness/.github/
command cp -f "$SRC"/.claude/commands/forge/*.md commands/
command cp -f "$SRC"/.claude/agents/*.md harness/agents/

# forge-install.sh is this plugin's own, not the source repo's: it installs the harness rather
# than being part of it, so a sync must not delete it.
[ -f harness/bin/forge-install.sh ] || echo "sync: WARNING harness/bin/forge-install.sh is missing"
chmod +x harness/bin/*.sh harness/bin/hooks/*.sh harness/githooks/pre-commit

echo "sync: commands $(ls commands | wc -l | tr -d ' '), agents $(ls harness/agents | wc -l | tr -d ' '), harness files $(find harness -type f | wc -l | tr -d ' ')"
echo "sync: from $SRC at $(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
