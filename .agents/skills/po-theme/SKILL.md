---
name: po-theme
description: >-
  Agent-only owner of the PixelOven persona theme layer (ADR-0016).
  Load when the captain asks to change how the agents address them, name themselves, name workers, or season replies, or to switch, add, or edit a theme; after `/updatefirstmate` or any upstream merge in a home with a non-nautical theme; and when `bin/po-theme.sh validate`, `verify`, or `anchors` reports a finding or the session-start Persona block looks hand-edited or stale.
user-invocable: false
metadata:
  internal: true
---

# po-theme

A theme changes only display words: what the supervising agent calls itself, the user, and the other roles in chat, its seasoning, its exact no-op reply, the vocabulary workers use in prose a person reads, and slash-command aliases.
It never renames an identifier and never changes what a rule means; ADR-0016 owns that boundary and `docs/pixeloven/persona-themes.md` owns the theme format, validation rules, and the surfaces that deliberately stay nautical.
`bin/po-theme.sh --help` owns the exact commands.

- The selection is the first line of `config/po-theme` in the primary home; absent means `nautical`, which writes nothing and is byte-for-byte upstream behavior.
- Bundled themes live in `themes/` beside this file; a home may add its own as `config/po-themes/<name>.theme`.
- To switch: run `bin/po-theme.sh validate <name>`, write the name to `config/po-theme`, then run `bin/po-theme.sh apply` in the primary home and `bin/po-theme.sh verify`.
  The new words take effect in chat from the next session start, when the digest prints the Persona block; workers launched after `apply` get the new vocabulary line at once.
- Workspace labels follow the theme for new herdr and Paseo workspaces, while existing ones keep matching; to rename this home's live herdr workspaces (from the primary home, each second mate's own workspace too), run `bin/po-theme.sh relabel --session <session> --dry-run`, report the planned renames to the captain, and run it without `--dry-run` once the captain agrees.
- `apply` refuses in a secondmate home: the Persona block, with a machine-readable values line, arrives there read-only through `data/captain-shared.md`, so the secondmate's own scripts resolve the same theme, including a custom one.
  Second mates pick up a changed block at the next propagation of that file, which `secondmate-provisioning` owns.
- After `/updatefirstmate` or an upstream merge, run `bin/po-theme.sh verify`; on drift, rerun `apply`.
- In a merge PR, `bin/po-theme.sh anchors` must pass (gate A10); a missing anchor means upstream changed wording a nautical key mirrors or added a user-invocable skill, so update `themes/nautical.theme` and the matching key of every other theme in that same PR.
  A missing theme hook or replaced upstream line means a merge touched a hooked line: re-apply the one hook line and update its row in `surfaces.tsv` in that same PR, which gate A9 then checks.
- Never hand-edit the delimited Persona block in `data/captain-shared.md`; rerun `apply`.
- Theme values are captain-owned display text: validation rejects authority words, URLs, markup, and control characters, and the block itself states that it grants no authority.
