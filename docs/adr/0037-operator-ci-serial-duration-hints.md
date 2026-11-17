# ADR-0037: The test runner may carry operator-CI duration hints for inherited serial scripts

- **Status:** Accepted
- **Date:** 2026-11-17
- **Deciders:** The operator
- **Source:** "Behavior portable serial 11" cancelled at the 30-minute job timeout twice on pull request #67 and ran 25 to 29 minutes on main and other pull requests; local carry refreshed or retired at each upstream synchronization

## Context

`bin/fm-test-run.sh` packs the portable serial test lane into twelve CI shards by longest-processing-time assignment over the hints in `portable_serial_weight_hints`, and a script without a hint is packed at the 45,000 ms default.
The inherited hints come from upstream's CI and had drifted far from what those scripts cost on operator CI.
`tests/fm-pr-check-security.test.sh` was hinted at 300,675 ms but took 417 to 501 seconds, `tests/fm-teardown.test.sh` 202,132 ms against 338 to 451 seconds, and `tests/fm-watch-arm.test.sh` 113,076 ms against 274 to 300 seconds.
Under their low hints the packer put all three on shard 11, which then measured 1,445 to 1,725 seconds of test time across the eleven operator CI runs sampled, while other shards measured 800 to 1,400.
On pull request #67 those three ran slower still (588, 529, and 325 seconds), and shard 11 was cancelled at the cap on both attempts.

ADR-0029 covers hint rows only for PixelOven-owned scripts, and ADR-0001 otherwise prohibits editing inherited files.

## Decision

ADR-0001 remains the default, and `bin/fm-test-run.sh` may carry operator-CI values in `portable_serial_weight_hints` for inherited portable serial scripts.
A row is carried when the script's median successful `duration_ms` across at least five recent operator CI portable serial timing artifacts differs from its inherited hint, or from the default for a script with none, by more than 30,000 ms; the row then holds that median.
Rows inside that margin keep upstream's value.
New rows sit in the table's sorted position, and changed rows keep their place.

The first rows come from the `fm-test-timing-portable-serial-*` artifacts of operator CI runs 43952258021, 43957378911, 43959970682, 43960027898, 43961839098, 43970909427, 43973358572, 43976722987, 43994645201, 44152382129, and 44154531545: 32 inherited values changed and 38 rows added for scripts that had none.

The median rather than the slowest sample is deliberate.
Runner speed varies per job, not per script: across those runs a whole shard ran up to 1.5 times its scripts' median cost, so a script's slowest sample mostly records which runner it landed on.
Packing on slowest samples would also break the packing target outright, since one slow-runner sample of `tests/fm-remote-secondmate-lifecycle-e2e.test.sh` (1,467,526 ms) exceeds it on its own.
The packing target's ten-minute reserve under the job timeout is what absorbs runner variance.

The shard count, the default weight, the coverage bounds, the packing logic, and every other runner behavior are outside this exception.
Upstream's `docs/fm-test-portable-shards.md` still describes the inherited hint provenance; it stays upstream bytes and this record owns the downstream values.
At each upstream synchronization, a changed upstream row takes upstream's value, and any row still differing from upstream by more than the margin is refreshed from a later operator timing artifact set rather than kept by hand; when no row differs by the margin, this exception ends.

## Consequences

With the carried rows, the largest modeled serial shard is 1,087,033 ms, and 6 of 303 portable serial scripts remain unmeasured.
The three heavy scripts land on three different shards.
Replaying the new packing against those runs, each shard's median-cost total is 1,058 to 1,142 seconds, about 19 minutes of job time with setup, where shard 11 sat at 1,488 seconds before.
Replaying each run's own per-script durations, the largest shard in any run is 1,560 seconds, about 26.6 minutes, and that run's figure is mostly one slow-runner sample of the lifecycle script, which no packing can split.
With every script at its slowest sample and pull request #67's three slow samples, the largest shard is 1,593 seconds, about 27 minutes.
The table now differs from upstream in 70 rows, so an upstream hint refresh conflicts beside them; each such conflict resolves by the synchronization rule above.

## Verification

`bin/fm-test-run.sh --check-coverage`, which CI runs as its test coverage guard job, reports the largest modeled serial shard and the unmeasured share and refuses past 1,200,000 ms or 15%.
Each portable serial job uploads `fm-test-timing-portable-serial-<shard>`, which shows its measured headroom and is the input to the next refresh.
The fork-contract workflow rejects any path outside the PixelOven namespaces and accepted ADR exceptions.

## Alternatives considered

- **Add a thirteenth serial shard.** Rejected because it does not fix the cause: under the stale hints, replaying a thirteen-shard packing still puts the three heavy scripts together, and its largest shard's median-cost total is 1,532 seconds, worse than twelve shards today.
- **Refresh every inherited row.** Rejected because it changes about 300 inherited rows for a packing whose worst replayed shard (1,563 seconds) is no better than this one's, so every upstream hint change would conflict.
- **Raise the serial job's `timeout-minutes`.** Rejected because it breaks the one shared normal-tier budget that `tests/fm-ci-workflow.test.sh` enforces and leaves the imbalance in place.
- **Waive the cancelled serial check.** Rejected because the same shard runs near the cap on main; a waiver hides the problem instead of fixing it.
