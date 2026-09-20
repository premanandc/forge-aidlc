---
description: Show the baseline and harnessed run numbers side by side.
---

Run `bin/metrics.sh summary` and report the table it prints.

Then read it honestly, because the headline number flatters the wrong thing. Wall time includes any time the machine slept or waited on a rate limit; `api` is the model's actual working time, and that is the one to compare. The harnessed run costs more sessions and more time than the baseline by design: it buys the locked tests, the independent review, both gate tiers and the evidence pack, and the baseline buys none of those. Say that rather than presenting the harness as faster.

If the user asks which is better, the useful comparison is the diff size and what the gates found, not the clock.

Do not append to `metrics/runs.jsonl`. Only `bin/ticket.sh` and `bin/baseline.sh` write it, at the end of a real run.
