# <T>: <title>

## Behaviour
The behaviour in prose with concrete example values (an NPI, a provider type, a date), so a
reader can picture one run of it.

## Acceptance criteria
Numbered. Each one observable and testable, one behaviour each, with example values. Cover the
happy path, every failure path, and what must stay unchanged.
1. Given ..., when ..., then ...

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
