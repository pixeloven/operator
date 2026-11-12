# ADR-0030: Run secondmates on hc with recovery-grade exit and relaunch

- **Status:** Proposed
- **Date:** 2026-11-12
- **Deciders:** The operator
- **Source:** Navigators invisible in the Herdr desktop app; pull request #59

## Context

In a terminal the Herdr desktop app projects, `fm-spawn` auto-selects the hc backend, whose `herdr.space` and `herdr.tab` labels are what make the app show a terminal.
Upstream's hc support refuses `--secondmate` spawns and has no `exit` or `relaunch` row in the control plane, so persistent secondmates (navigators) run on the TUI Herdr backend and never appear in the app.
The hc adapter itself lives in `bin/backends/`, but the spawn, control, liveness, and teardown paths that refuse or skip hc are inherited files, and ADR-0001 otherwise prohibits editing them.

## Decision

ADR-0001 remains the default, and the following inherited files may carry these bounded changes:

- `bin/fm-spawn.sh`: accepting `--secondmate` on hc, recording the spawn core's `hc_core`, placing a secondmate in its own home's Herdr app space, and re-creating a reclaimed hc terminal only in the recorded session while it still reaches the recorded core
- `bin/fm-control-lib.sh`: listing hc as state-verified and relaunch-capable, and an hc absence verdict that holds every hc reading to the recorded `hc_core`
- `bin/fm-control.sh`: the hc rows of `exit` and `relaunch`
- `bin/fm-secondmate-liveness-lib.sh`: settling every hc liveness reading against the recorded core, and refusing to respawn after a failed hc kill
- `bin/fm-backend.sh`: the comment describing the hc classifier
- `bin/fm-teardown.sh`: closing a forced-retired secondmate's hc workers as that secondmate's home
- `bin/fm-install-hc.sh` and the herdr-core pin assertion in `.github/workflows/ci.yml`: pinning herdr-core 0.1.20, the release the core identity and `ls --all` were measured on
- `docs/architecture.md`, `docs/hc-backend.md`, `docs/agent-control.md`, `docs/configuration.md`, and `docs/verification/runtime-backends.md`: the sentences and verification record describing these behaviors
- `tests/fm-backend-hc.test.sh`: the regression cases for these behaviors

Moving an existing task from another backend onto hc, and every other backend's behavior, are outside this exception.

The change is kept minimal so it can be offered upstream.
That offer is drafted later; nothing is published upstream now.
When an upstream synchronization brings an equivalent change, that merge takes upstream's version of these files, the A4 allowlist drops the ones no other ADR still needs, and this ADR is superseded by that merge.

## Consequences

Navigators can launch, restart, and recover on hc, so they appear in the Herdr desktop app, while TUI Herdr behavior is unchanged.
An hc endpoint counts as gone only when the core that answers is the one the task was created on.
Until an upstream synchronization brings an equivalent change, every synchronization has these files as an explicit contact surface to review.

## Verification

`tests/fm-backend-hc.test.sh` drives the real secondmate spawn, `exit`, `relaunch`, secondmate restart, and liveness recovery against a lifecycle-modelling fake core, including the different-core refusals.
The fork-contract workflow rejects any path outside the PixelOven namespaces and accepted ADR exceptions.

## Alternatives considered

- **Keep navigators on the TUI Herdr backend.** Rejected because they then never appear in the desktop app.
- **Move existing Herdr tasks onto hc in place.** Rejected for now because a Herdr task's worktree lease, presentation journal, and project-group placement have no hc-side owner.
- **Wait for upstream.** Rejected because upstream still refuses hc secondmates.
