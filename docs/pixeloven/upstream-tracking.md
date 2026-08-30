# Upstream tracking

Ledger of this fork's distance from `kunchenguid/firstmate`. One row per
observation or merge. Its purpose is to make the merge cadence a **measured
cost** rather than a guess — the input to the A1.4 merge rehearsal and to every
scheduling decision about upstream merges after it.

Upstream ships several commits per day and cuts **no releases**, so distance is
measured in commits, not versions.

## How to measure

```sh
git fetch upstream
git rev-list --count main..upstream/main            # commits we are behind
git log --oneline main..upstream/main               # what they are
git diff --stat main..upstream/main                 # the conflict surface
```

## Ledger

| Date | Our `main` | Upstream `main` | Behind by | Event | Notes |
|------|-----------|-----------------|-----------|-------|-------|
| 2026-08-16 | `6789876442d0` | `ef35d799a846` | **4 commits** | fork point (task A0.1) | Baseline. Recorded for the A1.4 merge rehearsal. **No merge performed** — Phase 0 seeds only. |
| 2026-08-17 | `d6d7f85` (= `v0.1.0`) | `bdae21ed09d2` | **8 commits** | **first merge** (task A1.4) | Clean: **zero conflicts**, merge wall **0.031 s**. Full record in [`upstream-merges.md`](upstream-merges.md). Pin advanced to `bdae21ed09d2`. |
| 2026-08-29 | `61539eb` | `9e3df47b4a5f` | **85 commits** | **second merge** | Two clean merge checkpoints, **zero conflicts**, combined merge wall **0.5 s**. Upstream advanced by two commits during validation, and the pin was refreshed after the final merge. |

The machine-readable half of this ledger is [`upstream-pin`](upstream-pin) — a
single line holding the upstream commit our tree currently contains. The
fork-contract gate reads it (assertions A4, A5, A7), so a merge that forgets to
advance it fails CI rather than drifting quietly.

## Baseline detail (2026-08-16)

- **Pin:** `6789876442d0fb6da9f70d86399a2930c5073ae2` — `chore: ignore
  scratchpad/ at the repo root (#2359)`, 2026-08-13.
- **Upstream head at fork time:** `ef35d799a846` — `fix(calm): keep Pi's export
  confirmation visible (#2461)`.
- **Distance:** 4 commits, accumulated over roughly 3 days. That is the number
  the A1.4 rehearsal starts from; expect it to be materially larger by the time
  the rehearsal runs, and record the value again then.
- Upstream also carries ~40 in-flight `fm/*` topic branches. These were
  deliberately **not** mirrored (ADR-0002) and are not part of this measurement.

## What A1.4 produced — done, 2026-08-17

The merge rehearsal was never "did it merge". It had to record:

1. Commits merged, and the wall-clock and review time it took.
2. **The conflict surface** — which files conflicted, and whether any of them
   were ours (they should not be, under the soft-fork contract; if they are,
   the contract is leaking and that is the finding).
3. Whether any merged change is consumer-visible, and therefore what semver
   bump the next tag needs ([ADR-0006](../adr/0006-operator-cuts-its-own-release-tags.md)).
4. A recommended cadence, argued from the observed cost.

All four, plus the standing procedure and the gate defect the rehearsal
uncovered, are in **[`upstream-merges.md`](upstream-merges.md)**. Headline: 8
commits, **zero conflicts**, **0.031 s** of merge, and a recommended cadence of
**every two weeks or ~15 commits, whichever comes first**.
