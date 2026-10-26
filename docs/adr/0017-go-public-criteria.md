# ADR-0017: Go-public criteria for PixelOven repositories

- **Status:** Accepted
- **Date:** 2026-10-26
- **Deciders:** Brian Gebel (the operator)
- **Source:** ADR-0003 (go-public review must have written criteria); roadmap task C4.3; retroactive go-public review of `pixeloven/operator`
- **Scope:** every public PixelOven repository, not only `operator`

## Context

ADR-0003 keeps every program repository private until a go-public review whose criteria
are written down before it runs, and applies a "treat as already public" content rule in
the meantime. Several PixelOven repositories, `operator` included, became public before
those criteria existed, so the first application of this ADR is retroactive: it decides
what published material must be fixed, removed or rotated, not whether to publish.

History in a repository that shares upstream history (ADR-0002) cannot be rewritten
cheaply, and GitHub retains pull-request refs (`refs/pull/N/head`) that only GitHub
Support can remove. The criteria therefore prefer forward fixes and controls, and
reserve history rewrites for live, unrotatable exposure.

## Decision

These criteria apply to every public PixelOven repository.
A repository may be public (or stay public, for a retroactive review) only when every
criterion below passes or has a recorded, operator-approved exception. Each finding is
classified as **must-fix now**, **should-fix**, or **acceptable**.

### C1 - Content rule (ADR-0003), over all reachable history
Scope: every commit reachable from any branch, tag, or `refs/pull/*` ref; commit
metadata (author/committer name and email, trailers) as well as content; PR, issue,
release and comment text; committed binaries/screenshots.
- No credentials. A live credential is **must-fix now**: rotate first, then decide on
  history. A rotated or fake credential is acceptable once allowlisted with a reason.
- No employer names in files, docs, or PR, issue, release and comment text.
- No colleague names or contact details.
- No internal host names, IP addresses, internal URLs, or SaaS tenant URLs.
- No content copied from private references. A bare link to a private repository is
  should-fix in mutable docs and acceptable in immutable records (accepted ADRs, merged
  PR text, commit messages).
- The one exception is the maintainer's own identity. Their names and email addresses,
  work and personal, are acceptable content, including an employer email domain in
  commit metadata. This does not extend to colleagues.
- This ADR amends ADR-0003's content rule only to the extent of that exception.
  ADR-0003 itself is not edited.
- History is rewritten only for a live, unrotatable exposure. Everything else gets a
  forward fix.

### C2 - Branches, tags and PR refs
- Every non-default branch is either open work with a live PR, or a documented
  long-lived branch. Merged or abandoned branches are deleted.
- Release tags are protected against deletion and force-update. Releases are immutable
  where the plan allows.
- The default branch is protected: no force push, no deletion, changes through PRs,
  and required status checks.

### C3 - Documentation
- README, LICENSE, NOTICE and CONTRIBUTING are present and accurate for an outside reader.
- Links in mutable docs resolve for an anonymous reader, or are marked private.
- Operational detail (host roles, provisioning paths, personal machine configuration)
  is described generically unless it is the subject of the document.

### C4 - CI on a public repository
- Untrusted PR code never reaches private infrastructure: no `self-hosted`, ARC or
  private labels (ADR-0011), and no `pull_request_target` checking out PR heads.
- The workflow token defaults to read-only. Each workflow declares least-privilege
  `permissions:`, and only release jobs get `contents: write`.
- No repository or environment secrets are reachable from PR-triggered jobs.
- Fork-PR workflows need maintainer approval for outside contributors, because the CI
  fan-out competes for the organization's shared concurrency.
- Public Actions logs and artifacts are checked for leaks (a sample at review time,
  and the secret-scanning gate after that).

### C5 - Security policy
- `SECURITY.md` names a private reporting channel, and GitHub private vulnerability
  reporting is enabled.
- GitHub secret scanning and push protection are enabled (free on public repos), in
  addition to the in-workflow gitleaks gate.
- Dependabot alerts and code scanning (CodeQL default setup) are enabled where a
  supported language or Actions workflows exist.

### C6 - Licence
- The licence file matches the declared licence (MIT, per ADR-0003). Upstream
  copyright notices are retained, and NOTICE attributes upstream and third-party
  components accurately.

## Consequences

- Go-public (or a retroactive review) becomes a checklist with evidence, not a feeling.
- Forward fixes and controls carry most of the load. Published history is accepted
  unless a live exposure forces a rewrite.
- Setting changes (C2, C4, C5) are operator actions. A review never applies them itself.

## Alternatives considered

- **Rewrite history whenever C1 fails.** Rejected: it breaks the upstream merge base
  (ADR-0002) and published tags, and it can't remove `refs/pull/*`, forks or mirrors.
- **Rely on the in-workflow gitleaks gate alone.** Rejected: it scans only the PR
  head's history at CI time, not commit metadata policy, PR text or pushes to other
  branches, and it can't block a push.
