# Persona themes

A persona theme changes the words the agents speak and the commands a person types, without changing a single upstream byte.
[ADR-0016](../adr/0016-persona-themed-at-the-edge.md) owns the decision and its bounded upstream hunks; `bin/po-theme.sh --help` owns the exact commands; the agent-only `po-theme` skill owns when the agent runs them.
This page owns the theme format, the validation rules, and the list of surfaces that deliberately stay nautical.

## What a theme changes

| Surface | How it is themed |
|---|---|
| Chat: self-name, the user's address word, role nouns, seasoning, the exact no-op reply | a Persona block in the primary home's `data/captain-shared.md`, which every session-start digest prints and every second mate inherits read-only |
| Worker prose a person reads, such as scout reports | one vocabulary line in the worker launch role contract |
| The intent-address guard for no-mistakes | also refuses the theme's vocative, so a theme never weakens it; the vocative comes from the applied Persona block, so a selection broken after `apply` does not switch the guard off |
| Slash commands | generated alias skills such as `/sitrep` for `/bearings`, hidden from `git status` through `.git/info/exclude`; primary home only |

Rules, identifiers, and record formats never change: an instruction that names the captain still binds the same person with exactly the same limits.

## Selecting a theme

```sh
bin/po-theme.sh validate operator   # schema, safety, and collision checks
printf 'operator\n' > config/po-theme
bin/po-theme.sh apply               # primary home only
bin/po-theme.sh verify              # exit 1 on any drift
```

The selection is the first line of the gitignored `config/po-theme`; absent, empty, or `nautical` means upstream's own voice, and `apply` then removes any block and alias it wrote earlier.
The chat words change from the next session start; workers launched after `apply` get the new vocabulary line at once.
Second mates pick up the block when `data/captain-shared.md` next propagates to them, and they resolve the theme from its values line, so a custom theme defined only in the primary home still applies there.
`apply` refuses in a second mate home, and a selection file there is ignored, because the persona is primary-authoritative.
After `/updatefirstmate` or an upstream merge, run `verify` and rerun `apply` if it reports drift.

A themed home spends about 1,150 estimated tokens of the default 7,500-token startup-memory budget on the block; a nautical home spends nothing.

## Theme format

A theme is a strict TOML subset, one `key = "value"` per line with `#` comments and no tables or escapes, so it parses with `awk` under Bash 3.2 and still reads as TOML.
Bundled themes live in `.agents/skills/po-theme/themes/`; a home may add its own as `config/po-themes/<name>.theme`, which shadows a bundled theme of the same name except `nautical`.
The bundled `nautical.theme` is the schema: every theme defines exactly its keys, plus any number of `avoid.<word>` entries.

| Key | Meaning |
|---|---|
| `schema`, `name`, `description` | `po-theme/1`, the file name without `.theme`, and a short description |
| `user`, `user_plural`, `user_address` | what the captain is called, and the vocative that opens a chat line |
| `self`, `self_plural`, `product` | what the first mate calls itself, and the product name |
| `worker`, `worker_plural`, `crew` | a crewmate, crewmates, and a group of them |
| `submate`, `submate_plural`, `fleet` | a second mate, second mates, and all work under way |
| `ship_task`, `scout_task` | a change task and a report task |
| `seasoning` | up to six optional flavor words, never used for bad news |
| `noop_reply`, `bad_news_example` | the exact no-op reply and an example bad-news opening, both starting with the vocative and a comma |
| `alias.<skill>` | the command a person types for each user-invocable upstream skill; the skill's own name means no alias |
| `avoid.<word>` | for a theme word upstream already uses with another meaning, the plain words to use in chat for that other meaning |

## Validation

`validate` and every resolution refuse a theme with:

- a missing or unknown key, or a wrong `schema` or `name`;
- a backtick, `$`, angle bracket, brace, square bracket, pipe, URL, non-printable, or non-ASCII character in any value;
- an authority word such as merge, approve, override, force, discard, delete, never, always, permission, or token in any value, except that a role title may use the noun "force";
- a role term that is not 1-24 letters, spaces, or hyphens, a vocative that is not one capitalized word, or seasoning that is not 1-6 comma-separated lowercase words;
- a no-op reply or bad-news example longer than 60 characters or not opening with the vocative and a comma;
- two roles sharing a term, a role taking another role's nautical word, or a role named after a status verb, harness, or Relay;
- an alias that names no upstream skill, shadows an existing skill, or repeats.

`validate` also counts each role word's existing uses in the upstream text.
A user or self word that already appears with another meaning is an error until the theme declares `avoid.<word>`; any other role word is a warning.
At the current pin, the bundled theme's "operator" appears about 460 times and "deploy" 35 times with other meanings, so both carry `avoid` entries; "recon" appears only as a test variable name and stays a warning.

## What stays nautical, deliberately

This scope is the captain's decision of 2026-10-21: the theme covers the edge a person reads, while identifiers, script names, and upstream text stay canonical.

- Every identifier: `fm-*` scripts, `FM_*` variables, home paths such as `data/captain.md`, skill directory names, status verbs, and the `fm/` branch prefix, which is already configurable per project.
- Parsed tokens workers see: the `## Captain's intent` and `## Firstmate spec` brief headings and the `FIRSTMATE_OP:` operational prefix.
- The tmux session name `firstmate`, which other homes and tooling look up by name.
- The Calm sailing-boat animation and its log lines; theming them was declined.
- The wedge-alarm notification title; theming it was declined.
- The Bearings board labels, until the scheduled Phase-3 follow-up task themes them.
- Upstream documentation as browsed on GitHub, until the scheduled Phase-3 follow-up task adds a themed docs view.
- The original command names in a second-mate home: alias skills are generated only in the primary home's code root, and the Persona block says so.
- Script help and diagnostics, which the agent reads and translates before speaking.

The agent still reads nautical text and speaks themed words, so occasional leakage is possible and is not mechanically enforced.

## Keeping themes in step with upstream

Gate A10 runs `bin/po-theme.sh anchors` and validates every bundled theme on every pull request.
`anchors` fails when upstream changes a literal the nautical theme mirrors, adds a user-invocable skill with no `alias.<skill>` key, or a merge drops one of ADR-0016's hook lines.
The fix belongs in the same merge PR: update `nautical.theme` and the matching key of every other bundled theme, which is exactly when a reviewer should notice that upstream changed its voice.
Gate A9 keeps the three hook hunks exactly as ADR-0016 lists them; [`identity.md`](identity.md#5-assertions--the-grep-evidence) documents both gates.
