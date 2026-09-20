# <T>: <title>

## Steps
Numbered; each names the file it touches and stays inside the Contract.
1. ...

## Files
Every production file added or changed.

## Risks
What could go wrong inside the gate, and what the implementer watches.

## Boundary review
Written by the architect (verdict line `Fits.` or `Does not fit: <why>`, then what the
implementer must watch), or by bin/ticket.sh as `Skipped by policy: architectureReview resolved
optional (risk <r>)`. The plan: commit carries `Reviewed-By: architect` or
`Architecture-Review: skipped (policy)` to match.
