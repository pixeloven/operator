# ADR-0005: Agent self-improvement is PR-gated

- **Status:** Accepted
- **Date:** 2026-08-16
- **Deciders:** Brian Gebel (the operator), with Claude Code
- **Source:** Program plan decision **D-05**; requirement **O-4**

## Context

`operator` dispatches agents that write code. It is itself code. The obvious and
attractive move is to point it at its own repository: overnight autonomous loops
improving the tool that runs the loops.

That is a genuine capability, and it is also the sharpest edge in this program.
Two properties make it sharper here than in an ordinary repository:

1. **This repository's contents execute in our agents' context.** Session-start
   hooks, pre-tool-use gates, turn-end guards, and launch templates in this repo
   run on every agent turn on the workstation. A bad change here is not a broken
   feature; it is a compromised execution surface.
2. **Every worker launches with its harness's permission gate disabled.** The
   supply-chain read ([supply-chain-read.md](../pixeloven/supply-chain-read.md))
   established that the launch templates pass `--dangerously-skip-permissions`,
   `--dangerously-bypass-approvals-and-sandbox`, `--always-approve`, `--yolo`,
   and equivalents by design. The safety boundary is the disposable worktree and
   the delivery mode — **not** the harness. Self-modification is precisely the
   case where "it's isolated in a worktree" stops being reassuring, because the
   change's destination is the thing doing the isolating.

The failure mode is not dramatic sabotage. It is an agent making a locally
reasonable change to a guard, gate, or hook that quietly widens authority, and
that change landing because it was the agent's own repository and nobody looked.

## Decision

**`operator` registers its own repository in its own project registry with
delivery posture `no-mistakes`.**

- Every agent-authored change to this repository — interactive dispatch,
  overnight autonomous loops, anything — arrives as a **pull request** and runs
  the full validation pipeline.
- **Humans merge.** There is no autonomous merge path to `main`, and no
  `+yolo` autonomy flag on this project, regardless of how small the change is.
- The posture is a property of the *project registration*, not of the task. A
  task cannot opt out by asking for a lighter mode; `fm-spawn` refuses a mode
  that carries less rigor than the registered posture without a loud deviation
  notice, and for this repository there is no acceptable lighter mode.
- This holds while the repository is private (ADR-0003). Privacy is not a
  substitute for review.

## Consequences

- Self-improvement stays available — the loop still runs, still proposes, still
  does the work — but its output is a proposal, not a fact. The capability is
  kept; the authority is not granted.
- Throughput on this repository is bounded by human review, deliberately. That
  is the cost being paid and it is the right one for a repository whose files
  run inside every agent turn.
- The registration is only real if it is verified. Task A1.3's acceptance is a
  *test agent PR that actually routes through the pipeline* — not a
  configuration file asserting that it would.
- Reviewers of PRs against this repository need a standing focus: changes to
  hooks, guards, gates, launch templates, and anything under `bin/` that
  touches authority are the high-risk class, and a change that widens authority
  should be treated as suspect until it argues otherwise.
- CI gates and the release workflow (A1.2) are a prerequisite for this posture
  to mean anything. A pipeline with no gates is a PR with extra steps.

## Alternatives considered

- **Direct-PR posture with auto-merge on green.** Rejected: the gates are
  deterministic checks, not a judgement about whether an authority boundary
  should move. Green CI cannot tell you that widening a pre-tool-use guard was
  the wrong call.
- **`local-only` for small changes, `no-mistakes` for "risky" ones.** Rejected:
  it requires the agent proposing the change to correctly classify its own
  blast radius. That is exactly the judgement we do not want to delegate here,
  and "small" changes to guard logic are the archetypal quiet failure.
- **Ban self-modification entirely.** Rejected: overcorrects. The loop's
  proposals are useful, and forbidding them buys nothing that human-merge does
  not already buy.
- **Rely on the harness sandbox as the backstop.** Not available — see Context.
  The harness gates are deliberately disabled at launch, so there is no sandbox
  to fall back on. This alternative is listed because it is the assumption a
  reader is most likely to arrive with.
