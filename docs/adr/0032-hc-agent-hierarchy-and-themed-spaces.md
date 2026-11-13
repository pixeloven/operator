# ADR-0032: Nest hc tasks under their supervisor, lease their copies, and name app spaces from the theme

- **Status:** Proposed
- **Date:** 2026-11-13
- **Deciders:** The operator
- **Source:** In the Herdr desktop app the primary was hard to tell from the other workers; an hc worker launched from a distrobox-wrapped terminal recorded the primary clone as its worktree

## Context

The Herdr desktop app nests sub-agents in its Agents panel by the core's `parent` field, and names a space nobody named after its first terminal's repository.
The hc adapter started every task terminal with `--no-parent`, so the panel was flat, and every Firstmate space read as the repository name.
A worker spawned on hc from a terminal whose program is `distrobox enter` recorded the primary clone as its worktree: hc reports the host-side wrapper as the terminal's foreground for good, so its folder never followed the shell into the slot `treehouse get` entered, and inside the container that host spelling (`/var/home/u`) of the primary clone passed the isolation check's path comparison as a different directory.
The changes that fix this sit in inherited files, which ADR-0001 otherwise prohibits editing.

## Decision

ADR-0001 remains the default, and the following inherited files may carry these bounded changes:

- `bin/backends/hc.sh`: starting a task terminal with `--parent` set to the launching supervisor's own live terminal on the same core (`--no-parent` otherwise), asking the shell itself for its folder when the foreground is a wrapper, and the `herdr-app` space-rename mechanism that keeps a name a person chose
- `bin/fm-spawn.sh`: leasing an hc crewmate's or scout's Treehouse copy durably as Herdr does, returning that lease on an aborted spawn whose terminal is proven gone, comparing endpoint folders and the isolation check's project and git directories by identity as well as by resolved path, and one line that calls `bin/po-theme.sh hc-spaces` after a fresh hc spawn
- `docs/hc-backend.md` and `docs/verification/runtime-backends.md`: the sentences and verification record describing these behaviors
- `tests/fm-backend-hc.test.sh` and `tests/fm-backend-hc-appdetect-smoke.test.sh`: the regression cases for these behaviors

The theme's labels reach the app only through `bin/po-theme.sh`, which owns which spaces a spawn names and the accept-set that decides whether a space still carries a name the home gave it.
The hc and spawn changes other than that one hook line are kept free of theme vocabulary so they can be offered upstream.
That offer is drafted later; nothing is published upstream now.
When an upstream synchronization brings an equivalent change, that merge takes upstream's version of these files, the A4 allowlist drops the ones no other ADR still needs, and this ADR is superseded by that merge.

## Consequences

The Agents panel can nest workers under their navigator and navigators under the primary, and the spaces carry the theme's labels while a person's own names survive.
An hc worker records the copy Treehouse leased to it, whatever program wraps its shell, and is refused before launch if that shell never reaches it.
An hc task's durable lease outlives its terminal, so teardown, not the terminal's exit, returns its slot, as on Herdr.
Agent state still cannot see a harness behind a wrapper, so `exit` and `relaunch` keep refusing those tasks.
Until an upstream synchronization brings an equivalent change, every synchronization has these files as an explicit contact surface to review.

## Verification

`tests/fm-backend-hc.test.sh` drives parent linkage, the wrapped-shell spawn and its refusal, space naming, and a parented secondmate's restart, liveness read, and cleanup against fake cores.
`tests/fm-backend-hc-appdetect-smoke.test.sh` proves the parent on a real core in an isolated lab.
`tests/po-theme-labels.test.sh` proves `relabel --hc` renames only automatic or self-given names.
The fork-contract workflow rejects any path outside the PixelOven namespaces and accepted ADR exceptions.

## Alternatives considered

- **Keep `--no-parent`.** Rejected because the Agents panel then cannot show the hierarchy.
- **Read the shell's folder from `/proc` of processes carrying the terminal's `HC_TERMINAL_ID`.** Rejected because it depends on a shared process namespace and on a wrapper passing the environment through, while the probe asks the shell itself.
- **Theme the space names inside the hc adapter.** Rejected because the adapter is an upstream file and the theme layer's hooks belong to `bin/po-theme.sh`.
