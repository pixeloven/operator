# ADR-0040: Carry the Herdr regroup of a relaunched secondmate's crew until a sync brings it

- **Status:** Accepted
- **Date:** 2026-11-20
- **Deciders:** The operator
- **Source:** Pull request #78; a navigator relaunched into a fresh Herdr workspace left its crew's projected workspaces under another parent; self-retiring local carry

## Context

Herdr presentation ordering places a new task's projected workspace directly after its owning home's workspace when the task spawns.
A secondmate relaunched into a fresh workspace is appended at the end of Herdr's workspace list, while the projected workspaces of its own running crew keep their old positions, so they now read as children of whichever parent precedes them.
Upstream `kunchenguid/firstmate` at the recorded pin never revisits that order after a secondmate launch.
`bin/fm-spawn.sh`, `bin/backends/herdr.sh`, and `docs/herdr-backend.md` are inherited files, and ADR-0001 otherwise prohibits editing them.

## Decision

The regroup lives in PixelOven's own `bin/po-herdr-regroup-lib.sh`, whose header owns its candidate rule, move sequence, and failure behavior.
It moves only the exact workspace ids that the secondmate home's own non-secondmate task records name for the session, only when the live label is a new-format projected child, using only the two verified `workspace.move` forms its header names, and it never closes, renames, restarts, or re-parents anything.
It builds on the Herdr adapter's existing helpers, so `bin/backends/herdr.sh` stays at upstream bytes.

ADR-0001 remains the default, and the following inherited files may carry these bounded changes:

- `bin/fm-spawn.sh`: one hunk after every Herdr secondmate launch that sources the library and, only when the home records a candidate, takes the existing session presentation-order lock and runs the regroup, warning and continuing when the lock is unavailable.
- `docs/herdr-backend.md`: one paragraph in "Ordering" describing the regroup, and a qualifying clause on the "Existing layouts are not force-renamed or rearranged" compromise.

`tests/po-herdr-regroup.test.sh` is PixelOven's own test, and its portable serial duration hint is an ADR-0029 row.
The change is kept minimal so it can be offered upstream through the normal contribution path; this exception does not publish it.
This carry retires itself: when an upstream synchronization brings an equivalent regroup, that merge takes upstream's version of both inherited files, the A4 allowlist drops `docs/herdr-backend.md`, the library and its test are deleted, and this ADR is superseded by that merge.

## Consequences

After a secondmate relaunch, its running crew's projected workspaces sit directly under it again in their existing relative order.
A secondmate home with no recorded crew workspace takes no lock and makes no Herdr call, so a first launch keeps upstream's command sequence exactly.
Every failed, ambiguous, or unverifiable step warns and leaves Herdr's current order, and the launch never fails because of the regroup.
Until an upstream synchronization brings an equivalent change, every synchronization has the one `bin/fm-spawn.sh` hunk and the `docs/herdr-backend.md` paragraph as an explicit contact surface to review.

## Verification

`tests/po-herdr-regroup.test.sh` drives the library against a stateful fake Herdr CLI and a mover that accepts only the two verified move forms, covering candidate selection, placement under a non-last parent, relative order, a failed move, and a home with no candidates that makes no Herdr call.
`tests/fm-backend-herdr-presentation-e2e.test.sh` proves on a real isolated Herdr lab session that a secondmate launch with no recorded crew makes no ordering or session-list call.
The fork-contract workflow rejects any path outside the PixelOven namespaces and accepted ADR exceptions, and assertion A9 holds `bin/backends/herdr.sh` to its registered theme hooks.

## Alternatives considered

- **Keep the function in `bin/backends/herdr.sh` and register each added line as a `lib` row.** Rejected because about 135 rows, many of them bare `fi`, `}`, and `return 0` lines, would make the hook registry carry a whole function and every synchronization of the adapter would conflict in that region.
- **Regroup from the watcher on every poll.** Rejected because it widens a presentation fix into a recurring rearrangement of layouts people may have arranged by hand.
- **Leave the order and rely on labels.** Rejected because a projected child's position is how a person reads which home owns it.
- **Wait for upstream.** Rejected because upstream has no equivalent change and relaunches happen in ordinary use.
