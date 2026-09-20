---
description: Show which gates a ticket must pass and which its policy relaxes, and why.
---

Ticket `$ARGUMENTS` (the first word is `<T>`). Read-only.

Run each of these and report the answers together:

```bash
bin/policy.sh <T> risk
bin/policy.sh <T> acceptance.intent
bin/policy.sh <T> acceptance.spec
bin/policy.sh <T> acceptance.tests
bin/policy.sh <T> architectureReview
bin/policy.sh <T> grandfathered
bin/policy.sh <T> show
```

Then say in a sentence or two what it means in practice: which steps need a human's `bin/accept.sh`, whether the architect will boundary-review the plan or `bin/ticket.sh` will commit it with the skipped-by-policy trailer, and where the value came from (the repo default in `.forge/policy.json`, a per-ticket override in `work/<T>/policy.json`, or the risk label).

Two things to say plainly when they apply. Intent and spec acceptance are always required and no policy relaxes them, so if someone is looking for a way round that, there isn't one. And `by-risk` resolves to required for a high-risk ticket, and for the architecture review also when the spec's Contract names an event or crosses a module, so the answer can change once the spec exists.

Never edit `.forge/policy.json` or `work/<T>/policy.json`. They are written by a human outside a ticket, and the guards refuse them to any session with a ticket in flight.
