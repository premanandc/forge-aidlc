---
description: Run the autonomous half of the chain for a ticket whose tests a human accepted: plan, boundary review by policy, impl, review, evidence, PR ready.
---

Ticket `$ARGUMENTS` (first word is `<T>`; an optional second word is the stage number to resume from, 4 to 8).

Preconditions, or stop and explain: on branch `ticket/<T>`; `tests: <T>` committed with its acceptance trailer (`bin/chain-check.sh <T>` passes); working tree clean; `bin/fleet-check.sh` passes.

Execute exactly:

```bash
bin/ticket.sh <T> [from-stage]
```

Then report the timeline it printed, whether the architect's boundary review ran or was skipped by policy (`bin/policy.sh <T> architectureReview`), the review disposition, the evidence summary, and the PR URL it marked ready. If the disposition is not `auto-pass`, tell the human what the reviewer found and how to record their resolution; do not resolve it yourself. Never merge the PR: the human's merge is the release.
