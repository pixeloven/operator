# ADR-0030: Carry upstream's Pi Calm fake-host field until a sync brings it

- **Status:** Accepted
- **Date:** 2026-11-12
- **Deciders:** The operator
- **Source:** "Behavior portable serial 11" CI failure on main, case "Pi Calm queued operational rows" in `tests/fm-calm-pi-extension.test.sh`; self-retiring upstream carry

## Context

From Pi 1.5.1, `InteractiveMode.updatePendingMessagesDisplay()` iterates the instance field `pendingBashComponents`, which Pi's constructor initializes.
`makeHost()` in `tests/fm-calm-pi-extension.test.sh` builds its fake host with `Object.create(InteractiveMode.prototype)`, which skips those initializers, so the test throws `this.pendingBashComponents is not iterable`.
Real Pi constructs the field, so the Calm extension is unaffected; only the test's fake host is incomplete.

Upstream added the same field to `makeHost()` in `kunchenguid/firstmate` commit `1d43f9cb797836015aecb5aa4c6e14cb3124c1f0` (2026-11-11), after this fork's upstream pin.
ADR-0001 otherwise prohibits editing upstream files.

## Decision

ADR-0001 remains the default, but until an upstream synchronization brings that commit or an equivalent, `tests/fm-calm-pi-extension.test.sh` may carry upstream's one-line `pendingBashComponents: [],` hunk in `makeHost()`, byte-identical to that commit.
Every other line of the file, and every other Pi test, remains outside this exception.

The exception retires itself.
When an upstream synchronization brings the hunk, the file returns to upstream bytes, the A4 allowlist drops the path, and this ADR is superseded by that merge.

## Consequences

The Pi Calm tests pass on Pi 1.5.1 and later.
Because the carried bytes match upstream's, the synchronization that brings them merges without conflict.

## Verification

`tests/fm-calm-pi-extension.test.sh` runs against the Pi release that `.github/workflows/ci.yml` installs.
The fork-contract workflow rejects any path outside the PixelOven namespaces and accepted ADR exceptions.

## Alternatives considered

- **Wait for the next upstream synchronization.** Rejected because main stays red until then.
- **Write an operator-specific fix.** Rejected because a divergent hunk would conflict with upstream's identical fix at the next synchronization.
