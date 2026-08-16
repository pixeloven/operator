# ADR-0006: operator cuts its own release tags

- **Status:** Accepted
- **Date:** 2026-08-16
- **Deciders:** Brian Gebel (the operator), with Claude Code
- **Source:** Program plan requirement **O-3**; global requirement **G-2**

## Context

G-2 requires every dependency to be pinned to an exact version, with no
HEAD-tracking and no unpinned `npx`. Consumers of `operator` — starting with the
Harmony workstation bootstrap (task P1.2) — need something to pin *to*.

The available options are constrained by upstream's habits: **firstmate ships no
releases at all.** There are no tags, no semver, no changelog cadence; a commit
SHA is the only identifier that exists. Consumers pinning "the version of
firstmate we use" today would be pinning a 40-character hex string with no
ordering semantics, no compatibility signal, and no way to answer "is this newer
than what I have, and does it break me?".

## Decision

**`operator` cuts real release tags. Consumers pin our tags — never upstream,
never a raw SHA.**

- Tags are semver, starting at `v0.1.0` (task A1.2).
- A tag is cut from `main` after CI gates pass. Tagging is a deliberate act, not
  a side effect of merging.
- The version a consumer installs is stated as a variable in that consumer's own
  configuration (for Harmony: `ansible/roles/bastion` defaults), so the pin is
  visible and greppable rather than buried in a command.
- Upstream SHAs remain recorded — in `NOTICE` (the fork point) and in
  [`docs/pixeloven/upstream-tracking.md`](../pixeloven/upstream-tracking.md)
  (every merge) — but they are **provenance**, not a consumer interface.
  Nobody outside this repository pins one.

### What the version number means

A tag says: *this tree, including whatever upstream we have merged, passed our
gates and is what we intend you to run.* Because upstream carries no
compatibility signal of its own, our semver is the only compatibility statement
in the chain. An upstream merge that changes behavior our consumers depend on is
a minor or major bump on our side even though upstream called it nothing.

## Consequences

- Consumers get an ordered, comparable, greppable pin, and a rollback target
  that is a single token.
- We take on the obligation to *mean* the version number. Since our tags are the
  only compatibility signal, a merged upstream change with consumer-visible
  behavior must be classified at tag time. Merge rehearsal (A1.4) is where that
  classification cost gets measured.
- Release cadence is decoupled from upstream cadence. Upstream can ship five
  commits a day; we tag when we have merged, reviewed, and gated them.
- Tag `v0.1.0` cannot be cut before CI gates exist (A1.2), and the workstation
  bootstrap (P1.2) cannot complete before that tag exists. This dependency chain
  is why P1.x sits in Phase 1 rather than Phase 0.
- If this repository ever publishes to a package registry, the registry version
  and the git tag must be the same number. No parallel versioning schemes.

## Alternatives considered

- **Pin consumers to upstream SHAs directly.** Rejected: no ordering, no
  compatibility signal, and it makes every consumer a direct dependant of a
  repository that changes several times a day and that we have deliberately put
  a review gate in front of (ADR-0001, O-2).
- **Pin consumers to our `main` branch.** Rejected outright by G-2. It is
  HEAD-tracking with extra steps, and it means an unreviewed merge reaches the
  workstation the moment it lands.
- **Date-based versions (CalVer).** Rejected: dates communicate recency, not
  compatibility. Given that our tags are the *only* compatibility statement in
  the chain, discarding that expressiveness is the wrong trade.
- **Mirror upstream's SHA as our version (e.g. `v0.0.0+6789876`).** Rejected:
  it re-exports upstream's lack of versioning through a semver-shaped wrapper,
  which is worse than either honest option.
