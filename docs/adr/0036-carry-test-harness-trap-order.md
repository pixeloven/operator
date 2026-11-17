# ADR-0036: Carry the test harness's signal-before-EXIT trap order until a sync brings it

- **Status:** Accepted
- **Date:** 2026-11-16
- **Deciders:** The operator
- **Source:** "Behavior portable serial 5" failing the `tests/fm-control.test.sh` dead-pid case on main and on pull requests #63 and #67; self-retiring local carry

## Context

The dead-pid leg of the Claude background-session case in `tests/fm-control.test.sh`, carried under ADR-0026, starts `sleep 30 &` and kills it at once to obtain a pid that is gone.
On CI it intermittently found its own fixture directory missing a moment after creating it, so it failed before it exercised `bin/fm-control.sh`.

`tests/lib.sh` armed its EXIT trap before its INT, TERM, HUP, and QUIT traps.
When a Bash 5.2 shell first sets an EXIT trap, it installs its own EXIT-running handler on every terminating signal not yet trapped and records that handler as the signal's original disposition.
A background child that receives a trapped signal before it has reset the traps it inherited restores the recorded original and re-raises the signal.
With the old order that original is the EXIT-running handler, so the child ran the parent shell's EXIT trap, which in `tests/fm-control.test.sh` is `rm -rf "$TMP_ROOT"`, and the suite lost every fixture under that root.
Arming the signal traps first records their real original disposition, so a signalled child dies from the signal without running any inherited trap.

Upstream `kunchenguid/firstmate` main `913bb7a` keeps the EXIT-first order.
`tests/lib.sh` and `tests/fm-test-fixture-cleanup.test.sh` are inherited files, and ADR-0001 otherwise prohibits editing them.

## Decision

ADR-0001 remains the default, and the following inherited files may carry these bounded changes:

- `tests/lib.sh`: the INT, TERM, HUP, and QUIT traps armed before the EXIT trap, with their actions unchanged, and the comment stating why the order matters.
- `tests/fm-test-fixture-cleanup.test.sh`: one regression case that signals freshly started background children from a shell sourcing `tests/lib.sh` and requires its live fixture root to survive.

No product script changes, and no test asserts less than before.
The change is kept minimal so it can be offered upstream through the normal contribution path; this exception does not publish it.
This carry retires itself: when an upstream synchronization brings an equivalent change, that merge takes upstream's version of both files, the A4 allowlist drops them, and this ADR is superseded by that merge.

## Consequences

A test that signals a background job it has just started no longer risks its parent's EXIT trap running in that child on Bash 5.2, including the dead-pid leg.
Untrapped terminating signals other than INT, TERM, HUP, and QUIT keep the old exposure, because no test in the suite sends them to a fresh child.
A test file that sets its own EXIT trap before it sources `tests/lib.sh` would still record the EXIT-running handler, and none does today.
Until an upstream synchronization brings an equivalent change, every synchronization has these two files as an explicit contact surface to review.

## Verification

On Bash 5.2.21, a shell that arms EXIT before TERM ran its EXIT trap in 2,994 of 3,000 immediately killed background children, while arming TERM first ran it in none.
On Bash 5.2.21 the unchanged `tests/fm-control.test.sh` fails the dead-pid leg with the CI error, and passes with the new order.
The new regression case fails on Bash 5.2.21 with the old order, and passes on Bash 3.2 and 5.2.21 with the new order.
The fork-contract workflow rejects any path outside the PixelOven namespaces and accepted ADR exceptions.

## Alternatives considered

- **Change only the dead-pid leg to wait for a process that exits on its own.** Rejected because the defect is in the shared harness, and any other test that signals a fresh background child would keep losing its fixtures the same way.
- **Skip cleanup in `fm_test_cleanup` unless it runs in the owning shell.** Rejected because Bash 3.2 has no `BASHPID`, and a test file's own EXIT trap, such as the one in `tests/fm-control.test.sh`, would not be covered.
- **Retry or skip the flaky leg.** Rejected because it hides a harness defect that removes live fixtures.
- **Wait for upstream.** Rejected because upstream keeps the EXIT-first order, and a red required shard blocks every pull request.
