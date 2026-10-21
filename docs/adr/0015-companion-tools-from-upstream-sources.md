# ADR-0015: Companion tools are acquired from upstream sources

- **Status:** Accepted
- **Date:** 2026-10-21
- **Deciders:** Brian Gebel (the operator)
- **Source:** Captain decisions of 2026-10-21 for the five-stage upstream synchronization
- **Supersedes:** [ADR-0010](0010-pixeloven-companion-forks-own-distribution.md), and the Node.js 22.19.0 provisioning clause of [ADR-0011](0011-operator-github-hosted-runner-routing.md)

## Context

ADR-0010 made PixelOven's public forks of gh-axi, chrome-devtools-axi, lavish-axi, tasks-axi, quota-axi, and no-mistakes the distribution sources selected by `operator`.
It carried a source-build installer, `bin/fm-install-pixeloven-tool.sh`, and downstream hunks in ten upstream-owned files to route every acquisition through it.

The upstream overlap investigation of 2026-10-21 measured what that costs on the next synchronization.
Upstream advanced 481 commits past our pin, and ADR-0010's hunks sit in several of the most frequently changed upstream files: `ci.yml`, `bin/fm-bootstrap.sh`, `docs/configuration.md`, and the bootstrap test fixtures.
Upstream also raised its tool floors past every fork pin: tasks-axi to 0.2.6, quota-axi to 0.1.51, and lavish-axi to 0.1.80, against fork pins of 0.2.5, 0.1.34, and 0.1.63.
Holding those floors down is not available, because the floor constants live in upstream files outside ADR-0010's list, and tasks-axi below its floor makes spawns, captain holds, and backlog handoff refuse.
Keeping ADR-0010 would therefore require syncing and revalidating six forks and re-porting the acquisition hunks onto restructured upstream code before every synchronization could land.

## Decision

`operator` acquires its six companion tools exactly as upstream `kunchenguid/firstmate` does at the current pin: the published npm packages and the upstream no-mistakes install path and reusable action, at the version floors upstream sets.

Every ADR-0010 tool-acquisition and contributor-guidance hunk in an upstream-owned file returns to upstream's bytes at the pin.
`bin/fm-install-pixeloven-tool.sh` and its test are removed, and `bin/fm-pixeloven-upstream-check.sh` keeps only the operator pin lineage check.
The Node.js 22.19.0 CI provisioning that ADR-0011 added for the installer is removed with it, because nothing else in the suite requires it.

ADR-0010's documentation-audience exception is the one part that stays in force, now owned here: `docs/documentation-audiences.json` may carry the entries that classify PixelOven-owned prose under `docs/pixeloven/` and `docs/adr/`, so upstream's audience check stays a real gate.

The PixelOven fork repositories are not changed by this decision; archiving them is a separate later decision.
The fork-contract gate's A4 allowlist drops every path that existed only for ADR-0010, and A8 asserts that no tracked file outside decision and documentation history selects a PixelOven fork or the retired installer.

## Consequences

The synchronization contact surface shrinks to the hunks owned by ADR-0008 and ADR-0011 through ADR-0014 plus the audience entries above, and upstream's acquisition changes and floor bumps merge as upstream wrote them.
Tool versions follow upstream's floors without a fork-sync and pin-bump cycle in between.

The supply-chain trade-off is accepted: `operator` again trusts upstream's npm publishers and the no-mistakes release path directly, and loses the ability to ship a downstream tool fix ahead of upstream.
[`supply-chain-read.md`](../pixeloven/supply-chain-read.md) records the current acquisition sources and the accepted deviations.
A downstream tool fix that cannot wait for upstream needs a new ADR rather than a quiet return to a fork.

`CONTRIBUTING.md` returns to upstream's bytes, so its contributor workflow names upstream's repository; [`fork-contract.md`](../pixeloven/fork-contract.md#contributing) says how that workflow maps onto `operator`.

## Alternatives considered

- **Keep ADR-0010 and bump the forks before the synchronization.** Rejected because it repeats the fork sync, source-build validation, and hunk re-port on every upstream merge.
- **Keep ADR-0010 but pin upstream packages inside the PixelOven installer.** Rejected because it keeps the whole ten-file contact surface while delivering upstream's packages, so it pays the sync cost for no distribution benefit.
- **Hold upstream's tool floors at the fork pins.** Rejected because the floors live in upstream files outside any accepted exception and the floor policy exists to keep the fleet current.
