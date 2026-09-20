---
description: List open tickets with their risk and chain stage; pass a stage to narrow it (backlog filed = awaiting intent).
---

Run `bin/issue.sh list $ARGUMENTS` and show the result as a table: ticket, risk, stage, title, issue number.

`$ARGUMENTS` is an optional stage: `filed`, `intent`, `spec`, `tests`, `impl`, `review`, `released`. With no argument it lists every open ticket. `/forge:backlog filed` is the queue of requests nobody has worked out the meaning of yet, which is where `/forge:intent <T>` starts.

Say which stage was listed, and how many. For tickets at `filed`, note that `/forge:intent <T>` starts one. For tickets at `review`, note that the pull request is waiting for a human to read and merge, and give its number from `bin/issue.sh pr <T>`.

One caveat worth repeating if you list `filed`: the label means nobody has **accepted** an intent, not that nobody has drafted one. A draft that was never accepted leaves no trace in the tracker, because the artifact and its marker are local and gitignored. Do not describe a `filed` ticket as untouched.

Do not fetch, edit, comment on or label any issue. This command only reads.
