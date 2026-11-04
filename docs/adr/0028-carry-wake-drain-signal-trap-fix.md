# ADR-0028: Carry the wake drain signal-trap fix until a sync brings it

- **Status:** Accepted
- **Date:** 2026-11-04
- **Deciders:** The operator
- **Source:** "Behavior portable serial 6" CI failure on pull request #47, where an interrupted wake drain survived TERM

## Context

On Bash 5.2, a trap that falls due while the shell rescans a `$(...)` word at expansion time runs inside that scan's half-open `$(` parser state.
That includes an unexecuted `${var:-$(...)}` alternative.
A plain trap action then fails with `trap: line 2: unexpected EOF while looking for matching ')'`, Bash discards the action, and the signal is lost.
Bash 5.3 defers such traps; no Bash 5.2 patch through 5.2.37 does, and the standard Ubuntu 24.04 runner ships Bash 5.2.21.

`bin/fm-wake-drain.sh` traps INT and TERM with plain `exit` actions so its EXIT cleanup runs on interruption.
In the CI failure, TERM landed as the drain released the recovery-marker lock, and the first `$(` scan after it was the `${BASHPID:-$(...)}` in `fm_current_pid`.
The drain lost TERM, finished, and exited 0, so `tests/fm-wake-queue.test.sh` reported that the pre-commit interruption unexpectedly succeeded.
A drain that ignores TERM or INT keeps running work its caller tried to stop.

Every fix lives in inherited files, and ADR-0001 otherwise prohibits editing them.

## Decision

ADR-0001 remains the default, and the following inherited files may carry these bounded changes:

- `bin/fm-wake-lib.sh`: `fm_trap_exit`, which traps signals to exit with a status through an action whose second line closes that phantom `$(` on Bash 5.2 and is never read elsewhere
- `bin/fm-wake-drain.sh`: installing its INT and TERM traps through `fm_trap_exit`
- `tests/fm-wake-queue.test.sh`: the regression cases that hold TERM pending at a `$(` scan, both through `fm_trap_exit` directly and through a drain acknowledgement

Every other trap in the repository is outside this exception.

The change is kept minimal so it can be offered upstream.
That offer is drafted later; nothing is published upstream now.
When an upstream synchronization brings an equivalent change, that merge takes upstream's version of these files, the A4 allowlist drops the ones no other ADR still needs, and this ADR is superseded by that merge.

## Consequences

The wake drain exits on INT and TERM on every supported Bash, including Bash 5.2, and its EXIT cleanup still runs.
Other scripts that trap signals with plain actions keep the Bash 5.2 exposure until separately fixed.
Until an upstream synchronization brings an equivalent change, every synchronization has these files as an explicit contact surface to review.

## Verification

The wake-queue tests force TERM to be pending at a `$(` scan and require exit status 143, the EXIT cleanup, an untouched queue, and a successful retry.
On Bash 5.2.21 both cases fail with the CI error when the drain's plain traps are restored, and they pass on Bash 3.2, 5.2.21, and 5.3.
The fork-contract workflow rejects any path outside the PixelOven namespaces and accepted ADR exceptions.

## Alternatives considered

- **Trap a named function instead of an inline string.** Rejected because Bash 5.2 fails to parse a function name in that state the same way.
- **Remove the `$(...)` from `fm_current_pid`.** Rejected because TERM then lands at the next `$(` scan instead; every command substitution in the drain's path is exposed.
- **Leave TERM and INT untrapped.** Rejected because the drain would then skip its EXIT cleanup on interruption.
- **Require Bash 5.3.** Rejected because the supported runners and hosts ship Bash 5.2 or 3.2.
- **Wait for upstream.** Rejected because upstream `kunchenguid/firstmate` main `bb8dd209` (2026-11-04) keeps the plain traps, and the drain keeps surviving TERM on Bash 5.2 meanwhile.
- **Contribute upstream first.** Deferred: an upstream offer follows later through the firstmate-self-repo path, and this carry retires when upstream lands an equivalent.
