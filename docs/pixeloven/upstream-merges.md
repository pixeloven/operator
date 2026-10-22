# Upstream merges - standing procedure and measurements

- **Task:** A1.4
- **Satisfies:** **O-2** (upstream merges are scheduled, reviewed PRs — never
  automatic) · **G-5** (nothing is ever posted upstream)
- **Related:** [`upstream-tracking.md`](upstream-tracking.md) (the distance
  ledger) · [`fork-contract.md`](fork-contract.md) · [`releases.md`](releases.md)
  (how a merge becomes a version number)

`upstream-tracking.md` records *how far behind we are*. This page records *what
it costs to catch up, and how to do it*.

---

## 1. The rule that keeps this reviewable

**We add by default and keep every existing-file exception exact and reviewed.**
[ADR-0001](../adr/0001-soft-fork-of-firstmate.md) owns the additive default, while the ADRs listed in [`fork-contract.md`](fork-contract.md) own each bounded existing-file exception.
Every merge is a live test of both rules.

**G-5, absolutely: this is a PULL ONLY.** Nothing is pushed, opened, commented,
or otherwise posted to `kunchenguid/*`. Upstream is only ever fetched, into a
neutral ref. Any upstream contribution is a separate, per-instance operator decision.

## 2. The standing procedure

```sh
# 1. Measure first - the ledger row is written before the merge, not after.
#    Fetch into a neutral ref; never add a remote (see below).
git fetch --no-tags https://github.com/kunchenguid/firstmate.git \
  main:refs/remotes/firstmate-upstream/main
git rev-list --count main..firstmate-upstream/main
git log   --oneline            main..firstmate-upstream/main

# 2. Merge on a branch. Never on main, never with a bot, never automatically.
git checkout -b "upstream-merge/$(date +%Y-%m-%d)"
git merge --no-ff --no-edit firstmate-upstream/main

# 3. Advance the machine-readable pin - the gates read this file (A4/A5/A7).
git rev-parse firstmate-upstream/main > docs/pixeloven/upstream-pin

# 4. Record the ledger row in upstream-tracking.md and the merge row below.

# 5. Open a PR. Review it as code, not as a formality: this repository's files
#    execute inside every agent turn, and workers launch with their harness
#    permission gates disabled (see supply-chain-read.md).
#
# 6. Merge it with a REAL MERGE COMMIT. Not --squash, not a rebase.
gh-axi pr merge <n> --merge
```

**Never add a remote named `upstream`, `github`, or `origin` for kunchenguid.**
A merge worker runs in a worktree of the shared project clone, so `git remote add` writes into that clone's shared `.git/config` and outlives the task.
Upstream's self-repository publication gate takes the remote marked `remote.<name>.gh-resolved=base` as a project's publication target, and otherwise the first of `upstream`, `github`, and `origin`, so an `upstream` remote pointing at `kunchenguid/firstmate` would make every later ship from that clone target upstream and be refused.
The neutral `refs/remotes/firstmate-upstream/main` ref carries no remote configuration and leaves the clone's publication target on `pixeloven/operator`.
Setting `git config remote.origin.gh-resolved base` in the project clone, which is what `gh repo set-default` writes, additionally pins that target to `origin`.

**Every `operator` home that ships to this repository needs two local settings.**
Since stage 2 of the fourth synchronization, that gate refuses every non-`local-only` ship on a project sharing firstmate's root commit unless the home grants publication to its target, and `pixeloven/operator` shares it by [ADR-0002](../adr/0002-seeded-with-full-upstream-history.md).
Set them once per home:

```sh
# In the operator home (local and gitignored; never committed, never scoped to kunchenguid):
printf 'maintainer github.com/pixeloven/operator\n' > config/firstmate-role
# In that home's operator project clone:
git -C projects/operator config remote.origin.gh-resolved base
```

[`docs/configuration.md`](../configuration.md#firstmate-role-configfirstmate-role) owns the role schema and target selection.

**Step 3 is not optional.** `docs/pixeloven/upstream-pin` is what the
fork-contract assertions diff against. Skipping it makes A4 report upstream's own
commits as O-1 violations; advancing it without merging is caught by A7.

> ### ⛔ Never rebase an upstream-merge branch — and never squash-merge one
>
> **Two habits that are correct for every other PR in this repository will
> silently destroy this one.** Both flatten the merge commit away:
>
> | Habit | What it does here |
> |---|---|
> | `git rebase origin/main` before opening the PR | replays upstream's commits as fresh cherry-picks |
> | `gh-axi pr merge --squash` (the repo's normal merge mode) | collapses the whole branch, merge commit included, into one commit on `main` |
>
> **An upstream-merge PR is merged with a real merge commit - `gh-axi pr merge --merge`.**
>
> The house habit of `git fetch origin && git rebase origin/main` before opening a
> PR is **wrong here, and silently so.** `git rebase` drops the merge commit and
> replays upstream's commits as fresh cherry-picks with new SHAs. The result looks
> fine — same tree, same files — but:
>
> - the upstream commit is **no longer an ancestor**, so the merge base with upstream
>   is gone and the *next* merge re-presents every one of these commits;
> - upstream's authorship SHAs are rewritten, which is exactly what
>   [ADR-0002](../adr/0002-seeded-with-full-upstream-history.md) seeded whole
>   history to avoid;
> - assertion **A7 fails**, which is how this was caught the first time it
>   happened — during this very rehearsal.
>
> The merge branch is cut from `main` and merges upstream into it, so it is
> already current with `main` by construction; there is nothing to rebase onto.
> If `main` genuinely moves underneath it, **merge `main` in** (`git merge
> origin/main`) or redo the upstream merge from a fresh branch. If a branch has
> already been flattened, recover it from the reflog rather than pushing it.
>
> The local topology check below is the operator-history portion of A7.
> Run it **after** the PR lands, too - a squash-merge passes every gate on the PR and only shows up as a failure on the *next* PR, by which point the merge base is already gone.
> [`identity.md`](identity.md#5-assertions--the-grep-evidence) owns the complete A7 contract, including canonical upstream and companion-fork lineage.
>
> ```sh
> git merge-base --is-ancestor "$(cat docs/pixeloven/upstream-pin)" HEAD \
>   && echo "merge topology intact"
> ```

### What the review is actually looking for

1. **Did anything conflict?** Resolve overlap in an ADR-accepted contact surface by behavior and ownership; a conflict anywhere else means the contract is leaking.
2. **Did upstream touch a file we also touch?** Review `README.md` plus the exact existing-file exceptions owned by the accepted ADRs; never choose one side wholesale.
3. **Is any merged change consumer-visible?** That decides the semver bump on
   our next tag ([ADR-0006](../adr/0006-operator-cuts-its-own-release-tags.md),
   [`releases.md`](releases.md) §2).
4. **Does upstream's own suite still pass on the merged tree?**
   Upstream's `ci.yml` is the only thing that can answer this, so it remains enabled for the whole merge PR and afterwards ([`releases.md`](releases.md) §4).
   Treat any failure as current evidence to investigate rather than relying on the resolved historical documentation-audience failure.
5. **Anything new in the supply chain?** New network calls, new installers, new
   telemetry, a changed pin. Feeds [`supply-chain-read.md`](supply-chain-read.md).

## Corrective ancestry restoration

PR #13 was squash-merged as `f4d52442776fa9d584cbb4a32018c0be8b518c58`, discarding its corrective graph-only merge topology.
The replacement graph-only merge commit `04a819b8596d69cf99c4f71dc6ac67aa8becb1d6` preserves the exact tree `5cd3bdce7a5b877d49b30b84513d7a1e02c6f81f` of that current `main` byte-for-byte and has parents, in order:

- first parent (PixelOven `main`): `f4d52442776fa9d584cbb4a32018c0be8b518c58`
- second parent (verified upstream pin): `1fbc7bb1fba262ef38a4dedf321d18c54669b129`

The replacement PR **MUST be merged with GitHub's `Create a merge commit` method** (never squash, rebase, or fast-forward).

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

### The second finding: the rebase habit destroys the merge

Immediately after the fix landed, the routine pre-PR `git rebase origin/main`
flattened the merge commit into eight cherry-picks and severed the merge base
with upstream. **A7 — added minutes earlier — caught it**, which is the cheapest
possible validation of a new assertion. The branch was restored from the reflog
and the prohibition is now written into the procedure above.

Worth stating plainly because it generalises: the standard "rebase before you
open a PR" advice is safe for every PR in this repository **except** the one kind
of PR this document is about.

### The third finding: upstream's own suite has never been green here

Re-enabling `ci.yml` for the merge (its one earning occasion) surfaced that
upstream's documentation-audience test fails on **every** PixelOven commit,
because it enumerates every tracked `*.md` repo-wide and requires each to be
classified in an upstream-owned inventory. It is green at the fork point and red
from the first PixelOven commit onward — nothing to do with this merge. It needs
an operator decision and is written up in [`releases.md`](releases.md) §4.

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

The second measurement is below.

## 4. Second synchronization - 2026-08-30

The second synchronization merged the current upstream default branch before applying any new downstream distribution change.

| | |
|---|---|
| Our `main` before | `61539eb05602b9b2859c94ee73a47bff2b328e3b` |
| Upstream `main` | `1fbc7bb1fba262ef38a4dedf321d18c54669b129` |
| Previous pin and merge base | `bdae21ed09d2cca4f57caed4bda9d30d8f9d9be8` |
| Behind by | **86 commits**, accumulated over **13 days** |
| **Conflicts** | **zero** |
| **Merge wall-clock** | **0.54 s total across three clean merge commands** |
| **Conflict-resolution time** | **none** |
| Files changed by upstream | 283 |
| Diff size | 61,171 insertions, 8,723 deletions |

Git's `ort` strategy first integrated `c731c36`, auto-merging `README.md` without conflict.
Upstream then advanced twice during validation, so two more clean merges integrated `9e3df47` and `1fbc7bb`.
Those merges auto-merged the overlapping downstream surfaces without conflict, including `README.md`, `bin/fm-test-run.sh`, `docs/configuration.md`, and `docs/documentation-audiences.json`.
The final tree keeps `1fbc7bb` as an ancestor and retains every PixelOven-only commit in ordinary history.

This synchronization is consumer-visible and brings substantial runtime, supervision, backend, documentation, and test behavior.
The next `operator` release therefore needs at least a minor version bump under the existing release policy.

The same task deliberately introduces ADR-0010 after the pure merge.
That decision expands the future contact surface from the README banner to an exact set of source-selection, CI acquisition, documentation-audience, and regression files.
Future synchronizations review those paths by behavior and ownership rather than choosing an upstream or downstream side wholesale.

The 86-commit distance was mechanically cheap but materially larger to review than the first eight-commit rehearsal.
The existing recommendation of every two weeks or roughly 15 commits remains the upper bound, and the commit trigger should win whenever upstream is moving quickly.

### Corrective ancestry merge after the PR #11 squash

PR #11 was squash-merged as `0e9bc603abcbd557c111cb4a798aceddde85087e` after its branch had already integrated the upstream pin.
The squash preserved the synchronized file tree but synthesized one new commit whose only parent was the prior PixelOven `main`, so `1fbc7bb1fba262ef38a4dedf321d18c54669b129` was no longer reachable and A7 failed.

The first corrective branch's merge recorded `0e9bc603abcbd557c111cb4a798aceddde85087e` as its first parent and the pinned upstream commit as its second parent.
That branch used Git's `ours` merge strategy because the squash had already landed the reviewed file content, preserving tree `facc2dabfbffcdf7aae862aac8b9822d820ae897` exactly while restoring the missing ancestry edge.
The current replacement repair and required merge method are recorded in [Corrective ancestry restoration](#corrective-ancestry-restoration).

## 5. Third synchronization - 2026-09-01

The third synchronization preserved the ordinary two-parent merge topology, with PixelOven `0c1b6e3c15bd` as the first parent and upstream `355f46fe5528` as the second.
It advanced from `1fbc7bb1fba2` by 10 upstream commits over two days, changing 58 files with 7,971 insertions and 324 deletions before merge resolution.
The merge wall time was not recorded.

Two content conflicts required review.
In `docs/configuration.md`, the resolution retained ADR-0010's PixelOven installer commands while accepting upstream's automatic backlog-transition contract.
In `tests/fm-pr-check-security.test.sh`, the resolution retained the downstream hosted-runner wait bound while taking upstream's semantic non-zombie liveness check.

The synchronization is consumer-visible: it adds atomic backlog transitions, bounded pane-churn absorb, promoted-worker definition-of-done rendering, quota selection and monitoring helpers, structured Lavish capture reading, custom-check unregistration, a Bash 3.2 public-followup fix, and isolated Herdr server environments.
Upstream's stock macOS lane also introduced a registry acquisition of `tasks-axi`; the same branch replaced that acquisition with `bin/fm-install-pixeloven-tool.sh tasks-axi` under Node 22.19, preserving ADR-0010's companion-distribution boundary without rewriting the merge commit.

## 6. Fourth synchronization, stage 1 of 2 - 2026-10-21

The fourth synchronization merges upstream in two reviewed stages, each a real two-parent merge.
Stage 1 merged upstream `8fd5575b1179c2479bb7668725e03b2d905556a5` into PixelOven `27404554274d`, 50 upstream commits past the previous pin `355f46fe5528`.
Upstream's own changes in that range touch 179 files with 23,518 insertions and 2,570 deletions.
Stage 2 continues from this pin to `0e82f3ee` (section 7).

| | |
|---|---|
| **Conflicts** | **6 files, 9 hunks** |
| **Merge wall-clock** | **0.14 s** |

Resolutions:

- `.github/workflows/ci.yml` took upstream's 20-minute serial timeout with its five-shard rebalance, superseding ADR-0011's 30-minute bump, and took upstream's stock macOS job unconditionally so it runs on every pull request; `workflow_dispatch` remains the only downstream trigger hunk.
- `bin/fm-task-inbox-lib.sh` and `tests/fm-task-inbox.test.sh` took upstream, whose own vanished-lock retry supersedes the downstream fix.
- `tests/fm-secondmate-reconcile.test.sh` took upstream, whose bounded wait supersedes the downstream flake fix.
- `tests/fm-task-delivery.test.sh` keeps both ADR-0008's delivery-lane test and upstream's task-subsection test.
- `docs/captain-hold-lifecycle.md` takes upstream's wording and re-adds ADR-0013's retention-archive clauses.

Three auto-merged downstream hunks were corrected on the same branch.
`bin/fm-lint-workflows.sh` returned to upstream bytes, because its optional actionlint-config hunk referenced a file neither tree carries and aborted under stock macOS Bash 3.2.
ADR-0014's mutex inspector now compares owner pids through upstream's `fm_current_pid`, matching upstream's new Bash 3.2 subshell ownership rule.
ADR-0012's Pi reconcile case now passes the typed quit shutdown event that upstream's session-replacement handler reads.

Superseded hunks whose upstream replacement is not yet merged stay until stage 2: the `tests/fm-pr-check-security.test.sh` wait bound, ADR-0014's terminal guard, and ADR-0012's lock-refusal re-check in `bin/fm-bootstrap.sh`.
The ADR-0012 and ADR-0014 cores are re-ported in stage 2, where upstream's rewrites of their owners arrive.
ADR-0012's file list now names its two incidental hunks, and the A4 allowlist drops the four paths that returned to upstream bytes.

Under stock macOS Bash 3.2, ADR-0014's serialized publication multiplies upstream's new per-lock process spawn, so the watcher-lock, wake-queue, and watch-triage suites exceed their local timing budgets while passing with longer waits.
Stage 2's re-port must measure that cost on Bash 3.2.

The stage is consumer-visible through upstream's behavior changes, including the stock macOS CI lane, so it counts toward the `v0.3.0` minor bump.

## 7. Fourth synchronization, stage 2 of 2 - 2026-10-21

Stage 2 merged upstream `0e82f3eebd211c025041de0c0fa066d140fd7cbf` onto stage 1's branch at `8473c8542ddb`, 427 upstream commits past the stage 1 pin `8fd5575b1179`.
Upstream's own changes in that range touch 587 files with 168,447 insertions and 10,844 deletions.
Upstream `main` stood six commits further ahead at `bd866530a07b` when this stage was cut.

| | |
|---|---|
| **Conflicts** | **18 files, 36 hunks** |
| **Merge wall-clock** | **0.29 s** |

Resolutions:

- `.agents/skills/process-event-sources/SKILL.md` and `tests/fm-pr-check-security.test.sh` took upstream, and `bin/fm-bootstrap.sh` returned to upstream bytes after it auto-merged: upstream's non-recursive steal mutex removed the lock refusal the bootstrap re-check absorbed, and upstream's watcher TERM fix replaced the downstream wait bound.
- `.github/workflows/ci.yml` took upstream's partitioned lint job name and kept ADR-0011's hosted-runner comment and `workflow_dispatch` trigger.
- `bin/fm-wake-lib.sh`, `bin/fm-watch.sh`, and `bin/fm-procevent.sh` were rebuilt from upstream and the ADR-0012 core re-ported onto them, as the overlap investigation's map prescribed.
  ADR-0012 keeps one pending row per captured result through `fm_wake_ensure_queued` over upstream's single locked append core and keeps sequence-aware presentation markers under upstream's three process-event headlines; the multi-source batch publication and the second append core were dropped.
  Reconcile keeps upstream's `published=` meaning, every unhandled result whose publication the pass ensured, and adds `queued=` for those already pending, so upstream's own suites read it unchanged.
- ADR-0014's lock serialization was first re-ported onto upstream's steal mutex and then withdrawn by the captain, so its files carry no hunks (see below).
- `bin/fm-captain-hold.sh` took upstream and re-grafted ADR-0013's archive verifier at the top of upstream's `verify_entry_durable`, accepting archived `reconciled` records and applying upstream's recorded-origin and self-inventory checks to archived rows.
  When exact and legacy identities are both active, upstream's exact identity wins; ambiguity still refuses whenever an archived candidate is involved.
- `bin/fm-spawn.sh` keeps both ADR-0008's Git isolation exports and upstream's new pre-launch exports, and adds `GIT_CONFIG_GLOBAL` and `GIT_CONFIG_NOSYSTEM` to upstream's `config/launch-env-allowlist` floor, proven by a launch regression in `tests/fm-task-delivery.test.sh`.
- `docs/configuration.md`, `docs/captain-hold-lifecycle.md`, and `docs/remote-secondmates.md` took upstream's rewritten layouts and re-worded the downstream contracts into them; `docs/documentation-audiences.json` unions both verification entries.
- The test conflicts union upstream's new cases with the downstream ones; the downstream triage and Pi cases now assert upstream's key-only headlines, and upstream's launch-failure case expects a replay after acknowledgement because ADR-0012 retires the presentation marker.
  The batch wake-queue case was removed with the code it covered.

The pull request's hosted CI exposed regressions in the re-ports, resolved on the branch.
ADR-0014's serialization made every ordinary lock acquisition publish and release a second lock, roughly doubling acquisition cost on upstream's new lock code (about 13 ms against 6 ms on Linux, 170 ms against 75 ms on stock macOS Bash 3.2), and the contention failed upstream's process-event, captain-hold, board, watcher, and supervision-host suites on hosted runners while passing in isolation.
The captain withdrew ADR-0014 on 2026-10-22: `bin/fm-wake-lib.sh` and `bin/fm-watch.sh` keep only ADR-0012 hunks, `docs/watcher-continuity.md` and `tests/fm-watcher-lock.test.sh` returned to upstream bytes, and the zero-winner reproduction is left to offer upstream separately.
ADR-0012's sequence-floor recovery refused an append when an empty wake queue was unreadable, which upstream's mail suite exercises, and its `published=` count had narrowed to new appends, which upstream's remote-reply suite reads; both now match upstream's behavior.
A test-list entry and a test local survived the conflict resolution unused.
Upstream's synthetic `TYPESAFE_API_KEY` fixture from upstream #4692 also trips the PixelOven secret scan, so `docs/pixeloven/gitleaksignore` accepts exactly that one fingerprint.

Two departures from the investigation's map are deliberate.
The bounded-recovery retry in `tests/fm-backend-herdr-presentation-e2e.test.sh` stays, because upstream's presentation recovery still refuses a contended concurrent resume after its bounded attempt unless `--herdr-resume-lock-wait` is passed.
Every ADR-0010 hunk the map re-applies is void under [ADR-0015](../adr/0015-companion-tools-from-upstream-sources.md), so upstream's tool floors, CI installs, and the unpinned Pi coding-agent package are taken as upstream wrote them.

ADR-0012 now names eleven files and ADR-0014 is withdrawn; the A4 allowlist drops the five paths that returned to upstream bytes.

Local verification before the PR covered the delivery suite, including the new launch regression and its counterfactual, the archived captain-hold cases under upstream's `tasks-axi` 0.2.6 floor, lint, the documentation-audience check, and the fork-contract assertions; the remaining affected suites were left to the pull request's CI.

The stage is consumer-visible through upstream's behavior changes, including raised tool floors, the self-repository publication gate, and the default-on supervision host, so it counts toward the `v0.3.0` minor bump.

## 8. Merge log

| Date | From | To | Commits | Conflicts | Merge wall | Notes |
|------|------|----|---------|-----------|------------|-------|
| 2026-08-17 | `6789876442d0` (fork point) | `bdae21ed09d2` | 8 | **0** | 0.031 s | Task A1.4 rehearsal. Cut after `v0.1.0`. Only contact surface was `README.md` (banner vs. line 178) and it merged cleanly. Produced the upstream-pin fix (A4/A5 re-anchored, A7 added). |
| 2026-08-30 | `bdae21ed09d2` | `1fbc7bb1fba2` | 86 | **0** | 0.54 s | Second synchronization used three clean merge checkpoints because upstream advanced twice during validation. Companion-fork distribution changes followed the first pure merge under ADR-0010. |
| 2026-09-01 | `1fbc7bb1fba2` | `355f46fe5528` | 10 | **2 files** | not recorded | Third synchronization preserved the two-parent merge, resolved configuration and test overlap, and corrected the new stock-macOS `tasks-axi` acquisition to the pinned PixelOven installer on the same branch. |
| 2026-10-21 | `355f46fe5528` | `8fd5575b1179` | 50 | **6 files** | 0.14 s | Fourth synchronization, stage 1 of 2. Took upstream for the superseded inbox, reconcile, and serial-timeout hunks; stock macOS now runs on every PR. |
| 2026-10-21 | `8fd5575b1179` | `0e82f3eebd21` | 427 | **18 files** | 0.29 s | Fourth synchronization, stage 2 of 2. Re-ported the ADR-0012 and ADR-0013 cores onto upstream's rewrites, withdrew ADR-0014, dropped the superseded bootstrap and pr-check hunks, and added the delivery lane to the launch-env floor. |
