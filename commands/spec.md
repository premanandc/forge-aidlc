---
description: Draft the spec for an accepted intent: spec-drafter writes it, the architect corrects the Contract, the human accepts.
---

Ticket `$ARGUMENTS` (first word is `<T>`). Second human gate. An agent drafts the spec, the architect corrects its Contract, a human accepts. You never accept and never commit.

1. Preconditions: on branch `ticket/<T>`, working tree clean, `intent: <T>` committed (`git log --format='%s%n%(trailers:key=Accepted-By)' | grep -A1 "^intent: <T>"` shows the trailer), no `spec: <T>` commit yet. Otherwise stop and explain (`/forge:intent <T>` first).
2. `echo <T> > work/.current-ticket` and `touch work/<T>/.drafting-spec`.
3. Delegate to the `spec-drafter` subagent: "Ticket <T> is active. intent: is accepted. Draft work/<T>/spec.md from work/<T>/intent.md following CLAUDE.md and your role. Do not commit."
4. Then delegate to the `architect` subagent: "Ticket <T> is active; work/<T>/.drafting-spec exists and spec.md is drafted. Correct the Contract section in place, write an ADR if a boundary changes, do not commit, following CLAUDE.md and your role."
5. Show the human: the acceptance criteria (numbered, verbatim), the final `## Contract`, the ADR path if any, the `## Open questions`, and `bin/policy.sh <T> architectureReview` (whether the plan will need the architect's boundary review). If the human answers questions here, apply them to `work/<T>/spec.md` and show the diff.
6. End with exactly:

```
Accept in your terminal:  bin/accept.sh <T> spec
```
