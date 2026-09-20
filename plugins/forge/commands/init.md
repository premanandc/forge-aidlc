---
description: Equip this repository with the Forge harness: vendor the scripts, seed the policy and fleet, and record where the agents came from.
---

Equip the current repository with the harness. `$ARGUMENTS` may carry `--owner "Name (login)"`.

1. Check you are at the root of a git repository with a clean working tree. If it is dirty, stop and say so: this writes a lot of files and the diff should be readable.
2. Show what will happen before it happens:

```bash
"${CLAUDE_PLUGIN_ROOT}/harness/bin/forge-install.sh" --from "${CLAUDE_PLUGIN_ROOT}" --dry-run
```

3. Summarise for the user: the scripts that will be vendored into `bin/`, the git hook, the templates, the workflows, the default policy, and the six agents with their families. Say plainly that the agents arrive with the suite's score rather than one earned here, and that the record will say so.
4. Ask for the owner if `--owner` was not given. Every family needs a named human who answers for what its agents produce, one name now covers all six, and the installer refuses to write `UNASSIGNED`. This is the one thing the suite cannot ship, so do not invent a name or reuse the git config without asking.
5. On confirmation, run it for real without `--dry-run`, then report what the fleet check said.

Then tell the user the three things the installer prints, which are genuinely theirs and cannot be automated: writing the architecture and prohibitions sections of `CLAUDE.md` for this codebase, setting the ticket id pattern and backlog source in `bin/issue.sh`, and adding golden tasks under `evals/` as they learn what their agents get wrong.

**Do not run this without confirmation.** It writes into a repository that is not yours, and installing a harness that refuses commits is something a person should choose deliberately.

If `bin/` or `.forge/` already exist, the installer keeps the existing policy and catalog and overwrites the scripts. Say that before running, because an upgrade and a first install look the same from here.
