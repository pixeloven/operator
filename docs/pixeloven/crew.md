# `crew` on every machine

`crew` is the PixelOven agent plugin: process skills, readable role definitions, and the `infra-skills`, `planning-skills`, `identity-skills`, and `language-skills` packs.
Since crew 0.67.0 one repository, `pixeloven/crew`, holds `crew` and the four packs and serves them as the `pixeloven` marketplace, and one crew release tag pins them all.
[ADR-0019](../adr/0019-crew-machine-level-delivery.md) owns the decision; `bin/po-crew.sh --help` owns the exact commands; the agent-only `po-crew` skill owns when the agent runs them.
This page owns how `crew` reaches workers, the supervising home's fence, and how to prove both.

## How `crew` reaches workers

| Piece | Owner |
|---|---|
| The five plugins, installed at user scope for Claude Code, Codex, and pi | dotfiles, on every `chezmoi apply` |
| The pin for all five plugins, the same crew release tag on all three tools | dotfiles, which pins its `pixeloven/crew` source to one release tag, such as `v0.67.0`, and moves it only in a reviewed change |
| Moving a machine to a new tag | dotfiles' one update command, run by hand; Claude Code's marketplace auto-update stays off |
| Keeping `crew` out of the supervising agent's own session | `bin/po-crew.sh fence`, in this repository |

Workers pick up user-scope plugins on their own: the hooks file the spawn writes into a worker copy carries no plugin settings, so the home's fence never reaches a worker.
Claude Code and pi workers get the skills and the role definitions; Codex workers get the skills only, because Codex's plugin format does not carry roles.
On pi, orchestration is operator itself; no in-session `crew` dispatch and no `pi-subagents` package is used.
A plugin someone disables stays disabled, because dotfiles installs only what is missing.

## The supervising home's fence

```sh
bin/po-crew.sh fence    # primary home; a no-op when already present
```

The fence is a `false` entry for each of the five plugins under `enabledPlugins` in the home's untracked `.claude/settings.local.json`.
`fence` merges only those entries and keeps every other key, such as permission rules, and backs the file up once to the home's gitignored `state/po-crew/settings.local.json.bak` before its first change.
It refuses a malformed file and leaves it unchanged.
It skips a second mate home, whose Claude settings come from the parent's spawn rather than from this file.
Never put the fence in the tracked `.claude/settings.json`: that would turn `crew` off for every worker copy of this repository.

## Checking the install

```sh
bin/po-crew.sh check    # read-only; exit 1 when any row is `fail`
```

It prints one row for the release, one per tool and plugin, and one for the fence.
The release row names the newest crew release tag published on `pixeloven/crew`, read with `gh api`.
Each tool is checked against the crew tag it is pinned to: Claude Code's marketplace and each plugin it installed, Codex's marketplace clone, and pi's one `crew` package.
When the published tags cannot be read, the release row is a `warn`, `comparing each tool against its own marketplace clone`, and newer releases go unreported.
A tool that is not installed prints a `skip` row.

| Row says | Meaning | Fix |
|---|---|---|
| `not installed` | dotfiles has not installed that plugin for that tool yet | `chezmoi apply` |
| `installed but disabled` | someone disabled it at user scope | re-enable it, or accept the reduced set |
| `behind` | the installed commit is not the commit of the crew tag the tool is pinned to | dotfiles' plugin update command |
| `not a published crew release tag`, `not pinned to a crew release tag`, or `pinned by commit` | the tool's pin is not a published `vX.Y.Z` crew tag | dotfiles' plugin update command |
| `on the retired pixeloven/marketplace catalogue` or `its own pre-fold package` | the machine has not moved to `pixeloven/crew`, as crew 0.67.0's Consumer impact describes | dotfiles' plugin update command, which makes the switch |
| `warn`: `crew vX.Y.Z is released` | the tool is at its tag, and a newer crew release exists | none for the machine; moving to it is a reviewed dotfiles change to the tag |
| `warn`: `has a skills filter` | pi's `crew` package filters its skills, so the pack is not checked | none, or remove the filter to carry every pack |
| `warn`: `marketplace install record not readable` | Codex's marketplace clone has no install record to read the source and tag from | dotfiles' plugin update command |
| `fence ... of five disabled` | the supervising home's own session can see `crew` | `bin/po-crew.sh fence` |

`check` spends no model tokens.
Crew Doctor remains the deeper check that a model runs inside a session.

## Proving a fresh worker sees `crew`

None of these calls a model.

| Tool | Command, from a worker's copy | Pass |
|---|---|---|
| Claude Code | `claude plugin list --json`, then the session's own skill and agent listing | the five plugins enabled; `crew:` skills and role agents listed |
| Codex | `codex debug prompt-input "hi"` | `crew:` and pack skills listed with descriptions |
| pi | `printf '{"id":"1","type":"get_commands"}\n' \| pi --mode rpc --no-session --offline` | the `crew` and pack skills listed |
| The fence | `(cd <primary home> && claude plugin list --json)` | the five `@pixeloven` entries show `enabled: false` |
