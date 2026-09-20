# forge

An AI-first delivery harness for Claude Code. Six narrow agents, three human acceptance gates
before any code is written, and deterministic gates after it.

The argument underneath: **requirements are settled by people, and what follows can be checked by
machines.** Agents draft the first half and a person accepts it. Agents execute the second half
and gates judge it. An agent that accepted its own draft would have taken a decision that is not
its to take, so the harness refuses in four places rather than asking nicely.

## Before you start

| tool | why |
|---|---|
| `git` | everything: the chain is git history, and the gates read it |
| `gh`, authenticated | issues and pull requests: the backlog, the chain comment on an issue, the release |
| `jq` | the policy, the fleet catalog, the review verdict and the evidence pack are all JSON |
| `python3` | the dependency guard and the agent definition parser |

```bash
brew install git jq gh python   # macOS
gh auth login
```

`/forge:init` checks all four and refuses to write anything until they are present, so you will
be told up front rather than three commands into a chain.

**One thing the harness does not supply: your build.** The CI workflow it vendors runs this
project's gates, and this project is Java and Maven, so `.github/workflows/gates.yml` pins Temurin
and calls `mvn`. Replace those build steps with your own. The parts that are not the build, the
chain check, the fleet check and the harness selftests, work anywhere.

## Install

```
/plugin marketplace add premanandc/forge-aidlc    # register the catalog
/plugin install forge@forge-aidlc                 # get the tool
/forge:init                                       # point it at a repository
```

The last one vendors the scripts, the git hook, the templates, the workflows and the default
policy into the project, installs the six agents into `.claude/agents/`, and records where each
came from. It asks who owns each agent family and refuses to proceed without an answer.

To try it before installing:

```bash
claude --plugin-dir /path/to/forge-aidlc/plugins/forge
```

## How a ticket moves

```
/forge:issue  "providers with an expired licence get through screening"   # files it, allocates PF-NNN
/forge:backlog filed                                                      # the queue
/forge:intent PF-103        → bin/accept.sh PF-103 intent                 # YOU accept
/forge:spec   PF-103        → bin/accept.sh PF-103 spec                   # YOU accept
/forge:tests  PF-103        → bin/accept.sh PF-103 tests                  # YOU accept; this locks them
/forge:ticket PF-103                                                      # the fleet runs, opens a PR
gh pr merge <N> --merge --subject "release: PF-103 ..."                   # YOU merge; that is the release
```

## Commands

**Running a ticket**

| command | does |
|---|---|
| `/forge:issue <story>` | file a request; allocates the next ticket id, applies the labels |
| `/forge:backlog [stage]` | open tickets with risk and stage; `filed` is the queue awaiting intent |
| `/forge:intent <T>` | intent-drafter states the problem and raises what the request left unsaid, then stops |
| `/forge:spec <T>` | spec-drafter writes behaviour and criteria; the architect fixes the Contract; both stop |
| `/forge:tests <T>` | test-designer writes the failing tests and proves they fail, then stops |
| `/forge:ticket <T>` | the autonomous half: plan, boundary review by policy, implementation, review, evidence, PR ready |
| `/forge:review <T>` | the independent reviewer alone; the only thing that writes a verdict |
| `/forge:release <T>` | assemble the evidence pack and stop, naming the pull request you merge |

**Looking at things** (all read-only)

| command | does |
|---|---|
| `/forge:fleet [agent]` | the agents in chain order, their purposes, owners and rungs |
| `/forge:chain <T>` | where a ticket stands, who accepted what, what the gate still wants |
| `/forge:policy <T>` | which gates this ticket must pass and which its policy relaxes, and why |
| `/forge:health` | fleet integrity, the guard, chain and ticket selftests, and the tier 1 gate |
| `/forge:metrics` | the un-harnessed baseline against a harnessed run |
| `/forge:reddiff [name]` | the negative proofs: changes that break one rule, and the gate that catches each |

**Looking after the fleet**

| command | does |
|---|---|
| `/forge:admit <agent>` | prepare an agent's admission and hand the decision to you |
| `/forge:init` | equip a repository with the harness |

**Two things deliberately have no command.** Accepting an artifact is `bin/accept.sh`, which
refuses to run without a terminal and records your GitHub login in a commit trailer. Merging the
pull request is the release, and the guard denies `gh pr merge` outright. Both should cost a
deliberate act in your own shell.

## The agents

| step | agent | rung | does |
|---|---|---|---|
| 1 | intent-drafter | assist | turns a request into a statement of the problem, raising what it leaves unsaid |
| 2 | spec-drafter | assist | turns an accepted intent into behaviour and acceptance criteria |
| 3 | architect | propose | fixes the Contract tests compile against; writes an ADR if a boundary moves |
| 4 | test-designer | assist | writes the failing tests and proves they fail for the right reason |
| 5 | implementer | propose | makes them pass with the smallest diff that keeps the gate green |
| 6 | release-manager | propose | runs both gate tiers, assembles the evidence, and stops |

`assist` drafts for a human who accepts or amends, and never commits scope. `propose` commits on a
ticket branch and proposes a pull request. Nothing here may merge one.

## What lands in your repository, and why

The plugin supplies the commands, the hook wiring and the agent definitions. Everything the gates
need is copied into your project, and that is deliberate rather than clumsy:

- **`bin/`**, the guards, the chain check and the gate scripts. CI runs these, and a rule that
  only exists while an agent session is running enforces nothing.
- **`.claude/agents/`**, the six definitions. The fleet check hashes these files against the
  record, so an agent living only in a plugin cache could not be hash-locked or carry provenance.
- **`.forge/policy.json`** and the fleet catalog, both human-written and refused to agent sessions.
- **`FLEET.md`** and **`evals/admissions.log`**, which are your repository's record of which
  agents you trust and why.

## Two things worth knowing before you install

**The agents arrive with this suite's score, not one earned in your repository.** They passed its
golden tasks upstream, and the installer records exactly that: an `installed` line naming the
suite and version, which `FLEET.md` shows in a provenance column. An agent admitted in your own
repository shows who authorised it instead. Those are different claims and the table keeps them
apart. Add golden tasks under `evals/` as you learn what your agents get wrong, then
`bin/admit.sh <agent>` to earn a local score.

**The suite ships capability, not accountability.** Every family needs a named human who answers
for what its agents produce, and no installer can know who your QA lead is. It asks.

## After installing

Three things are genuinely yours and cannot be automated:

1. Write the architecture and prohibitions sections of `CLAUDE.md` for your codebase.
2. Set the ticket id pattern and backlog source in `bin/issue.sh` (search for `# template:`).
3. Add golden tasks under `evals/` as you learn what your agents get wrong.
