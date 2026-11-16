# ADR-0035: Carry a third CI lint partition until a sync brings one

- **Status:** Accepted
- **Date:** 2026-11-16
- **Deciders:** The operator
- **Source:** "Lint 1" cancelled at the 30-minute job timeout on main and on pull requests #61, #62, #63, #64, and #65; self-retiring local carry

## Context

`bin/fm-lint.sh --partition` splits the canonical shell inventory across CI runners by packing roots largest-first by file bytes, and `.github/workflows/ci.yml` ran two partitions as `Lint 1` and `Lint 2` under the shared 30-minute normal-tier timeout.
Bytes are only a proxy for ShellCheck time, and runner speed varies.
On main, each partition already spent 1,178 to 1,482 seconds in ShellCheck, so the jobs took 20 to 27 minutes and were cancelled at the cap on slower runners.
On pull request #63, the added files moved about 470 seconds of slow roots into partition 1, which reached at least 1,781 seconds of ShellCheck time and was cancelled at the cap on every attempt.
No diagnostic was involved; the cut is the packing plus runner speed.

The inherited parser accepts only `1of2` and `2of2`, and ADR-0001 otherwise prohibits editing inherited files.

## Decision

ADR-0001 remains the default, and the following inherited files may carry these bounded changes:

- `bin/fm-lint.sh`: `--partition KofN` for any `N` of 2 or more, packing roots onto the least-loaded of `N` partitions with ties to the lowest index, plus the matching header, usage, and refusal text.
  For `N` of 2 the selection is identical to the inherited one.
- `.github/workflows/ci.yml`: the lint matrix `partition: [1, 2, 3]`, which adds a `Lint 3` job.
- `tests/fm-lint.test.sh`: the partition regression covering complete, disjoint, source-aware two- and three-partition splits and the refused malformed values.

The byte-weight proxy, the per-root bounds, the timeout tiers, and every other lint behavior are outside this exception.
Upstream's `CONTRIBUTING.md` required-check list and `docs/fm-test-portable-shards.md` job count still describe two lint partitions; they stay upstream bytes and this record owns the downstream count.
This carry retires itself: when an upstream synchronization brings its own partition-count support or a lint matrix of three or more, that merge takes upstream's parser, matrix, and test, and this exception ends.

## Consequences

Each lint job carries about a third of the inventory instead of half.
Replaying the packing against per-root ShellCheck times from CI telemetry reproduces measured partition totals within 2 seconds, and with each root at its slowest observed time across three runs, the largest of three partitions is 1,155 seconds on main and 1,194 seconds with pull request #63's files, about 20 minutes against the 30-minute cap.
Every pull request and push runs one more lint job, so total lint runner time grows only by one job's setup, about a minute.
`Full suite` already needs every lint leg, so `Lint 3` gates it without any other change.

## Verification

`tests/fm-ci-workflow.test.sh` proves the CI lint matrix covers every canonical root exactly once through `bin/fm-lint.sh --partition KofN --list-files`, and `tests/fm-lint.test.sh` proves both splits are complete, disjoint, deterministic, and full analysis.
Each lint job uploads per-root telemetry as `fm-lint-telemetry-<partition>`, which shows its remaining headroom.
The fork-contract workflow rejects any path outside the PixelOven namespaces and accepted ADR exceptions.

## Alternatives considered

- **Raise the lint job's `timeout-minutes`.** Rejected because it breaks the one shared normal-tier budget that `tests/fm-ci-workflow.test.sh` enforces, and lets lint wall time keep growing unchecked.
- **Weight partitions by measured time instead of bytes.** Rejected because it needs a committed per-root timing table in the inherited script that rots as files change, which is a larger and longer-lived hunk, while three byte-balanced partitions already leave about ten minutes of headroom.
- **Four partitions.** Rejected for now because three already give that headroom; four would bring the largest partition to at most about 940 seconds for one more job on every run.
- **Waive the cancelled lint checks.** Rejected because the cap cancels them on main too; a waiver hides the problem instead of fixing it.
