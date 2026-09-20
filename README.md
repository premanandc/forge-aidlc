# Forge

An AI-first delivery harness, packaged as a Claude Code plugin.

Six narrow agents, three human acceptance gates before any code is written, and deterministic
gates after it. The argument underneath: **requirements are settled by people, and what follows
can be checked by machines.** Agents draft the first half and a person accepts it; agents execute
the second half and gates judge it.

## What it is

One plugin, `forge`. Six narrow agents, sixteen `/forge:*` commands, and the gate scripts that get
vendored into whatever repository you equip. Full documentation, including every command and what
lands in your repository, is in [plugins/forge/README.md](plugins/forge/README.md).

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
