# The soft-fork contract

`pixeloven/operator` is a **soft fork** of [`kunchenguid/firstmate`](https://github.com/kunchenguid/firstmate)
(MIT, © 2026 Kun Chen). This page is the operating rule; the reasoning lives in
[ADR-0001](../adr/0001-soft-fork-of-firstmate.md) and
[ADR-0002](../adr/0002-seeded-with-full-upstream-history.md).

## The rule, in one line

**We add files. We do not edit upstream's.**

## Fork point

| | |
|---|---|
| Upstream | `https://github.com/kunchenguid/firstmate` |
| Fork commit | `6789876442d0fb6da9f70d86399a2930c5073ae2` |
| Commit subject | `chore: ignore scratchpad/ at the repo root (#2359)` |
| Commit date | 2026-08-13 |
| Seed method | full upstream history pushed unchanged; `main` = the fork commit |

`upstream` is configured as a git remote. To see everything PixelOven has
changed, at any time:

```sh
git diff 6789876442d0fb6da9f70d86399a2930c5073ae2..main
```

## Where our code goes

| Surface | Path | Note |
|---|---|---|
| Runtime backends | `bin/backends/` | new adapter files only |
| Skills | `.agents/skills/po-*` | the `po-` prefix exists so upstream can never collide with us |
| Documentation | `docs/pixeloven/` | |
| Decisions | `docs/adr/` | |
| CI we own | `.github/workflows/pixeloven-*.yml` | upstream's three workflows are never edited |

Anything that does not fit one of these needs a new ADR that says why, and which
namespace it claims.

Nothing inside the upstream surface is renamed — not the `fm-*` scripts, not the
`FM_*` variables, not the captain/crewmate vocabulary. The reasoning, and the
prose rule that "the operator" means the human (G-7), are in
[`identity.md`](identity.md).

The contract is **enforced on every pull request** by
[`pixeloven-gates.yml`](../../.github/workflows/pixeloven-gates.yml): it fails
the build if the diff against the fork point touches anything outside the table
above, or if `README.md` differs from upstream outside the banner block. The
assertions are documented in [`identity.md`](identity.md#5-assertions--the-grep-evidence).

## The one edited upstream file

`README.md` carries a single delimited PixelOven banner block at the very top,
pointing here. Nothing else in it is changed. This is a bounded, deliberate
exception recorded in ADR-0001 — one hunk, in the file least likely to carry
load-bearing behavior.

## Taking upstream changes

1. Upstream merges are **scheduled, reviewed pull requests**. Never automatic,
   never a bot that self-merges, never a background job (requirement O-2).
2. Every merge records its before/after distance in
   [`upstream-tracking.md`](upstream-tracking.md).
3. A merge is code review, not a formality: this repository's files execute
   inside every agent turn, and workers launch with their harness permission
   gates disabled (see [supply-chain-read.md](supply-chain-read.md)).

```sh
git fetch upstream
git log --oneline main..upstream/main     # what's new
git merge --no-ff upstream/main           # on a branch, into a PR
```

## Releasing

`operator` cuts its own semver tags from `v0.1.0`. **Consumers pin our tags —
never upstream, never a raw SHA** (requirement O-3,
[ADR-0006](../adr/0006-operator-cuts-its-own-release-tags.md)). The policy, what
a tag means, how it relates to an upstream merge, and the CI cost of this
repository are in [`releases.md`](releases.md).

## Attribution

`LICENSE` is upstream's MIT license, retained verbatim and unmodified. `NOTICE`
records the attribution and the fork point. Because history was seeded whole,
`git blame` attributes every upstream line to its actual author.

## What we never do

- Push anything to `kunchenguid/*` or any other upstream repository without
  per-instance approval from the operator (requirement G-5).
- Rewrite history on `main` — it would destroy the merge base with upstream and
  make the whole contract unimplementable.
