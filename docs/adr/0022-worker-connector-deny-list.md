# ADR-0022: Claude workers honor config/crew-exclude-tools

- **Status:** Proposed
- **Date:** 2026-10-28
- **Deciders:** The operator
- **Source:** Worker tooling investigation, sections 4 and 6; operator review choosing one local list for every runtime

## Context

Claude workers launch with `--dangerously-skip-permissions` unless `config/claude-permission-mode` selects `auto`, and no worker launch carries an `mcp__` deny rule.
A ship or scout worker can therefore send mail, post to chat, change calendar events, create or transition issues, and share or trash documents through the claude.ai connectors with no prompt; only prompt discipline guards against that today.
Claude Code evaluates `permissions.deny` before the permission mode, and a bare tool-name deny removes the tool from the session.

The local, gitignored `config/crew-exclude-tools` already names tools to keep from ship and scout workers, but only Pi honors it, and every other runtime, Claude included, refuses a non-empty list.
Which tools to keep from workers depends on each operator's connectors, so the list belongs in that local file rather than tracked content.
The runtime check lives in `bin/fm-exclude-tools-lib.sh` and the Claude launch settings are built in `bin/fm-spawn.sh`; both are inherited files, and ADR-0001 otherwise prohibits editing them.

## Decision

ADR-0001 remains the default, but the following inherited files may carry Claude support for `config/crew-exclude-tools`:

- `bin/fm-exclude-tools-lib.sh`: `claude` in the supported-runtime check and its refusal text, and `fm_exclude_tools_claude_deny` with its read-name warning
- `bin/fm-spawn.sh`: building the deny fragment from the checked list for Claude ship and scout launches, appending it to their inline `--settings` JSON, and the header notes naming it
- `docs/configuration.md`: the Claude rows and "Claude workers" subsection of "Worker tool exclusions"
- `docs/examples/crew-exclude-tools`: the copyable example list of claude.ai connector write tools, with its `docs/documentation-audiences.json` entry
- `tests/fm-spawn-dispatch-profile.test.sh`: the Claude ship, scout, secondmate, warning, and example assertions, and Claude's removal from the refusal loop

Firstmate's own session, a secondmate's own agent, raw launch commands, and every other runtime are outside this exception.

## Consequences

With no local list, every launch is unchanged.
With one, Claude ship and scout workers lose the listed tools under both permission postures, the same list keeps hiding them from Pi workers, and other runtimes keep refusing it.
`config/crew-exclude-tools` stays out of the inherited configuration set, so each home, including a secondmate home, keeps its own list.
The list names exact tools, so a newly added or renamed connector tool stays available until someone adds it.
Every upstream synchronization has these files as an explicit contact surface to review.

## Verification

The spawn dispatch-profile tests drive real ship, scout, and secondmate launches and assert the deny rules each one carries.
The fork-contract workflow rejects any path outside the PixelOven namespaces and accepted ADR exceptions.

## Alternatives considered

- **Keep relying on prompt discipline.** Rejected because nothing stops a worker that ignores its brief.
- **Put the deny rules in user settings.** Rejected because that also blocks the primary's and navigators' own sessions.
- **Track the list in the repository.** Rejected on operator review because the right list depends on each operator's connectors.
- **A separate Claude-only local list.** Rejected on operator review in favor of one local list that serves every runtime.
- **Deny connector tools by wildcard.** Rejected for now because it also removes every read tool; open policy questions about unclassified and mixed read-or-write tools stay with the operator.
