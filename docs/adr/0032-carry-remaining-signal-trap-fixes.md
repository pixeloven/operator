# ADR-0032: Carry the remaining Bash 5.2-safe signal traps until a sync brings them

- **Status:** Accepted
- **Date:** 2026-11-12
- **Deciders:** The operator
- **Source:** ADR-0028's follow-up: the lock-handoff helper and other scripts kept plain signal traps; extends ADR-0028

## Context

ADR-0028 records how Bash 5.2 loses a signal whose trap falls due while the shell rescans a `$(...)` word, and how `fm_trap_exit` avoids that for the wake drain.
Every other plain signal trap in `bin/` kept that exposure.
The lock-handoff helper `_fm_lock_acquire_wait_handoff` in `bin/fm-wake-lib.sh` traps TERM and INT to release the lock it took and exit 143.
On Bash 5.2 that action is dropped when TERM is pending at a `$(` scan, so the helper goes on to hand the lock to its caller instead of releasing it.
Other scripts trap HUP, INT, TERM, or PIPE to exit, sometimes after a cleanup step, and keep running work their caller tried to stop in the same way.

`fm_trap_exit` lived in `bin/fm-wake-lib.sh`, which several of those scripts cannot source because it sets home state paths and creates the state directory.
Upstream `kunchenguid/firstmate` main `a9ae3c0` (2026-11-12) keeps every one of these plain traps.

Every fix lives in inherited files, and ADR-0001 otherwise prohibits editing them.

## Decision

ADR-0001 remains the default, and inherited files may carry these bounded changes:

- New `bin/fm-trap-lib.sh`: `fm_trap_exit` moves here unchanged in behavior, gains `--run <action>` to run a cleanup action before the exit, and has no source-time side effects.
- `bin/fm-wake-lib.sh`: sourcing `bin/fm-trap-lib.sh` in place of its own `fm_trap_exit` definition, and installing the lock-handoff helper's TERM and INT trap through `fm_trap_exit --run`.
- Signal traps whose action ends the shell, installed through `fm_trap_exit` with the same action and status, plus one line sourcing `bin/fm-trap-lib.sh` where the script does not already load `bin/fm-wake-lib.sh` first: `bin/fm-backlog-handoff.sh`, `bin/fm-claude-stop-autoarm.sh`, `bin/fm-codex-stop-park.sh`, `bin/fm-contributions.sh`, `bin/fm-home-summary-refresh.sh`, `bin/fm-lock.sh`, `bin/fm-mail-check.sh`, `bin/fm-osc7501.sh`, `bin/fm-pr-check.sh`, `bin/fm-pr-health.sh`, `bin/fm-remote-delta-read.sh`, `bin/fm-remote-doctor.sh`, `bin/fm-remote-entrypoint.sh`, `bin/fm-remote-home-provision.sh`, `bin/fm-remote-inherit-push.sh`, `bin/fm-remote-job-worker.sh`, `bin/fm-review-check.sh`, `bin/fm-secondmate-reconcile.sh`, `bin/fm-spawn.sh`, `bin/fm-startup-growth-check.sh`, `bin/fm-supervision-handoff.sh`, `bin/fm-supervision-host.sh`, `bin/fm-tool-update-check.sh`, `bin/fm-usage-warner.sh`, `bin/fm-wake-grant.sh`, `bin/fm-watch-arm.sh`, `bin/fm-watch.sh`, and `bin/fm-x-lib.sh`.
- `bin/fm-lint.sh`: the same trap change, sourcing `bin/fm-trap-lib.sh` only when it is beside the script, and otherwise defining a plain-trap `fm_trap_exit` so a lone copy still runs.
- `bin/fm-teardown.sh`: `fm-trap-lib.sh` in its list of sources it requires before sourcing them.
- `docs/scripts.md`: the inventory row for `bin/fm-trap-lib.sh`.
- `tests/fm-wake-queue.test.sh`: regression cases that hold TERM pending at a `$(` scan through `fm_trap_exit --run` and through the lock-handoff helper, and one that delivers TERM outside a scan through `fm_trap_exit --run`.
- Test fixtures that copy `bin/fm-wake-lib.sh` or a script above into a scratch root: `fm-trap-lib.sh` added to the copied files, in `tests/fm-afk-return.test.sh`, `tests/fm-agy-primary.test.sh`, `tests/fm-claude-stop-autoarm.test.sh`, `tests/fm-codex-hook-layer-live-e2e.test.sh`, `tests/fm-cursor-primary.test.sh`, `tests/fm-extension-binding.test.sh`, `tests/fm-gotmp.test.sh`, `tests/fm-mail-check.test.sh`, `tests/fm-on.test.sh`, `tests/fm-pi-branch-extension.test.sh`, `tests/fm-remote-backlog-handoff.test.sh`, `tests/fm-remote-entrypoint.test.sh`, `tests/fm-remote-job-claim-reap.test.sh`, `tests/fm-remote-job-launchagent.test.sh`, `tests/fm-remote-job-orphan-reap.test.sh`, `tests/fm-remote-job-process-start.test.sh`, `tests/fm-remote-transport-lanes.test.sh`, `tests/fm-session-lock-ancestry.test.sh`, `tests/fm-startup-growth-check.test.sh`, `tests/fm-turnend-guard.test.sh`, and `tests/fm-wake-queue.test.sh`.

A signal trap whose action can return instead of ending the shell stays a plain trap, because the line that closes the phantom `$(` is a syntax error when it is read.
That leaves the flag-setting and signal-forwarding traps in `bin/fm-spawn.sh`, `bin/fm-timeout-lib.sh`, and `bin/fm-watch.sh`, `worker_shutdown` in `bin/fm-remote-job-worker.sh`, and the cleanup-only HUP, INT, and TERM traps in `bin/fm-check-register.sh`, `bin/fm-pr-reviewers.sh`, `bin/fm-pr-state.sh`, and `bin/fm-record-export.sh` exposed on Bash 5.2.
The exiting traps in `bin/fm-afk-launch.sh` and `bin/fm-supervise-daemon.sh` also stay plain, because ADR-0020's theme-hook registry holds those upstream files to their registered hook lines and gate A9 rejects any other change.

The change is kept minimal so it can be offered upstream together with ADR-0028's.
When an upstream synchronization brings an equivalent change, that merge takes upstream's version of these files, the A4 allowlist drops the ones no other ADR still needs, and this ADR and ADR-0028 are superseded by that merge.

## Consequences

Every signal trap in `bin/` whose action ends the shell, including the lock-handoff helper's, apart from the two theme-registered files, now runs its action and exits on Bash 5.2 when the signal is pending at a `$(` scan, and behaves as before on Bash 3.2 and 5.3.
The traps whose action can return, and the exiting traps in the two theme-registered files, keep the Bash 5.2 exposure until Bash 5.3 or a different change removes it.
`bin/fm-trap-lib.sh` is one more file that any scratch root copying `bin/fm-wake-lib.sh` or a script above must include.
Until an upstream synchronization brings an equivalent change, every synchronization has these files as an explicit contact surface to review.

## Verification

The wake-queue tests force TERM to be pending at a `$(` scan through `fm_trap_exit --run` and through the lock-handoff helper, and require exit status 143, the action or lock release, the EXIT cleanup, and no parse error.
On Bash 5.2.21 both cases fail with the CI error and the lock left held when the plain traps are restored, and every case passes on Bash 3.2, 5.2.21, and 5.3.
The fork-contract workflow rejects any path outside the PixelOven namespaces and accepted ADR exceptions.

## Alternatives considered

- **Source `bin/fm-wake-lib.sh` wherever `fm_trap_exit` is needed.** Rejected because sourcing it sets home state paths and creates the state directory, which the lint, remote, and check scripts must not do.
- **Keep `fm_trap_exit` in `bin/fm-wake-lib.sh` and repeat it elsewhere.** Rejected because two copies of one mechanism drift.
- **Append the closing line to every trap, including ones that return.** Rejected because a returning action then reads that line and reports a syntax error on every signal.
- **Fix only the lock-handoff helper.** Rejected because the other exiting traps share the same exposure and the same fix.
- **Wait for upstream.** Rejected because upstream keeps the plain traps.
