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
plus the first measured rehearsal live in `upstream-merges.md` (task A1.4).

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

### The cost finding

This repository is **private, on a free-plan org** — 2,000 included Actions
minutes per month, and private-repo minutes bill against them. GitHub bills each
**job** rounded up to the minute, and `macos` bills at **10×**.

Estimated from the workflow's own documented timings (its comments state
measured shard walls):

| Lane | Jobs | Wall | Multiplier | Billed |
|---|---|---|---|---|
| lint, coverage, invariants, aggregate | 4 | ~1 min each | 1× | ~4 |
| portable parallel shards | 2 | ~1–2 min each | 1× | ~4 |
| portable serial matrix | 4 | ~4.8 min each | 1× | ~19 |
| real-Herdr lane | 1 | 15–40 min (cap 75) | 1× | ~30 |
| `macos-stock-bash` | 1 | ~2–3 min | **10×** | ~25 |
| **`ci.yml` total** | **12** | | | **≈ 80–90 min per run** |
| `pixeloven-gates.yml` | 2 | seconds | 1× | ~2 |

`ci.yml` fires on **both** the pull request and the subsequent push to `main`, so
**one landed PR costs roughly 160–180 billed minutes** — about **9 % of the
monthly allowance per PR**, or **~11 PRs before the budget is gone**. Our own
gates add ~2 % of that.

**This is an inherited property of upstream's suite, not a defect, and it is not
ours to fix by editing.** O-1 forbids touching `ci.yml`. The available levers are
repository *settings* rather than files, and they are the operator's call:

1. **Disable `ci.yml` at the repository level** (Actions → workflow → Disable, or
   `gh api -X PUT /repos/pixeloven/operator/actions/workflows/<id>/disable`).
   Nothing in the tree changes; the file stays byte-identical for upstream
   merges. This is the single biggest saving and the recommended default while
   the repo is private and pre-pilot — our own gates plus the merge review
   already cover what we change, and we change no shell.
2. **Leave it on and accept ~11 PRs/month**, revisiting when ARC lands.
3. **Migrate to the ARC self-hosted pool** (Phase 0.5 / M0.1) — self-hosted
   minutes do not bill against the allowance. This fixes the cost permanently,
   but `ci.yml` names `ubuntu-latest`/`macos-latest` explicitly and re-pointing
   it would mean editing an upstream file. So ARC fixes *our* workflows' cost,
   not upstream's, unless a runner group is labelled to intercept
   `ubuntu-latest` (possible, and worth evaluating at M0.1).

Whichever is chosen, our own workflows stay on `ubuntu-latest` until M0.1 lands;
the migration is a follow-up noted in both workflow headers.

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
| `v0.1.0` | 2026-08-17 | none — the fork point `6789876442d0` | First tag. The reviewed pre-upstream-merge state: fork contract, ADR-0001…0006, supply-chain verdict, identity doc, PixelOven gates and release workflow. This is the tag Harmony's `bastion` role installs (P1.2). |
