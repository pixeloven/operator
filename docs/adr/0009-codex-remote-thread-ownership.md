# ADR-0009: Codex Remote thread ownership and observation paths

- **Status:** Proposed
- **Date:** 2026-08-22
- **Deciders:** Brian Gebel (the operator)
- **Source:** Issue #7 and PR #8

## Context

Issue #7 and its comments record two controlled trials against Codex CLI/App Server 0.148.0 and the current iOS Remote client.
Each trial launched a fresh standalone Codex CLI thread under Herdr, pinned its exact identity, opened the discoverable thread from iOS while the CLI writer was active, checked that the terminal worker remained healthy, stopped the CLI through the normal control path, and reopened the same stored thread after ownership was released.
While the standalone CLI owned the stored thread writer, iOS discovered and titled the exact thread but opening it showed `Error loading messages.` and the managed App Server reported `already has an active writer`.
The terminal worker remained healthy and continued writing its transcript through the conflict.
After Firstmate stopped the CLI and ownership was released, iOS loaded the complete stored transcript and read-only process evidence showed the managed Remote App Server holding the exact rollout and writer-lock descriptors.
That counterfactual distinguishes the deterministic concurrent-writer conflict from worker failure, missing transcript data, connectivity loss, and stale worktree cleanup.
In the first trial, fresh-App-Server `thread/read` and `thread/turns/list` calls observed the live externally owned thread without loading or resuming it, changing its transcript or metadata, or harming its writer.
The second trial negotiated the experimental pagination capability only partially, so it does not independently reverify the bounded turns-list path and does not disconfirm the first result.
The existing Desktop host-tool smoke separately proves create, send, read, archive, and lifecycle-file return at the host-tool layer.

## Decision

A standalone terminal Codex CLI and the managed iOS Remote App Server cannot both own the same stored thread writer.
Interactive attachment to the same Herdr or tmux terminal endpoint is acceptable when operator discipline substitutes for input locking.
Discipline by the operator cannot prevent the separate-writer conflict because the Remote open and resume path attempts to acquire ownership before the operator can choose not to type.
An explicit interactive handoff must checkpoint and stop the terminal writer, verify release, and only then open the stored thread through Remote.
Stored-thread reads can support a bounded `/peep <task-id>` transcript and authoritative status snapshot without resuming the worker.
That observer capability is narrower than the complete Firstmate backend acceptance contract and must not be represented as a selectable backend.
Read-only presentation is a useful optional guardrail, not a product requirement.

## Consequences

The ownership conflict is a deterministic writer boundary rather than evidence that the terminal worker or stored transcript failed.
A bounded observer can be evaluated independently of a complete backend.
A Remote-native worker still requires a supported Firstmate bridge and the complete create, send, live-state, stop, and status-return contract.
The proposal records evidence and decision boundaries only and implements no backend, observer, handoff, socket client, transport, scheduler, or runtime behavior.

## Alternatives considered

1. Project a bounded stored-thread and authoritative task-status snapshot through Firstmate `/peep <task-id>`.
2. Attach to the same Herdr endpoint over remote SSH, with a possible upstream spectator mode as an optional guardrail.
3. Attach to the same tmux endpoint from a mobile client in read-only or interactive mode.
4. Publish bounded pane and status captures through an authenticated private-network web projection.
5. Project milestones, recent output, decisions, and links into the captain-facing Firstmate thread.
6. Checkpoint the worker, stop the terminal writer, verify release, and open the stored thread through Remote as an explicit ownership handoff.
7. Launch selected work under the Remote-native owner after a supported Firstmate bridge and status return channel exist.
8. Create disposable snapshot or fork companion threads while accepting their staleness, naming, and cleanup costs.
9. Ask OpenAI for spectator open, typed writer-conflict diagnostics, and a documented shared transport.
10. Consider contributing an optional spectator mode to Herdr upstream.

## Exclusions

- Production use of the undocumented managed-daemon socket is excluded.
- Concurrent `thread/resume` against a terminal-owned stored thread is excluded.
- Premature `codex-app` backend registration is excluded.
- Premature extraction of the stored-thread proof into a standalone AXI is excluded until its reusable ownership and protocol contract are settled.

## Open questions

1. Should `/peep` remain owned by the operator-facing integration until its contract is proven, or begin as a generic upstream Firstmate primitive?
2. Where should the exact Codex thread id and its home, rollout, checkout, and backend binding live in normal task metadata, and when can spawn record it transactionally?
3. Should checkpoint-stop-release-open become a supported handoff workflow, and what evidence proves Remote released ownership before any terminal relaunch?
4. Should the next validation start with Herdr remote attachment to the same live terminal endpoint before investing in `/peep`, handoff automation, or a shared transport?
