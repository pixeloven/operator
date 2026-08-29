# ADR-0007: PixelOven CI lives in its own workflow namespace

- **Status:** Accepted
- **Date:** 2026-08-17
- **Deciders:** Brian Gebel (the operator), with Claude Code
- **Source:** Task **A1.2**; requirements **O-1**, **O-3**, **G-2**, **G-6**

## Context

G-6 requires CI gates from day one. This repository already carries **three
workflows, all of them upstream's**: `ci.yml` (the shell test suite),
`no-mistakes-required.yml` (PR-body pipeline enforcement) and
`windows-herdr-spike.yml` (a `workflow_dispatch` spike). Under
[ADR-0001](0001-soft-fork-of-firstmate.md) none of them may be edited.

So our gates have to live somewhere new — and
[`docs/pixeloven/fork-contract.md`](../pixeloven/fork-contract.md) is explicit
that a surface outside the four already-declared namespaces (`bin/backends/`,
`.agents/skills/po-*`, `docs/pixeloven/`, `docs/adr/`) **needs an ADR that says
why, and which namespace it claims.** This is that ADR.

Two further forces shaped the content rather than the location:

1. **`pixeloven` is a GitHub *organization*.** The marketplace
   `gitleaks/gitleaks-action` requires a `GITLEAKS_LICENSE` secret for
   organization-owned repositories, and we hold no license key. The
   github-hosted template in the harmony-ci action library carries exactly that
   caveat in a comment.
2. **ARC routing is a separate organization-owned concern.** The repository was
   initially created before the PixelOven ARC pool was available, so its first
   workflows used GitHub-hosted runners. The later ARC migration is recorded in
   ADR-0009.

## Decision

**PixelOven CI is claimed as a fifth namespace: `.github/workflows/pixeloven-*.yml`.**

- Two workflows are added: `pixeloven-gates.yml` (per-PR gates) and
  `pixeloven-release.yml` (tag → GitHub Release, the O-3 mechanism).
- **Every check is scoped to files PixelOven authored.** actionlint runs against
  `pixeloven-*.yml` only; the docs link check runs against `docs/pixeloven/**`
  and `docs/adr/**` only. ShellCheck over `bin/**` is *not* duplicated — upstream's
  `ci.yml` owns it through `bin/fm-lint.sh`, which is the single owner of that
  lint definition.
- **Third-party tools are installed as pinned release binaries verified by
  SHA256**, not as marketplace actions, wherever a license or token gate would
  otherwise apply. gitleaks and actionlint are installed this way; their versions
  and digests live in the workflow's `env:` block so a version bump and its
  digest move in the same commit (G-2). `actions/checkout` is pinned to a full
  commit SHA.
- gitleaks runs with `--redact` so a candidate secret is never echoed into a log
  (G-3).
- Linux jobs now use the organization-owned `lattice` ARC pool. Native macOS
  and Windows jobs retain `macos-latest` and `windows-latest` respectively.
- The fork contract's own assertions — the diff-against-the-fork-point check and
  the G-7 naming rule — run as a step in `pixeloven-gates.yml`, so task A1.1's
  "grep clean" acceptance is continuously enforced rather than claimed once.
  They are documented in [`docs/pixeloven/identity.md`](../pixeloven/identity.md).

## Consequences

- The declared PixelOven surface is now **five** namespaces. The banner in
  `README.md` and the fork-contract table are updated to match; both remain
  inside their existing sanctioned bounds.
- **Collision with upstream is structurally impossible**: any workflow upstream
  adds cannot be named `pixeloven-*` unless upstream deliberately adopts our
  prefix. The prefix is also what makes ownership *greppable* — assertion A4 in
  the gates workflow keys on it to decide whether a changed file is ours.
- **An upstream regression can never fail our gates**, because our gates never
  grade upstream's code. That matters: a gate that failed on upstream's shell
  would manufacture pressure to edit upstream's shell, which is precisely what
  the fork contract exists to prevent.
- We carry a small maintenance obligation: two pinned tool digests to bump.
  That is the price of not depending on a licensed action.
- **The inherited `ci.yml` remains expensive and is not ours to fix by editing.**
  Its measured cost and the settings-level options are recorded in
  [`docs/pixeloven/releases.md`](../pixeloven/releases.md); the choice among them
  is the operator's, and is a repository setting, not a file change.
- `no-mistakes-required.yml` will fail on our own pull requests until this
  repository is registered in the project registry with posture `no-mistakes`
  (task A1.3, [ADR-0005](0005-agent-self-improvement-is-pr-gated.md)). That red
  check is expected, and is evidence the enforcement works.

## Alternatives considered

- **Add our jobs to upstream's `ci.yml`.** Rejected outright by O-1. It would
  also conflict on every upstream merge, in the file upstream changes most.
- **Ship no CI of our own and rely on upstream's suite.** Rejected: upstream's
  suite grades upstream's shell. It cannot see whether our diff stayed additive,
  whether our docs' links resolve, whether a secret entered the tree, or whether
  a PixelOven doc violated G-7 — which is the entire risk surface this fork adds.
  G-6 also requires gates from day one.
- **One unprefixed workflow, e.g. `ci-gates.yml`.** Rejected: the prefix is the
  ownership boundary. Without it, "is this file ours?" becomes a judgement call
  in a check that has to answer it mechanically.
- **The marketplace `gitleaks/gitleaks-action`.** Rejected: `GITLEAKS_LICENSE` is
  required for organization-owned repositories and we have no key. The pinned
  binary is also a *smaller* supply-chain surface — one tarball with a recorded
  digest, versus an action whose tag could move.
- **Add `osv-scanner` and `dependency-review` for completeness.** Rejected as
  decorative: the only manifest in the tree is `.opencode/plugins/package.json`
  = `{"private": true, "type": "module"}`, with no dependencies and no lockfile
  anywhere. A gate that scans nothing teaches a reviewer to ignore it. Instead a
  zero-cost tripwire step fails the build the moment a lockfile or a
  dependency-bearing manifest appears — from our work or from an upstream merge —
  and its remedy is additive: enable the scanner. The decision cannot rot
  silently.
- **`yamllint` and a markdown linter.** Rejected: actionlint already validates
  the workflow YAML we author, and both tools want a config file at a path
  outside our declared namespaces. The markdown check that earns its place is a
  relative-link check over our two doc trees, which needs no config and catches
  the defect class a cross-linked ADR set actually suffers.
- **`semgrep`.** Deferred: registry rulesets are login-gated (zero findings
  without a token) and the harmony baseline ruleset is baked into the private
  ARC runner image. Revisit with the ARC migration.
- **Wait for ARC before adding any gates.** Rejected: G-6 says gates from day
  one, and task A1.2 gates task P1.2. GitHub-hosted labels were the initial
  fallback; ADR-0009 records the later Linux migration to `lattice`.
