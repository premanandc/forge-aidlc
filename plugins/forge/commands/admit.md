---
description: Prepare an agent's admission: check it is ready, prove its golden tasks bite, and hand the decision to the human.
---

`$ARGUMENTS` is the agent name. This command does everything about an admission except the decision.

1. `bin/admit.sh --check <agent>` — is the candidate there, is somebody in the catalog accountable for it, does it have three golden tasks with assertions, and what would change if it were admitted.
2. If that reports ready, `bin/admit.sh <agent> --selftest` — proves each task's assertions fail on the bare fixture and pass on a reference answer, without spending a model run. Report the counts.
3. `cat FLEET.md` and the agent's lines in `evals/admissions.log`, so the human can see what it is joining and what its history is.
4. Report anything marked `no`, and what would fix it. A missing catalog entry is the interesting one: it means nobody has said which family the agent belongs to or who owns its output, and that is deliberately a human's sentence to write.

Then stop, and print the command for the human to run in their own terminal:

```
bin/admit.sh <agent>
```

**You cannot admit an agent, and should not try.** `bin/admit.sh` refuses without a terminal, asks the human to type their GitHub login, and records them in an `Authorised-By` trailer. Which agents may act decides who writes the code every other gate then judges, so it is the one decision the harness will not take from a session. If the user asks you to do it anyway, say that and give them the command.

Never move a definition into `.claude/agents/`, edit `FLEET.md`, or append to `evals/admissions.log` by hand. Those are written by `bin/admit.sh` alone, and `bin/fleet-check.sh` fails if they disagree.
