# ADR-0013: Archived captain-hold completion may modify bounded upstream surfaces

- **Status:** Accepted
- **Date:** 2026-09-14
- **Deciders:** The operator
- **Source:** Captain-approved archived answer compatibility

## Context

Captain-held task completion must recognize previously answered legacy decisions after tasks-axi retention moves them from the active backlog into `data/done-archive.md`.
The canonical completion owner, its lifecycle documentation, and its focused executable regression are inherited upstream files.
Implementing archive compatibility only in a new PixelOven namespace would leave the active completion path unchanged.

ADR-0001 otherwise prohibits editing upstream files, and the existing exceptions do not authorize captain-hold completion behavior in these surfaces.
The exception therefore needs to be explicit and limited to the owner, its contract, and its regression.

## Decision

ADR-0001 remains the default, but the following existing upstream files may carry narrowly reviewed archived captain-hold completion hunks:

- `bin/fm-captain-hold.sh`
- `docs/captain-hold-lifecycle.md`
- `tests/fm-captain-hold-lifecycle.test.sh`

[`docs/captain-hold-lifecycle.md`](../captain-hold-lifecycle.md) remains the single owner of the current lifecycle contract.
Every other upstream file remains outside this exception.
Renames, broad rewrites, unrelated cleanup, and changes to private fleet lifecycle records remain prohibited.

## Consequences

The inherited completion path can verify canonical archived answer provenance without weakening active-row, exact-identity, close-mode, replay, or missing-row refusal guarantees.
Future upstream merges have an explicit three-file contact surface to review.
The fork-contract gate accepts exactly these paths while continuing to reject unrelated upstream-file changes.

## Verification

The focused executable lifecycle test exercises active and archived captain-hold completion through the public script interface, including valid current and legacy records and malformed, ambiguous, unresolved, or missing provenance.
The fork-contract workflow compares the complete tree against the current upstream pin and rejects any path outside the PixelOven namespaces and accepted ADR exceptions.

## Alternatives considered

- **Implement a parallel PixelOven-only completion command.** Rejected because existing callers would remain on the inherited owner and two lifecycle authorities would drift.
- **Permit every inherited captain-hold surface.** Rejected because the compatibility change needs only the exact owner, contract, and regression listed above.
- **Treat the existing notification-reconciliation exception as sufficient.** Rejected because ADR-0012 authorizes a different behavior and does not list these files.
