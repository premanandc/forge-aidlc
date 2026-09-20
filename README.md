# Forge

An AI-first delivery harness, packaged as a Claude Code plugin.

Six narrow agents, three human acceptance gates before any code is written, and deterministic
gates after it. The argument underneath: **requirements are settled by people, and what follows
can be checked by machines.** Agents draft the first half and a person accepts it; agents execute
the second half and gates judge it.

## What you get

**Six agents**, each with one job, a family, an accountable owner and a rung on an autonomy
ladder. Four of them draft and stop. None may merge.

| step | agent | does |
|---|---|---|
| 1 | intent-drafter | turns a request into a statement of the problem, raising what it leaves unsaid |
| 2 | spec-drafter | turns an accepted intent into behaviour and acceptance criteria |
| 3 | architect | fixes the Contract tests compile against; writes an ADR if a boundary moves |
| 4 | test-designer | writes the failing tests and proves they fail for the right reason |
| 5 | implementer | makes them pass with the smallest diff that keeps the gate green |
| 6 | release-manager | runs the gates, assembles the evidence, and stops |

**Sixteen commands**, namespaced under `forge:`. `/forge:issue` files a request and allocates its
id, `/forge:intent`, `/forge:spec` and `/forge:tests` draft and stop, `/forge:ticket` runs the
autonomous half. `/forge:fleet`, `/forge:chain`, `/forge:policy`, `/forge:health`, `/forge:metrics`
and `/forge:reddiff` are read-only views.

**The gates themselves**, vendored into your repository as shell scripts: the write guards, the
commit-chain check, the fleet integrity check, and the workflows that run them in CI. They are
scripts and not prompts deliberately, so the same rules apply from a terminal and in CI where no
agent session exists.

## Install

```bash
claude --plugin-dir /path/to/forge          # try it
/forge:install                              # equip the current repository
```

The installer vendors the scripts, seeds the policy and the fleet catalog, and records where each
agent came from. It will ask you one question it cannot answer itself.

## Two things worth knowing before you install

**The agents arrive with the suite's score, not one earned in your repository.** They passed the
suite's golden tasks upstream, and the installer records exactly that: an `installed` line naming
the suite and version, which `FLEET.md` shows in a provenance column. An agent admitted in your
own repository shows who authorised it instead. The two are different claims and the table says
which is which. Add golden tasks under `evals/` as you learn what your agents get wrong, then
`bin/admit.sh <agent>` to earn a local score.

**The suite ships capability, not accountability.** Every family needs a named human who answers
for what its agents produce, and no installer can know who your QA lead is. It asks, and refuses
to write `UNASSIGNED`.

## What it will not do for you

Accepting an artifact and merging a pull request have no command, and that is the point. Both
require a person at a terminal: `bin/accept.sh` refuses to run without one and records your
GitHub login in a commit trailer, and the guard denies `gh pr merge` outright. The friction is the
feature.

## Development

The harness is developed and exercised in a real project and copied here:

```bash
./sync-from-source.sh /path/to/the-source-repo
claude plugin validate .
```
