# PixelOven tasks-axi workflow dependency — end-to-end evidence

The workflow dependency command was exercised locally with Node `v22.23.2`,
which satisfies the configured Node 22.19 floor.

```console
$ bin/fm-install-pixeloven-tool.sh --source tasks-axi
tasks-axi	https://github.com/pixeloven/tasks-axi	d9175b6d083d693c5b6ca21652454d52e4b312d9	0.2.5	npm

$ bin/fm-install-pixeloven-tool.sh tasks-axi "$E2E_ROOT/fm-tools"
fm-install-pixeloven-tool.sh: fetching https://github.com/pixeloven/tasks-axi at d9175b6d083d693c5b6ca21652454d52e4b312d9
Lockfile is up to date, resolution step is skipped
$ tsc
0.2.5
fm-install-pixeloven-tool.sh: installed tasks-axi 0.2.5 from pixeloven/tasks-axi@d9175b6d083d693c5b6ca21652454d52e4b312d9 at $E2E_ROOT/fm-tools/bin/tasks-axi

$ "$E2E_ROOT/fm-tools/bin/tasks-axi" --version
0.2.5

$ readlink "$E2E_ROOT/fm-tools/bin/tasks-axi"
../lib/node_modules/tasks-axi/dist/bin/tasks-axi.js

$ node -e 'const p=require(process.argv[1]); console.log(p.name+"@"+p.version)' "$E2E_ROOT/fm-tools/lib/node_modules/tasks-axi/package.json"
tasks-axi@0.2.5

$ PATH="$E2E_ROOT/fm-tools/bin:$PATH" FM_TEST_ONLY=test_first_register_succeeds_with_empty_lock_list_under_bash32 /bin/bash tests/fm-public-followup.test.sh
ok - first register succeeds with an empty lock list under /bin/bash
```

The committed workflow was also parsed as YAML and normalized. Its dependency
sequence is `actions/setup-node@v6` at `22.19.0`, then the PixelOven installer
and `GITHUB_PATH` export, then the `/bin/bash {0}` snapshot-consumer step.

The preserved merge topology was checked from Git's commit graph:

```text
cae184f12cec2e926578fb62c9bd8ed598534aae 287c3241613a6b40e96795c553ce80d321ce88d8
287c3241613a6b40e96795c553ce80d321ce88d8 4bb77b961a673f82a7fd6813fcab3365a4b9abcf
4bb77b961a673f82a7fd6813fcab3365a4b9abcf 0c1b6e3c15bd6196222e207840e0ac4054adf1ca 355f46fe5528ccc9790481171bf9da48dee2e90d
```

Thus `4bb77b9` remains the ordinary two-parent merge between the PixelOven base
and authoritative upstream, with the pin and distribution correction as normal
descendant commits.
