# Golden tasks

Every candidate agent in `.claude/agents-candidates/` earns its place in `.claude/agents/` by
passing all three golden tasks under `evals/<agent>/`. `bin/admit.sh <agent>` runs them. An agent
must first be named in `.forge/fleet-catalog.json` with a family, a purpose, a ladder rung and a
human owner: admission refuses a candidate nobody is accountable for.

```
evals/<agent>/
  policy.sh        # the tool rules the candidate runs under (belt and braces with the guards)
  <task>/
    task.md        # the prompt the candidate receives, verbatim
    fixture/       # files overlaid onto a scratch worktree before the run (work/<T>/..., src/...)
    fixture.sh     # chain history laid down before the run, via evals/lib/fixture.sh
    assert.sh      # mechanical checks, sourcing evals/lib/assert.sh; exit 0 = pass
    expected/      # optional: a reference answer, so --selftest can prove the assertions pass
```

Tickets used by golden tasks are synthetic (`PF-9xx`) so an eval never pre-builds real backlog
work. Assertions check files, sections, diffs, compilation, test outcome and commit subjects.
There is no LLM judging: an admission gate that flakes teaches the wrong lesson.

`bin/admit.sh <agent> --selftest` runs each task's assertions against `fixture/` alone (must fail)
and against `fixture/` plus `expected/` when present (must pass), proving the assertions bite
without spending a Claude run.

## Fixtures carry the human gates

`evals/lib/fixture.sh` builds the chain history a task starts from, the way the real factory
produces it: `intent:`, `spec:` and `tests:` carry an `Accepted-By` trailer, because only
`bin/accept.sh` writes those commits and only for a human at a terminal. `fixture_drafting <T>
<stage>` leaves the `work/<T>/.drafting-<stage>` marker in place, which is what stops an agent
from committing its own draft. A fixture that skipped either would let a candidate pass a gate the
real chain would refuse.

- `fixture_accepted_spec <T> "<summary>"` — intent and spec accepted; where the test-designer starts.
- `fixture_locked_tests <T> "<summary>"` — the above plus accepted, locked tests; where the implementer starts.
- `fixture_drafting <T> <stage>` — an artifact drafted and not yet accepted.

## What the drafting agents must not do

`intent-drafter`, `spec-drafter` and `test-designer` sit on the assist rung: they produce an
artifact and stop. Their assertions check `assert_no_commit` and, for the test-designer, that
`work/<T>/.tests-locked` does **not** exist. Committing and locking are what a human's
`bin/accept.sh` does. An agent that does either has taken a decision that is not its to take, and
the golden task fails it for that alone, however good the artifact is.
