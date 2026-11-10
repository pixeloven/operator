# ADR-0029: The test runner may carry duration hints for PixelOven-owned tests and a twelfth serial shard

- **Status:** Accepted
- **Date:** 2026-11-09
- **Deciders:** The operator
- **Source:** Sixth upstream synchronization; the merged tree tripped the runner's unmeasured-script and shard-packing bounds

## Context

`bin/fm-test-run.sh` packs the portable serial test lane into CI shards from measured duration hints, and its coverage guard refuses when more than 15% of portable serial scripts have no hint.
PixelOven-owned test scripts run in that lane, but the inherited hint table carried no rows for them.
Before the sixth synchronization, operator `main` stood at 42 of 282 unmeasured scripts (14.9%).
Upstream's own tree at `913bb7a7` stood at 44 of 296 (14.9%), so the merged tree reached 49 of 302 (16.2%) and failed the guard.
The five unmeasured scripts were all PixelOven-owned.

The same guard also refuses when the modeled packing of the largest portable serial shard exceeds 1,200,000 ms.
Upstream's own tree at `913bb7a7` already packs its largest of 11 shards to 1,195,718 ms, so with measured hints for the PixelOven scripts the merged tree's largest shard reached 1,200,355 ms, and leaving any one hint out still overflowed it.

ADR-0001 otherwise prohibits editing inherited files, and ADR-0026 covers only its own test's rows in this file.

## Decision

ADR-0001 remains the default, and `bin/fm-test-run.sh` may carry one row per PixelOven-owned test script in `portable_serial_weight_hints`.
A PixelOven-owned test script is one in a PixelOven namespace or claimed by an accepted ADR as a new file, such as `tests/po-*.test.sh` and `tests/fm-pixeloven-upstream-check.test.sh`.
Each value is the slowest successful `duration_ms` for that script in an operator CI timing artifact, and each row sits in the table's sorted position.

The first rows come from the `fm-test-timing-aggregate` artifact of operator `main` CI run 42423701373, where every sample exited 0:

- `tests/fm-pixeloven-upstream-check.test.sh`: 300 ms
- `tests/po-crew.test.sh`: 6601 ms
- `tests/po-delivery-lane-credential.test.sh`: 3194 ms
- `tests/po-theme-labels.test.sh`: 13679 ms
- `tests/po-theme.test.sh`: 27327 ms

`bin/fm-test-run.sh` may also set `PORTABLE_SERIAL_SHARDS=12`, and `.github/workflows/ci.yml` may carry the matching `shard: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]` matrix for the portable serial job.
This shard hunk retires itself: when an upstream synchronization brings an upstream shard count of 12 or more, that merge takes upstream's count and matrix, and only the hint rows remain under this exception.

Rows for inherited scripts, the guard, its bounds, and the packing logic are outside this exception.
Upstream's `docs/fm-test-portable-shards.md` still describes eleven serial shards; it stays upstream bytes and this record owns the downstream count.

## Consequences

The merged tree measures 44 of 302 unmeasured scripts (14.6%), the PixelOven scripts are packed on measured weights instead of the default guess, and the largest of 12 modeled serial shards packs to 1,100,330 ms.
Every pull request and push runs one more portable serial Linux job, roughly twenty minutes of runner time.
Every new PixelOven-owned test script that joins the portable serial lane needs a row here, refreshed from a later operator timing artifact when its cost changes.
The rows sit in an inherited sorted table, so an upstream synchronization can conflict beside them, as the sixth synchronization did on ADR-0026's row; each such conflict keeps both rows.

## Verification

`bin/fm-test-run.sh --check-coverage`, which CI runs as its test coverage guard job, reports the unmeasured share and the largest modeled serial shard and refuses past 15% or 1,200,000 ms, and `tests/fm-test-run.test.sh` asserts both bounds.
The fork-contract workflow rejects any path outside the PixelOven namespaces and accepted ADR exceptions.

## Alternatives considered

- **Run PixelOven-owned tests in the PixelOven gates workflow instead of the inherited lanes.** Rejected because it needs a runner exclusion hunk in the same inherited file plus a new job, and moves their coverage out of the inherited CI.
- **Prove the PixelOven scripts isolated and run them in the portable parallel lanes.** Rejected because it needs hunks in the inherited isolation-proof candidate set and a concurrent proof run, more surface than one shard count.
- **Raise the 15% bound or the packing target downstream.** Rejected because it weakens the inherited balance guard and is still an uncovered inherited-file hunk.
- **Ship the synchronization with the guard red under a waiver.** Rejected because the merge caused the failure; it is not a pre-existing flake on `main`.
