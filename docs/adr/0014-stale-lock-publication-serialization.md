# ADR-0014: Stale-lock publication serialization may modify bounded upstream surfaces

- **Status:** Accepted
- **Date:** 2026-09-13
- **Deciders:** The operator
- **Source:** Captain-approved hosted stale-lock scheduling race correction

## Context

An ordinary claimant could publish a primary lock after its precheck while a stale-lock stealer held the matching mutex.
That interleaving could make the stealer fail and then make the ordinary claimant remove its own candidate, leaving no winner.
The serialization guard also had to remain recoverable if its own process died after publication, without growing an unbounded chain of guard locks.
Upstream later replaced the recursive steal-mutex chain with a per-reaper tombstone reaper but kept the zero-winner interleaving, so only the serialization remains downstream.
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

Primary-lock publication and stale-lock stealing share upstream's nonblocking steal mutex, and a dead mutex holder is reaped through upstream's tombstone reaper rather than a downstream guard level.
The downstream terminal guard was dropped in the second stage of the `v0.3.0` synchronization in favour of that reaper.
A losing claimant reports a holder PID only while that process is live, so a watcher start reports recovery in progress instead of naming a dead recorded PID.
A claimant that loses only the publication mutex while the lock is absent retries rather than stealing, and never reports the mutex holder as the lock's holder.
A directory-form publication mutex left by a pre-symlink build is not reaped, and while it remains it blocks ordinary publication of that lock; no current build creates one.
Each ordinary acquisition pays one extra mutex publication and release.
The focused regression may live beside the inherited watcher-lock tests without weakening the additive-only fork rule.
The fork-contract gate accepts exactly these paths while continuing to reject unrelated upstream-file changes.

## Alternatives considered

- **Keep the race and retry at callers.** Rejected because zero winners is a shared lock-boundary defect.
- **Permit every inherited watcher test.** Rejected because this correction needs only the existing focused watcher-lock suite.
- **Add a parallel PixelOven lock implementation.** Rejected because callers would remain on the unsafe inherited boundary and two lock implementations would drift.
