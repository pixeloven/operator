---
name: po-theme
description: >-
  Agent-only owner of the PixelOven persona theme layer and design-system layer: switching, adding, editing, applying, verifying, and relabeling themes, and choosing or adding the design system of generated pages.
  Load before writing a Lavish page or generated HTML report; when the captain asks to change how the agents address them, name themselves, name workers, or season replies, to switch, add, or edit a theme, or to switch, add, or edit a design system (the look of generated pages); when renaming live workspaces to a changed theme's labels; after `/updatefirstmate`, an upstream merge, or any fast-forward of this repository in a home with a non-nautical theme; while preparing or fixing an upstream-merge PR, including a failing anchors or hook-registry gate; when a clear or compaction left no Persona block in context; and when `bin/po-theme.sh validate`, `verify`, `anchors`, `ds-validate`, or the session-start headline reports a finding, the Persona block looks hand-edited or stale, or the session-start digest prints a `design drift:` line.
user-invocable: false
metadata:
  internal: true
---

# po-theme

A theme changes only display words: what the supervising agent calls itself, the user, and the other roles in chat, its seasoning, its exact no-op reply, the vocabulary workers use in prose a person reads, workspace labels, and slash-command aliases.
It never renames an identifier (script, path, environment variable, skill directory, status verb, or a brief heading code parses) and never changes what a rule means; a theme grants no authority.
`docs/pixeloven/persona-themes.md` owns the theme format, validation rules, and the surfaces that deliberately stay nautical; `bin/po-theme.sh --help` owns the exact commands.

## Selection

- The selection is the first line of `config/po-theme` in the primary home; absent means `nautical`, which writes nothing and is byte-for-byte upstream behavior.
- Bundled themes live in `themes/` beside this file; a home may add its own as `config/po-themes/<name>.theme`, copied from a bundled theme and edited, since the bundled nautical theme is the key schema.

## Switch, add, or edit a theme

1. Run `bin/po-theme.sh validate <name>` and fix every error it reports before going further.
2. Write the name to `config/po-theme` in the primary home.
3. Run `bin/po-theme.sh apply` in the primary home, then `bin/po-theme.sh verify`, which must exit 0.
4. Tell the captain that the new words take effect in chat from the next session start, when the digest prints the Persona block; workers launched after `apply` get the new vocabulary line at once, and second mates pick up the changed block at the next propagation of `data/captain-shared.md`, which `secondmate-provisioning` owns.

`apply` refuses in a secondmate home: the Persona block, with a machine-readable values line, arrives there read-only through `data/captain-shared.md`, so the secondmate's own scripts resolve the same theme, including a custom one.
Never hand-edit the delimited Persona block in `data/captain-shared.md`; rerun `apply`.
Theme values are captain-owned display text: validation rejects authority words, URLs, markup, and control characters.

## Relabel live workspaces

Workspace labels follow the theme for new herdr and Paseo workspaces, while existing ones keep matching.
To rename this home's live herdr workspaces (from the primary home, each second mate's own workspace too):

1. Run `bin/po-theme.sh relabel --session <session> --dry-run`.
2. Report the planned renames to the captain.
3. Run it without `--dry-run` once the captain agrees.

## Persona lost after a clear or compaction

When a clear or compaction left no Persona block in context, read the block from `data/captain-shared.md` before the next reply and use its words; the session-start headline points to the same file.

## Verify and drift

- After `/updatefirstmate`, an upstream merge, or any fast-forward of this repository, run `bin/po-theme.sh verify`.
- On drift (a `persona drift` headline line or a nonzero `verify`), rerun `bin/po-theme.sh apply` in the primary home, then `verify` again.
- In a second mate home, a drift line saying the inherited block differs from the bundled theme means the primary home must rerun `apply` and propagate, or this home's checkout must be updated if it is the newer one; report it to the parent rather than editing the block.

## Upstream-merge PR anchors

In a PR that merges upstream firstmate, `bin/po-theme.sh anchors` must pass (gate A10) and `bin/po-theme.sh registry check-diff <upstream-ref>` must pass (gate A9). Fix each finding in that same PR:

- A missing anchor means upstream changed wording a nautical key mirrors or added a user-invocable skill: update `themes/nautical.theme` and the matching key of every other theme.
- A `surface canary` finding means upstream added a person-visible nautical string: theme it through a registered hook, or add a `residue.tsv` row whose reason opens with its rule or stage.
- A missing theme hook or replaced upstream line means the merge touched a hooked line: re-apply the one hook line and update its row in `surfaces.tsv`.

## Design systems

A design system supplies the look of generated pages, chosen independently of the theme; `docs/pixeloven/design-systems.md` owns its format, role contract, component markup, and validation.

- Before writing a Lavish page or generated HTML report, copy the design system in force with `bin/po-theme.sh ds-css > <artifact-dir>/po-ds.css`, link it at the document root with one stylesheet link in `<head>` and `class="po-page"` on `<body>`, build decisions, checklists, reviews, and status chips from its `po-` components, and write every label in the theme's words (`bin/po-theme.sh ds-labels` prints the status-chip labels).
- The selection is the first line of `config/po-design` in the primary home; absent means `firstmate`, the Firstmate Default, which writes nothing.
  To switch: run `bin/po-theme.sh ds-validate <name>`, write the name to `config/po-design`, then run `bin/po-theme.sh apply` and `bin/po-theme.sh verify` in the primary home.
- A home's own design system lives in `config/po-designs/<name>/`; it is captain-owned data that validation keeps free of URLs, at-rules, and script, and a vendored stylesheet in it stays pinned by its checksum.
- On a `design drift:` line, run `bin/po-theme.sh verify` and rerun `apply` in the primary home; never hand-edit `state/po-design/` or the `po-design` marker line in `data/captain-shared.md`.
