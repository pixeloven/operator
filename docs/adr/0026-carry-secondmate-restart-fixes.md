# ADR-0026: Carry the secondmate restart fixes until a sync brings them

- **Status:** Accepted
- **Date:** 2026-10-30
- **Deciders:** The operator
- **Source:** Navigator restart diagnosis report and its tmux lab reproduction

## Context

Restarting a persistent secondmate failed two ways.
During `fm-control.sh relaunch` the mate's pane holds only a shell for 20 to 30 seconds; the watcher's secondmate liveness tick read that gap as a dead mate, killed the endpoint, and then had its own spawn refused by the relaunch's spawn lock, leaving the mate with no endpoint.
`fm-secondmate-restart.sh` then reported the first stderr line, often an unrelated notice or configuration advisory, instead of the real error, and waited its full persist timeout on a mate whose endpoint was already gone.
Separately, a Claude agent moved into a Claude Code background session by `/background` treats `/exit` as a detach and keeps running outside its pane, so the exit verb could never confirm the stop.

Every fix lives in inherited files, and ADR-0001 otherwise prohibits editing them.

## Decision

ADR-0001 remains the default, and the following inherited files may carry these bounded changes:

- `bin/fm-control.sh`: holding the secondmate's per-task liveness lock across a secondmate relaunch, bounded by `FM_CONTROL_LIVENESS_WAIT`, and refusing `exit` and `relaunch` on a Claude agent that `claude agents --json` lists as a background session in the task's directory
- `bin/fm-remote-secondmate-relaunch.sh`: holding the primary's own per-task liveness lock for the whole remote relaunch, released on every exit path
- `bin/fm-secondmate-liveness-lib.sh`: `fm_secondmate_liveness_lock_wait`, and the relaunch never killing an endpoint while a spawn of that task holds its spawn lock or once the endpoint no longer reads dead
- `bin/fm-watch.sh`: logging such a deferred liveness relaunch to the triage log instead of raising it
- `bin/fm-secondmate-restart.sh`: reporting the real error line, and reporting at once, without a persist request, a local mate whose endpoint is not found or holds no running agent
- `bin/fm-spawn.sh`: `"disableAgentView": true` in every Firstmate-launched Claude agent's `--settings`
- `bin/fm-test-run.sh`: the family and timing rows for the new live end-to-end test
- `docs/agent-control.md`, `docs/configuration.md`, `docs/remote-secondmates.md`, and `docs/verification/runtime-backends.md`: the sentences and verification record describing these behaviors
- `tests/fm-control.test.sh`, `tests/fm-control-relaunch.test.sh`, `tests/fm-remote-secondmate-relaunch.test.sh`, `tests/fm-secondmate-liveness.test.sh`, `tests/fm-secondmate-restart.test.sh`, `tests/fm-wake-queue.test.sh`, and the new `tests/fm-claude-agent-view-live-e2e.test.sh`: the regression cases for these behaviors, including the lab reproduction
- `tests/fm-backend-orca.test.sh`, `tests/fm-secondmate-harness.test.sh`, and `tests/fm-spawn-dispatch-profile.test.sh`: the expected Claude launch settings carrying `disableAgentView`

The user's own Claude settings, every other verb, and every other runtime are outside this exception.

The change is kept minimal so it can be offered upstream.
That offer is drafted later; nothing is published upstream now.
When an upstream synchronization brings an equivalent change, that merge takes upstream's version of these files, the A4 allowlist drops the ones no other ADR still needs, and this ADR is superseded by that merge.

## Consequences

A secondmate restart no longer loses its endpoint to the watcher's liveness check, and a failed restart names its real cause.
A Firstmate-launched Claude agent cannot be sent to the background, and one that already runs there is refused with the recovery steps rather than left at `exit=unconfirmed`.
Until an upstream synchronization brings an equivalent change, every synchronization has these files as an explicit contact surface to review.

## Verification

The control, relaunch, liveness, restart, and wake-queue tests drive the public scripts through each failure, including the relaunch-versus-watcher race from the lab reproduction.
The fork-contract workflow rejects any path outside the PixelOven namespaces and accepted ADR exceptions.

## Alternatives considered

- **Lengthen the liveness timeout.** Rejected because any fixed timeout can still land inside the relaunch gap.
- **Set `disableAgentView` in user settings.** Rejected because that also changes the operator's own Claude sessions.
- **Stop a background session from the exit verb.** Rejected because stopping it without a persist request can lose the agent's open work.
- **Wait for upstream.** Rejected because upstream `kunchenguid/firstmate` main `355a3071` (2026-10-30) has no equivalent fix, and navigators keep dying on restart meanwhile.
- **Contribute upstream first.** Deferred: an upstream offer follows later through the firstmate-self-repo path, and this carry retires when upstream lands an equivalent.
