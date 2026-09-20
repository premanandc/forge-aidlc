---
description: Run the independent reviewer on a ticket's impl commits; the only way a verdict gets written.
---

Run `bin/review.sh $ARGUMENTS` and report the disposition, the findings, and whether the risk floor was triggered. The reviewer is a separate headless session that sees only the spec, the locked tests and the diff. Never edit `work/*/review-verdict.json` yourself.
