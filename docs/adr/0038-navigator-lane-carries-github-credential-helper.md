# ADR-0038: A secondmate's delivery lane carries its launcher's GitHub credential helper

- **Status:** Proposed
- **Date:** 2026-11-18
- **Deciders:** The operator
- **Source:** `bin/fm-teardown.sh` landed-work checks failed from a navigator shell during the 2026-11-17 gfm retirement until the navigator re-ran with `GIT_CONFIG_NOSYSTEM` unset

## Context

[ADR-0008](0008-autonomous-delivery-lane.md) gives every launch from `bin/fm-spawn.sh`, secondmates included, a task-owned Git configuration as `GIT_CONFIG_GLOBAL` with `GIT_CONFIG_NOSYSTEM=1`.
On macOS, Apple Git wires the `osxkeychain` credential helper from a system-level file that `GIT_CONFIG_NOSYSTEM=1` hides, so a navigator shell has no credential helper and any HTTPS fetch of a private GitHub repository fails.
A secondmate is a persistent supervisor in its own home rather than a disposable task worker: it runs teardown landed-work checks, fleet syncs, and pull request state reads that need the same GitHub reach as the firstmate that launched it.
[ADR-0022](0022-delivery-lane-github-credential-helper.md)'s operator-configured helper does not close the gap: the main home has none configured, the file is not inherited into secondmate homes, and configuring it would also hand the helper to every ship and scout worker.
`bin/fm-delivery-lane.sh` is PixelOven's own file under ADR-0008, while `bin/fm-spawn.sh` and `docs/configuration.md` are upstream's.

## Decision

`bin/fm-delivery-lane.sh prepare` accepts `--carry-github-credential-helper`, and `bin/fm-spawn.sh` passes it for secondmate launches only.
With the flag, and when `config/delivery-lane-github-credential-helper` is absent or blank, prepare resolves the effective `credential.helper` list that the launching process's own Git configuration applies to `https://github.com`, from the generic key and the exact `credential.https://github.com.helper` key in configuration order with Git's empty-value reset.
Each surviving helper is written as a `credential.https://github.com.helper` entry in the lane, so the helpers answer for no other host.
Nothing else from the system or human configuration is carried, signing stays disabled, the autonomous identity is unchanged, and `GIT_CONFIG_NOSYSTEM=1` stays exported.
An operator-configured ADR-0022 setting still wins as the lane's single entry, a launch with nothing to carry writes a lane byte-identical to the plain one, and an unreadable host configuration stops the launch.

ADR-0001 remains the default, and the upstream files this exception touches are one spawn hunk in `bin/fm-spawn.sh` and a paragraph in ADR-0022's "Worker GitHub credential helper" section of `docs/configuration.md`.
`bin/fm-delivery-lane.sh`, `tests/po-delivery-lane-credential.test.sh`, and `docs/verification/delivery-lane.md` are PixelOven's own files.

## Consequences

A navigator can fetch, push, and run landed-work checks against private GitHub repositories with the credential its launching firstmate uses.
That credential is the operator's personal one wherever the launcher's helper reads it, which ADR-0022 deliberately avoided for task workers; ship and scout workers keep the ADR-0008 and ADR-0022 behavior unchanged.
A secondmate's own crewmates do not inherit the helper, because their lanes are prepared without the flag.
A navigator launched before this change keeps its old lane until it is relaunched.
Future upstream merges have one more `bin/fm-spawn.sh` hunk and one more `docs/configuration.md` paragraph to review.

## Alternatives considered

- **Drop `GIT_CONFIG_NOSYSTEM=1` for secondmates.** Rejected because it re-enables every system setting, including signing configuration ADR-0008 keeps away from unattended agents.
- **Configure ADR-0022's setting in the main home.** Rejected because it changes every ship and scout worker too, and the setting is not inherited into secondmate homes.
- **Inherit ADR-0022's setting into secondmate homes.** Rejected because the main home has no setting to inherit, and the operator's own Git configuration already names the helper.
- **Copy every credential setting of every host.** Rejected because the need is GitHub only, and carrying other hosts' helpers widens the navigator's reach for no reason.
- **Infer a secondmate launch inside `bin/fm-delivery-lane.sh` without a spawn hunk.** Rejected because the lane script only sees a config path, and guessing the launch kind from home records is fragile where an explicit flag is exact.
