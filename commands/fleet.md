---
description: Show the fleet: which agents exist, what each one is for, where it sits in a ticket's life, and who owns it.
---

Run `cat FLEET.md`, then `bin/fleet-check.sh`.

Present it for someone seeing it for the first time, in this order:

1. **The six agents in chain order**, one line each: step, name, and its one purpose in your own words. The table reads top to bottom as a ticket's life, from the request arriving to the release being proposed.
2. **Where the humans are.** Between steps 2 and 3 a person accepts the intent and the spec; after step 4 a person accepts the tests, which is what locks them; after step 6 a person merges. Name those as the seams rather than as extra steps.
3. **The autonomy ladder.** Say which agents only draft (`assist`) and which may commit on a branch and propose (`propose`). No agent in this fleet is on the `act` rung.
4. **What the fleet check just proved:** every installed definition is byte-identical to the text that passed its golden tasks, every agent has a catalogued owner, and FLEET.md matches what its sources render. If it failed, say so first and quote the failure.

Two things worth saying if the audience asks how an agent got there, without going into the machinery: it passed three golden tasks whose assertions were written first, and a named human authorised it. `evals/admissions.log` has every run including the rejections. Do not walk through creating or admitting an agent unless asked; it is a different talk.

`$ARGUMENTS` may name one agent. If it does, show that row, then `cat .claude/agents/<name>.md` and summarise what it may and may not touch, which is usually the more interesting half.

Read-only. Never edit `FLEET.md`, the catalog or any agent definition here.
