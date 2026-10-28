# ADR-0022: The delivery lane may carry an operator-configured GitHub credential helper

- **Status:** Accepted
- **Date:** 2026-10-28
- **Deciders:** The operator
- **Source:** Worker GitHub credentials from the operator's service account instead of the personal GitHub CLI login

## Context

[ADR-0008](0008-autonomous-delivery-lane.md) gives every autonomous worker a task-owned Git configuration as `GIT_CONFIG_GLOBAL` with `GIT_CONFIG_NOSYSTEM=1`.
That isolation also removes every credential helper the human configuration supplies, so a worker's plain `git fetch` or `git ls-remote` of a private GitHub repository over HTTPS fails with "could not read Username".
The operator wants workers to take GitHub credentials from a dedicated non-personal source rather than borrow the personal GitHub CLI login.
Which source, and how it stores the secret, is private to each machine and must not appear in tracked files.

`bin/fm-delivery-lane.sh` is PixelOven's own file under ADR-0008, while `docs/configuration.md` is upstream's and needs an explicit exception for a new section.

## Decision

The optional local, gitignored `config/delivery-lane-github-credential-helper` names one Git credential helper command.
When it is present and not blank, `bin/fm-delivery-lane.sh prepare` writes it through `git config` as the lane's single `credential.https://github.com.helper` entry, so Git owns the quoting of any shell-snippet helper.
An absent, empty, or whitespace-only file leaves the lane byte-identical to the ADR-0008 lane, and a multi-line or unreadable file stops the spawn.
Signing stays disabled, the autonomous identity is unchanged, and preflight is unchanged.
The helper value is a command, never a credential, and neither it nor anything it returns is printed or written outside the lane file.

Tracked code stays generic: it names no secret manager, secret location, or credential, and the tests use dummy helpers.
The setting resolves like every other config file, so `bin/fm-spawn.sh` needs no change.

ADR-0001 remains the default, and the only upstream file this exception touches is `docs/configuration.md`, which may carry the one "Worker GitHub credential helper" section placed before "Worker launch environment".
The script, `tests/po-delivery-lane-credential.test.sh`, and `docs/verification/delivery-lane.md` are PixelOven's own files.

## Consequences

Workers can clone, fetch, and push private GitHub repositories over HTTPS with whatever credential source the operator configures per machine.
The configured source answers only for `https://github.com`; other hosts keep the ADR-0008 behavior.
The file is not inherited into secondmate homes, so each home that needs it installs its own copy.
Future upstream merges have one more `docs/configuration.md` section to review.
Rotating or scoping the credential and organizing the store that holds it remain the operator's machine-level concern.

## Alternatives considered

- **Forward the personal GitHub CLI login into workers.** Rejected because it is exactly the personal credential the operator wants workers to stop borrowing.
- **Write the credential into the lane configuration.** Rejected because the lane file is inspectable during the task and a stored secret would outlive the Git call that needed it.
- **Name the secret manager in tracked code.** Rejected because the source is private per machine and the fork stays generic.
- **Pass the setting's location through a `bin/fm-spawn.sh` change.** Rejected because the standard config resolution already reaches the same directory, so no upstream script hunk is needed.
- **Hand-quote the value into the lane file.** Rejected because shell-snippet helpers carry quotes, backslashes, and command substitution that only Git's own writer is guaranteed to round-trip.
