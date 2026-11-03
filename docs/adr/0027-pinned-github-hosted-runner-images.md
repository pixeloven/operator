# ADR-0027: Linux CI may pin a standard GitHub-hosted runner image version

- **Status:** Accepted
- **Date:** 2026-11-02
- **Deciders:** The operator
- **Source:** Fifth upstream synchronization; upstream pinned its Linux jobs to `ubuntu-24.04`
- **Amends:** [ADR-0011](0011-operator-github-hosted-runner-routing.md)

## Context

[ADR-0011](0011-operator-github-hosted-runner-routing.md) routes every executable Linux job to `ubuntu-latest`, and `tests/fm-lint-workflows.test.sh` enforces exactly that label.
Its purpose is the trust boundary: public and untrusted work runs only on standard GitHub-hosted runners, never on private ARC or self-hosted capacity.

GitHub is moving `ubuntu-latest` from Ubuntu 24.04 to 26.04, with the rollout finishing on 2026-11-19.
Ubuntu 26.04 ships Rust coreutils, whose `timeout` and `sleep` behave differently from GNU coreutils, and upstream measured its watcher suites failing on those runners.
Upstream [kunchenguid/firstmate#7798](https://github.com/kunchenguid/firstmate/pull/7798) therefore pins every Linux job in `.github/workflows/ci.yml` to `ubuntu-24.04`, and the fifth synchronization brings that change.

## Decision

ADR-0011's label clause is amended: an executable Linux job uses a standard GitHub-hosted Ubuntu label, either `ubuntu-latest` or a pinned standard version label.
The pinned version currently accepted is `ubuntu-24.04`, which `.github/workflows/ci.yml` takes from upstream unchanged.
`tests/fm-lint-workflows.test.sh` accepts exactly the labels this ADR and ADR-0011 name, so a new pinned version is added there deliberately rather than by pattern.

Every other part of ADR-0011 stands, including its prohibition on `self-hosted`, ARC, `lattice`, Harmony, or any other private-runner fallback, and its inherited-file exception list, which already covers both files touched here.

## Consequences

Linux CI keeps the image upstream's suites are proven on, and the label follows upstream when upstream lifts or moves its pin.
A future image migration is a reviewed change to an allowlist entry rather than a silent runner swap.
The trust boundary is unchanged: every accepted label is a standard GitHub-hosted runner.

## Alternatives considered

- **Keep `ubuntu-latest` on every job.** Rejected because those jobs would move to 26.04 by 2026-11-19, where upstream's watcher suites are known to fail, and each job would carry a downstream hunk against upstream's pin.
- **Accept any `ubuntu-*` label by pattern.** Rejected because an exact list keeps every image change visible in review.
