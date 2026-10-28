# ADR-0022: Claude workers launch with a claude.ai connector deny list

- **Status:** Proposed
- **Date:** 2026-10-27
- **Deciders:** The operator
- **Source:** Worker tooling investigation, sections 4 and 6; draft PR for review before shipping

## Context

Claude workers launch with `--dangerously-skip-permissions` unless `config/claude-permission-mode` selects `auto`, and no worker launch carries an `mcp__` deny rule.
A ship or scout worker can therefore send mail, post to chat, change calendar events, create or transition issues, and share or trash documents through the claude.ai connectors with no prompt; only prompt discipline guards against that today.
Claude Code evaluates `permissions.deny` before the permission mode, and a bare tool-name deny removes the tool from the session.

The worker launch settings are built in `bin/fm-spawn.sh`, and the entry parser they reuse lives in `bin/fm-exclude-tools-lib.sh`; both are inherited files.
ADR-0001 otherwise prohibits editing upstream files, and no existing exception covers the exclude-tools library or the tests that assert the exact worker launch.

## Decision

ADR-0001 remains the default, but the following inherited files may carry the worker connector deny list:

- `bin/fm-worker-connector-deny.list`, the new tracked list of denied write-class connector tools
- `bin/fm-exclude-tools-lib.sh`: the shared `fm_tool_list_parse` entry parser that `fm_exclude_tools_names` now calls, and `fm_worker_connector_deny_fragment`
- `bin/fm-spawn.sh`: resolving the fragment before any mutation, appending it to the ship and scout inline `--settings` JSON, and the header note naming it
- `docs/configuration.md`: the "Claude worker connector deny list" section and its index link
- `tests/lib.sh`: the `fm_test_claude_worker_settings` helper
- `tests/fm-spawn-dispatch-profile.test.sh`: the ship, scout, and secondmate launch assertions
- `tests/fm-backend-orca.test.sh`: the exact staged Claude launch, which now carries the deny fragment

Firstmate's own session, secondmates, raw launch commands, and every non-Claude runtime are outside this exception.

## Consequences

Ship and scout workers lose the listed connector write tools under both permission postures, and read tools stay available.
The list names exact tools, so a newly added or renamed connector tool stays allowed until someone classifies it.
Every upstream synchronization has these files as an explicit contact surface to review.

## Verification

The spawn dispatch-profile tests drive real ship, scout, and secondmate launches and assert the deny rules each one carries.
The fork-contract workflow rejects any path outside the PixelOven namespaces and accepted ADR exceptions.

## Alternatives considered

- **Keep relying on prompt discipline.** Rejected because nothing stops a worker that ignores its brief.
- **Put the deny rules in user settings.** Rejected because that also blocks the primary's and navigators' own sessions.
- **Deny connector tools by wildcard.** Rejected for now because it also removes every read tool; open policy questions about unclassified and mixed read-or-write tools stay with the operator.
