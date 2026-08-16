# ADR-0002: Seeded with full upstream history at the pin

- **Status:** Accepted
- **Date:** 2026-08-16
- **Deciders:** Brian Gebel (the operator), with Claude Code
- **Source:** Task **A0.1** ("push as initial history or single seed commit — record which in an ADR")

## Context

Seeding a fork has two shapes:

1. **Squash-seed** — take the tree at the pin, commit it once as "initial
   commit", push. Clean, small, one author.
2. **History-seed** — push upstream's own commit graph unchanged, with our
   `main` pointing at the pin.

The choice looks cosmetic. It is not, because of what [ADR-0001](0001-soft-fork-of-firstmate.md)
commits us to: **recurring upstream merges.**

`git merge` needs a **merge base** — a commit reachable from both sides. A
squash-seed has no commit in common with `upstream/main`. Merging upstream into
it either refuses outright or, with `--allow-unrelated-histories`, treats every
one of the ~7,000 upstream files as an *add* and conflicts against our identical
copies. The soft-fork contract would be unimplementable from day one.

Attribution matters too: firstmate is MIT and the license requires the copyright
notice be preserved. A squash-seed technically satisfies that through `LICENSE`
and `NOTICE`, but it flattens ~2,400 upstream commits into one commit authored
by us, which reads as authorship we do not have.

## Decision

**Seed with full upstream history.**

Concretely, what was done:

```
git clone https://github.com/kunchenguid/firstmate.git operator
cd operator
git remote rename origin upstream
git checkout -B main 6789876442d0fb6da9f70d86399a2930c5073ae2
git remote add origin https://github.com/pixeloven/operator.git
git push origin main:main
```

- `main` in `pixeloven/operator` is exactly upstream commit
  `6789876442d0fb6da9f70d86399a2930c5073ae2` — byte-identical tree, unchanged
  history, no squash, no rewrite.
- Only `main` was pushed. Upstream's ~40 in-flight `fm/*` topic branches and its
  tags were deliberately **not** mirrored: they are upstream's working state,
  not our history, and mirroring them would make `git branch -a` unreadable.
- `upstream` remains configured as a remote so `git fetch upstream` works and
  the merge base resolves.

## Consequences

- `git merge upstream/main` works with a real merge base. The A1.4 merge
  rehearsal is a genuine rehearsal rather than a conflict-resolution stunt.
- `git log` and `git blame` attribute every upstream line to Kun Chen. MIT
  attribution is satisfied structurally, not just by a text file.
- The repository carries upstream's full history (~2,400 commits). This is a
  clone-size cost only; it is not large.
- **Our first commit is not the root commit.** Anyone auditing "what did
  PixelOven change?" must diff against the pin, not read from the beginning.
  The canonical command is recorded in
  [`docs/pixeloven/fork-contract.md`](../pixeloven/fork-contract.md):
  `git diff 6789876442d0fb6da9f70d86399a2930c5073ae2..main`
- Because history is shared, a future decision to go public must consider that
  we republish upstream's commit history. Upstream is public and MIT, so this is
  permitted; it is noted here so the go-public review (ADR-0003) does not have to
  rediscover it.

## Alternatives considered

- **Single squash "seed commit".** Rejected: breaks the merge base, which breaks
  the soft-fork contract (ADR-0001) that is the entire reason for this repo's
  shape. It also misattributes ~2,400 upstream commits.
- **GitHub's fork button.** Rejected for two independent reasons: a GitHub fork
  of a public repo cannot be made private, and it binds the repo to upstream's
  network (PRs default to targeting upstream, which risks a G-5 violation by
  accident).
- **Shallow clone (`--depth 1`) then push.** Rejected: a shallow history cannot
  serve as a merge base either, and `git push` of a shallow clone is a known
  source of corrupt remote history.
- **Mirror every upstream branch and tag.** Rejected: upstream's topic branches
  are its in-flight work. They add noise, and any of them could become an
  accidental base for our own work.
