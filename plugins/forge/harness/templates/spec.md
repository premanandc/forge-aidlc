# <T>: <title>

## Behaviour
The behaviour in prose with concrete example values (an NPI, a provider type, a date), so a
reader can picture one run of it.

## Acceptance criteria
Numbered. Each one observable and testable, one behaviour each, with example values. Cover the
happy path, every failure path, and what must stay unchanged.
1. Given ..., when ..., then ...

## Cross-functional criteria
The requirements that are not about what it computes. Named prompts, because a blank invitation
to "consider non-functional concerns" is always answered with silence. Each one gets a numbered,
testable criterion or the words `not applicable, because ...` so a thin answer is visible rather
than absent:
- **Latency and load**: what the change puts on a request path, and what is acceptable.
- **Authorisation**: who may do the new thing, and who may not.
- **Auditability**: what must be recorded about who changed what, and when.
- **Operability**: how an operator sees the new failure modes. A fallback that hides a
  misconfiguration needs something that says so.
- **Data**: retention, migration of what already exists, and what happens to it on rollback.

## Contract
Drafted by the architect. The surface tests may compile against, nothing more:
- Module: one of enrollment, screening, decision, registry, correspondence, shared.
- Types: every existing or new type by fully qualified name; new methods with signatures.
- Events: published or consumed; event records live in `shared.events`, implement `ForgeEvent`
  and are constructed only by the owning module. An added or changed event needs an ADR.
- Persistence: the Liquibase changeset, if any. HTTP: paths, verbs, status codes, problem types.
- Unchanged: what a reader might expect to move but does not.

## Open questions
One checkbox each; the product owner (or the architect for Contract questions) answers before
accepting. An unticked box blocks bin/accept.sh.
- [ ] ...

## Out of scope

<!-- Acceptance is the Accepted-By trailer on the spec: commit, written by bin/accept.sh. -->
