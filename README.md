# Forge

A delivery harness for Claude Code that makes an agent stop and ask a person at the three points
where stopping matters.

Agents write working code quickly; the trouble is rarely the code. It is that one actor drafts the
requirement, decides what it means, writes the tests, satisfies them and reports success, with no
person deciding anything and no record saying otherwise. Forge splits that in two: **requirements
are settled by people, and what follows is checked by machines.** The refusals are enforced by
hooks and git rather than by asking an agent nicely.

Full reasoning, including what it does not claim, is in
[plugins/forge/README.md](plugins/forge/README.md).

## What it is

One plugin, `forge`. Six narrow agents, sixteen `/forge:*` commands, and the gate scripts that get
vendored into whatever repository you equip. Full documentation, including every command and what
lands in your repository, is in [plugins/forge/README.md](plugins/forge/README.md).

## Before you start

You need `git`, `jq`, `python3`, and `gh` authenticated (`gh auth login`). `/forge:init` checks
all four before writing anything. The CI workflow it vendors runs a Maven build, because that is
what the project it came from uses; swap those steps for your own.

## Install

```
/plugin marketplace add premanandc/forge-aidlc    # register the catalog
/plugin install forge@forge-aidlc                 # get the tool
/forge:init                                       # point it at a repository
```

Private repository, so installing uses your existing git credentials. If background update checks
fail to authenticate, run `gh auth setup-git` once, or set
`CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE=1` so a failure leaves the installed plugin
working rather than dropping it.

## Development

The harness is developed and exercised in a real project and copied here:

```bash
plugins/forge/sync-from-source.sh /path/to/the-source-repo
claude plugin validate ./plugins/forge
```

The repository is a marketplace holding one plugin, which is the layout Claude Code documents:
`.claude-plugin/marketplace.json` at the root lists `./plugins/forge`, and the plugin carries its
own `.claude-plugin/plugin.json`. A second plugin later is another entry and another directory.
