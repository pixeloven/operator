# Supply-chain read — operator's execution surface

- **Tasks:** A0.2 (firstmate execution surface) · A0.3 (gnhf, lavish-axi, herdr)
- **Date:** 2026-08-16
- **Reader:** Claude Code, for the operator
- **Subject:** `kunchenguid/firstmate` @ `6789876442d0fb6da9f70d86399a2930c5073ae2`
- **Status:** this document **gates Phase 1** (tasks P1.1–P1.5). Nothing installs
  on the workstation before it is read and accepted.

---

## Verdict

> ## **PASS — with three mandatory conditions.**

The firstmate execution surface at the pin is **clean**: it does not phone home,
does not fetch or execute remote code at runtime, does not write outside the
user's own home, and contains no telemetry, analytics, or credential-exfiltration
path. Code quality and defensive discipline are high — checksum-pinned installers,
fail-closed locking, explicit refusal over guessing.

The findings that matter are not defects in firstmate. They are **properties of
the model** it implements, and **two of its adjacent npm tools**:

| # | Condition | Blocks |
|---|---|---|
| **C1** | Understand and accept that **every worker launches with its harness's permission gate disabled**. The isolation boundary is the git worktree plus the delivery mode — *not* the harness sandbox. See [F-1](#f-1). | P1.2 — must be an explicit, recorded acceptance, not a discovery later |
| **C2** | **`gnhf` and `lavish-axi` phone home by default.** Both ship an analytics client, enabled unless opted out. The workstation role must set `GNHF_TELEMETRY=0` and `LAVISH_AXI_TELEMETRY=0`. See [F-8](#f-8). | P1.2 |
| **C3** | **The Relay must stay off.** firstmate's optional Relay posts to a third-party service; it activates only when a pairing token exists in `$FM_HOME/.env`. Do not create one, and assert its absence. See [F-2](#f-2). | P1.2, P1.5 |

Two lower-severity items need an owner but block nothing:
**F-9** (herdr license discrepancy) and **F-10** (herdr version drift: the plan
pins v0.8.0, firstmate's installer pins 0.7.4).

---

## 1. Scope and method

### Read in full

| Surface | Files |
|---|---|
| Dispatch | `bin/fm-spawn.sh` (2,852 lines) |
| Control plane | `bin/fm-control-lib.sh` |
| Backend abstraction | `bin/fm-backend.sh` |
| Reference backend | `bin/backends/tmux.sh` |
| Bootstrap | `bin/fm-bootstrap.sh` |
| Pi extensions | `.pi/extensions/*.ts` + `.pi/extensions/lib/*.ts` (7 files) |
| Harness hooks | `.claude/settings.json`, `.codex/hooks.json`, `.cursor/hooks.json`, `.grok/hooks/*.json` (4), `.opencode/plugins/*.js` (5) + `lib/` |
| Repo config | `.gitignore`, `.no-mistakes.yaml`, `.tasks.toml`, `LICENSE` |

### Swept across the whole `bin/` tree (159 scripts)

Outbound network (`curl`/`wget`/`fetch`/sockets/hostnames); dynamic execution
(`eval`, `exec`, sourcing, `base64 -d`); writes outside `$FM_HOME`
(`$HOME`, `/etc`, `/usr`, `sudo`, `launchctl`, `systemctl`, `crontab`); and
telemetry vocabulary (`telemetry`, `analytics`, `sentry`, `posthog`, `umami`,
`mixpanel`, `segment`).

### The three questions asked

1. Does it **phone home**?
2. Does it **write outside its own home**?
3. Does it **curl-pipe remote code**?

---

## 2. Findings — firstmate (A0.2)

### F-1 · Every worker launches with its harness permission gate disabled — **BY DESIGN, HIGH IMPACT**

`launch_template()` in `bin/fm-spawn.sh` is the single most important thing in
this read. Each verified adapter is launched with its own approval/sandbox
mechanism turned off:

| Adapter | Flag |
|---|---|
| claude | `--dangerously-skip-permissions` |
| codex | `--dangerously-bypass-approvals-and-sandbox` |
| opencode | `OPENCODE_CONFIG_CONTENT='{"permission":{"*":"allow"}}'` |
| grok | `--always-approve` |
| cursor | `--trust --yolo` |
| kimi | `--auto` |
| muse | `--yolo` (also disables muse's filesystem **and network** sandbox) |

This is deliberate and documented — an unattended worker cannot answer an
approval prompt. But it relocates the safety boundary, and the relocation must
be understood rather than discovered:

**The boundary is the disposable git worktree + the delivery mode
(`no-mistakes` / `direct-PR` / `local-only`) + the pre-tool-use seatbelts. There
is no harness sandbox underneath it.**

A worker can write anywhere the invoking user can write. The worktree is an
*organisational* isolation, not a kernel one.

Mitigations actually present in the code, and they are real:

- Ship/scout spawns **refuse** unless the task path is a real git worktree root
  distinct from the primary checkout.
- A fresh worker's worktree fetches origin and resets to the remote default
  branch tip; an unreachable origin or unclean tree **refuses the spawn** rather
  than risking a PR on stale history.
- The delivery contract (`--mode`, `--yolo`) is required per ship spawn and
  validated against the brief on disk; a mismatch is refused. A mode carrying
  less rigor than the project's registered posture prints a loud deviation
  notice.
- A no-mistakes gate agent is fail-closed refused from spawning direct reports
  at all (`fm_refuse_if_gate_agent`).
- PreToolUse seatbelts (`fm-arm-pretool-check.sh`, `fm-cd-pretool-check.sh`) can
  block a bash command; the Pi extension verifiably blocks on `{block: true}`.

**Recommendation.** Accept explicitly (condition C1). Where the blast radius of
"anything this user can write" is unacceptable, run workers in a Coder workspace
rather than on the workstation. This is a posture decision for the operator, not
a code fix.

> Positive signal in the same function: firstmate sets
> `MUSE_EXPERIMENTAL_FOREIGN_PERSONAL_CONTEXT_KILL=on` **specifically to stop
> muse loading the operator's personal `~/.claude` rules and shipping them to
> vendor-hosted inference.** That is upstream choosing privacy on the user's
> behalf, at the cost of extra complexity. It materially raises confidence in the
> author's posture.

### F-2 · The Relay is the only outbound path, and it is opt-in — **CONDITION C3**

`bin/fm-x-lib.sh` implements "Relay": answering public mentions on X and Discord.

- Default endpoint: `https://myfirstmate.io` (overridable via `FMX_RELAY_URL`).
- Requests: `POST {relay}/connector/<endpoint>`, 10s timeout, bearer auth from a
  header file that is `mktemp`-created and `trap`-deleted on every exit path
  including `HUP INT TERM` — the token is never placed on a command line where
  `ps` could read it. **Good hygiene.**
- **Activation is gated on `FMX_PAIRING_TOKEN` existing in `$FM_HOME/.env`.**
  With no token: `fm-bootstrap.sh` actively *removes* the relay poll shim and the
  30s watcher cadence, and the poll never runs. A `FMX_DRY_RUN` preview mode
  records would-be posts locally instead of sending.

**With no pairing token, firstmate makes no outbound network requests at all.**

**Recommendation.** Do not create `$FM_HOME/.env`. P1.5's secrets-discipline
review should assert its absence by status (`test ! -f`), never by printing it
(G-3).

### F-3 · Bootstrap prints `curl | sh` strings — it never executes them — **NOT A FINDING**

`install_cmd()` in `bin/fm-bootstrap.sh` contains:

```
treehouse)    echo "curl -fsSL https://kunchenguid.github.io/treehouse/install.sh | sh"
no-mistakes)  echo "curl -fsSL https://raw.githubusercontent.com/.../install.sh | sh"
```

These are **`echo`** — human-readable install hints emitted in a `MISSING: <tool>`
diagnostic. Bootstrap performs no download and no execution. Verified by reading
every call path into `install_cmd`.

Noted anyway because it is exactly the string an automated scanner flags, and
because *a human who follows the hint* is curl-piping unpinned remote code. If
these tools are ever installed on the workstation, install them the way
firstmate's own CI does — see F-4 — not the way the hint says.

### F-4 · Third-party binary installers are checksum-pinned — **EXEMPLARY**

`bin/fm-install-herdr.sh`, `fm-install-treehouse.sh`, `fm-install-shellcheck.sh`
each: pin an exact version → select the official GitHub Releases asset by
OS/arch → `curl -fsSL --max-filesize <bound>` → **verify an in-repo SHA-256**
→ install → **re-verify** the installed binary reports the exact pinned version
(herdr additionally gates on a minimum wire-protocol number). Any mismatch is a
hard `die`.

This is better than most production supply chains and is the pattern our own
Phase 1 installers should copy verbatim.

### F-5 · Writes outside `$FM_HOME` — bounded, documented, all inside `$HOME`

| Path | Purpose | Read/Write |
|---|---|---|
| `${GROK_HOME:-$HOME/.grok}/hooks/` | grok has no project-scoped hook; firstmate installs a global hook + per-token auth dir | write |
| `$HOME/.kimi-code/config.toml`, `$HOME/.kimi-code/fm-turn-end.d/` | same problem, same shape; one delimited "Firstmate region" in the toml | write |
| `${XDG_STATE_HOME:-$HOME/.local/state}/firstmate/procevent-claims` | cross-home process-event claim files | write |
| `$HOME/.cursor/projects/` | reading cursor's own conversation transcripts for turn-end detection | read |
| `${XDG_DATA_HOME:-$HOME/.local/share}/muse/sessions` | reading muse's session event log (muse ships no hook engine) | read |
| `$HOME/Library/LaunchAgents`, `$HOME/Library/Logs` + `launchctl bootstrap` | macOS LaunchAgent for the **remote secondmate** job worker only | write |

**No writes to `/etc`, `/usr`, or any system path. Zero occurrences of `sudo` in
the entire `bin/` tree. No `crontab`, no `systemctl`.** The `launchctl` path is
user-scoped (`gui/$uid`) and only on the remote-secondmate feature, which we do
not use in Phase 1.

Each write is a documented consequence of a harness that offers no
project-scoped hook. Acceptable; worth knowing before debugging "why does my
`~/.grok` have files in it".

### F-6 · Harness hooks invoke repo-local scripts only — **CLEAN**

All 12 hook definitions across `.claude/`, `.codex/`, `.cursor/`, `.grok/`,
`.opencode/` resolve their command through the harness's own project-root
variable (`$CLAUDE_PROJECT_DIR`, `$CURSOR_PROJECT_DIR`, `$GROK_WORKSPACE_ROOT`)
or `pwd -P`, and exec a `bin/fm-*.sh` from this repository. No URLs, no `eval`,
no remote fetch, no package execution.

The codex hooks additionally self-verify before running: they confirm
`AGENTS.md` and `.codex/hooks.json` exist and that the hook file *actually
declares the script being invoked* (via `jq`) before piping the payload to it —
defence against being triggered in a foreign checkout.

Two behavioral notes, not security findings:

- `.claude` Stop and `.cursor` stop hooks carry **`timeout: 28800`** (8 hours).
  That is the away-mode supervision design, but a hung guard can hold a session
  for a very long time. Know it before diagnosing a "stuck" agent.
- Hooks invoke `bash -lc` in several places, so the user's login profile is
  sourced into the hook environment. Standard, but it means shell-profile
  contents are part of this execution surface.

### F-7 · Pi extensions and OpenCode plugins — **CLEAN**

7 TypeScript extensions and 6 JS plugins. Imports are `node:*` builtins plus the
harness SDKs (`@earendil-works/pi-coding-agent`, `pi-tui`, `typebox`). **No HTTP
client is imported and no `fetch` is called.** All writes target
`$FM_HOME/state`. The extensions self-fingerprint with a SHA-256 of their own
file into a load marker, and gate every write on owning the session lock —
verified by walking up to 8 parent PIDs before claiming ownership. Careful work.

One thing to be aware of: the watcher arm child is spawned as

```
bash -lc 'config_dir="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"; [ -f "$config_dir/x-mode.env" ] && . "$config_dir/x-mode.env"; exec "$FM_WATCH_ARM_SCRIPT" --restart'
```

`config/x-mode.env` is **dot-sourced into a shell**, so anything in it executes.
It is a local, user-owned, `.gitignore`d file that firstmate itself generates
(it sets one variable, `FM_CHECK_INTERVAL=30`). Not a vulnerability — but it *is*
a config-file-to-code-execution path, which is precisely why
[ADR-0005](../adr/0005-agent-self-improvement-is-pr-gated.md) puts agent-authored
changes to this repository behind human merge.

### F-7b · Repository hygiene — **CLEAN**

`.gitignore` excludes `.env`, `config/`, `state/`, `data/`, `projects/`,
`.no-mistakes/`, `.lavish/`. Every runtime secret and every piece of operational
state is structurally uncommittable. `LICENSE` is unmodified MIT © 2026 Kun Chen.
The only "telemetry" string in the repo is `fm-lint`'s local performance TSV,
written to a local path and never transmitted.

---

## 3. Findings — adjacent tooling (A0.3)

### F-8 · `gnhf` and `lavish-axi` phone home by default — **CONDITION C2**

Both ship an identical, self-hosted **Umami** analytics client, **enabled by
default**, opt-**out** only.

| | `gnhf@0.1.44` | `lavish-axi@0.1.50` |
|---|---|---|
| Endpoint | `https://a.kunchenguid.com/api/send` | same |
| Baked website ID | `7f4707fa-4e80-4977-8320-4ade27692d85` | `ec110e22-c6db-4987-947c-3de184766708` |
| Opt-out env | `GNHF_TELEMETRY=0\|false\|off` | `LAVISH_AXI_TELEMETRY=0\|false\|off` |
| Event | `run` — on every completed run | `command` — on every CLI invocation |
| Timeout | 1s, fire-and-forget, failures swallowed | same |

**What `gnhf` transmits per run:** `agent` (which harness you used), `mode`,
`status`, `signal`, `iterations`, `success_count`, `fail_count`, `commit_count`,
`total_input_tokens`, `total_output_tokens`, `duration_ms`, `prevent_sleep`,
`push_each_iteration`, `commit_message_preset`, `stop_when_set`, plus
`platform` / `arch` / `version`.

**What `lavish-axi` transmits:** `command`, `status` (success|error), plus
`platform` / `arch` / `version`.

**Assessment.** No file contents, no paths, no repository names, no prompt text,
no credentials. `hostname` is the literal constant `"cli"`, not the machine
name. So this is **usage telemetry, not data exfiltration** — the payloads are
small and were read field by field.

It is still an unrequested outbound request to a third-party endpoint on every
invocation, and `gnhf`'s payload discloses our harness choice, token
consumption, and autonomous-run success rate. Under G-3's spirit that is not
acceptable silently.

**Recommendation (mandatory).** The bastion role must export
`GNHF_TELEMETRY=0` and `LAVISH_AXI_TELEMETRY=0` for every context that invokes
these tools — shell profile *and* any scheduled/`vigil` invocation environment,
since a routine will not inherit an interactive profile. Assert by presence, not
by value.

**Scope is narrower than feared — checked, not assumed.** The other four
axi-family tools firstmate expects (`gh-axi@0.1.30`, `tasks-axi@0.2.5`,
`quota-axi@0.1.28`, `chrome-devtools-axi@0.1.29`) were downloaded and scanned:
**zero occurrences** of the analytics host and no telemetry opt-out variable.
Only `gnhf` and `lavish-axi` carry it.

### F-8b · npm package hygiene — otherwise good

| | `gnhf@0.1.44` | `lavish-axi@0.1.50` |
|---|---|---|
| Install lifecycle scripts (`preinstall`/`install`/`postinstall`) | **none** | **none** |
| `prepare` / `prepack` | none | `prepare: npm run build` |
| Registry signature | present | present |
| SLSA provenance attestation | **present** | **present** |
| License | MIT | MIT |
| Runtime deps | 2 (`commander`, `js-yaml`) | 8 (incl. `express`, `open`, `chokidar`) |
| Files | 5 | 44 |

- **No install-time code execution in either.** `lavish-axi`'s `prepare` runs on
  a *git* install, not a registry tarball install — and `scripts/` is not even
  shipped in the tarball, so it could not run. Install from the registry, never
  from the git URL.
- Both publish **SLSA build provenance**, which means the tarball is traceable
  to a CI build of a named source commit. Verify with `npm audit signatures`.
- **`gnhf` makes no network calls other than the telemetry above.** Its only
  `fetch(` occurrence is inside a doc comment; its `createServer` calls are
  `node:net` free-port probes bound to `127.0.0.1`.
- **`lavish-axi` runs a local HTTP server** (`express`) that serves artifacts for
  human review, and can publish to `https://ht-ml.app` — but publishing is behind
  a user-clicked Share dialog, not automatic. It **binds `127.0.0.1` by default**;
  `LAVISH_AXI_HOST` can widen it to `0.0.0.0`/`::`, and the package's own help
  text warns that doing so "exposes an unauthenticated server that can read and
  serve arbitrary local files to anything that can reach it". Leave
  `LAVISH_AXI_HOST` unset. Its rendered artifacts also load `cdn.jsdelivr.net`
  and `esm.sh` assets in the browser — relevant only if the artifact HTML is
  opened, and not a CLI-side network call.

### F-9 · herdr license discrepancy — **NEEDS AN OWNER, blocks nothing now**

`github.com/ogulcancelik/herdr` — note this is **not** a `kunchenguid` repo —
ships an Apache-2.0 `LICENSE` file and reports `Apache-2.0` in its GitHub
metadata. But firstmate's own runtime diagnostic string describes herdr as
`dual-licensed AGPL-3.0-or-later/commercial`.

Those cannot both be current. AGPL and Apache-2.0 imply very different
obligations if herdr is ever used inside something we distribute or expose as a
network service.

**Recommendation.** Resolve with the publisher before herdr becomes load-bearing.
Not blocking: our Phase 1 backend is tmux, and herdr is only required for remote
secondmates.

### F-10 · herdr version drift — **RECONCILE BEFORE P1.2**

- The program plan's base pin (G-2) says **herdr `v0.8.0`**.
- firstmate at our pin installs **`0.7.4`** (`bin/fm-install-herdr.sh`), with
  in-repo SHA-256s for the 0.7.4 assets and a wire-protocol floor of 16.
- Elsewhere in `fm-spawn.sh`, herdr **0.8.0** is referenced as the floor for the
  presentation-spaces layout feature — so upstream knows about 0.8.0 but its CI
  installer has not moved.

`v0.8.0` exists (published 2026-08-03) with four platform assets.

**Checksum provenance for v0.8.0 (A0.3's question), answered precisely:** the
release ships **no `SHA256SUMS` file, no detached signatures, and no GitHub
build attestation** (the attestations API returns 404 for the asset digest).
The only checksums available are **GitHub's own upload-time digests**, retrievable
via the API:

| Asset | GitHub-reported SHA-256 |
|---|---|
| `herdr-linux-x86_64` | `b872ea7e40fa2cb17e857ac9b62b1bf26db7b403c622f5d2f3f5b35f6e9acd28` |
| `herdr-linux-aarch64` | `f647ac66468d9efbc642fe534fb284468f0aea60641606fc008dfc0d82a3ca87` |
| `herdr-macos-aarch64` | `d53a9f93fccfdfcc55632927bf51002f5add0aa7990bcdf508ffbd84ac658178` |
| `herdr-macos-x86_64` | `77cb5afd6c8fcaaaf3bc28e474ec01c209331ad08094e20d7f8aa9b0bb78d649` |

That is **transport integrity, not publisher provenance** — it proves the bytes
you download match what GitHub stored, not that the publisher intended them.
It is what firstmate's own installer relies on too (its pins were presumably
taken the same way), so it is not a regression; it is the ceiling of what herdr
currently offers.

**Recommendation.** Either (a) drop the plan's herdr pin to `0.7.4` to match what
firstmate actually installs, or (b) keep `v0.8.0` and record the four digests
above in our own installer, in the F-4 pattern. Decide before P1.2 writes the
ansible role. Do not leave the plan and the code disagreeing.

---

## 4. Answers to the three questions

| Question | firstmate @ pin | gnhf | lavish-axi | herdr |
|---|---|---|---|---|
| **Phones home?** | **No** — unless the optional Relay is paired (F-2) | **Yes, by default** (F-8) | **Yes, by default** (F-8) | not analysed at runtime; binary, pinned by checksum |
| **Writes outside its own home?** | Bounded and documented; all within `$HOME`; no system paths, no `sudo` (F-5) | writes `~/.gnhf` | writes under the invoking project | n/a |
| **Curl-pipes remote code?** | **No.** Prints hints it never runs (F-3); real installers are checksum-pinned (F-4) | No | No | n/a |

---

## 5. Residual risks accepted

1. **F-1 is the model, not a bug.** Workers have the invoking user's full write
   authority. Coder workspaces are the mitigation where that is unacceptable.
2. **Upstream moves fast with no releases.** Mitigated by the pin, the soft-fork
   contract, and reviewed merges (O-2) — not by this read, which is valid only
   for `6789876442d0`.
3. **This read covered the assigned execution surface, not all 159 `bin/`
   scripts line by line.** The remaining scripts were swept for the three
   questions above and for dynamic execution, but not individually reviewed.
   The remote-secondmate subsystem (`fm-remote-*.sh`, ~15 scripts, SSH + macOS
   LaunchAgent) is the largest unreviewed area and deserves its own read before
   it is ever enabled.
4. **`config/x-mode.env` is dot-sourced into a shell** (F-7). Fine today;
   relevant to any future feature that lets an agent write `config/`.

## 6. Re-read triggers

Redo this read when any of these happen:

- An upstream merge lands (O-2) — at minimum, re-run the sweeps against the diff.
- `gnhf` or `lavish-axi` is version-bumped — the telemetry posture is a build-time
  constant and can change silently.
- herdr, treehouse, or the remote-secondmate subsystem is enabled.
- A new harness adapter is added to `launch_template()` — check what permission
  gate it disables.

---

*Published in two places (task A0.2): this file, and the knowledge-corpus note
`operator-supply-chain-read`. Linked from ductiletoaster/harmony#1237.*
