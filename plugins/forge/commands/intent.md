---
description: Start a ticket. Fetch its issue, let the intent-drafter draft work/<T>/intent.md, and stop for the product owner to accept.
---

Ticket `$ARGUMENTS` (the first word is the ticket id `<T>`, e.g. PF-102). This is the first human gate of the chain: an agent drafts the intent, a human accepts it. You never accept and never commit.

1. Preconditions: `git status --porcelain` is empty, and `git log --format=%s | grep -E "^intent: <T>"` finds nothing. If either fails, stop and explain.
2. `bin/issue.sh fetch <T>` (writes `work/<T>/ticket.json` from the GitHub issue). If there is no issue, stop: the human opens one with the Ticket template or runs `bin/issue.sh seed`.
3. If the current branch is not `ticket/<T>`: `git switch -c ticket/<T>` (or `git switch ticket/<T>` if it exists).
4. `echo <T> > work/.current-ticket` and `touch work/<T>/.drafting-intent`. While that marker exists the guards refuse every commit; only `bin/accept.sh` removes it.
5. Delegate to the `intent-drafter` subagent: "Ticket <T> is active (work/.current-ticket). Draft work/<T>/intent.md from work/<T>/ticket.json following CLAUDE.md and your role. Do not commit." If `.claude/agents/intent-drafter.md` does not exist, stop: the agent is not admitted (`bin/admit.sh intent-drafter`).
6. Show the human the draft's `## Scope` and `## Open questions` verbatim, and `bin/policy.sh <T> risk`. If the human answers questions in this conversation, apply the answers to `work/<T>/intent.md` yourself (tick the boxes and record the answer beside them) and show the diff.
7. End with exactly this instruction, and nothing that could be mistaken for acceptance:

```
Accept in your terminal:  bin/accept.sh <T> intent
```

It refuses to run from an agent, asks you to type your GitHub login, commits `intent: <T> <title>` with your `Accepted-By` trailer, pushes `ticket/<T>`, opens the draft PR and labels the issue.
