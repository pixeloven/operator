# Releases — versioning policy and what a tag means

- **Task:** A1.2
- **Satisfies:** **O-3** (`operator` cuts release tags; consumers pin our tags,
  never upstream, never a raw SHA) · **G-6** (semver from the first tag) ·
  **G-2** (everything pinned exactly)
- **Decision:** [ADR-0006](../adr/0006-operator-cuts-its-own-release-tags.md)

---

## 1. Policy

**`operator` ships semver tags, starting at `v0.1.0`.** Upstream
(`kunchenguid/firstmate`) ships **no releases at all** — no tags, no semver, no
changelog cadence — so our tags are the **only compatibility signal in the
entire chain. We take on the obligation to mean the number.**

| Rule | |
|---|---|
| Format | `vMAJOR.MINOR.PATCH`, optional pre-release/build suffix. Enforced by the release workflow. |
| Start | `v0.1.0` |
| Cut from | `main`, only. The release workflow refuses a tag that is not contained in `main`. |
| Precondition | `PixelOven gates` green on the commit being tagged. Tagging is a deliberate act, never a side effect of merging. |
| Registry parity | If this repository ever publishes to a package registry, the registry version and the git tag are the same number. No parallel schemes. |

### What a tag means to a consumer

> *This tree — including whatever upstream we have merged — passed our gates and
> is what we intend you to run.*

Consumers pin the tag, and the pin lives as a **variable in the consumer's own
configuration** so it is visible and greppable rather than buried in a command.
For Harmony that is `ansible/roles/bastion` defaults (task P1.2, requirement
H-1). Consumers never pin `main`, never pin an upstream SHA.

Upstream SHAs are still recorded — in [`NOTICE`](../../NOTICE) (the fork point)
and in [`upstream-tracking.md`](upstream-tracking.md) (every merge) — but they
are **provenance, not a consumer interface**.

### 0.x semantics

While the major version is `0`, the minor position carries breaking changes and
the patch position carries everything else. This is normal 0.x semver and it is
what the first Harmony pilot runs against.

## 2. How a release relates to upstream merges

The two cadences are **decoupled on purpose**. Upstream can ship five commits a
day; we tag when we have merged, reviewed, and gated them.

```
upstream/main ──(scheduled, reviewed PR — O-2)──▶ our main ──(gates green)──▶ tag ──▶ consumers
```

The classification step is the one that costs something. Upstream calls its
changes nothing, so **we** must decide what an incoming change means for our
consumers, at tag time:

| Incoming upstream change | Our bump |
|---|---|
| No consumer-visible behaviour change (internal refactor, upstream tests, upstream docs) | patch |
| New capability, or changed behaviour a consumer could notice, that stays compatible | minor (0.x) |
| Behaviour a consumer depends on changes or is removed | minor while 0.x; major from 1.0 |
| PixelOven-authored addition (`bin/backends/`, `.agents/skills/po-*`) | minor if it adds a capability, patch otherwise |

Docs-only changes under `docs/pixeloven/` and `docs/adr/` do not require a tag at
all.

Every merge records its before/after distance and its conflict surface in
[`upstream-tracking.md`](upstream-tracking.md), and the standing merge procedure
plus the first measured rehearsal live in
[`upstream-merges.md`](upstream-merges.md) (task A1.4).

## 3. Mechanism

[`.github/workflows/pixeloven-release.yml`](../../.github/workflows/pixeloven-release.yml)
fires on `push: tags: ['v*']` and:

1. validates the tag is semver,
2. refuses a tag that is not contained in `main`,
3. creates the GitHub Release with generated notes, marked `--latest`.

It uses the preinstalled `gh` CLI rather than a marketplace release action —
fewer pinned SHAs to maintain on a job that holds a write-capable token.

### Cutting a release

```sh
git fetch origin && git checkout main && git pull --ff-only
# confirm "PixelOven gates" is green on this commit
git tag -a v0.1.0 -m "operator v0.1.0"
git push origin v0.1.0        # the workflow does the rest
```

The tag is annotated so it carries its own author and date. Never move a tag
after it is published: a consumer that has already pinned it would silently get
a different tree.

## 4. CI on this repository

Two suites run here, and they have very different characters:

| Workflow | Owner | Fires on | Character |
|---|---|---|---|
| `ci.yml` | **upstream** — never edited (O-1) | push to `main`, every PR | heavy: 2 parallel test shards + a 4-way serial matrix + a real-Herdr lane capped at 75 min + a `macos-latest` job |
| `no-mistakes-required.yml` | **upstream** — never edited (O-1) | every PR | asserts the PR body carries the `no-mistakes` pipeline signature |
| `windows-herdr-spike.yml` | **upstream** — never edited (O-1) | `workflow_dispatch` only | costs nothing unless invoked |
| `pixeloven-gates.yml` | **ours** | push to `main`, every PR | 2 jobs, both seconds of real work |
| `pixeloven-release.yml` | **ours** | `push: tags: ['v*']` | 1 job |

### The cost finding — measured, not estimated

This repository is **private, on a free-plan org** — 2,000 included Actions
minutes per month, and private-repo minutes bill against them. GitHub bills each
**job** rounded up to the minute, and `macos` bills at **10×**.

Measured on the first real run (PR #3, 2026-08-17):

| Job | Wall | Multiplier | Billed |
|---|---|---|---|
| Lint shell scripts | 5m57s | 1× | 6 |
| Test coverage guard | 8s | 1× | 1 |
| Repo invariants | 6s | 1× | 1 |
| Behavior portable parallel 1 | 2m12s | 1× | 3 |
| Behavior portable parallel 2 | 1m39s | 1× | 2 |
| Behavior portable serial 1 | 9m41s | 1× | 10 |
| Behavior portable serial 2 | 10m51s | 1× | 11 |
| Behavior portable serial 3 | 10m25s | 1× | 11 |
| Behavior portable serial 4 | 11m49s | 1× | 12 |
| Behavior tests (Herdr) | 7m17s | 1× | 8 |
| Behavior timing aggregate | ~10s | 1× | 1 |
| **Stock macOS Bash snapshot compatibility** | 1m49s | **10×** | **20** |
| **`ci.yml` total** | | | **≈ 86 billed min per run** |
| `pixeloven-gates.yml` — gitleaks | 9s | 1× | 1 |
| `pixeloven-gates.yml` — workflows · docs · fork contract | 7s | 1× | 1 |
| **`pixeloven-gates.yml` total** | | | **2 billed min per run** |

Two corrections to earlier estimates, both from real data: the **serial shards
are ~10–12 min each**, not the ~4.8 min the workflow comment implies, and the
**Herdr lane finishes in ~7 min**, not the 15–40 min its old comment estimated
(upstream's own #2413 says the same, merged in A1.4).

`ci.yml` fires on **both** the pull request and the subsequent push to `main`, so
**one landed PR costs ≈ 172 billed minutes** — **8.6 % of the monthly allowance
per PR**, or **≈ 11 PRs before the budget is gone**. Our own gates are **1.2 %**
of one `ci.yml` run.

### The documentation-audience collision - resolved by ADR-0008

Upstream's `tests/fm-documentation-audiences.test.sh` runs `bin/fm-doc-audience-check.sh`, which enumerates maintained prose across the repository and requires each path to be classified in the upstream-owned `docs/documentation-audiences.json`.
PixelOven prose was therefore unclassified even though the fork added only new documentation files.

Demonstrated locally at three points in our history:

| Tree | `bin/fm-doc-audience-check.sh` |
|---|---|
| fork point `6789876442d0` (pure upstream) | `ok surfaces=68 local_links=253` |
| `a5e90e3` (Phase 0, task A0.1 — **before** any A1 work) | **fails**: 11 unclassified |
| `d6d7f85` (`v0.1.0`) | **fails**: 14 unclassified |

The failure dates from the first PixelOven commit and is a structural collision between the additive-only contract and an upstream invariant that enumerates the whole tree.
Relocating the documents cannot solve it because the inventory scope is repository-wide.

On 2026-08-22 the operator accepted [ADR-0008](../adr/0008-documentation-audience-inventory-exception.md), which permits the central inventory to classify fork-owned prose while preserving every inventory policy field and upstream classification.
The PixelOven fork gate enforces that semantic boundary and rejects any added classification outside `docs/adr/` and `docs/pixeloven/`.
This creates an ongoing merge-conflict cost in one upstream-owned data file in exchange for making the inherited documentation check authoritative and green.

The same PR diagnosis observed a separate `tests/fm-remote-job.test.sh` worker-readiness timeout in one CI run.
Seven consecutive focused runs passed unchanged, including the relocated-root worker identity case, which establishes non-reproduction rather than a proven environmental cause.
The PR contains no runtime change, and the failed CI run passed the initial startup and stale-code replacement cases before the relocated-root readiness symptom.
The exact CI-only timing or worker-lock release cause remains unresolved, and the passing reruns do not disprove a latent race.
The available evidence therefore does not justify a runtime change in this documentation repair.

### The levers, and how to pull them

**This is an inherited property of upstream's suite, not a defect, and it is not
ours to fix by editing.** O-1 forbids touching `ci.yml`. The available levers are
repository *settings* rather than files:

1. **Disable `ci.yml` at the repository level.** Nothing in the tree changes; the
   file stays byte-identical for upstream merges. The single biggest saving, and
   the recommended posture while the repo is private and pre-pilot: our own gates
   plus the merge review already cover what we change, and **we change no shell**.
2. **Leave it on and accept ~11 PRs/month**, revisiting when ARC lands.
3. **Migrate to the ARC self-hosted pool** (Phase 0.5 / M0.1) — self-hosted
   minutes do not bill against the allowance. This fixes the cost permanently,
   but `ci.yml` names `ubuntu-latest`/`macos-latest` explicitly and re-pointing it
   would mean editing an upstream file. So ARC fixes *our* workflows' cost, not
   upstream's, unless a runner group is labelled to intercept `ubuntu-latest`
   (worth evaluating at M0.1).

#### The disable, as a documented reversible posture

Option 1 is a **posture, not a deletion**. Recorded here so that whoever finds it
switched off in two months can explain it and reverse it in one command.

```sh
# Find the workflow id (the numeric id is stable; the path is the readable key).
gh api /repos/pixeloven/operator/actions/workflows \
  --jq '.workflows[] | select(.path==".github/workflows/ci.yml") | {id, name, state}'

# Disable
gh api -X PUT /repos/pixeloven/operator/actions/workflows/<id>/disable

# Re-enable
gh api -X PUT /repos/pixeloven/operator/actions/workflows/<id>/enable
```

(Equivalently: Actions → *CI* → ⋯ → Disable workflow.)

**Re-enable triggers — both mandatory:**

1. **Before any upstream merge, and for the whole merge PR.** An upstream merge is
   the one occasion where upstream's suite earns its cost: it is the only thing
   that can answer *"does the merged tree still pass upstream's own tests"*, which
   is a first-class question for [`upstream-merges.md`](upstream-merges.md).
   Re-enable, open the merge PR, record the result in the merge log, then disable
   again once it has landed.
2. **At the ARC migration (M0.1)**, when self-hosted minutes change the economics
   and the whole calculation should be redone.

Whichever posture is chosen, our own workflows stay on `ubuntu-latest` until M0.1
lands; the migration is a follow-up noted in both workflow headers.

### Expected red check on every PR

`Require no-mistakes` fails on any pull request whose body lacks the upstream
pipeline signature. That is upstream's enforcement that contributions arrive
through the `no-mistakes` pipeline — **it working is evidence for task A1.3**,
not a defect. The workflow is upstream's and is never edited. The repository has
no branch protection (private, free plan), so `gh pr merge --squash` still
merges; note the red check in the PR body.

## 5. Release log

| Tag | Date | Upstream merged through | Notes |
|---|---|---|---|
| `v0.1.0` | 2026-08-17 | none — the fork point `6789876442d0` | First tag, commit `d6d7f85`. The reviewed **pre-upstream-merge** state: fork contract, ADR-0001…0007, supply-chain verdict, identity doc, PixelOven gates and this release workflow. This is the tag Harmony's `bastion` role installs (P1.2). |

The **next** tag will carry the A1.4 upstream merge (8 upstream commits through
`bdae21ed09d2`). Per §2 it is a **minor** bump — `v0.2.0` — because
[`upstream-merges.md`](upstream-merges.md) records consumer-visible behaviour
changes in it (`/stow` gains open-record persistence; `CLAUDE.md` changes shape
from a symlink to an `@AGENTS.md` pointer file).
