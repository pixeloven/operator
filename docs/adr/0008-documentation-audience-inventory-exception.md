# ADR-0008: Fork documentation may extend the upstream audience inventory

- **Status:** Accepted
- **Date:** 2026-08-22
- **Deciders:** Brian Gebel (the operator)
- **Source:** PR #8 diagnosis; requirement **O-1**

## Context

The upstream `bin/fm-doc-audience-check.sh` enumerates every tracked maintained-prose path and requires one classification in `docs/documentation-audiences.json`.
Sixteen existing PixelOven documents under `docs/adr/` and `docs/pixeloven/` are therefore unclassified, so the inherited portable serial shard fails identically on `main` and PR #8.
The checker accepts an alternate inventory at its command line, but the inherited test invokes the central inventory and offers no fork extension point.
Relocating fork prose cannot solve the failure because the inventory scope covers the whole repository.
The central inventory is upstream-owned, so changing it requires a deliberate exception to the additive-only rule in [ADR-0001](0001-soft-fork-of-firstmate.md).

## Decision

PixelOven may extend `docs/documentation-audiences.json` only to classify maintained prose under `docs/adr/` and `docs/pixeloven/`.
The exception does not permit changing the inventory version, scope, allowed audiences, setup audiences, README setup targets, required owner pointers, or any upstream classification.
The inventory path must retain its upstream regular-file mode so the exception cannot redirect the checker through a symlink.
Assertion A4 in `.github/workflows/pixeloven-gates.yml` permits this exact file and no other upstream-owned path.
The same PixelOven-owned workflow compares the current inventory with the inventory at the recorded upstream pin and fails unless every policy field and upstream surface remains semantically identical and every added surface belongs to one of the two fork-owned documentation namespaces.

## Consequences

The inherited documentation-audience check can validate PixelOven prose and its local links instead of remaining permanently red.
Every new maintained PixelOven document must receive an audience classification in the central inventory.
Upstream changes to the central inventory can conflict with the fork's classifications during a scheduled upstream merge.
The conflict cost is accepted because the semantic guard keeps the exception narrow and makes any broader policy drift fail closed.
No other upstream-owned file becomes writable under the fork contract.

## Alternatives considered

- Accept the inherited shard as permanently red.
  Rejected because the required outcome is a genuinely green PR and a red baseline masks future documentation defects.
- Maintain a second fork-owned audience inventory.
  Rejected because the inherited test invokes the upstream central inventory and would still fail.
- Ask upstream to add an extension mechanism.
  Deferred because it requires separate approval for upstream contact and does not repair the existing PR.
- Broadly allow upstream documentation or configuration edits in A4.
  Rejected because it would weaken the soft-fork contract beyond the one proven collision.
