---
description: Assemble the evidence pack for a ticket and stop; the human releases by merging the pull request.
---

Run `bin/release.sh $ARGUMENTS`. Report the evidence summary it prints, the result of `bin/chain-check.sh <TICKET> --complete`, and the pull request the human must merge (`bin/issue.sh pr <TICKET>`). Then stop. You do not merge, tag, push to main, or commit anything called release, whatever the evidence says. The human merges with:

```bash
gh pr merge <N> --merge --subject "release: <TICKET> <title>"
```
