# Upstream merges — the standing procedure, and the first rehearsal

- **Task:** A1.4
- **Satisfies:** **O-2** (upstream merges are scheduled, reviewed PRs — never
  automatic) · **G-5** (nothing is ever posted upstream)
- **Related:** [`upstream-tracking.md`](upstream-tracking.md) (the distance
  ledger) · [`fork-contract.md`](fork-contract.md) · [`releases.md`](releases.md)
  (how a merge becomes a version number)

`upstream-tracking.md` records *how far behind we are*. This page records *what
it costs to catch up, and how to do it*.

---

## 1. The rule that makes this cheap

**We add files; we never edit upstream's** ([ADR-0001](../adr/0001-soft-fork-of-firstmate.md)).
Every merge is a live test of that rule. The rehearsal below is the first
measurement, and the number it produced is the argument for keeping the rule.

**G-5, absolutely: this is a PULL ONLY.** Nothing is pushed, opened, commented,
or otherwise posted to `kunchenguid/*`. The `upstream` remote exists to fetch.
Any upstream contribution is a separate, per-instance operator decision.

## 2. The standing procedure

```sh
# 1. Measure first - the ledger row is written before the merge, not after.
git remote add upstream https://github.com/kunchenguid/firstmate.git   # once
git fetch --no-tags upstream main
git rev-list --count main..upstream/main
git log   --oneline            main..upstream/main

# 2. Merge on a branch. Never on main, never with a bot, never automatically.
git checkout -b "upstream-merge/$(date +%Y-%m-%d)"
git merge --no-ff --no-edit upstream/main

# 3. Advance the machine-readable pin - the gates read this file (A4/A5/A7).
git rev-parse upstream/main > docs/pixeloven/upstream-pin

# 4. Record the ledger row in upstream-tracking.md and the merge row below.

# 5. Open a PR. Review it as code, not as a formality: this repository's files
#    execute inside every agent turn, and workers launch with their harness
#    permission gates disabled (see supply-chain-read.md).
```

**Step 3 is not optional.** `docs/pixeloven/upstream-pin` is what the
fork-contract assertions diff against. Skipping it makes A4 report upstream's own
commits as O-1 violations; advancing it without merging is caught by A7.

### What the review is actually looking for

1. **Did anything conflict?** Under the contract nothing should. If something
   does, *the contract is leaking* — that is the finding, not the conflict.
2. **Did upstream touch a file we also touch?** Today there is exactly one:
   `README.md`. See §4.
3. **Is any merged change consumer-visible?** That decides the semver bump on
   our next tag ([ADR-0006](../adr/0006-operator-cuts-its-own-release-tags.md),
   [`releases.md`](releases.md) §2).
4. **Does upstream's own suite still pass on the merged tree?** Upstream's
   `ci.yml` is the only thing that can answer this, and an upstream merge is the
   one occasion where it earns its cost — so it is **re-enabled for the whole
   merge PR** and disabled again afterwards ([`releases.md`](releases.md) §4).
   Read it as a *diff of which tests fail*, not as pass/fail: one shard is
   **known red on every run** because our documents are not in upstream's
   documentation-audience inventory, a pre-existing condition dating from the
   first PixelOven commit and written up in [`releases.md`](releases.md) §4.
5. **Anything new in the supply chain?** New network calls, new installers, new
   telemetry, a changed pin. Feeds [`supply-chain-read.md`](supply-chain-read.md).

## 3. Rehearsal — 2026-08-17

The first merge, run as task A1.4 immediately after `v0.1.0` was tagged.

| | |
|---|---|
| Our `main` before | `d6d7f85` (= `v0.1.0`) |
| Upstream `main` | `bdae21ed09d2cca4f57caed4bda9d30d8f9d9be8` |
| Previous pin | `6789876442d0fb6da9f70d86399a2930c5073ae2` (fork point, 2026-08-13) |
| Behind by | **8 commits**, accumulated over **4 days** |
| Merge base | `6789876442d0…` — exactly the fork point |
| **Conflicts** | **zero** |
| **Merge wall-clock** | **0.031 s** |
| **Conflict-resolution time** | **none — there was nothing to resolve** |
| Files changed by upstream | 35 |
| Of those, in a PixelOven namespace | **0** |

The merge base being *exactly* the pin is worth stating plainly: it confirms
[ADR-0002](../adr/0002-seeded-with-full-upstream-history.md)'s call to seed with
full upstream history rather than a squash. A squashed seed would have had no
merge base at all and this operation would not have been a merge.

### What came in

| Commit | |
|---|---|
| `bdae21e` | `fix(ci): keep CLAUDE.md pointer check valid (#2515)` |
| `4913723` | `fix(memory): emit a real @AGENTS.md pointer instead of a CLAUDE.md symlink (#2512)` |
| `362c508` | `fix(decisions): close decision holds at answer time via one general keyed-answer path (#2490)` |
| `e518906` | `feat(stow): add open-record persistence to /stow before reset (#2488)` |
| `ef35d79` | `fix(calm): keep Pi's export confirmation visible (#2461)` |
| `196fb65` | `docs(skills): add remote-secondmate recovery hint for false-negative verdicts (#2456)` |
| `7a3259e` | `fix: keep the public promise reachable when work is routed to a second mate (#2457)` |
| `f1a4af4` | `fix(ci): fail hung Herdr behavior runs in 20 minutes (#2413)` |

Spread: `bin/` 8 files · `tests/` 7 · `docs/` 7 · `.agents/skills/` 7 · plus
`AGENTS.md`, `CONTRIBUTING.md`, `CLAUDE.md`, `README.md`, `.pi/`, and
`.github/workflows/ci.yml`. **1,584 insertions, 101 deletions.**

Two are worth flagging beyond the diff:

- **`CLAUDE.md` changed file mode `120000 → 100644`** (#2512): it is no longer a
  symlink to `AGENTS.md` but a real file containing an `@AGENTS.md` import
  pointer. #2515 updates upstream's own `invariants` job to assert the new shape.
  Both arrived together, so the merged tree is self-consistent — but a mode
  change is exactly the kind of thing that would have conflicted had we ever
  "tidied" that file.
- **`ci.yml` gained a 20-minute step timeout on the Herdr lane** (#2413), and
  upstream's comment states the healthy wall is **~7 minutes**, not the 15–40 the
  old comment estimated. That materially improves the cost picture recorded in
  [`releases.md`](releases.md) §4 — an upstream merge paying for itself in
  information about our own budget.

### The conflict surface, and why it was empty

Not luck. Of the 35 files upstream changed, **exactly one is a file we also
touch: `README.md`.** Our change there is the delimited banner block at the very
top; upstream's change was a table row at line 178. Git merged both without a
murmur.

That single file is the fork's **entire file-level contact surface with
upstream**, and it is the place the first real conflict will eventually appear —
if upstream restructures the head of `README.md`. When it does, the resolution is
mechanical (keep the banner block, take upstream's body wholesale) and assertion
A5 proves the result byte-for-byte. Everything else we own lives in namespaces
upstream cannot collide with by construction.

### The finding: the gate was anchored to the wrong commit

**The merge was clean. The gate was not.** Running the fork-contract assertions
on the merged tree failed:

- **A4** listed all 35 upstream-changed files as O-1 violations.
- **A5** reported `README.md` differing from "upstream" outside the banner.

Both were anchored on the **frozen fork point**, which stops being the right
baseline the moment we merge. The question A4 and A5 ask is *"what have we
changed on top of upstream"*, and after a merge that baseline is the newly merged
upstream commit, not the fork point.

**Fix, landed in this same PR:** `docs/pixeloven/upstream-pin` holds the upstream
commit the tree currently contains; A4 and A5 read it; **A7** (new) refuses a pin
that is not a real commit contained in this history, so it cannot be advanced
without an actual merge. Advancing the pin is now step 3 of the procedure above,
which also keeps `upstream-tracking.md` from going stale while the gate keeps
passing.

This is precisely the class of defect a rehearsal exists to surface: it would
otherwise have been discovered by a red gate on a real merge, under time
pressure, with the wrong remedy (weaken the assertion) close to hand.

### Cost, and the recommended cadence

| | |
|---|---|
| Mechanical merge | **0.031 s** |
| Conflict resolution | **0** |
| Review (8 commits, 35 files, 1,584 insertions) | the real cost — one focused reading |
| Gate correction found by this rehearsal | one-off, now paid |

**Recommended cadence: every two weeks, or ~15 commits behind, whichever comes
first.** Argued from what was measured, not from habit:

- **The mechanical cost is nil and does not scale with distance** — the merge is
  milliseconds because our surfaces do not overlap, and that stays true whether
  we are 8 commits behind or 80.
- **The review cost scales linearly with commits**, and it is the only real cost.
  8 commits over 4 days was one comfortable reading. Upstream is running ~2
  commits/day, so two weeks is ~28 commits — near the top of what stays one
  sitting. Fifteen commits is the earlier trigger when upstream sprints.
- **Merging more often is not free either**: each merge PR costs a full run of
  upstream's expensive `ci.yml` (see [`releases.md`](releases.md) §4), and each
  needs a tag classification. Weekly would roughly double that overhead to buy
  freshness nobody is waiting on.
- **Not slower than two weeks**, because the review is the bottleneck and review
  quality falls off a cliff past ~30 commits — which is exactly when a merge
  stops being a merge and becomes an audit.

Revisit after the second merge; two data points beat one.

## 4. Merge log

| Date | From | To | Commits | Conflicts | Merge wall | Notes |
|------|------|----|---------|-----------|------------|-------|
| 2026-08-17 | `6789876442d0` (fork point) | `bdae21ed09d2` | 8 | **0** | 0.031 s | Task A1.4 rehearsal. Cut after `v0.1.0`. Only contact surface was `README.md` (banner vs. line 178) and it merged cleanly. Produced the upstream-pin fix (A4/A5 re-anchored, A7 added). |
