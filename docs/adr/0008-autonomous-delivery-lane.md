# ADR-0008: Autonomous delivery lane

- **Status:** Accepted
- **Date:** 2026-08-25
- **Deciders:** The operator
- **Requirements:** Separate interactive human signing from autonomous agent delivery

## Context

The host's interactive Git configuration enables SSH commit signing through a human credential provider.
That configuration is intentionally not suitable for unattended workers because it can require an unlocked 1Password agent or an interactive signing key selection.
Autonomous workers need a deterministic delivery path without changing the captain's global Git configuration, credentials, or shared validation daemon.

## Decision

Autonomous workers receive a task-owned Git configuration through `bin/fm-delivery-lane.sh`.
The configuration disables commit and tag signing and supplies a stable autonomous identity.
`fm-spawn.sh` exports that configuration together with `GIT_CONFIG_NOSYSTEM=1` before every worker launch.
The configuration is disposable with the task temporary root and remains inspectable during execution.
The helper performs a non-destructive signing preflight and reports when ambient 1Password or incomplete SSH signing settings are being overridden.

## Consequences

Human Git configuration and credentials remain unchanged and continue to govern interactive work.
Autonomous commits are intentionally unsigned and attributable to the stable autonomous identity.
The focused delivery regression proves an unsigned commit succeeds with an ambient 1Password SSH signer and incomplete SSH signing configuration.
