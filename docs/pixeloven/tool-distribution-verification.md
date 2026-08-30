# Companion tool distribution verification

- **Observed:** 2026-08-30
- **`operator` upstream:** `kunchenguid/firstmate@1fbc7bb1fba262ef38a4dedf321d18c54669b129`
- **Contract owner:** [`tool-distribution.md`](tool-distribution.md)
- **Executable inventory:** [`bin/fm-install-pixeloven-tool.sh`](../../bin/fm-install-pixeloven-tool.sh)

## Repository and release state

The following read-only `gh-axi` checks were run for each of `gh-axi`, `chrome-devtools-axi`, `lavish-axi`, `tasks-axi`, `quota-axi`, and `no-mistakes`:

```sh
gh-axi repo view pixeloven/<tool>
gh-axi release list -R pixeloven/<tool> --limit 5
gh-axi api /repos/pixeloven/<tool> --jq \
  '{fork: .fork, parent: .parent.full_name, default_branch: .default_branch}' --full
gh-axi api /repos/pixeloven/<tool>/compare/main...kunchenguid:main --jq \
  '{status: .status, ahead_by: .ahead_by, behind_by: .behind_by}' --full
```

All six repositories reported `visibility: public`, `fork: true`, the matching `kunchenguid/<tool>` parent, and `default_branch: main`.
The five AXI comparisons reported `status: identical`, `ahead_by: 0`, and `behind_by: 0` at the selected commits.
The no-mistakes comparison proved that `pixeloven/no-mistakes@70185bf682521ed1822e51dc09fa327b85b87e79` contains current upstream `1a3f74d86d2646967d6f1e7dce8853023c41768c` plus five downstream commits.
All six release listings reported `count: 0` and `releases: []`, proving that an installer could not select a PixelOven release asset at this observation.

The no-mistakes shared-action commit selected by `.github/workflows/no-mistakes-required.yml` was also checked at the downstream source:

```sh
gh-axi api HEAD \
  '/repos/pixeloven/no-mistakes/contents/.github/actions/require-no-mistakes/verify.py?ref=70185bf682521ed1822e51dc09fa327b85b87e79' \
  --full
```

It returned an empty successful HEAD response rather than HTTP 404.

## Source installation

The exact npm fork paths were exercised into disposable prefixes with:

```sh
bin/fm-install-pixeloven-tool.sh gh-axi <prefix>
bin/fm-install-pixeloven-tool.sh chrome-devtools-axi <prefix>
bin/fm-install-pixeloven-tool.sh lavish-axi <prefix>
bin/fm-install-pixeloven-tool.sh tasks-axi <prefix>
bin/fm-install-pixeloven-tool.sh quota-axi <prefix>
```

Each command fetched its recorded `pixeloven/<tool>` commit, completed the locked source build, installed an executable under `<prefix>/bin`, and returned the exact expected version from that installed executable.

The no-mistakes path was exercised with the checksum-verified Go 1.25.0 Linux toolchain and isolated Go caches:

```sh
bin/fm-install-pixeloven-tool.sh no-mistakes <prefix>
<prefix>/bin/no-mistakes --version
```

The installed binary reported `no-mistakes version v1.60.1 (70185bf) 2026-08-30T02:08:45+00:00`.
The source-install command made no daemon lifecycle call.

Portable regression coverage uses:

```sh
bin/fm-test-run.sh tests/fm-install-pixeloven-tool.test.sh
bin/fm-test-run.sh tests/fm-bootstrap.test.sh
bin/fm-test-run.sh tests/fm-no-mistakes-required.test.sh
```

The first test executes the installer's public source inventory, all five npm build/deploy/install paths with their declared executable layouts and lockfile-selected production dependencies, failure-safe npm and no-mistakes replacement, unsafe executable-path refusal, the no-mistakes build/install path, the closed-tool refusal, and the daemon-lifecycle negative guarantee with isolated fakes.
