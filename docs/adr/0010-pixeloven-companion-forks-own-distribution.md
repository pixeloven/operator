# ADR-0010: PixelOven companion forks own distribution

- **Status:** Accepted
- **Date:** 2026-08-29
- **Deciders:** Brian Gebel (the operator)
- **Supersedes:** ADR-0001's absolute ban on editing upstream files, only for the bounded distribution surfaces below
- **Source:** `operator` upstream synchronization and companion-fork migration

## Context

ADR-0001 made `operator` additive-only so upstream merges stayed cheap and authorship stayed intact.
That rule served the first synchronization well, but it also left every required AXI tool and no-mistakes installed or verified from `kunchenguid/*` distribution endpoints.

PixelOven now maintains public forks of all six companion tools.
Downstream fixes must be usable before or without upstream acceptance, so `operator` cannot keep selecting upstream registry packages, release assets, raw action files, or install scripts as its distribution authority.

The five AXI repositories do not commit built `dist/` output on their default branches, and their GitHub forks do not publish npm packages.
The no-mistakes fork has no GitHub Releases because GitHub forks do not inherit a parent's release assets.
A URL swap to a nonexistent fork release would therefore look correct while remaining unusable.

## Decision

PixelOven's public companion forks are the distribution sources selected by `operator`.
[`bin/fm-install-pixeloven-tool.sh`](../../bin/fm-install-pixeloven-tool.sh) is the single owner of the exact repository, commit, expected version, and source-build mechanics for all six tools.
The installer fetches an exact fork commit, builds and deploys npm tools from their committed pnpm lockfiles, and builds no-mistakes from source without driving daemon lifecycle behavior.

ADR-0001 remains the default, but the following existing upstream files may carry narrowly reviewed PixelOven distribution or documentation-audience hunks:

- `.github/workflows/ci.yml`
- `.github/workflows/no-mistakes-required.yml`
- `CONTRIBUTING.md`
- `bin/fm-bootstrap.sh`
- `bin/fm-test-run.sh`
- `docs/configuration.md`
- `docs/documentation-audiences.json`
- `docs/examples/watched-tools.json`
- `tests/fm-bootstrap.test.sh`
- `tests/fm-no-mistakes-required.test.sh`

The new installer and its colocated test are also accepted in the inherited `bin/fm-*` and `tests/fm-*` namespaces.
Every other upstream file stays outside this exception.
Renames, broad rewrites, and unrelated cleanup in the listed files remain prohibited.

Each companion fork tracks its matching upstream default branch through reviewed merges that preserve ancestry.
A downstream fix lands and validates in the PixelOven fork first.
Offering the same fix upstream is optional and never blocks a PixelOven install or `operator` release.

## Consequences

Future upstream merges have a small, explicit file-level contact surface instead of a zero-contact claim.
The fork-contract gate allowlists only the paths above plus the established PixelOven namespaces and continues to compare against the moving upstream pin.

Pin bumps are `operator` changes and receive normal review, tests, and attribution checks.
The six tools' built-in update commands are not the PixelOven update path because they resolve upstream registries or releases.
Updating means synchronizing and validating the corresponding PixelOven fork first, then reviewing a pin bump in the installer.

Source builds add Node, corepack, and pnpm requirements for AXI installs and a Go toolchain requirement for no-mistakes installs.
This is the smallest viable path while the public forks have no independent package or release artifacts.
If PixelOven later publishes signed packages or release assets, a new ADR may replace the source-build mechanism after end-to-end verification.

## Alternatives considered

- Keep installing upstream packages and wait for upstream fixes.
  Rejected because upstream acceptance would remain a delivery dependency.
- Replace repository names in existing commands without testing the artifact path.
  Rejected because the npm forks have no published packages and the no-mistakes fork has no release assets.
- Build a general package-control plane.
  Rejected because six exact companion sources need a closed installer, not a new package manager.
- Publish releases from this task.
  Rejected because this task changes `operator` only and has no authority to edit, release, or push a companion repository.
