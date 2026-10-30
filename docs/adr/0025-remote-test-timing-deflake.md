# ADR-0025: Carry a timing deflake for two inherited remote tests

- **Status:** Proposed
- **Date:** 2026-10-30
- **Deciders:** The operator
- **Source:** The "Behavior portable serial 5" CI shard failing on main and pull requests

## Context

The "Behavior portable serial 5" CI shard fails intermittently on main and on pull requests.
In `tests/fm-remote-secondmate-lifecycle-e2e.test.sh`, the watcher auto-relaunch leg gives up on a fixed 30-second wall-clock bound, shorter than the relaunch bound the watcher enforces itself, so a slow runner fails a relaunch the watcher still accepts.
In `tests/fm-remote-job.test.sh`, the stale-ownership leg kills only the serving worker child, so its restart supervisor and readiness heartbeat can outlive the crash and republish ownership after the stale records are written.

ADR-0001 otherwise prohibits editing upstream files, and no existing exception covers these two tests.

## Decision

ADR-0001 remains the default, and the following inherited files may carry this one bounded change:

- `tests/fm-remote-secondmate-lifecycle-e2e.test.sh`: the watcher auto-relaunch leg sets `FM_SECONDMATE_LIVENESS_TIMEOUT` explicitly and waits for that bound plus probe headroom on the wall clock
- `tests/fm-remote-job.test.sh`: the stale-ownership leg kills the crashed worker's whole process group and waits for it to exit

No product script changes, and neither leg asserts less than before.

The change is kept minimal so it can be offered upstream.
When an upstream synchronization brings an equivalent change, that merge takes upstream's version of both files, the A4 allowlist drops them, and this ADR is superseded by that merge.

## Consequences

The shard stops failing a relaunch or crash recovery that the product handles correctly on a slow runner.
A genuinely stuck watcher still fails the leg, now after the watcher's own relaunch bound rather than an arbitrary shorter one.
Until an upstream synchronization brings an equivalent change, every synchronization has these two files as an explicit contact surface to review.

## Verification

Both tests run in the "Behavior portable serial 5" CI shard.
The fork-contract workflow rejects any path outside the PixelOven namespaces and accepted ADR exceptions.

## Alternatives considered

- **Raise the fixed loop count only.** Rejected because the bound would still be unrelated to the watcher's own relaunch timeout and could drift from it again.
- **Change the watcher or the remote job worker.** Rejected because the product behavior is correct; only the tests' timing and crash fixture were wrong.
- **Leave the shard failing until upstream fixes it.** Rejected because a red required shard blocks every pull request.
