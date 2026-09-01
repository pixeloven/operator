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

Five workflows run here, and they have very different characters:

| Workflow | Owner | Fires on | Character |
|---|---|---|---|
| `ci.yml` | upstream suite, with ADR-0011's GitHub-hosted routing and ADR-0010's bounded tasks-axi acquisition hunk | push to `main`, every PR; native macOS is manual/non-blocking | heavy: 2 parallel test shards + a 4-way serial matrix + a real-Herdr lane capped at 75 min + a `macos-latest` job |
| `no-mistakes-required.yml` | **upstream**, with ADR-0010's bounded PixelOven action source hunk | every PR | enforces the contribution contract owned by [`CONTRIBUTING.md`](../../CONTRIBUTING.md) |
| `windows-herdr-spike.yml` | **upstream** — never edited (O-1) | `workflow_dispatch` only | costs nothing unless invoked |
| `pixeloven-gates.yml` | **ours** | push to `main`, every PR | 2 jobs, both seconds of real work |
| `pixeloven-release.yml` | **ours** | `push: tags: ['v*']` | 1 job |

### The cost finding — measured, not estimated

The native macOS compatibility job is intentionally non-blocking for routine PR delivery and is run manually or on pushes to `main`.
Releases affecting shell portability must have recent native macOS evidence, or equivalent current upstream evidence, recorded before release.
The following billing figures are historical evidence from the repository's private, free-plan period, when the organization had 2,000 included Actions minutes per month and private-repository jobs consumed that allowance.
At that time GitHub billed each job rounded up to the minute and applied a 10x multiplier to macOS jobs.

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

During that private-repository period, `ci.yml` fired on both the pull request and the subsequent push to `main`, so one landed PR consumed approximately 172 billed minutes, or 8.6 percent of the monthly allowance.
The PixelOven gates consumed approximately 1.2 percent of one `ci.yml` run.

### The historical documentation-audience failure - resolved 2026-08-29

Upstream's `tests/fm-documentation-audiences.test.sh` runs `bin/fm-doc-audience-check.sh`, which enumerates every tracked prose surface repo-wide and requires each one to be classified in `docs/documentation-audiences.json`.
Every PixelOven document was therefore unclassified from the first downstream commit through `v0.1.0`.

Demonstrated locally at three points in our history:

| Tree | `bin/fm-doc-audience-check.sh` |
|---|---|
| fork point `6789876442d0` (pure upstream) | `ok surfaces=68 local_links=253` |
| `a5e90e3` (Phase 0, task A0.1 — **before** any A1 work) | **fails**: 11 unclassified |
| `d6d7f85` (`v0.1.0`) | **fails**: 14 unclassified |

ADR-0010 accepted the documentation inventory as one bounded existing-file exception because maintained downstream prose needs the same audience and owner checks as upstream prose.
The inventory now classifies every PixelOven ADR and project document, so `bin/fm-doc-audience-check.sh` can be read as a real pass/fail gate again.
That file is part of the future upstream contact surface and must be reconciled by ownership during every synchronization.

One further shard failure on the same run — `Behavior portable serial 3`,
`tests/fm-remote-job.test.sh`: *"remote job worker did not report ready after
startup"* — is an environmental flake in an upstream secondmate test, unrelated to
anything PixelOven adds.

### Current hosted-runner routing

The measured suite remains expensive, but executable validation is required for the intended public repository.
[ADR-0011](../adr/0011-operator-github-hosted-runner-routing.md) owns the bounded hosted-runner routing, private-runner exclusion, Node floor, and verification contract.

Do not disable the required suite as a cost workaround.
If hosted-runner billing or capacity blocks execution, treat that as an operational blocker rather than routing untrusted code to private infrastructure.

### Required no-mistakes check

[`CONTRIBUTING.md`](../../CONTRIBUTING.md) owns the signature and current-head attestation contract enforced by `Require no-mistakes`.
The check is expected to be green before merge.
ADR-0010 changes only the reusable action source to `pixeloven/no-mistakes` at the selected downstream commit `0e546529579f7a862f6f2fecef4905ddd10e2494`.
Upstream ancestry and corrective ancestry pull requests additionally follow the merge-commit contract in [`upstream-merges.md`](upstream-merges.md).

## 5. Release log

| Tag | Date | Upstream merged through | Notes |
|---|---|---|---|
| `v0.1.0` | 2026-08-17 | none — the fork point `6789876442d0` | First tag, commit `d6d7f85`. The reviewed **pre-upstream-merge** state: fork contract, ADR-0001…0007, supply-chain verdict, identity doc, PixelOven gates and this release workflow. This is the tag Harmony's `bastion` role installs (P1.2). |

The **next** tag will carry both completed upstream synchronizations: the 8-commit A1.4 merge through `bdae21ed09d2` and the subsequent 86-commit synchronization through `1fbc7bb1fba2`.
Per §2 it is a **minor** bump - `v0.2.0` - because [`upstream-merges.md`](upstream-merges.md) records consumer-visible behavior across runtime, supervision, backends, documentation, and tests, including `/stow` open-record persistence and the `CLAUDE.md` pointer-file change.
