# ADR-0001: Soft fork of firstmate, additive-only

- **Status:** Accepted
- **Date:** 2026-08-16
- **Deciders:** Brian Gebel (the operator), with Claude Code
- **Source:** Program plan decision **D-01**; requirements **O-1**, **O-2**

## Context

`operator` is PixelOven's interactive multi-agent execution component. Rather
than build one, we adopt [`kunchenguid/firstmate`](https://github.com/kunchenguid/firstmate)
(MIT), whose own design states that *"the cloned repo is the distro"* — there is
no package to install; instantiating the tool **is** cloning it and launching a
harness inside it. Forking is therefore the designed consumption model, not a
workaround.

Two facts constrain how we fork:

1. **Upstream has no releases.** A commit SHA is the only pin available. At the
   time of this decision upstream moves several commits per day.
2. **We will need to keep taking upstream work.** firstmate is actively
   developed and the parts we care about (harness adapters, supervision, control
   plane) are exactly the parts that change. A hard fork would strand us.

The failure mode we are designing against is the ordinary one: edits scattered
through upstream files make every subsequent merge a conflict-resolution
exercise, the merge cost rises until merges stop, and the fork silently becomes
a hard fork nobody chose.

## Decision

**`pixeloven/operator` is a soft fork of firstmate: additive-only.**

- **Upstream files are not edited.** Our surface is *new files*:
  - new runtime backends under `bin/backends/`
  - new skills under `.agents/skills/po-*`
  - our documentation under `docs/pixeloven/`
  - our decisions under `docs/adr/`
- **Upstream merges are scheduled, reviewed pull requests** — never automatic,
  never a background job (O-2).
- The upstream remote is kept as `upstream`; `origin` is `pixeloven/operator`.

### The one carve-out, stated explicitly

`README.md` is an upstream file, and GitHub renders it as the repository's front
page. We prepend a single delimited PixelOven banner block at the top of it
pointing at [`docs/pixeloven/fork-contract.md`](../pixeloven/fork-contract.md),
and change nothing else in that file. This is a deliberate, bounded exception:
one hunk, at the top, in the file least likely to carry load-bearing behavior.
Broader documentation-identity work is scheduled separately (task A1.1) and
will be re-evaluated against this ADR when it happens.

## Consequences

- Upstream merges stay cheap and reviewable: conflicts can only arise in the
  README banner hunk and in files upstream adds at paths we also chose.
- We give up the ability to *fix* upstream behavior in place. When upstream
  behavior is wrong for us, the options are: (a) a new file that overrides it
  through a documented extension point, (b) an upstream contribution, or (c) a
  new ADR that explicitly retires this constraint for a named file.
- Our namespace prefixes (`bin/backends/`, `.agents/skills/po-*`,
  `docs/pixeloven/`) become load-bearing. `po-*` in particular exists so an
  upstream skill can never collide with one of ours.
- `docs/pixeloven/upstream-tracking.md` must record the upstream distance at
  each merge point so the merge cadence is priced rather than guessed.
- Nothing is ever pushed to `kunchenguid/*` without per-instance approval
  (program plan G-5).

## Alternatives considered

- **Hard fork / rename everything.** Rejected: it discards every future upstream
  improvement in a component we did not write and do not want to own, in
  exchange for cosmetic ownership.
- **Vendor firstmate as a dependency and layer on top.** Rejected: there is no
  dependency to vendor. firstmate is not a package, a library, an MCP server, or
  a CLI — it is a repository you run inside. There is no seam to depend on.
- **Track upstream `main` automatically (auto-merge, or a scheduled bot PR that
  self-merges on green).** Rejected: upstream ships several commits a day with
  no release discipline, and this repository's own contents execute inside our
  agents with harness permission gates disabled (see
  [supply-chain-read](../pixeloven/supply-chain-read.md)). Every upstream commit
  is code we run; a human reads it (O-2).
- **Edit upstream files freely and rely on `git merge` to sort it out.**
  Rejected: this is the documented path to an accidental hard fork.
