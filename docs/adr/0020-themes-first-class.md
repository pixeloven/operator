# ADR-0020: Themes are a first-class feature

- **Status:** Accepted
- **Date:** 2026-10-26
- **Deciders:** Brian Gebel (the operator)
- **Source:** Operator decisions of 2026-10-26 on persona completion (D1-D4 and the agreed boundary), building on the op-persona-complete-r1 and op-themes-plan-r2 investigations
- **Amends:** [ADR-0016](0016-persona-themed-at-the-edge.md).
  Decisions 1 (no upstream byte changes except the listed hunks), 4 (exactly three hunks), and 8 (gates A4, A9, A10) are replaced by this record's decisions 6-9.
  ADR-0016's selection, Persona block, aliases, validation, namespace claims, and the bundled `operator` vocabulary stand, except that role words become lowercase (decision 3).

## Context

ADR-0016 themed chat, worker prose, and slash commands, and deliberately left workspace labels, alerts, Calm, the Bearings board, and the docs nautical.
On 2026-10-26 the operator asked for themes to be a first-class feature covering nearly everything a person sees or hears, including pictures and animations.
The operator also agreed an architectural boundary that never changes.
The theme layer must stay cheap to carry against an upstream that ships about 9.5 commits a day.
It must also be shaped so it can be offered upstream as an opt-in layer once proven.

Measured cost of the hooks this record permits: replaying upstream's weekly windows over the 50 days before the pin gave 3 conflicted single-line hunks across 14 replays, never more than 1 in a week (op-themes-plan-r2 investigation).

## Decision

1. **Nautical is the default and byte-identical.**
   With no selection, or with `nautical` selected, every hook returns upstream's own literal from a compiled-in fallback without reading any theme file.
   Every person-visible output and every match behavior then equals upstream's exactly.
   The bundled `nautical.theme` mirrors those literals, and the gates prove it (decision 9).

2. **The boundary.**
   Every string, glyph, picture, or animation in the product belongs to exactly one class:
   - **Architectural (A)** - never themed. A string is architectural when any of these holds:
     - R1: it is a file, directory, script, mod, extension, or skill directory name, an environment variable or config key, or a token of a file format;
     - R2: code in this repository, or a tool it drives, reads it back to decide behavior: it parses, matches, looks up, keys, or routes on it (status verbs such as `captain-held`, backlog fields and kinds, brief headings such as `## Captain's intent`, `FIRSTMATE_OP:`, the steering doorbell line, task ids, `fm-<id>` names, outcome verdict values, board payload keys, the tmux and zellij session names, the cmux and zellij tab titles, Paseo terminal names, hometags, and the herdr agent-view `source`);
     - R3: it is a canonical command, skill, model-tool, or plugin name (themes add aliases instead);
     - R4: its primary reader is an agent: `AGENTS.md`, skills including their frontmatter descriptions, briefs and charters, operational input and wake prompts, system prompts, tool descriptions, script headers, and the output of any script the agent runs;
     - R5: it is attribution or a third-party product name (upstream's name in licenses and manifests, `crew`, `no-mistakes`).
   - **Themed (T)** - every other string, glyph, picture, or animation that reaches a person without an agent in between.
     That covers chat and voice, workspace and sidebar labels and states, notification and alert titles, supervision notes and glyphs, Calm text and animation, toasts and notices, the Bearings board and fleet views, the output of the documented human entry points, menu descriptions of mod and extension commands and of alias skills, and docs as browsed through the generated view.
   - **Dual (D)** - a themed display string that code also matches.
     It is themed only when every matcher accepts the accept-set of decision 5; otherwise it is architectural under R2.
     That is why the herdr and Paseo workspace labels are themed, while the cmux tab titles, whose title is the task's only identity after an app relaunch, are not.
   A stays canonical whenever it conflicts with T.
   The registry of decision 4 lists every T and D site and the human entry points.
   The residue list in [`persona-themes.md`](../pixeloven/persona-themes.md) names every person-visible A string with its rule number.

3. **Lowercase convention.**
   Role terms and the product word are lowercase common nouns; the validator refuses an uppercase letter in them.
   Only `user_address` is capitalized, and it is used at the start of a chat line.
   The Persona block tells the agent to capitalize a role word only where English grammar requires it, such as at the start of a sentence.

4. **Schema `po-theme/2` and the surface registry.**
   `po-theme/1` keys are unchanged, and a `po-theme/1` file stays valid: every new key is optional and has a derived default.
   New key families:
   - `label.primary`, `label.submate`, `label.afk` - workspace labels; the defaults are `lower(self)` with spaces as hyphens, `lower(submate)`, and `<label.primary>-afk-daemon`;
   - `str.<surface>.<name>` - one display string per registered site, such as `str.board.call`, `str.alert.wedge_title`, and `str.calm.command`;
     a value may use the placeholders `{user}`, `{User}`, `{self}`, `{product}`, `{submate}`, `{worker}`, and `{fleet}`, so a new theme inherits role-word strings and needs explicit values only for idiom such as "Underway";
   - `glyph.<name>` - one code point from a curated allow-list, such as `glyph.ship` and `glyph.anchor`;
   - `sprite.<name>`, `icon.<name>`, and `image.<name>` - asset references (decision 10);
   - `docs.<word>` - the drop-in replacement the docs view uses where upstream already uses a theme word with another meaning (it pairs with `avoid.<word>`).
   `nautical.theme` defines every key explicitly with upstream's literal.
   `.agents/skills/po-theme/surfaces.tsv` is the single owner of where each key is used.
   Each row gives the key, its class (T or D), the file, the hook token at the site, and whether upstream or PixelOven owns the file.

5. **Parsers during a transition.**
   A dual site creates or prints with the active theme's word and matches against an accept-set.
   The accept-set holds the canonical word, the active theme's word, and every word this home applied earlier, read from `state/po-theme/history`.
   Matching ships before any renaming, so a live container named under an older theme is never orphaned.
   `bin/po-theme.sh relabel` renames this home's own live containers to the current label.
   It touches only containers whose label is in this home's accept-set and whose id this home recorded, and never sweeps a shared namespace.
   It then retires history entries that no live container uses.
   Architectural strings never take themed values, so no parser of an architectural format changes.

6. **Mechanism.**
   - `bin/po-theme-lib.sh` (sourceable, Bash 3.2) provides `po_str`, `po_label`, `po_accept`, and `po_glyph`.
     Each returns the compiled-in nautical literal at once when the home is nautical.
   - `apply` writes the resolved, validated values to `state/po-theme/values` and copies referenced assets beside them.
     A second-mate home builds the same cache from its inherited Persona values line.
   - The Claude Code mod and the Pi extension read the same file through one PixelOven-owned module, `po-theme-values.ts`.
     It sits inside the Claude plugin folder, because Claude Code refuses a hooks-module import from outside it, and is symlinked into `.pi/extensions/lib/` the way upstream already shares its sprite module.
   - An upstream-owned file changes only by single-line hooks listed in the registry: one call that replaces a literal.

7. **Generated docs view.**
   `bin/po-theme.sh render-docs` writes a read-only themed copy to `$FM_HOME/data/po-docs/`.
   The copy covers the person-facing docs (audiences `public-product`, `operator-current`, and `operator-example` in `docs/documentation-audiences.json`), `README.md`, `VISION.md`, `AGENTS.md`, every `SKILL.md`, and the `--help` of each human entry point.
   It rewrites prose words through the role mapping, applying `docs.<word>` first, and substitutes registered pictures.
   It never changes code spans, fenced blocks, link targets other than registered pictures, identifiers, file names in text, or product names.
   No file in the view is named `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, or `SKILL.md` (they become `*.themed.md`), so no harness can load it as instructions.
   Agents never read the view.

8. **Validation.**
   Every value is validated before every use, as in ADR-0016, plus these rules:
   - `label.*` matches `^[a-z][a-z0-9-]{1,15}$`, does not start with `fm-`, and does not equal or prefix another label or a canonical label;
   - `str.*` follows ADR-0016's character and authority-word rules (at most 80 characters, placeholders only from the fixed set) and may not contain an architectural token: a status verb, `FIRSTMATE_OP`, a brief heading, an `fm-` prefix, or a payload key;
   - `glyph.*` is one code point from the allow-list;
   - every asset passes its own format validator (decision 10).

9. **Gates** (identity.md section 5; each runs on every pull request):
   - A4 admits the upstream-owned files the registry lists, in place of a hand-maintained path list for theme hooks.
   - A9 becomes registry-driven: every changed line in a registered upstream-owned file must be the registered hook, added or replacing exactly one line, and at most once.
   - A10 `anchors` also checks two things: every registered hook token is present, and every nautical value still occurs in upstream's version of its file at the pin.
     A new surface canary scans upstream's person-facing producer patterns for nautical words: notification titles, command-registration descriptions, `ui.notify`, `$.ui.toast`, `$.ui.log`, backend label functions, and board text nodes.
     It fails on any match that is neither registered nor listed as residue, so a new upstream surface becomes a reviewed theme decision.
   - New A11, architectural invariance: in a scratch home, the same fixed set of architectural outputs is generated under `nautical` and under every bundled theme, and the outputs must be byte-identical.
     The set covers brief headings, a status line, a backlog row, task ids and `fm-<id>` names, tmux and zellij session names, hometags, cmux and Paseo routing names, the herdr agent-view source, skill directories, and environment variable names.

10. **Assets.**
    - A sprite is data in a strict text format, `po-sprite/1`, and is never code.
      Its `kind` is either:
      - `glyphs`, which swaps the figure over upstream's built-in motion (3 cells on top, 5 at the base);
      - `frames`, which supplies at most 16 frames of at most 2 rows × 12 cells plus a tick between 120 and 1000 ms.
      Glyphs come from an allow-list of single-column code points (U+2500-U+259F, U+25A0-U+25FF, U+2800-U+28FF, printable ASCII).
    - An icon is a 24×24 SVG fragment limited to `path`, `circle`, `line`, `polyline`, and `rect` elements with numeric attributes, and no script, style, or link.
    - An image is a PNG or SVG file used only by the docs view.
    - The sailboat, the ⛵ and ⚓ glyphs, and the board's anchor and ship icons are the nautical theme's built-in assets.

11. **Namespaces.**
    This record extends ADR-0016's claims with `bin/po-theme-lib.sh`, `.agents/skills/po-theme/surfaces.tsv`, `.agents/skills/po-theme/assets/`, `.claude/mods/firstmate-calm/lib/po-*.ts`, `.claude/mods/firstmate-calm/tests/po-*.test.ts`, and the symlink `.pi/extensions/lib/po-theme-values.ts`.
    For an upstream offer, the `po-` prefix becomes upstream's own prefix; no other change is needed.

## Consequences

- This record is built in stages, one pull request each, starting with decision 3; until a stage lands, its surfaces stay as ADR-0016 left them, and [`persona-themes.md`](../pixeloven/persona-themes.md) lists which surfaces are themed today.
- A themed home sees its theme in chat, workspace labels, the herdr sidebar, alerts, supervision notes, Calm, the board, the fleet view, human-run command output, menus, and the docs view.
- A nautical home stays byte-for-byte upstream, and A11 proves the architectural layer identical under every theme.
- Some strings a person sees stay canonical on purpose, each with its rule: cmux and zellij tab titles and Paseo terminal names (R2), the tmux session (R2), operational input and the doorbell line (R2, R4), original skill names and descriptions beside their aliases (R3, R4), agent-run script output (R4), and plugin manifests (R5).
- The merge cost is about 30 single-line hooks, measured in the op-themes-plan-r2 investigation.
- `relabel` is a Herdr lifecycle action, so its build task needs a Herdr-lab brief.
- When upstream rewords a registered literal, A10 fails the merge PR, and `nautical.theme` is updated in the same PR.

## Alternatives considered

- **Keep ADR-0016's edge only.** This does not meet the operator's 2026-10-26 ask.
- **Theme the output of every script.** ADR-0016 measured 3-21 conflicted `bin/` files a week, for output the agent reads and already translates.
- **Theme routing names with dual matching.** cmux ids do not survive an app relaunch, so the title is the only task identity, and a mismatch loses live tasks; the operator ruled these architectural (D4).
- **Render `AGENTS.md` and skills in place.** This dirties the tree, stalls the guarded self-update, and changes the text that states every authority rule.
- **Theme assets as code (a TypeScript sprite per theme).** This puts executable theme content in an agent-loaded module and multiplies upstream-owned files; data assets keep the hook to one line per harness.

