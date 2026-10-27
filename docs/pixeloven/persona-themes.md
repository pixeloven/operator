# Persona themes

A persona theme changes the words the agents speak and the commands a person types, and [ADR-0020](../adr/0020-themes-first-class.md) extends it, stage by stage, to everything a person sees or hears.
[ADR-0016](../adr/0016-persona-themed-at-the-edge.md) owns the original edge decision and [ADR-0020](../adr/0020-themes-first-class.md) owns its amendment, the boundary rules, and the bounded upstream hooks; `bin/po-theme.sh --help` owns the exact commands; the agent-only `po-theme` skill owns when the agent runs them.
This page owns the theme format, the validation rules, the boundary between themed and architectural text, and the list of person-visible strings that stay canonical.

## What a theme changes

| Surface | How it is themed |
|---|---|
| Chat: self-name, the user's address word, role nouns, seasoning, the exact no-op reply | a Persona block in the primary home's `data/captain-shared.md`, which every session-start digest prints and every second mate inherits read-only |
| Worker prose a person reads, such as scout reports | one vocabulary line in the worker launch role contract |
| The intent-address guard for no-mistakes | also refuses the theme's vocative, so a theme never weakens it; the vocative comes from the applied Persona block, so a selection broken after `apply` does not switch the guard off |
| Slash commands | generated alias skills such as `/sitrep` for `/bearings`, hidden from `git status` through `.git/info/exclude`; primary home only |
| Herdr and Paseo workspace labels | the home workspace a person sees in the sidebar, such as `spotter` and `navigator-gfm`, and the away-mode daemon's herdr workspace; matching also accepts the nautical names and every label this home applied earlier, so a live workspace is never orphaned |

Rules, identifiers, and record formats never change: an instruction that names the captain still binds the same person with exactly the same limits.

## Selecting a theme

```sh
bin/po-theme.sh validate operator   # schema, safety, and collision checks
printf 'operator\n' > config/po-theme
bin/po-theme.sh apply               # primary home only
bin/po-theme.sh verify              # exit 1 on any drift
bin/po-theme.sh relabel --session default --dry-run   # then without --dry-run
```

The selection is the first line of the gitignored `config/po-theme`; absent, empty, or `nautical` means upstream's own voice, and `apply` then removes any block and alias it wrote earlier.
The chat words change from the next session start; workers launched after `apply` get the new vocabulary line at once.
Second mates pick up the block when `data/captain-shared.md` next propagates to them, and they resolve the theme from its values line, so a custom theme defined only in the primary home still applies there.
`apply` refuses in a second mate home, and a selection file there is ignored, because the persona is primary-authoritative.
After an update that changes a theme's words, such as the lowercase role words of ADR-0020, the primary home reruns `apply` so second mates inherit the new block; until then a second mate reads an inherited values line's role words in lowercase.
After `/updatefirstmate` or an upstream merge, run `verify` and rerun `apply` if it reports drift.

### Workspace labels

New herdr and Paseo home workspaces take the theme's label from the first spawn after `apply`, and a second mate takes it once the block reaches it.
Existing workspaces keep their names and are still found, because every matcher accepts the nautical label, the current label, and every label this home applied earlier, kept in `state/po-theme/history`.
`relabel` finishes a switch in herdr: it renames only the workspaces this home's task records name in that session, and only when their label is one of this home's own, then retires history labels no live workspace of this home still uses: that session, every other herdr session its task records name, and Paseo workspaces for its projects. If any of those cannot be listed, it keeps the whole history.
It never guesses a session, and it does not rename Paseo workspaces, which keep matching by the accept-set.

A themed home spends about 1,150 estimated tokens of the default 7,500-token startup-memory budget on the block; a nautical home spends nothing.

## Theme format

A theme is a strict TOML subset, one `key = "value"` per line with `#` comments and no tables or escapes, so it parses with `awk` under Bash 3.2 and still reads as TOML.
Bundled themes live in `.agents/skills/po-theme/themes/`; a home may add its own as `config/po-themes/<name>.theme`, which shadows a bundled theme of the same name except `nautical`.
The bundled `nautical.theme` is the schema: every theme defines exactly its keys, plus any number of `avoid.<word>` entries.
The `label.*` keys are the exception: they are optional, allowed only under schema `po-theme/2`, and derive from the role words when absent.

| Key | Meaning |
|---|---|
| `schema`, `name`, `description` | `po-theme/1` or `po-theme/2`, the file name without `.theme`, and a short description |
| `user`, `user_plural`, `user_address` | what the captain is called, and the vocative that opens a chat line, the only capitalized term |
| `self`, `self_plural`, `product` | what the first mate calls itself, and the product name |
| `worker`, `worker_plural`, `crew` | a crewmate, crewmates, and a group of them |
| `submate`, `submate_plural`, `fleet` | a second mate, second mates, and all work under way |
| `ship_task`, `scout_task` | a change task and a report task |
| `seasoning` | up to six optional flavor words, never used for bad news |
| `noop_reply`, `bad_news_example` | the exact no-op reply and an example bad-news opening, both starting with the vocative and a comma |
| `alias.<skill>` | the command a person types for each user-invocable upstream skill; the skill's own name means no alias |
| `avoid.<word>` | for a theme word upstream already uses with another meaning, the plain words to use in chat for that other meaning |
| `label.primary`, `label.submate`, `label.afk` | the primary home's workspace label, the prefix of a second mate's `<label>-<id>`, and the away-mode daemon workspace; the defaults are `self` and `submate` lowercased with spaces as hyphens, and `<label.primary>-afk-daemon` |

## Validation

`validate` and every resolution refuse a theme with:

- a missing or unknown key, or a wrong `schema` or `name`;
- a backtick, `$`, angle bracket, brace, square bracket, pipe, URL, non-printable, or non-ASCII character in any value;
- an authority word such as merge, approve, override, force, discard, delete, never, always, permission, or token in any value, except that a role title may use the noun "force";
- a role term or product name that is not 1-24 lowercase letters, spaces, or hyphens, a vocative that is not one capitalized word, or seasoning that is not 1-6 comma-separated lowercase words;
- a no-op reply or bad-news example longer than 60 characters or not opening with the vocative and a comma;
- two roles sharing a term, a role taking another role's nautical word, or a role named after a status verb, harness, or Relay;
- an alias that names no upstream skill, shadows an existing skill, or repeats;
- a label, given or derived, that is not 2-24 lowercase letters, digits, or hyphens starting and ending with a letter or digit, starts with `fm-`, makes the primary and second-mate labels equal or prefix each other or the other role's nautical label, or makes the away-daemon label equal a home label, read as a second-mate label, or prefix a home label.

`validate` also counts each role word's existing uses in the upstream text.
A user or self word that already appears with another meaning is an error until the theme declares `avoid.<word>`; any other role word is a warning.
At the current pin, the bundled theme's "operator" appears about 460 times and "deploy" 35 times with other meanings, so both carry `avoid` entries; "recon" appears only as a test variable name and stays a warning.

## Role words are lowercase

Role terms and the product name are common nouns, so a theme writes them in lowercase, such as `spotter`, `specialist`, and `task force`.
Only `user_address` is capitalized, because it opens a chat line.
The Persona block tells the agent to capitalize a role word only where a sentence starts.

## The boundary

[ADR-0020](../adr/0020-themes-first-class.md) decision 2 owns the rule: every string, glyph, picture, or animation is architectural, themed, or dual.
Architectural text never changes under any theme: file, directory, script, and skill directory names, environment variables and config keys, identifiers and parsed formats, routing keys, canonical command and skill names, text whose primary reader is an agent, and attribution or third-party product names.
Everything else a person sees or hears without an agent in between is themed.

Themed today: chat, worker prose a person reads, the intent-address guard, slash-command aliases, and the herdr and Paseo workspace labels, as listed above.
Not yet themed, and scheduled by later ADR-0020 stages: the herdr sidebar states, the wedge-alarm notification title, supervision-note glyphs, Calm text and animation, the Bearings board, the fleet view, the output of human-run commands, and the docs view.

## Residue: person-visible strings that stay canonical

Each entry names the ADR-0020 rule that keeps it canonical.

| String | Rule |
|---|---|
| Script, mod, extension, and skill directory names, such as `fm-*` scripts; `FM_*` variables; home paths such as `data/captain.md`; the `fm/` branch prefix, which is already configurable per project | R1 |
| Status verbs, backlog fields and kinds, task ids and `fm-<id>` names | R2 |
| The `## Captain's intent` and `## Firstmate spec` brief headings and the `FIRSTMATE_OP:` operational prefix | R2 |
| The tmux session name `firstmate`, the zellij session name, the cmux and zellij tab titles, and Paseo terminal names | R2 |
| Operational input, including the away-mode escalation text, and the steering doorbell line | R2, R4 |
| Original command names and skill descriptions beside their aliases, and the original command names in a second-mate home, where alias skills are not generated | R3, R4 |
| Script help, diagnostics, and other output of scripts the agent runs, which the agent translates before speaking | R4 |
| Plugin manifests and third-party product names such as `crew` and `no-mistakes` | R5 |

The agent still reads nautical text and speaks themed words, so occasional leakage is possible and is not mechanically enforced.

## Keeping themes in step with upstream

Gate A10 runs `bin/po-theme.sh anchors` and validates every bundled theme on every pull request.
`anchors` fails when upstream changes a literal the nautical theme mirrors, adds a user-invocable skill with no `alias.<skill>` key, or a merge drops one of ADR-0016's hook lines.
The fix belongs in the same merge PR: update `nautical.theme` and the matching key of every other bundled theme, which is exactly when a reviewer should notice that upstream changed its voice.
Gate A9 keeps the three hook hunks exactly as ADR-0016 lists them and holds every other upstream-owned file to the hook lines `.agents/skills/po-theme/surfaces.tsv` registers, which `anchors` also checks against upstream at the pin.
Gate A11 proves the routing names and generated brief text identical under every bundled theme.
[`identity.md`](identity.md#5-assertions--the-grep-evidence) documents the gates.
