# The soft-fork contract

`pixeloven/operator` is a **soft fork** of [`kunchenguid/firstmate`](https://github.com/kunchenguid/firstmate)
(MIT, © 2026 Kun Chen). This page is the operating rule; the reasoning lives in
[ADR-0001](../adr/0001-soft-fork-of-firstmate.md),
[ADR-0002](../adr/0002-seeded-with-full-upstream-history.md), and the bounded exceptions in
[ADR-0008](../adr/0008-autonomous-delivery-lane.md),
[ADR-0009](../adr/0009-operator-arc-runner-routing.md), and
[ADR-0010](../adr/0010-pixeloven-companion-forks-own-distribution.md).

## The rule, in one line

**We add by default. We edit upstream files only for the exact downstream surfaces accepted by an ADR.**

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
| CI we own | `.github/workflows/pixeloven-*.yml` | |
| Companion installer | `bin/fm-install-pixeloven-tool.sh` | closed inventory of six public PixelOven forks |
| Companion installer tests | `tests/fm-install-pixeloven-tool.test.sh` | executable source and lifecycle contract |

Anything that does not fit one of these needs a new ADR that says why and which namespace it claims.
ADRs 0008 through 0010 list the exact existing upstream files that may carry their bounded downstream hunks.

Nothing inside the upstream surface is renamed — not the `fm-*` scripts, not the
`FM_*` variables, not the captain/crewmate vocabulary. The reasoning, and the
prose rule that "the operator" means the human (G-7), are in
[`identity.md`](identity.md).

The contract is **enforced on every pull request** by [`pixeloven-gates.yml`](../../.github/workflows/pixeloven-gates.yml).
It fails the build if the diff against the current upstream pin touches anything outside the owned namespaces and accepted ADR allowlists, if `README.md` differs from upstream outside the banner block, or if the companion source inventory selects anything other than the six matching PixelOven forks.
The assertions are documented in [`identity.md`](identity.md#5-assertions--the-grep-evidence).

## Bounded upstream-file exceptions

`README.md` carries a single delimited PixelOven banner block at the very top, pointing here.
Nothing else in it is changed.
This remains the identity exception recorded in ADR-0001.

ADR-0010 separately permits the exact source-selection, CI acquisition, contributor guidance, audience inventory, and regression files needed to make PixelOven's companion forks independently usable.
Those are behavior-owned hunks, not permission for renames, cleanup, or unrelated downstream edits.
The companion source and sync policy is owned by [`tool-distribution.md`](tool-distribution.md).

ADR-0008 owns the isolated unsigned delivery lane, and ADR-0009 owns the exact Linux ARC workflow routing exceptions.

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
