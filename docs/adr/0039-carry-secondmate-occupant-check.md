# ADR-0039: Carry the secondmate endpoint occupant check until a sync brings it

- **Status:** Accepted
- **Date:** 2026-11-20
- **Deciders:** The operator
- **Source:** A navigator's recorded Herdr pane read alive at session start while it hosted the primary session; self-retiring local carry

## Context

A secondmate's recorded endpoint can outlive the agent that was launched into it, and a different agent session can then occupy the same pane.
On 2026-11-20, after an accidental session kill, the session-start digest reported a navigator as `endpoint: alive` while its recorded Herdr pane hosted the primary session, whose working directory was the main home rather than the navigator's home.
Both the session-start digest and the secondmate liveness probe judged liveness from pane presence alone, so neither noticed, and neither offered a recovery.

Upstream `kunchenguid/firstmate` main `427056c` (2026-11-12) has the same presence-only reads.
`bin/fm-backend.sh`, `bin/fm-secondmate-liveness-lib.sh`, `bin/fm-session-start.sh`, and their tests are inherited files, and ADR-0001 otherwise prohibits editing them.
`bin/fm-session-start.sh` also carries an ADR-0020 theme hook, so gate A9 holds every line it changes to a hook registry row.

## Decision

ADR-0001 remains the default, and the following inherited files may carry these bounded changes:

- `bin/fm-backend.sh`: the read-only `fm_backend_endpoint_occupant_cwd` and `fm_backend_endpoint_occupant_verdict`, which read the occupant's working directory from Herdr's live `foreground_cwd` or tmux's `pane_current_path` and print `match`, `mismatch` with that directory, or `unknown`.
- `bin/fm-secondmate-liveness-lib.sh`: a local `alive` reading checked against that verdict, where `mismatch` is a non-relaunchable result and an unreadable occupant keeps `alive` with a presence-only note, plus the header lines that state it.
- `bin/fm-session-start.sh`: the bounded occupant read for a present local secondmate endpoint, the `endpoint: mismatch` and presence-only `endpoint: alive` digest lines, and the header lines that state them.
  These lines are registered as `lib` plumbing rows in `.agents/skills/po-theme/surfaces.tsv`, so A9 still holds the file to its pin diff.
- `tests/fm-secondmate-liveness.test.sh` and `tests/fm-session-start.test.sh`: regression cases for a matching, foreign, and unreadable occupant.

Ordinary ship and scout endpoints, remote secondmate routes, and every recovery action are outside this exception.
A mismatch is reported and never relaunched or repaired automatically, because the occupant is a live agent that belongs to someone else.
The change is kept minimal so it can be offered upstream through the normal contribution path; this exception does not publish it.
This carry retires itself: when an upstream synchronization brings an equivalent change, that merge takes upstream's version of these files, the registry drops the `lib` rows for `bin/fm-session-start.sh`, the A4 allowlist drops the paths no other ADR still needs, and this ADR is superseded by that merge.

## Consequences

A secondmate endpoint that a foreign agent occupies now reads as a mismatch at session start and during supervision instead of alive, which surfaces it for a decision rather than hiding it.
An occupant whose directory cannot be read keeps the old alive verdict and says it is presence only, so no endpoint reads worse than before on missing evidence.
The check is a directory comparison, so a foreign agent started inside the secondmate's own home still reads alive.
Until an upstream synchronization brings an equivalent change, every synchronization has these files and the registry rows as an explicit contact surface to review.

## Verification

`tests/fm-secondmate-liveness.test.sh` and `tests/fm-session-start.test.sh` drive a recorded Herdr endpoint through a fake `herdr` whose occupant runs in the home, inside it, outside it, and with an unreadable directory, and require `alive`, `alive`, `mismatch`, and the presence-only `alive` respectively; the session-start case also requires an ordinary ship endpoint to read alive unchanged.
`bin/po-theme.sh registry check-diff` passes with the `lib` rows and fails without them.
The fork-contract workflow rejects any path outside the PixelOven namespaces and accepted ADR exceptions.

## Alternatives considered

- **Compare the occupant's agent session id with the recorded one.** Rejected because not every harness records a session id the backend can read back, while every supported pane backend reports a working directory.
- **Relaunch the secondmate when its pane is occupied by someone else.** Rejected because that would kill or displace a live agent that does not belong to the secondmate.
- **Move the session-start read into a PixelOven-owned script.** Rejected because the digest loop that prints the verdict is inherited, so a hook line would still be needed there, and a second owner of the endpoint read would drift.
- **Wait for upstream.** Rejected because upstream keeps the presence-only reads, and a misread secondmate blocks recovery now.
