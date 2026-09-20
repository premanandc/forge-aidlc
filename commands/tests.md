---
description: Draft the failing tests for an accepted spec and stop for the QA lead to accept; acceptance commits and locks them.
---

Ticket `$ARGUMENTS` (first word is `<T>`). Third human gate. The test-designer drafts failing tests and proves them red; a human accepts them, and acceptance is what commits `tests:` and creates the lock. You never accept, commit, or lock.

1. Preconditions: on branch `ticket/<T>`, working tree clean, `spec: <T>` committed with its acceptance trailer, no `tests: <T>` commit, no `work/<T>/.tests-locked`. Otherwise stop and explain.
2. `echo <T> > work/.current-ticket` and `touch work/<T>/.drafting-tests`.
3. Delegate to the `test-designer` subagent: "Ticket <T> is active. intent: and spec: are accepted. Draft the failing tests for <T> from the spec's Contract following CLAUDE.md and your role; prove them red; do not commit and do not lock."
4. Show the human: the criteria-to-tests map the agent reported, the new test files (`git status --porcelain src/test`), the red it observed (the failing assertion or the missing Contract symbol), and `bin/policy.sh <T> acceptance.tests` (whether this acceptance is required or relaxable for the ticket).
5. End with exactly:

```
Accept in your terminal:  bin/accept.sh <T> tests
```

Then the fleet takes over: `bin/ticket.sh <T>`.
