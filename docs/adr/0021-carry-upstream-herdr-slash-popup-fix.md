# ADR-0021: Carry upstream's Herdr slash-popup composer fix until a sync brings it

- **Status:** Accepted
- **Date:** 2026-10-26
- **Deciders:** The operator
- **Source:** Herdr send-failure investigation; option B, carry the upstream fix now

## Context

Claude Code 2.1.291 and later marks the selected row of its slash-command popup with `❯`, the same glyph its composer uses.
The inherited composer classifier in `bin/fm-composer-lib.sh` reads that marked row as the bottom-most composer candidate, so a typed `/command` sitting above its popup is never proven as the payload.
On Herdr that refuses every slash-command delivery: slash steers through `fm-send`, the `/exit` behind `fm-control exit` and `relaunch`, and secondmate restarts.
Plain-text steers still work.

Upstream's fix is [kunchenguid/firstmate#6695](https://github.com/kunchenguid/firstmate/pull/6695), "fix(bin): restore Claude slash-command submission on Herdr", open and unmerged at head `c5903f6291a1c225de1f2ada2e6e901825cfce56` on base `127f0f30a4b272b68ec9196bf47d4db90ad40617`.
The operator's investigation verified it live against Claude 2.1.311.
Every hunk applies to this tree with exact context, because operator has not changed these files since the upstream pin.

ADR-0001 otherwise prohibits editing upstream files, and no existing exception covers the composer classifier.

## Decision

ADR-0001 remains the default, but until an upstream synchronization brings #6695 or an equivalent fix, the following inherited files may carry that pull request's hunks, byte-identical to its head:

- `bin/fm-composer-lib.sh`: the new `_fm_composer_bare_is_popup_selection` guard, its call in `_fm_composer_select_cursorless`, that function's two extra arguments and its two call sites, and the classifier comment naming the exception
- `tests/fm-composer-lib.test.sh`
- `tests/fm-backend-herdr.test.sh`
- `tests/fm-herdr-submit-confirm-live-e2e.test.sh`
- `tests/captures/claude-2.1.291-slash-popup/`, six new captured screens the tests read

Upstream's matching hunk in `docs/verification/runtime-backends.md` records its own verification runs and is not carried; the synchronization that brings the fix brings it.
Every other upstream file, and every other composer or Herdr change, remains outside this exception.

The exception retires itself.
When an upstream synchronization brings #6695 or an equivalent fix, that merge takes upstream's version of each file above, and the A4 allowlist drops these paths as they return to upstream bytes, exactly as earlier synchronizations dropped returned ADR-0012 paths.
This ADR is then superseded by the merge that retired it.

## Consequences

Slash-command delivery to Claude Code workers on Herdr works again without waiting for upstream to merge.
Because the carried bytes match the upstream pull request, a synchronization that brings it merges these hunks without conflict; a synchronization that brings a different fix replaces them with upstream's.
Until then, every synchronization has these files as an explicit contact surface to review.

## Verification

The focused composer and Herdr backend tests exercise the marked popup row against the captured Claude 2.1.291 screens through the public classifier and send paths, including refusal of a partial payload while the popup is on screen.
The live end-to-end test stays opt-in, as upstream ships it.
The fork-contract workflow rejects any path outside the PixelOven namespaces and accepted ADR exceptions.

## Alternatives considered

- **Wait for upstream to merge #6695.** Rejected because every slash steer, worker exit, relaunch, and secondmate restart on Herdr fails until then.
- **Write an operator-specific fix.** Rejected because a divergent fix in the same function would conflict with whatever upstream lands, against the guidance to align with upstream practice.
- **Carry the whole pull request, including its verification doc.** Rejected because the doc hunk records upstream's own runs and is not needed for the behavior.
