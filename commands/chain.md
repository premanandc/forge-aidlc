---
description: Show where a ticket stands in the chain: its commits, who accepted what, and what the gate still wants.
---

Ticket `$ARGUMENTS` (the first word is `<T>`; pass `complete` as a second word to check it as a finished ticket). Read-only.

```bash
bin/chain-check.sh <T>              # or: bin/chain-check.sh <T> --complete
bin/issue.sh list                   # for the issue's stage label
bin/issue.sh pr <T>                 # the pull request number, if one is open
```

Report: which of the six stages exist, who accepted each of the first three (the `Accepted-By` trailer), whether the boundary review ran or was skipped by policy, the review disposition if there is one, and the gate results if the evidence exists. Then say what the next step is and who does it, naming the exact command.

When the chain check fails, quote its `FAIL` lines verbatim rather than paraphrasing. They name the rule that was broken, which is more useful than a summary.

Never make a commit, move a label, or edit anything under `work/<T>/` here.
