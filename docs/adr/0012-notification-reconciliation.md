# ADR-0012: Notification reconciliation may modify bounded upstream surfaces

- **Status:** Accepted
- **Date:** 2026-09-08
- **Deciders:** The operator
- **Source:** Process-result notification reliability reconciliation

## Context

Reliable process-result presentation crosses the inherited process-event runner, durable wake queue, watcher, agent handling procedure, operator documentation, and their focused tests.
Implementing that behavior only in a new PixelOven namespace would leave the inherited clients on the old notification path and would not fix delivery.

ADR-0001 otherwise prohibits editing upstream files, and the existing exceptions do not authorize notification behavior in these surfaces.
The exception therefore needs to be explicit and no broader than the cross-layer path exercised by the change.

## Decision

ADR-0001 remains the default, but the following existing upstream files may carry narrowly reviewed process-result notification reconciliation hunks:

- `.agents/skills/process-event-sources/SKILL.md`
- `bin/fm-procevent-lib.sh`
- `bin/fm-procevent.sh`
- `bin/fm-wake-lib.sh`
- `bin/fm-watch.sh`
- `docs/configuration.md`
- `docs/remote-secondmates.md`
- `tests/fm-pi-watch-extension.test.sh`
- `tests/fm-procevent.test.sh`
- `tests/fm-wake-queue.test.sh`
- `tests/fm-watch-triage.test.sh`

[`docs/configuration.md`](../configuration.md#process-to-event-sources-stateprocevent) remains the single owner of the durability and presentation contract.
The skill owns only the handling procedure, and the remote-secondmate page carries only the client-path consequence.
Every other upstream file remains outside this exception.
Renames, broad rewrites, unrelated cleanup, and changes to preserved fleet state or historical evidence remain prohibited.

## Consequences

The inherited clients can implement and test one coherent notification path without pretending those changes are additive-only.
Future upstream merges have an explicit eleven-file contact surface to review.
The fork-contract gate accepts exactly these paths while continuing to reject unrelated upstream-file changes.

## Verification

The focused executable tests exercise capture, queueing, presentation, replay, acknowledgement, marker retirement, and watcher continuity through their public script interfaces.
The fork-contract workflow compares the complete tree against the current upstream pin and rejects any path outside the PixelOven namespaces and accepted ADR exceptions.

## Alternatives considered

- **Implement a parallel PixelOven-only notification stack.** Rejected because inherited clients would keep using the unreliable path and two notification control planes would drift.
- **Allow every inherited process-event or watcher file.** Rejected because the change needs only the exact files listed above.
- **Treat the existing `docs/configuration.md` exception as sufficient.** Rejected because ADR-0010 authorizes only companion-distribution and documentation-audience hunks in that file.
