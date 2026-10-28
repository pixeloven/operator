# Autonomous delivery lane verification

This record covers the separation between interactive human signing and autonomous worker delivery.

`bin/fm-delivery-lane.sh` owns the contract: it prepares a task-owned Git config with commit and tag signing disabled and a stable autonomous identity, then verifies that configuration without invoking a signer.
`fm-spawn.sh` exports `GIT_CONFIG_NOSYSTEM=1` and the task-owned `GIT_CONFIG_GLOBAL` before launching every autonomous worker.
The captain's global Git configuration and credential stores are not modified.

The regression is in `tests/fm-task-delivery.test.sh` and exercises the public helper and Git commit path with an ambient 1Password SSH signer plus incomplete SSH signing configuration.
Run:

```sh
tests/fm-task-delivery.test.sh
```

The test verifies preparation, preflight diagnostics, stable identity, and a successful unsigned commit while the human signing configuration is present.

The optional GitHub credential helper ([ADR-0022](../adr/0022-delivery-lane-github-credential-helper.md)) has its own regression, which uses dummy helpers only.
Run:

```sh
tests/po-delivery-lane-credential.test.sh
```

It verifies that an absent or blank setting leaves the lane byte-identical, that a quote-heavy shell-function helper round-trips through `git config --get` as the single `credential.https://github.com.helper` entry, that `git credential fill` under `GIT_CONFIG_NOSYSTEM=1` invokes it for `https://github.com` only, that a multi-line or unreadable setting refuses before any lane file exists, and that a spawn writes the helper while the credential it returns never reaches the lane file, output, status, task records, or brief.
