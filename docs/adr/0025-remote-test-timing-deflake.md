# ADR-0025: Carry a timing deflake for two inherited remote tests until a sync brings it

- **Status:** Accepted
- **Date:** 2026-10-30
- **Deciders:** The operator
- **Source:** The "Behavior portable serial 5" CI shard failing on main and pull requests; option A, carry both test fixes under one exception

## Context

The "Behavior portable serial 5" CI shard fails intermittently on main and on pull requests.
In `tests/fm-remote-secondmate-lifecycle-e2e.test.sh`, the watcher auto-relaunch leg gives up on a fixed 30-second wall-clock bound, while the relaunch it waits for has a floor of roughly 28 seconds and the watcher itself bounds it at 120 seconds, so a slow runner fails a relaunch the watcher still accepts.
In `tests/fm-remote-job.test.sh`, the stale-ownership leg kills only the serving worker child, so its restart supervisor and readiness heartbeat can outlive the crash and refresh readiness or republish ownership after the leg plants its stale records.

Upstream already fixed the first leg in [kunchenguid/firstmate@3004ccb107](https://github.com/kunchenguid/firstmate/commit/3004ccb107), part of [kunchenguid/firstmate#7518](https://github.com/kunchenguid/firstmate/pull/7518).
Upstream has no fix for the second leg; its copy of the test is identical to ours.

ADR-0001 otherwise prohibits editing upstream files, and no existing exception covers these two tests.

## Decision

ADR-0001 remains the default, but until an upstream synchronization brings equivalent changes, the following inherited files may carry exactly these hunks:

- `tests/fm-remote-secondmate-lifecycle-e2e.test.sh`: the watcher auto-relaunch leg hunk from upstream 3004ccb107, byte-identical, which pins `FM_SECONDMATE_LIVENESS_TIMEOUT` and waits for that bound plus 30 seconds of probe headroom on the wall clock
- `tests/fm-remote-job.test.sh`: a local hunk in the stale-ownership leg that kills the crashed worker's whole process group and waits for it to exit before planting the stale records

No product script changes, and neither leg asserts less than before.
The local `fm-remote-job` hunk is kept minimal so it can be offered upstream later through the normal contribution path; this exception does not publish it.
Every other upstream file, and every other change to these two tests, remains outside this exception.

The exception retires itself.
When an upstream synchronization brings 3004ccb107 or an equivalent change, that merge takes upstream's version of the e2e test, and the A4 allowlist drops it as it returns to upstream bytes.
When upstream accepts the `fm-remote-job` fix or an equivalent one, the same happens for that test.
This ADR is then superseded by the merge that retires its last path.

## Consequences

The shard stops failing a relaunch or crash recovery that the product handles correctly on a slow runner.
A genuinely stuck watcher still fails the leg, now after the watcher's own relaunch bound rather than an arbitrary shorter one.
Because the e2e hunk matches upstream, a synchronization that brings it merges without conflict.
Until both paths retire, every synchronization has these two files as an explicit contact surface to review.

## Verification

Both tests run in the "Behavior portable serial 5" CI shard.
The fork-contract workflow rejects any path outside the PixelOven namespaces and accepted ADR exceptions.

## Alternatives considered

- **Raise the fixed loop count only.** Rejected because the bound would still be unrelated to the watcher's own relaunch timeout, and upstream already replaced that approach.
- **Carry only the upstream e2e hunk.** Rejected because the stale-ownership race also fails the shard, and it has a deterministic reproduction.
- **Change the watcher or the remote job worker.** Rejected because the product behavior is correct; only the tests' timing and crash fixture were wrong.
- **Wait for an upstream synchronization.** Rejected because a red required shard blocks every pull request, and upstream has no fix for the second leg.
