# ADR-0003: PixelOven org, private until a go-public review

- **Status:** Accepted
- **Date:** 2026-08-16
- **Deciders:** Brian Gebel (the operator), with Claude Code
- **Source:** Program plan decision **D-02**; requirement **G-6**

## Context

The PixelOven agent stack is intended to be **public** — that is the point of
building it as a standard-plus-tools rather than as private glue. But "intended
to be public" and "public now" are different states, and the gap between them is
where mistakes become permanent.

Two specific hazards apply to this repository:

- The fork carries a large upstream surface we have read but do not yet operate.
  Publishing before the supply-chain verdict (task A0.2) would mean endorsing
  code we had not finished auditing.
- Early-stage repos accumulate operational detail — host names, project
  registries, delivery postures — that is fine internally and wrong publicly.
  `.gitignore` already excludes `config/`, `state/`, `data/`, `projects/`, and
  `.env`, but that is a mechanism, not a review.

## Decision

- Every new repository in this program is created in the **PixelOven GitHub org**
  (`github.com/pixeloven`), **private**, licensed **MIT**, with **semver from the
  first tag** and CI gates from day one.
- A repository becomes public only after an explicit **go-public review** whose
  criteria are written down before it is run. Nothing goes public by default,
  by drift, or because it "feels ready".
- **Until that review passes, treat both repositories as if they were already
  public for content purposes.** No employer names, colleague names, credentials,
  host names, or private-reference content enters them — private today is not a
  licence to be careless, because history is forever and the go-public review
  does not rewrite it.

The go-public criteria themselves are a Phase 3 deliverable (task C4.3,
`roadmap.md`) and will be recorded as their own ADR when written.

## Consequences

- CI, branch protection, and secret scanning have to work on private repos on
  the org's current (free) plan. Where a GitHub feature is public-only, the gate
  is implemented in the workflow itself rather than deferred.
- Nothing here is discoverable by others yet, so external adoption — which is
  the whole thesis for `pulse`'s AXIs — starts only after the review. That cost
  is accepted in exchange for not publishing something wrong.
- The "treat as public" content rule is the operative constraint day to day.
  It is what makes the private→public transition a review rather than a scrub.
- MIT is fixed now rather than at publication, so contributions never need
  relicensing.

## Alternatives considered

- **Public from day one.** Rejected: publishes an un-audited fork surface and
  removes the ability to make an early mistake quietly. The stack's value does
  not depend on being public *early*, only on being public *eventually*.
- **Private forever, publish selected artifacts.** Rejected: the AXIs' adoption
  wedge is that each is independently useful to any agent. That requires real
  public packages, not extracts.
- **Public repo with private history rewritten before publication.** Rejected:
  history rewriting on a repo with a shared upstream merge base
  ([ADR-0002](0002-seeded-with-full-upstream-history.md)) would destroy the
  merge base. The content rule above is the cheaper and more honest control.
