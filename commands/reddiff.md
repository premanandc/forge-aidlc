---
description: Show the negative proofs: changes that break exactly one rule, and the gate that catches each.
---

`$ARGUMENTS` is optional: a red diff name (`boundary`, `oracle`, `self-approve`, `unaccepted`), or `--all`.

With no argument, run `bin/reddiff.sh list` and show what each one breaks and which gate should catch it.

With a name or `--all`, run `bin/reddiff.sh verify $ARGUMENTS` and report, per red diff, three things: whether the write guard refused it before the commit where there is such a layer, whether the intended gate caught it, and whether anything else broke. Say plainly that the third is the one that makes it a proof: a change that trips two gates at once demonstrates neither.

`boundary` runs Maven and takes about forty seconds. The other three are chain checks and are immediate.

Never run `bin/reddiff.sh pr`, which pushes a deliberately broken branch and opens a pull request. That is a human's call, because it puts a red pull request on the repository for everyone to see. Tell the user the command if they want it.

Verification builds each change in a throwaway worktree and removes it afterwards, so nothing touches the working tree. If one reports WRONG, quote what the gate actually said rather than summarising, and do not adjust the gate, the guard or the expectation to make it pass. A red diff that stopped failing is telling you a rule has gone missing.
