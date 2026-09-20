---
description: File a new request as a GitHub issue: allocate the next ticket id, label it, and post it.
---

`$ARGUMENTS` is the request in the user's own words, however rough. It may be a single line.

A request is not a commitment. Keep this step thin: what someone wants and roughly how risky it is. What the request leaves unsaid is the **intent** step's job, and `/forge:intent` exists precisely so those gaps are found against the code and answered by a person. Do not interrogate the user here, and do not draft an intent.

1. Read the request. If it is already clear enough to file, say what you are about to file and ask the user to confirm, in one exchange:
   - the **title**, a short noun phrase, not the whole sentence
   - the **modules** it looks like it touches, from the architecture table in `CLAUDE.md`, or none if you cannot tell
   - the **risk**, `low`, `medium` or `high`

   Ask only about what you genuinely cannot infer. If the request names a module, do not ask which module.

2. On confirmation:

```bash
bin/issue.sh new "<story>" --title "<title>" --modules "<a, b>" --risk <r>
```

Omit `--risk` and it is inferred: two or more modules means `high`, because a boundary is in play and the policy should tighten rather than relax. The script says what it inferred. Omit `--modules` if you do not know; guessing wrong there sets a gate.

3. Report the id it allocated, the issue URL, and that the next step is `/forge:intent <T>`.

**Filing writes to the repository and everyone can see it, so confirm before you post, every time.** If the user asks for several at once, list them all and confirm once, then file them in order.

Never set a `stage:` label other than the `stage:filed` the script applies, never comment on the new issue, and never start drafting its intent in the same breath. The id is allocated from the highest existing ticket below 900; the 900s are reserved for golden tasks and are skipped.
