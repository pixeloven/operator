# ADR-0009: `operator` Linux CI routes through the PixelOven ARC pool

- **Status:** Superseded by ADR-0011
- **Date:** 2026-08-25
- **Deciders:** Brian Gebel (the operator)
- **Source:** Captain-approved PR #10 remediation

## Context

The PixelOven organization now has a working ARC pool exposed through the
`lattice` runner label.

A successful `pixeloven/lattice` run reached ephemeral ARC runners with
`runs-on: lattice`, while PR #10's `operator` Linux jobs requested
`ubuntu-latest` and could not reach that pool.

## Decision

Route every intended Linux job in the `operator` workflows through
`runs-on: lattice`.

This includes the inherited CI suite, the no-mistakes PR-body check, the
PixelOven gates, and the PixelOven release validation job.

Retain `macos-latest` for the stock macOS Bash 3.2 compatibility check and
`windows-latest` for the native Windows Herdr automation spike.

The ARC label and repository access policy remain organization-owned
configuration; this repository change does not alter billing or runner-group
permissions.

## Consequences

Linux checks no longer consume GitHub-hosted Linux minutes when the ARC pool is
available and authorized for this repository.

Native macOS and Windows checks remain dependent on GitHub-hosted capacity and
are reported separately if the organization has no hosted-runner budget.

The workflow comments and the PixelOven fork-contract allowlist record the
intentional exception to the original soft-fork baseline.

## Verification

A successful `pixeloven/lattice` run (`32260565843`) used the `lattice` label
and ephemeral runners for its Linux jobs, while its E2E and aggregator jobs
intentionally remained on `ubuntu-latest`.

The operator repository API reports Actions enabled, but this token cannot
read organization runner-group membership. An organization administrator must
confirm that the `lattice` group includes `pixeloven/operator`.
