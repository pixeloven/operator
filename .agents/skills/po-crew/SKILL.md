---
name: po-crew
description: >-
  Agent-only owner of PixelOven crew delivery (ADR-0019).
  Load when the captain asks whether crew or its skill packs are installed, current, or available to workers; when a worker reports crew skills or roles missing; when setting up a new primary home; and before changing this home's crew fence.
user-invocable: false
metadata:
  internal: true
---

# po-crew

`crew` and its four skill packs reach every worker through the user-scope install that dotfiles maintains for Claude Code, Codex, and pi, pinned by the `pixeloven/marketplace` catalogue.
ADR-0019 owns that decision, `docs/pixeloven/crew.md` owns the delivery model and what each check row means, and `bin/po-crew.sh --help` owns the exact commands.

- Run `bin/po-crew.sh check` for the install, the pins, and this home's fence; it is read-only and spends no tokens.
- Installing, re-installing, and updating plugins belong to dotfiles, never to this home: relay a `not installed` or `behind` row to the captain with the fix the row names.
- A new primary home runs `bin/po-crew.sh fence` once; it keeps every other key in `.claude/settings.local.json` and skips a second mate home.
- Never put the fence in the tracked `.claude/settings.json`, and never remove it to give this session `crew`.
- On pi, orchestration is this firstmate; do not set up in-session `crew` dispatch or install `pi-subagents` for workers.
