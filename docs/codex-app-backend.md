# Codex App backend boundary

Codex App is not a selectable Firstmate runtime backend.
Codex Desktop host tools can create and supervise visible threads and those threads can write Firstmate status files when given an authorized path, but Firstmate has no supported shell-callable bridge to those host tools.
A manual thread ledger is not a backend.

## Acceptance contract

A future Codex App backend must satisfy the same lifecycle contract as terminal-backed adapters:

1. Create a task endpoint and return a durable thread id.
2. Send the initial instructions and later operator messages to that endpoint.
3. Read enough live state or bounded transcript to supervise the task.
4. Archive, kill, or otherwise stop the exact endpoint.
5. Let the thread append Firstmate's normal lifecycle lines to `state/<id>.status`.

The status return channel is mandatory.
A visible thread that cannot report into Firstmate's normal lifecycle is not a complete backend.

## Stored-thread ownership

A standalone terminal Codex CLI and the managed iOS Remote App Server cannot both own the same stored thread writer.
While the CLI owns the writer, the thread remains discoverable and titled in iOS, but opening it produces a generic message-loading failure and an exact-thread active-writer conflict.
The terminal worker remains healthy and continues writing its transcript through that conflict.
After Firstmate stops the CLI and its ownership is released, iOS can load the stored transcript and the managed Remote App Server can become the new writer.

Interactive attachment to the same Herdr or tmux terminal endpoint is acceptable when operator discipline substitutes for input locking.
Operator discipline cannot prevent the separate-writer conflict because the Remote open and resume path attempts to acquire ownership before the operator can choose not to type.
Read-only presentation remains a useful optional guardrail, not a product requirement.

## Current blocker

Firstmate backend scripts are shell entry points and can call tmux, Herdr, Zellij, Orca, and cmux directly.
Codex Desktop host tools are available to a Desktop conversation, not to arbitrary Firstmate subprocesses.
The missing component is a Codex Desktop-supported shell-callable transport, not another local ledger.

`codex app-server --stdio` exposes useful JSON-RPC pieces such as thread start, turn start, thread read, and thread archive.
A one-process probe could create and archive a thread record, but no supported bridge was found that lets Firstmate create, continue, read, and archive the same visible Desktop-owned endpoint over its full lifetime.
A raw Desktop control-socket proxy is not a supported transport.
These partial pieces do not authorize adding `codex-app` to the known or spawn-capable backend registries.

Stored-thread read methods can support a bounded `/peep <task-id>` transcript and status snapshot without resuming the worker.
That observer capability satisfies a narrower supervision need, but it does not satisfy the complete backend acceptance contract above.

## Candidate support paths

The ownership boundary leaves these alternatives open for focused evaluation:

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

Production use of the undocumented managed-daemon socket and concurrent `thread/resume` are excluded.
Do not register a `codex-app` backend before the complete acceptance contract passes, and do not prematurely extract the stored-thread proof into a standalone AXI before its reusable ownership and protocol contract are settled.

## Required bridge

Implementation can begin after Codex Desktop exposes one supported interface:

- a CLI wrapper for create, send, read, and archive host-tool operations;
- a documented JSON-RPC or MCP transport with stable framing; or
- a maintained helper that speaks the supported transport and returns plain JSON to a shell adapter.

The bridge must provide these semantics:

```text
create: task id, worktree request, initial instructions -> thread id, cwd, state
send: thread id, text -> accepted or rejected
read: thread id, bounded cursor -> transcript and live state
archive: thread id -> archived or stopped
return: thread appends state/<id>.status lifecycle lines
```

Once available, Firstmate should add a real `bin/backends/codex-app.sh`, persist `backend=codex-app` and `codex_app_thread_id=`, and route spawn, send, peek, watch, and cleanup through the shared dispatcher.

## Rollout

Ship and scout tasks come first.
Secondmate support remains out of scope until create, send, read, status return, and archive are proven through the normal backend dispatcher.
Until then, Codex App remains a blocked backend boundary with a verified host-tool capability record, not a selectable backend.

[`verification/runtime-backends.md`](verification/runtime-backends.md#codex-app-host-tools) owns the active Desktop host-tool smoke without exposing task-specific thread ids or local paths.
