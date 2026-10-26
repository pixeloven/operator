# ADR-0019: `crew` reaches workers through the machine-level install that dotfiles maintains

- **Status:** Accepted
- **Date:** 2026-10-26
- **Deciders:** Brian Gebel (the operator)
- **Source:** the operator's decisions of 2026-10-26 on the crew-everywhere investigation; closes the delivery decisions D4 to D7 parked by the first-class crew recon

## Context

`crew` is the PixelOven agent plugin: process skills, readable role definitions, and four skill packs (`infra-skills`, `planning-skills`, `identity-skills`, `language-skills`).
The operator's goal is to avoid installing or managing `crew` per project or per machine, and to have it enabled, with all of its skills, as part of onboarding a machine through dotfiles.

The `pixeloven/marketplace` catalogue already pins every plugin to one reviewed commit SHA, and a catalogue change is itself a reviewed pull request.
Claude Code, Codex, and pi can all install the five plugins at user scope from that catalogue, and pi accepts the same commit SHA as its package ref, so one pin source serves all three tools.
A fresh session on each tool listed every `crew` and pack skill; Claude Code and pi also listed the role definitions, while Codex's plugin format does not carry them.

Workers already inherit user-scope plugins: `bin/fm-spawn.sh` writes only hooks into a worker copy's `.claude/settings.local.json`, so nothing at the home level reaches a worker.
The supervising agent's own session is the one place `crew` does not belong, because its role definitions and process skills overlap the supervision contract and its descriptions share the supervising session's skill-listing budget.
That fence already lived, untracked and hand-written, in the primary home's `.claude/settings.local.json`.

The first-class crew recon parked four delivery decisions until a trigger: the delivery mechanism (D4), the default selection (D5), the pin policy (D6), and crew onboarding's apply mode (D7).
It recommended an operator-pinned per-launch subset with an `fm-spawn.sh` hunk; the operator's goal of full power on every machine replaces that with a machine-level install.

## Decision

1. `crew` and the four packs reach workers through the user-scope install that dotfiles maintains on every machine, for Claude Code, Codex, and pi.
   This repository installs, pins, and updates nothing itself.
2. The pin is the commit SHA each plugin has in the `pixeloven/marketplace` catalogue, for all three tools.
   A machine moves only when a reviewed catalogue re-pin merges and someone runs dotfiles' one update command, which brings Claude Code, Codex, and pi to the catalogue pins together.
   Claude Code's marketplace auto-update stays off.
3. The supervising home is fenced: `bin/po-crew.sh fence` merges a `false` entry for each of the five plugins into the home's untracked `.claude/settings.local.json`, keeping every other key in that file.
   The fence is never tracked in `.claude/settings.json`, which would impose one home's choice on every home and turn `crew` off in every worker copy of this repository.
   A secondmate home is skipped, because its Claude settings come from the parent's spawn.
4. `bin/po-crew.sh check` is the free, read-only, scripted check of the install, the pins, and the fence.
   Crew Doctor stays the in-session check run by a model.
5. On pi, `crew` is skills plus readable role definitions.
   Orchestration on pi is operator itself: no in-session `crew` dispatch is used or fenced, `pi-subagents` is not installed or required, and `bin/fm-spawn.sh` carries no `crew` line.
6. This closes the parked decisions: D4 is the machine-level install rather than a per-launch subset; D5 is every skill and all four packs; D6 is the catalogue SHA, moved by a reviewed re-pin; D7 is unchanged, so crew onboarding's apply mode stays fenced.
7. This ADR gives `bin/po-*` and `tests/po-*` their second purpose, the `crew` delivery helper, and claims the skill directory `.agents/skills/po-crew/` and the documentation-audience entries for its pages.
   It edits no upstream file.

## Consequences

- A machine onboarded through dotfiles has `crew` for every worker on every tool with no per-project or per-home step.
- Every worker on a machine runs the same reviewed `crew` commit, and that commit changes only on a reviewed re-pin plus an explicit update, never under a running session.
- Workers on this repository also see `crew`; the worker contract still forbids delegating the task, which is the exposure already accepted for Claude workers.
- Codex workers get the skills but not the role definitions until Codex's plugin format carries them.
- A plugin someone disables stays disabled through dotfiles' install, and `check` reports it, so a deliberate disable is visible rather than silently repaired.
- A new primary home needs `bin/po-crew.sh fence` once; dotfiles may run it when the home is configured, and `check` reports a missing fence.
- Per-project pack scoping is given up; the skill-listing budget was measured with room to spare, and Crew Doctor reports description cost if that changes.

## Alternatives considered

- **An operator-pinned per-launch subset with an `fm-spawn.sh` hunk** (the parked D4 recommendation).
  It gives per-task scoping and a pin record operator owns, but it costs an upstream-file hunk and a second pin source, and it delivers a subset rather than the full set the operator asked for.
- **Installing per project or per home.**
  This is the per-project management the operator wants to avoid.
- **Claude Code marketplace auto-update.**
  Claude Code would follow each re-pin at the next session start, but Codex and pi would still need an update, so the three tools would drift apart, and instructions would change under workers that run with permission gates off without anyone acting.
- **A worker-launch dispatch fence on pi.**
  It guards a tool that is now neither installed nor required, so it would be an upstream hunk with nothing to fence.
- **Tracking the fence in `.claude/settings.json`.**
  It is an upstream file outside the fork's namespaces, and it would turn `crew` off for every worker copy of this repository as well as the supervising home.
