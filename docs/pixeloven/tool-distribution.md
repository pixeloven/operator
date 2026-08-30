# Companion tool distribution

`operator` selects PixelOven's public forks as the distribution sources for its five AXI tools and no-mistakes.
The upstream projects remain the original works, and their histories, licenses, notices, and authorship stay intact in every fork.

## Sources

- [`pixeloven/gh-axi`](https://github.com/pixeloven/gh-axi), forked from [`kunchenguid/gh-axi`](https://github.com/kunchenguid/gh-axi).
- [`pixeloven/chrome-devtools-axi`](https://github.com/pixeloven/chrome-devtools-axi), forked from [`kunchenguid/chrome-devtools-axi`](https://github.com/kunchenguid/chrome-devtools-axi).
- [`pixeloven/lavish-axi`](https://github.com/pixeloven/lavish-axi), forked from [`kunchenguid/lavish-axi`](https://github.com/kunchenguid/lavish-axi).
- [`pixeloven/tasks-axi`](https://github.com/pixeloven/tasks-axi), forked from [`kunchenguid/tasks-axi`](https://github.com/kunchenguid/tasks-axi).
- [`pixeloven/quota-axi`](https://github.com/pixeloven/quota-axi), forked from [`kunchenguid/quota-axi`](https://github.com/kunchenguid/quota-axi).
- [`pixeloven/no-mistakes`](https://github.com/pixeloven/no-mistakes), forked from [`kunchenguid/no-mistakes`](https://github.com/kunchenguid/no-mistakes).

[`bin/fm-install-pixeloven-tool.sh`](../../bin/fm-install-pixeloven-tool.sh) is the executable source inventory.
Run `bin/fm-install-pixeloven-tool.sh --list` for the exact commit and expected version currently selected for each fork.
The script's header owns acquisition, build, destination, and no-mistakes daemon-safety mechanics.

## Installation and updates

The AXI forks do not publish separate npm packages and their default branches do not contain built `dist/` output.
The installer therefore fetches each exact PixelOven commit, installs dependencies from its committed pnpm lockfile, builds it, and deploys the production runtime from that same frozen lockfile into the requested prefix.

The no-mistakes fork has no inherited GitHub Release assets.
Its path builds the exact fork commit with the version and commit metadata pinned by the installer, installs only the CLI, and never starts, stops, restarts, or updates a running daemon.

The tools' in-band `update` commands are not the `operator` update path because those commands select upstream npm registries or GitHub Releases.
An update starts by synchronizing the matching PixelOven fork, landing and validating any downstream fix there, and then reviewing the exact pin bump in `operator`.

## Fork synchronization policy

Each PixelOven companion fork tracks its matching upstream default branch with upstream ancestry preserved.
Synchronization is reviewed and never rewrites shared history.
Downstream fixes land and validate in the PixelOven fork before `operator` selects them.
Contributing a fix upstream is welcome when useful, but optional, and upstream acceptance is never a prerequisite for PixelOven distribution.

The bounded exception to `operator`'s additive soft-fork contract is recorded in [ADR-0010](../adr/0010-pixeloven-companion-forks-own-distribution.md).
Current acquisition evidence lives in [`tool-distribution-verification.md`](tool-distribution-verification.md).
