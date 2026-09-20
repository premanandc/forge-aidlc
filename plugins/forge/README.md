# forge

A delivery harness for Claude Code that makes an agent stop and ask a person at the three points
where stopping matters.

## The problem it solves

Agents write working code quickly. The trouble is rarely the code.

It is that an agent asked to build something will draft the requirement, decide what the
requirement means, write the tests, satisfy them, and report success, in one unbroken motion. No
person decided anything, and nothing in the record says otherwise. Four failures follow, and every
one is familiar:

- **A spec nobody agreed to.** The agent inferred what you meant, sensibly, and inferred wrong in
  a way that only surfaces after the code exists.
- **Tests adjusted until they pass.** A failing test is an obstacle if the same actor owns the
  test and the implementation. The oracle moves and the build goes green.
- **Work that reviewed itself.** An agent's own account of its work is not a review, however
  thorough it reads.
- **No record.** Six months later nobody can say who agreed to what, or on what evidence, because
  approval happened in a chat window nobody kept.

None of these are fixed by a better prompt. "Please stop and ask" is a request, and an agent
optimising for a finished task will route around a request.

## What it does about it

It splits a ticket in two. **Requirements are settled by people; what follows is checked by
machines.**

Before any code exists, three artifacts need a human's acceptance: the statement of the problem,
the specification, and the failing tests. Agents draft all three and stop. A person accepts each
one deliberately, and that acceptance is recorded as a signature on a commit.

After that, agents work and deterministic gates judge them: the tests are frozen, the module
boundaries checked, an independent reviewer sees only the spec, the tests and the diff, and the
evidence is assembled before anything can ship. You merge; nothing else can.

**The refusals are mechanical, not instructional.** An agent cannot commit an artifact you have
not accepted, cannot write an acceptance signature, cannot touch a test once it is locked, cannot
write its own review verdict, and cannot merge. Those are enforced by hooks and git, not by
paragraphs in a prompt asking nicely.

## Who this is for

Teams who want agents to do more of the work and need to be able to answer, later, who decided
what and on what basis. It costs you three decisions per ticket. If that sounds like too much
friction for what you are building, it probably is, and you should not install it.

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

## How it is enforced

Four layers read the same rule file, `bin/guard.sh`, and see different things. That matters,
because each covers what the others cannot.

| layer | fires when | sees | exists |
|---|---|---|---|
| PreToolUse on Edit/Write | an agent is about to write a file | the target path | only in a Claude session |
| PreToolUse on Bash | an agent is about to run a command | the command text | only in a Claude session |
| `.git/hooks/pre-commit` | **anyone** commits | the staged files | always, for every commit |
| `bin/chain-check.sh` | on demand, and in CI on every push | the git history | anywhere, no session needed |

The first two stop an agent before it acts and can say why in the refusal. The third stops the
commit itself and cannot be talked around, but it only sees files. The fourth is not a guard at
all: it reads the history afterwards and runs in CI, where no hook and no agent session exists.

A worked example. An agent cannot write an acceptance signature, because the Bash layer refuses
any command containing a commit with that trailer. But suppose one got past it: the chain check
would still refuse a `tests:` commit whose spec nobody accepted, and that check runs on GitHub
where the agent has no reach at all. The test lock works the same way, caught by the Bash layer
when an agent reaches for a frozen test and by the pre-commit layer whatever route the change
took.

**What it does not claim.** These stop agents, not you. Nothing prevents you hand-crafting a
commit with someone else's name in an acceptance trailer, any more than git stops you setting
`user.name` to a colleague's. What you get is a record that is *checkable*, not one that is
unforgeable by the person who owns the repository.

**The rules are tested like code**, because they are code. `bin/guard-selftest.sh` runs 45 cases,
`bin/chain-check-selftest.sh` builds 22 deliberately broken histories, and
`bin/ticket-preconditions-selftest.sh` checks the autonomous half refuses to start early. Nearly
every case is a bug that actually happened, including the permissive ones: a guard that blocks too
much is as broken as one that blocks too little, and most of those cases exist because an
over-broad rule once stopped legitimate work.

Run all of it, plus your own build, with `/forge:health`.

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
- **`.forge/`**, human-written and refused to agent sessions: `policy.json` for which gates this
  repo requires, the fleet catalog for who owns which agents, and `project.json` for the facts
  about your codebase.
- **`FLEET.md`** and **`evals/admissions.log`**, which are your repository's record of which
  agents you trust and why.

**The line between those two kinds of file is the one that matters.** Everything in `bin/` is
vendor code: you never need to read it, and an install replaces all of it without asking.
Everything that varies by project lives in `.forge/`, which an install keeps. Ticket id pattern,
backlog source, the order agents appear in the registry and your module names are configuration,
so they are read from `.forge/project.json` rather than edited into the scripts. Earlier versions
had five such values sitting in `bin/` behind `# template:` comments, which meant re-installing
silently threw away work somebody had done.

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
2. Fill in `.forge/project.json`: the ticket id pattern, the backlog source if you have one, and
   your module names. Until the modules are named the architect's boundary review is required on
   every ticket, because an unknown module count fails closed.
3. Add golden tasks under `evals/` as you learn what your agents get wrong.
