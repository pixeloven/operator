# Persona themes

A persona theme changes the words the agents speak and the commands a person types, and [ADR-0020](../adr/0020-themes-first-class.md) extends it, stage by stage, to everything a person sees or hears.
[ADR-0016](../adr/0016-persona-themed-at-the-edge.md) owns the original edge decision and [ADR-0020](../adr/0020-themes-first-class.md) owns its amendment, the boundary rules, and the bounded upstream hooks; `bin/po-theme.sh --help` owns the exact commands; the agent-only `po-theme` skill owns when the agent runs them.
This page owns the theme format, the validation rules, the boundary between themed and architectural text, and the list of person-visible strings that stay canonical.
The look of generated pages is a separate, independent choice, which [design systems](design-systems.md) owns.

## What a theme changes

| Surface | How it is themed |
|---|---|
| Chat: self-name, the user's address word, role nouns, seasoning, the exact no-op reply, and the `/bearings` digest section names | a Persona block in the primary home's `data/captain-shared.md`, which every session-start digest prints and every second mate inherits read-only, plus a two-line headline at the head of the digest |
| Worker prose a person reads, such as scout reports | one vocabulary line in the worker launch role contract |
| Supervision notes the supervision branch writes | one vocabulary paragraph in each per-wake prompt, never in the branch's system prompt, which stays byte-identical across themes |
| The intent-address guard for no-mistakes | also refuses the theme's vocative, so a theme never weakens it; the vocative comes from the applied Persona block, so a selection broken after `apply` does not switch the guard off |
| Slash commands | generated alias skills such as `/sitrep` for `/bearings`, hidden from `git status` through `.git/info/exclude`; primary home only |
| Herdr and Paseo workspace labels | the home workspace a person sees in the sidebar, such as `spotter` and `navigator-gfm`, and the away-mode daemon's herdr workspace; matching also accepts the nautical names and every label this home applied earlier, so a live workspace is never orphaned |
| Herdr desktop app space names | the same labels on the spaces the hc backend's terminals show in, while the app window is open; a name a person chose is kept |
| The Calm working animation in Claude Code and Pi | a `po-sprite/1` asset the theme names, drawn in place of the sailboat; with none, upstream's sailboat frame for frame |
| The Bearings board (`/bearings lavish`) | its title, wordmark, section names, call-answer text, and the words for the user and the agent, plus the theme's brand and Underway icons, through `bin/po-theme.sh render-board`; the template stays upstream-identical |
| The fleet view (`bin/fm-fleet-view.sh`) | its title and its Under Way and second-mate headings |
| The human inbox commands (`bin/fm-inbox.sh` note and status) | the agent's name and the idle-home line |
| The remote doctor's verdict (`bin/fm-remote-doctor.sh`) | the second-mate words of its not-ready verdict line |
| The voice relay's spoken answers | one vocabulary paragraph after the voice model's system text, so it says the theme's words aloud |
| Alias-skill menu descriptions | one sentence per alias saying what the command does in the theme's words |

Rules, identifiers, and record formats never change: an instruction that names the captain still binds the same person with exactly the same limits.

## Selecting a theme

```sh
bin/po-theme.sh validate operator   # schema, safety, and collision checks
printf 'operator\n' > config/po-theme
bin/po-theme.sh apply               # primary home only
bin/po-theme.sh verify              # exit 1 on any drift
bin/po-theme.sh relabel --session default --dry-run   # then without --dry-run
bin/po-theme.sh relabel --hc --dry-run                 # Herdr desktop app spaces, then without --dry-run
```

The selection is the first line of the gitignored `config/po-theme`; absent, empty, or `nautical` means upstream's own voice, and `apply` then removes any block and alias it wrote earlier.
The chat words change from the next session start; workers launched after `apply` get the new vocabulary line at once, and the supervision branch from its next wake.
Second mates pick up the block when `data/captain-shared.md` next propagates to them, and they resolve the theme from its values line, so a custom theme defined only in the primary home still applies there.
`apply` refuses in a second mate home, and a selection file there is ignored, because the persona is primary-authoritative.
After an update that changes a theme's words, such as the lowercase role words of ADR-0020, the primary home reruns `apply` so second mates inherit the new block; until then a second mate reads an inherited values line's role words in lowercase.
A block written by an older `apply` can lack keys a newer checkout's theme schema requires; a second mate fills each missing key from its checkout's bundled theme of the block's name (nautical for a custom theme) so the inherited theme, its workspace labels, and its headline still resolve, rather than falling back to nautical labels such as `2ndmate-<id>`.
After `/updatefirstmate` or an upstream merge, run `verify` and rerun `apply` if it reports drift.

### Headline and drift at session start

The Persona block prints near the end of the session-start digest, and a harness that spills a long digest to a file shows only its first part inline, which is how the persona was lost after a compaction.
So every digest and every re-emit after a clear or compaction also prints `headline` right below its section header: one line with the address word, the exact no-op reply, and the role words from the applied block, and one line pointing to the full block in `data/captain-shared.md`.
The `Persona: ` line in `AGENTS.md` tells the agent to read that file before its next reply whenever a clear or compaction left no Persona block in its context.
`headline` also runs `verify` and, on any drift, adds the single line `persona drift: rerun apply in the primary home`.
In a second mate home, `verify` reports an inherited block missing newer keys as `persona drift: inherited block predates this checkout's theme keys (<keys>); rerun apply in the primary home`; otherwise it compares the inherited block with the bundled theme of the same name in that home's checkout and, when they differ, such as a block written before a theme changed its words, reports `persona drift: inherited block differs from the bundled <name> theme; rerun apply in the primary home (or update this home if it is newer)`, which `headline` prints in place of the generic drift line.
A custom primary-only theme skips that comparison: either it has no bundled file, or it is a local theme in the primary home's `config/po-themes/` that shadows a bundled one of the same name, which `apply` records by ending the values line with a bare `source=local` token (the line is otherwise unchanged, and a block from a bundled theme carries no token).
Under nautical `headline` prints nothing, so a nautical digest is unchanged; only when `data/captain-shared.md` still holds a Persona block that a nautical `apply` has not yet removed does it print the drift line.

### Workspace labels

New herdr and Paseo home workspaces take the theme's label from the first spawn after `apply`, and a second mate takes it once the block reaches it, which for a new second mate is before its first workspace exists: the `--secondmate` spawn propagates `data/captain-shared.md` into the home before it ensures the home's workspace, so the workspace is created as `<label.submate>-<id>`.
Existing workspaces keep their names and are still found, because every matcher accepts the nautical label, the current label, and every label this home applied earlier, kept in `state/po-theme/history`.
`relabel` finishes a switch in herdr: it renames only the workspaces this home's task records name in that session, and only when their label is one of this home's own; a primary home's second mate record names that second mate's own workspace, which is renamed to its `navigator-<id>` label only when that second mate's own home (the `home=` its record names, else its `data/secondmates.md` entry) already accepts both its current label and the new one, as that home's own checkout resolves them, since its workers spawn from that checkout's code and the block can reach it before a theme-aware checkout does; until both have, relabel skips it and says to rerun after they propagate, and it skips a remote or unreadable home as one it cannot read locally. It then retires history labels no live workspace of this home still uses: that session, every other herdr session its task records name, and every Paseo workspace, whatever its folder. If any of those cannot be listed, it keeps the whole history.
It never guesses a session, and it does not rename Paseo workspaces, which keep matching by the accept-set.
When this home has hc records, the open Herdr desktop app's space names count as live labels too, and a closed app window keeps the whole history.

### Herdr desktop app spaces

The desktop app names a space nobody named after its first terminal's repository, so the primary and every second mate used to read alike.
After each fresh hc spawn, `bin/po-theme.sh hc-spaces <task-id>` names the space the task shows in after the launching home's label, a second mate's space after that second mate's `navigator-<id>` label, and the space the launching supervisor's own terminal shows in after the launching home's label.
`relabel --hc` does the same for every hc record of the home after a switch.
Both rename a space only while it carries the app's automatic name or one of its label's accept-set words, never one a person chose, and do nothing when no app window is open; [`hc-backend.md`](../hc-backend.md#space-names) owns the app mechanics.

### Sidebar state and alert title

With Herdr project groups on, a task waiting on the user shows the theme's `str.sidebar.needs` state in the herdr sidebar, `needs-operator` under the bundled operator theme, from the next sync after `apply`.
The away-mode wedge alarm's macOS and herdr notifications carry the theme's `str.alert.wedge_title`, `operator: away-mode escalations WEDGED` under the operator theme.
Nothing matches either string, so a switch needs no relabel.

### The Bearings board

`bin/fm-bearings-board.sh` builds the board from `bin/po-theme.sh render-board`'s output, which changes only the template lines `surfaces.tsv` registers for it: the `str.board.*` and `str.digest.*` strings replace their nautical words inside each line, so the page reads, for example, `Operator's Call`, `Sitrep - task force board`, and `ask spotter to rebuild the board` under the operator theme, and the theme's `icon.brand` and `icon.underway` pictures replace the anchor and the ship.
It reads the strings and pictures from the values cache, revalidates each icon, and prints the template byte for byte under nautical words and the Firstmate Default, or whenever the theme cannot be resolved.
The board's payload keys and its answer context (`fm-bearings-answer.v1`) never change, so an answer from a themed board closes a held call exactly as before.
A design system other than the Firstmate Default is injected after the template's styles, as [design systems](design-systems.md) describes.

### Digest section names

The `str.digest.*` strings name the four `/bearings` digest sections the agent copies into chat, and the board's sections: `Captain's Call`, `Underway`, `Recently Landed`, and `Charted Next` under nautical.
The Persona block adds one table row for each name the theme changes, such as `Captain's Call (the /bearings section)` mapped to the theme's `{User}'s Call` heading built from its user word, so a themed chat heading survives a compaction.
Because the block's identifiers rule keeps brief headings as written, a model can read `Captain's Call` as a fixed title, so when the call heading changes the block also states it outright in one sentence, in the form "The Bearings/sitrep digest heading `Captain's Call` reads `{User}'s Call`; other digest headings stay as written."
That sentence is a registered `str.digest.call` hook in `surfaces.tsv`, so `anchors` fails if it is lost.
`anchors` accepts a digest heading in the `/bearings` skill written with either a straight (U+0027) or a curly (U+2019) apostrophe.
The skill text and the board payload keys, such as `captains_call`, stay canonical.

A themed home spends about 1,320 estimated tokens of the default 7,500-token startup-memory budget on the block; a nautical home spends nothing.

## Theme format

A theme is a strict TOML subset, one `key = "value"` per line with `#` comments and no tables or escapes, so it parses with `awk` under Bash 3.2 and still reads as TOML.
Bundled themes live in `.agents/skills/po-theme/themes/`; a home may add its own as `config/po-themes/<name>.theme`, which shadows a bundled theme of the same name except `nautical`.
The bundled `nautical.theme` is the schema: every theme defines exactly its keys, plus any number of `avoid.<word>` entries.
The `label.*` and `str.*` keys are the exception: they are optional, allowed only under schema `po-theme/2`, and derive from the role words when absent.
The picture keys (`sprite.calm`, `icon.*`, `image.*`) are optional too and also need `po-theme/2`; an absent one keeps nautical's built-in picture, which is upstream's own drawing.

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
| `str.sidebar.needs`, `str.alert.wedge_title` | the herdr group state of a task waiting on the user, and the away-mode wedge-alarm notification title; the defaults are `needs-` and `user` lowercased with spaces as hyphens, and `<product>: away-mode escalations WEDGED` |
| `str.digest.call`, `str.digest.underway`, `str.digest.landed`, `str.digest.charted` | the `/bearings` digest section names; the defaults are `<user_address>'s Call`, `Underway`, `Recently Landed`, and `Charted Next` |
| `str.calm.name`, `str.calm.command`, `str.calm.pi_command`, `str.branch.model_command`, `str.watch.arm_command` | the name in Pi Calm's notice, and the menu descriptions of Claude Code's and Pi's `/calm`, Pi's `/supervision-model`, and Pi's `/fm-watch-arm-pi`; the defaults name the product, capitalized where upstream capitalizes it, and call the Calm figure the working animation |
| `glyph.ship`, `glyph.anchor` | the glyph before a routine supervision note and before an outcome for the user; one code point each from a curated allow-list, distinct, and never the other's upstream glyph; the defaults are upstream's ⛵ and ⚓ |
| `sprite.calm` | the `.sprite` asset that draws the Calm working animation in both harnesses in place of the sailboat |
| `str.board.title`, `str.board.brand`, `str.board.user`, `str.board.self` | the Bearings board's page title, its wordmark, and the words it uses for the user and the agent; the defaults are `<Alias> - <fleet> board` from the `/bearings` alias, that alias, and the `user` and `self` words |
| `str.fleet.title`, `str.fleet.underway`, `str.fleet.secondmates` | the fleet view's title and headings; the defaults are the `fleet` word title-cased plus ` View`, `Under Way`, and the `submate_plural` word title-cased |
| `str.inbox.agent`, `str.inbox.idle` | the agent's name in the inbox commands' note and status output, and the status line for a home with no workers; the defaults are the `self` word and `no <worker_plural> active` |
| `str.doctor.submate` | the words for a remote second mate in `bin/fm-remote-doctor.sh`'s not-ready verdict, `error: this host is not ready for a remote second mate`; the default is `remote <submate>` |
| `icon.brand`, `icon.underway` | the `.svg` icon assets for the Bearings board's brand mark and Underway heading |
| `image.banner`, `image.poster` | the `.png` or `.svg` picture assets for the README banner and the supervision-branch poster, validated and copied now and shown once the docs view exists |

### Pictures

A picture key names an asset file: a lowercase name of letters, digits, and hyphens with the kind's extension, at most 64 characters.
A bundled theme's assets live in `.agents/skills/po-theme/assets/`; a home's own theme looks in `config/po-themes/assets/` first.
`apply` validates every asset, and `refresh` copies each valid one into `state/po-theme/assets/` beside the values cache, which names it; the harnesses read only that copy, so a picture changes at the next session or load after `apply`.
A second mate home rebuilds its cache from its inherited values line and finds assets the same way in its own checkout, so a picture that exists only in the primary home's `config/po-themes/assets/` keeps nautical's picture there, with a warning from `refresh`.
Assets are data in strict formats, never code:

- A sprite is a `po-sprite/1` file in the theme syntax, with `schema = "po-sprite/1"` and a `kind`.
  Every cell is one terminal column under both harnesses: printable ASCII, U+2500-U+25FF (box drawing, blocks, geometric shapes), or U+2800-U+28FF (braille), at most 4096 bytes in all.
  - `kind = "glyphs"` gives `top`, exactly 3 cells, and `base`, exactly 5 cells, which replace the sail and the hull while upstream's motion, swell, freeze, and resume carry on unchanged.
  - `kind = "frames"` gives `tick_ms` (a whole number from 120 to 1000) and 1-16 frames numbered from 1 without gaps, each with a `frame.<n>.base` and an optional `frame.<n>.top` of 1-12 cells.
    The frames loop at `tick_ms` in Calm's own scheduler time (220 ms per step), the figure sits at the left edge with low water after it, and a row narrower than the widest frame shows water only.
- An icon is a 24×24 SVG fragment of self-closing `path`, `circle`, `line`, `polyline`, and `rect` elements, at most 32 of them and 8 KiB, whose attributes are path data or numbers from 0 to 24, so it can carry no script, style, or link.
- An image is a PNG of at most 1 MiB, or an SVG document of at most 256 KiB with no script, style, embedded document, entity, character reference other than the five predefined XML ones (`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`), backslash escape, event handler, animation, or reference outside itself.

An asset that is missing or fails its validator when the harness reads it draws nautical's picture instead, with a warning.

## Validation

`validate` and every resolution refuse a theme with:

- a missing or unknown key, or a wrong `schema` or `name`;
- a backtick, `$`, angle bracket, brace, square bracket, pipe, URL, non-printable, or non-ASCII character in any value other than a glyph;
- an authority word such as merge, approve, override, force, discard, delete, never, always, permission, or token in any value, except that a role title may use the noun "force";
- a role term or product name that is not 1-24 lowercase letters, spaces, or hyphens, a vocative that is not one capitalized word, or seasoning that is not 1-6 comma-separated lowercase words;
- a no-op reply or bad-news example longer than 60 characters or not opening with the vocative and a comma;
- two roles sharing a term, a role taking another role's nautical word, or a role named after a status verb, harness, or Relay;
- an alias that names no upstream skill, shadows an existing skill, or repeats;
- a label, given or derived, that is not 2-24 lowercase letters, digits, or hyphens starting and ending with a letter or digit, starts with `fm-`, makes the primary and second-mate labels equal or prefix each other or the other role's nautical label, or makes the away-daemon label equal a home label, read as a second-mate label, or prefix a home label;
- a display string, given or derived, longer than 80 characters or containing a status verb, `FIRSTMATE_OP`, a brief heading, an `fm-` token, `%`, or `&`, a sidebar state that is not label-shaped or equals another group state (`running`, `problem`, `done`), a digest or fleet-view section name that is not a heading of at most 32 letters, digits, spaces, hyphens, or apostrophes starting with a letter or digit, or repeats another section name of its surface, or a board string that is not at most 48 letters, digits, spaces, periods, hyphens, or apostrophes starting with a letter or digit, so it can close no quote, comment, or tag of the page; a menu description (a `str.*command` key) may run to 120 characters and use a status verb as an ordinary word, since no code reads it back;
- a glyph that is not one code point from the allow-list in `bin/po-theme.sh`, or note glyphs that are shared or swap upstream's;
- a picture key outside the listed set, an asset name that is not a plain file name of the key's kind, or an asset that is missing or fails its format's rules above.

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

Themed today: chat, worker prose a person reads, the words and glyphs of supervision notes, the intent-address guard, slash-command aliases and their menu descriptions, the herdr and Paseo workspace labels and the Herdr desktop app space names, the herdr sidebar state of a task waiting on the user, the wedge-alarm notification title, Calm's and the supervision commands' menu descriptions, Pi Calm's notice, the Calm working animation when the theme names a sprite, the Bearings board and its icons, the fleet view's headings, the inbox commands' note and status words, the remote doctor's not-ready verdict, and the voice relay's spoken words, as listed above.
The note glyphs change only on screen: the outcome store and the notes the agent reads keep upstream's glyphs, so Pi shows a note written before a theme was applied with the theme's glyph, while Claude Code keeps a line it already logged as it was.
The Claude Code mod and the Pi extensions read the values cache through `.claude/mods/firstmate-calm/lib/po-theme-values.ts` and pick up a theme change at their next session or load; run `bin/po-theme.sh apply` after updating so the cache carries the current keys.
The bundled `operator` theme names no pictures yet, so it keeps nautical's sailboat, board icons, and docs pictures.
Not yet themed, and scheduled by a later ADR-0020 stage: the docs view and its pictures.
In `bin/fm-remote-doctor.sh` only the not-ready verdict line is themed; the rest of its readiness output stays canonical, as the residue table below records.

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
| The rest of `bin/fm-remote-doctor.sh`'s readiness output beside its themed not-ready verdict: the `check`, `fix`, and `action` lines the agent reads, the `docs/remote-secondmates.md` path, the `Firstmate` owner of the files it installs, and the wrapper marker it reads back | R1, R4, R5 |
| The text of supervision-branch health notes delivered to the main conversation for action (their glyph is themed), and Pi Calm's stderr diagnostics | R4 |
| Plugin manifests and third-party product names such as `crew` and `no-mistakes` | R5 |

The agent still reads nautical text and speaks themed words, so occasional leakage is possible and is not mechanically enforced.

## Keeping themes in step with upstream

Gate A10 runs `bin/po-theme.sh anchors` and validates every bundled theme on every pull request.
`anchors` fails when upstream changes a literal the nautical theme mirrors, adds a user-invocable skill with no `alias.<skill>` key, adds a person-facing nautical string the surface canary below does not know, or a merge drops one of ADR-0016's hook lines.
The fix belongs in the same merge PR: update `nautical.theme` and the matching key of every other bundled theme, which is exactly when a reviewer should notice that upstream changed its voice.
Gate A9 keeps the three hook hunks exactly as ADR-0016 lists them and holds every other upstream-owned file to the hook lines `.agents/skills/po-theme/surfaces.tsv` registers, which `anchors` also checks against upstream at the pin.
A board template row registers a line that stays upstream-identical, so `anchors` catches an upstream rewording of any line `render-board` themes.
Gate A11 proves the routing names and generated brief text identical under every bundled theme.

### The surface canary

`anchors` also runs the surface canary from [ADR-0020](../adr/0020-themes-first-class.md) decision 9, so a new upstream string a person sees cannot arrive in the nautical voice unnoticed.
It scans the tracked script, module, and page sources outside `tests/` and `docs/` for upstream's person-facing producer patterns: `ui.notify`, `$.ui.toast`, and `$.ui.log` calls (every line of the call), command-registration descriptions (`registerCommand` and `$.command.register`), notification titles (`display notification`, `herdr notification show`, `terminal-notifier`, `notify-send`), and board page text (`.html` files without their styles and comments).
A line fails when it carries one of the nautical theme's words - its role terms, plurals, product, second-mate label, and seasoning, matched as whole words in any case - unless the line is a registered hook in `surfaces.tsv` or a residue row covers it.
Backend label functions are not scanned: every themed label is a registered hook, and the rest are routing names under rule R2 that gate A11 holds identical.

The canary's residue list is `.agents/skills/po-theme/residue.tsv`, beside the hook registry.
Each tab-separated row names a file, a fixed substring of the producer line (it covers every line of that file containing it), and why the line stays nautical.
The reason opens with the ADR-0020 rule that keeps the string canonical (`R1`-`R5`) or the stage that will theme it (`S1`-`S7`), then a colon, such as `S6: README banner alt text; the docs view themes it`; a row without one is a finding.
When the canary fails in a merge PR, decide in that PR: theme the string through a registered hook, or add a residue row whose reason says why it stays nautical for now.
A stage that themes a surface removes its rows, and `anchors` prints a note for any row that no longer matches a producer line so the list shrinks with the tree.
[`identity.md`](identity.md#5-assertions--the-grep-evidence) documents the gates.
