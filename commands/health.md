---
description: Check the harness itself: fleet integrity, the guard, chain and ticket selftests, and the tier 1 gate.
---

Run these in order and report each result. Keep going after a failure; the point is a full picture.

```bash
bin/fleet-check.sh
bin/guard-selftest.sh
bin/chain-check-selftest.sh
bin/ticket-preconditions-selftest.sh
mvn
```

Report a short table: check, outcome, and for the selftests the counts they print. For `mvn`, report pass or fail and the wall time.

If anything fails, say what and quote the failing line, then stop and hand it back. Do not fix a guard, a gate or a selftest as a side effect of a health check: those files are the harness's own rules, and changing them because a check went red is how a harness stops meaning anything. A red check is a finding to report, not a chore to clear.

`$ARGUMENTS` may name a ticket; if it does, also run `bin/chain-check.sh <T>` and include it.
