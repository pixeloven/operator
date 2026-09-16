# ADR-0014: Stale-lock publication serialization may modify bounded upstream surfaces

- **Status:** Accepted
- **Date:** 2026-09-13
- **Deciders:** The operator
- **Source:** Captain-approved hosted stale-lock scheduling race correction

## Context

An ordinary claimant could publish a primary lock after its precheck while a stale-lock stealer held the matching mutex.
That interleaving could make the stealer fail and then make the ordinary claimant remove its own candidate, leaving no winner.
The serialization guard also had to remain recoverable if its own process died after publication, without growing an unbounded chain of guard locks.
Correcting the shared lock boundary and proving both interruption windows requires changes to inherited lock code and its focused regression.

## Decision

ADR-0001 remains the default, but the following existing upstream files may carry narrowly reviewed stale-lock publication serialization hunks:

- `bin/fm-wake-lib.sh`
- `bin/fm-watch.sh`
- `docs/watcher-continuity.md`
- `tests/fm-watcher-lock.test.sh`

[`docs/watcher-continuity.md`](../watcher-continuity.md) remains the single owner of the current lock behavior and regression contract.
Every other upstream file remains outside this exception.

## Consequences

Primary-lock publication and stale-lock stealing share a nonblocking mutex boundary whose abandoned guard is reclaimed through one terminal recovery level.
The focused regression may live beside the inherited watcher-lock tests without weakening the additive-only fork rule.
The fork-contract gate accepts exactly these paths while continuing to reject unrelated upstream-file changes.

## Alternatives considered

- **Keep the race and retry at callers.** Rejected because zero winners is a shared lock-boundary defect.
- **Permit every inherited watcher test.** Rejected because this correction needs only the existing focused watcher-lock suite.
- **Add a parallel PixelOven lock implementation.** Rejected because callers would remain on the unsafe inherited boundary and two lock implementations would drift.
