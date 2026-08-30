# ADR-0011: `operator` CI uses standard GitHub-hosted runners

- **Status:** Accepted
- **Date:** 2026-08-30
- **Deciders:** Brian Gebel (the operator)
- **Source:** Hosted-runner remediation after PR #11
- **Supersedes:** [ADR-0009](0009-operator-arc-runner-routing.md)

## Context

PR #11 restored the current upstream and PixelOven companion-source integration, but every executable Linux job still requested the private `lattice` runner label.
The pull-request checks and fresh `main` checks therefore remained queued without an eligible runner.

The intended public repository must treat pull-request code as untrusted.
PixelOven's ARC capacity is reserved for private trusted workloads and is not a fallback for `operator`.

The PixelOven source installer requires Node.js 22.19 or newer for AXI tools.
Jobs that install those tools or execute their integration tests must provision that floor explicitly instead of depending on a mutable runner image default.

## Decision

Every executable Linux job in `operator` workflows uses `ubuntu-latest`.
The stock macOS compatibility job retains `macos-latest`, and the Windows Herdr spike retains `windows-latest`.
No workflow may add `self-hosted`, ARC, `lattice`, Harmony, or another private-runner fallback for public or untrusted work.

The obsolete actionlint custom-runner declaration is removed.
Actionlint's standard runner-label model therefore rejects undeclared private labels during local lint before a workflow can strand required checks.

CI jobs that execute `bin/fm-install-pixeloven-tool.sh` or its integration tests provision Node.js 22.19.0 explicitly.

## Consequences

Required pull-request and default-branch checks can execute without private runner-group, ARC scale-set, Harmony tenant, App, or PAT dependencies.
Linux jobs consume standard GitHub-hosted capacity, while native macOS and Windows evidence remain on their matching hosted platforms.
The repository keeps read-only workflow permissions for pull-request code and gains no secret or private-runner fallback.
This decision changes workflow routing only; it does not authorize a repository visibility or settings change.

## Verification

`bin/fm-lint.sh` validates every workflow with the pinned actionlint version and no private-label exception.
`bin/fm-test-run.sh tests/fm-lint-workflows.test.sh` parses the workflow model, checks the hosted runner allowlist and Node floor, and proves a private runner label is rejected by the real workflow linter.
GitHub job metadata for the remediation pull request must show terminal green Linux jobs on standard GitHub-hosted runners before merge.

## Alternatives considered

- **Keep `lattice` while the repository is private.** Rejected because the immediate checks have no eligible runner and the intended public trust boundary does not permit private ARC execution.
- **Add a private-runner fallback after `ubuntu-latest`.** Rejected because untrusted code must never become eligible for private infrastructure.
- **Move only pull-request jobs.** Rejected because push and release validation would retain an unnecessary private dependency and the same routing drift could recur.
