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
| **C1** | Understand and accept that **every worker launches with its harness's permission gate disabled**. The isolation boundary is the git worktree plus the delivery mode — *not* the harness sandbox. See [F-1](#f-1--every-worker-launches-with-its-harness-permission-gate-disabled--by-design-high-impact). | P1.2 — must be an explicit, recorded acceptance, not a discovery later |
| **C2** | **`gnhf` and `lavish-axi` phone home by default.** Both ship an analytics client, enabled unless opted out. The workstation role must set `GNHF_TELEMETRY=0` and `LAVISH_AXI_TELEMETRY=0`. See [F-8](#f-8--gnhf-and-lavish-axi-phone-home-by-default--condition-c2). | P1.2 |
| **C3** | **The Relay must stay off.** firstmate's optional Relay posts to a third-party service; it activates only when a pairing token exists in `$FM_HOME/.env`. Do not create one, and assert its absence. See [F-2](#f-2--the-relay-is-the-only-outbound-path-and-it-is-opt-in--condition-c3). | P1.2, P1.5 |

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

---

# Part 2 — firstmate's required toolbelt (P1.6)

- **Task:** P1.6 — supply-chain read of the toolbelt `bin/fm-bootstrap.sh` requires
  on `PATH`, feeding P1.2's pins
- **Requirements:** **H-1** (one command, everything pinned) · **G-2** (exact pins,
  no HEAD-tracking, no unpinned `npx`)
- **Date:** 2026-08-17
- **Reader:** Claude Code (Researcher), for the operator
- **Subjects:** `tasks-axi`, `quota-axi`, `no-mistakes`, `gh-axi`,
  `chrome-devtools-axi` — plus the two transitive dependencies they drag in,
  `axi-sdk-js` and `chrome-devtools-mcp`
- **Status:** this part **gates P1.2**. The pins in §9 are the ones the bastion
  role installs; the environment variables in §10 are not optional.

---

## Verdict

> ## **PASS — with five mandatory conditions (C4–C8).**

Nothing here is malicious. All five tools are MIT, all four npm packages publish
both a registry signature and SLSA build provenance, and no payload carries file
contents, paths, repository names, prompt text, or credentials.

The findings are about **how these tools get onto a machine and what they do to
it afterwards** — and on that axis the toolbelt is materially worse than
firstmate itself:

| # | Condition | Blocks |
|---|---|---|
| **C4** | **`no-mistakes` is not the npm package of that name.** The tool firstmate requires is a Go binary from `kunchenguid/no-mistakes`; npm `no-mistakes` is a different publisher's TS/JS analysis tool. Install from the pinned GitHub release with checksum verification — never `npm i -g no-mistakes`, never the `curl \| sh` hint. See [F-11](#f-11--no-mistakes-is-not-an-npm-package--condition-c4). | P1.2 |
| **C5** | **`no-mistakes` phones home by default**, to the same `a.kunchenguid.com` Umami endpoint as `gnhf` and `lavish-axi`. Set `NO_MISTAKES_TELEMETRY=0` — **and set it where the daemon will see it**, which is not the shell profile. See [F-12](#f-12--no-mistakes-phones-home-by-default-and-the-daemon-does-not-read-your-shell-profile--condition-c5). | P1.2 |
| **C6** | **`chrome-devtools-axi` runs `npx -y chrome-devtools-mcp@latest` at runtime** unless told otherwise — a floating fetch-and-execute, in the exact words G-2 forbids. Pin `chrome-devtools-mcp` and export `CHROME_DEVTOOLS_AXI_MCP_PATH`. See [F-13](#f-13--chrome-devtools-axi-runs-npx--y-chrome-devtools-mcplatest--condition-c6). | P1.2 |
| **C7** | **`no-mistakes` installs and enables a `systemd --user` unit** and runs a persistent daemon. P1.2 must own that unit deliberately or H-1's idempotency claim is not true. See [F-14](#f-14--no-mistakes-installs-a-systemd---user-unit-and-runs-a-daemon--condition-c7). | P1.2, H-1 |
| **C8** | **Every tool ships an in-band pin-breaker.** `<tool> update` really does run `npm install -g <pkg>@latest`; `no-mistakes` background-checks GitHub on nearly every invocation. Set `NO_MISTAKES_NO_UPDATE_CHECK=1` and record `update` as forbidden. See [F-15](#f-15--every-tool-ships-an-in-band-pin-breaker--condition-c8). | P1.2 |

Three lower-severity items need an owner but block nothing: **F-16**
(`setup hooks` rewrites `~/.claude/settings.json`), **F-17** (`quota-axi` reads
every local harness credential store), **F-18** (the `axi-sdk-js ^0.1.10` caret
makes the pins non-hermetic).

**No license discrepancy anywhere.** Every package declares MIT, ships an MIT
`LICENSE` (© 2026 Kun Chen), and carries no conflicting runtime string. The
herdr problem (F-9) does not repeat here.

---

## 7. Scope and method

`bin/fm-bootstrap.sh` declares the toolbelt in one line:

```
COMMON_TOOLS="node git gh no-mistakes gh-axi chrome-devtools-axi lavish-axi tasks-axi quota-axi"
```

Everything in it is checked for presence; five of the eight also carry a version
floor. Each tarball was downloaded from the registry and read — never installed —
and the `no-mistakes` release binary was downloaded, checksum-verified, and read
alongside its source at the matching tag.

| Surface | What was read |
|---|---|
| npm tarballs | `package.json` (scripts, bin, deps, files), every shipped `dist/` entry point, `LICENSE` |
| Sweeps per tarball | `http`/`https`/`fetch`/`axios`, `umami`/`analytics`/`telemetry`/`posthog`/`sentry`/`segment`, `DO_NOT_TRACK`, every `process.env.*` reference, every `child_process` call |
| `no-mistakes` | the v1.48.0 `linux-amd64` binary (string extraction) **and** the repo at tag `v1.48.0` — `internal/telemetry`, `internal/update`, `internal/daemon`, `internal/agent`, `internal/pipeline` |
| Install paths | `docs/install.sh` from `kunchenguid/no-mistakes@main`, fetched and read, never executed |
| firstmate | `bin/fm-bootstrap.sh`, `bin/fm-tasks-axi-lib.sh`, `bin/fm-quota-axi-lib.sh`, `bin/fm-nm-run-lib.sh`, `.no-mistakes.yaml` |

### The floors, and where each one lives

A future bump has exactly three files to touch:

| Tool | Floor | Declared in |
|---|---|---|
| `tasks-axi` | `0.2.4` | `bin/fm-tasks-axi-lib.sh:37` — `FM_TASKS_AXI_MIN` (the file names itself the single owner) |
| `quota-axi` | `0.1.25` | `bin/fm-quota-axi-lib.sh:12` — `FM_QUOTA_AXI_MIN` |
| `no-mistakes` | `1.31.2` | `bin/fm-bootstrap.sh:795` — `NO_MISTAKES_MIN` |
| `gh-axi` | `0.1.29` | `bin/fm-bootstrap.sh:803` — `GH_AXI_MIN` |
| `lavish-axi` | `0.1.46` | `bin/fm-bootstrap.sh:804` — `LAVISH_AXI_MIN` |
| `chrome-devtools-axi` | **none** | presence-only; it appears in `COMMON_TOOLS` and nowhere else |

The AXI-family floor policy is stated at `bin/fm-bootstrap.sh:796-802` and is
worth quoting, because it changes how our pins should be maintained:

> Every axi-family floor is the CURRENT LATEST published version of that tool,
> captain-bumped periodically… It is NOT the minimum feature-introduced version.
> These floors are expected to drift upward as new versions ship.

So a floor is a *freshness* assertion, not a compatibility assertion. Upstream
will keep raising it, and a floor above our pin turns into a `MISSING:` line in
bootstrap output rather than a failure. That is the correct fail-closed shape —
but it means our pins need a scheduled bump, not a one-time decision.

---

## 8. Findings — the toolbelt (P1.6)

### F-11 · `no-mistakes` is not an npm package — **CONDITION C4**

This is the single most important finding in Part 2, and it is a naming trap.

`bin/fm-bootstrap.sh:758` gives the install hint:

```
no-mistakes) echo "curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh | sh" ;;
```

The tool firstmate requires is **`github.com/kunchenguid/no-mistakes`** — a
25 MB Go binary, MIT, ~7.7k stars, currently tagged `v1.53.0`. The npm registry
also has a package called `no-mistakes`. It is **not the same software**:

| | firstmate's `no-mistakes` | npm `no-mistakes@0.43.3` |
|---|---|---|
| Publisher | `kunchenguid` | `jonathanong` (`jongleberry`) |
| What it is | agent-driven review/fix/document/test/lint/push/PR pipeline (Go) | "Static codebase analysis tools for TS/JS dependencies, dependents, and symbols" |
| Distribution | GitHub Releases tarball | npm, with a `postinstall` that downloads a binary from `jonathanong/no-mistakes` releases |
| Version line | `v1.31.2` … `v1.53.0` | `0.43.3` |

Note the version lines. firstmate's floor is `1.31.2`; the npm package is on
`0.43.3`. So an accidental `npm i -g no-mistakes` **fails the floor and reports
`MISSING:` — fail-closed, which is lucky rather than designed.** It would still
have put a foreign publisher's binary on the bastion's `PATH` under the name
firstmate shells out to (`bin/fm-nm-run-lib.sh` calls bare `no-mistakes "$@"`),
and its `postinstall` runs `node scripts/install.js`, which downloads a release
asset with the download base overridable by `NO_MISTAKES_RELEASE_BASE_URL`.

**And the official install path is worse than the wrong one.** The 85-line
`docs/install.sh`, read in full:

1. resolves `https://api.github.com/repos/kunchenguid/no-mistakes/releases/latest`
   at run time — **floating**, the precise thing G-2 forbids;
2. downloads `no-mistakes-${VERSION}-${OS}-${ARCH}.tar.gz` and extracts it with
   **no checksum, no signature, no attestation check** — even though the release
   *ships a `checksums.txt` the script never fetches*;
3. **escalates to `sudo`** (`sudo mkdir -p`, `sudo ln -s`) to symlink into
   `/usr/local/bin` whenever `$HOME/.local/bin` is not already on `PATH` — an
   interactive prompt in the middle of an unattended play, and the only `sudo`
   anywhere in this toolchain;
4. finishes with `"$BIN_PATH" daemon restart`, i.e. it installs a background
   service as a side effect of installing a CLI (see F-14).

**Recommendation (mandatory).** P1.2 installs `no-mistakes` the way
`bin/fm-install-herdr.sh` installs herdr — the F-4 pattern:

- pin the exact tag, download the exact release asset;
- verify against the digest recorded below **before** anything is unpacked;
- install into a fixed user-owned prefix (`~/.local/bin`, already on the
  bastion's `PATH`) so no `sudo` branch is ever reachable;
- re-verify `no-mistakes --version` reports the pinned version;
- manage the daemon explicitly (F-14) rather than inheriting the script's
  `daemon restart`.

**Which tag to pin: `v1.48.0`, and the reason matters.** Tags run to `v1.53.0`,
but `releases/latest` returns **`v1.48.0`** (published 2026-08-08) — tags
`v1.49.0` through `v1.53.0` have **no GitHub Release and therefore no binaries**.
`v1.48.0` is the newest installable version, it clears the `1.31.2` floor with
room, and it is what the upstream install script would have fetched anyway.

`v1.48.0` **does** ship a publisher-authored `checksums.txt`, and its six entries
match GitHub's own upload-time digests exactly. Verified by download:

| Asset | SHA-256 |
|---|---|
| `no-mistakes-v1.48.0-linux-amd64.tar.gz` | `c67c65d626f4c6e6b44c2c079232ec8104f565d124cbe5a300766c85c2ba5bc0` |
| `no-mistakes-v1.48.0-linux-arm64.tar.gz` | `7ce8b7f712acc889f48788418435cdd28375222c9450e43a024d043824edb2b2` |
| `no-mistakes-v1.48.0-darwin-amd64.tar.gz` | `129f6a164bbdc9a35d2ad890e270b3aca1c9f245d8950faee950a74dc76b07e3` |
| `no-mistakes-v1.48.0-darwin-arm64.tar.gz` | `af6bfaffec8f961282aa19333e64f0cf82d1be95bab34ae2290ae6d570032279` |

The `linux-amd64` digest above was confirmed against a locally downloaded
tarball. As with herdr (F-10) there is **no build attestation** — the
attestations API returns 404 for the asset digest — so this is publisher-asserted
integrity, not provenance. It is still a step above herdr `0.8.0`, which offers
no `checksums.txt` at all.

### F-12 · `no-mistakes` phones home by default, and the daemon does not read your shell profile — **CONDITION C5**

`internal/telemetry/telemetry.go` is the same Umami client pattern A0.3 found in
`gnhf` and `lavish-axi` (F-8), now in Go:

| | `no-mistakes@v1.48.0` |
|---|---|
| Endpoint | `https://a.kunchenguid.com/api/send` |
| Baked website ID | `f959e889-92f5-4121-8a1f-571b10861198` (ld-flagged in at release build; recovered from the shipped binary) |
| Opt-out env | `NO_MISTAKES_TELEMETRY` = `0` \| `false` \| `off` (case-insensitive, trimmed) |
| Host / ID overrides | `NO_MISTAKES_UMAMI_HOST`, `NO_MISTAKES_UMAMI_WEBSITE_ID` — these **redirect**, they do not disable |
| Events | `command`, `run`, `step`, `fix`, `approval`, `wizard`, plus `/tui` and `/wizard` pageviews |
| Transport | `POST`, 1s timeout, fire-and-forget in a goroutine, failures swallowed |

**What it transmits**, read field by field: `command`, `status`, `duration_ms`,
`agent` (which harness the pipeline drove), `trigger`, `branch_role`,
`step_count`, `event`, `step`, `findings_count`, `selected_findings_count`,
`source` (`auto`|`user`), `attempt`, `outcome`, `matched_agent`, `score`,
`demo_mode`, plus `platform`/`arch`/`version`. `hostname` is the literal constant
`"cli"`. **No repository name, no branch name, no path, no diff, no prompt
text, no credential.** Same assessment as F-8: usage telemetry, not
exfiltration — and there is real restraint in it (`trackReadSurface` samples
high-frequency agent polling behind a state fingerprint plus a 10-minute
heartbeat, specifically so status loops do not flood the endpoint).

**The part that will catch us out.** The richest events — the `run` lifecycle —
are emitted by the **daemon** (`internal/daemon/manager.go`), not by the CLI
process. The daemon runs as a `systemd --user` unit that no-mistakes generates
itself, and `internal/daemon/service_systemd.go:107-117` writes only three kinds
of `Environment=` line: `HOME`, `PATH`, and forwarded proxy variables.
**`NO_MISTAKES_TELEMETRY` is not forwarded.**

So `export NO_MISTAKES_TELEMETRY=0` in a shell profile silences the CLI and
leaves the daemon reporting. This is the same trap A0.3 flagged for `vigil`
routines (a scheduled invocation inherits no interactive profile), one layer
deeper.

**Recommendation (mandatory).** Set the variable where the systemd *user
manager* itself will apply it to every unit — `~/.config/environment.d/*.conf`,
which survives no-mistakes regenerating its own unit file — **and** in the shell
profile for the CLI path. Do not hand-edit the generated unit: a reinstall
rewrites it. Assert by presence, never by echoing the value (G-3).

> Positive signal in the same file: when proxy variables *are* forwarded into the
> unit, `writeServiceFile` drops the file to `0600` and does the write via a
> temp-file rename, explicitly because a proxy URL can embed credentials and a
> plain `os.WriteFile` would leave a pre-existing `0644` file world-readable
> during the transition. That is a careful author.

### F-13 · `chrome-devtools-axi` runs `npx -y chrome-devtools-mcp@latest` — **CONDITION C6**

`chrome-devtools-axi` is a thin wrapper: it spawns `chrome-devtools-mcp` over
stdio MCP and drives Chrome through it. `dist/src/bridge.js`
(`resolveTransportSpec`) resolves that child in three steps:

1. `CHROME_DEVTOOLS_AXI_MCP_PATH` — explicit override, always wins;
2. auto-detect `$(npm prefix -g)/lib/node_modules/chrome-devtools-mcp/build/src/bin/chrome-devtools-mcp.js`;
3. **fall back to `npx -y chrome-devtools-mcp@latest`.**

Step 3 is a floating fetch-and-execute on every invocation where the first two
miss. G-2 names this case in so many words ("no unpinned `npx`"). It is not
visible in the tarball's dependency tree — it only happens at run time — so a
lockfile or an `npm ls` audit will never show it.

`chrome-devtools-mcp@1.7.0` itself is reassuring: Google-published, Apache-2.0,
registry signature **and** provenance present, **zero runtime dependencies**
(rollup-bundled), and no install lifecycle script in the tarball (`scripts/` is
not shipped, so its `prepare` cannot run). The problem is purely that we would be
running whatever `@latest` resolves to that day.

**One more unpinned fetch behind it.** The bundled Puppeteer inside
`chrome-devtools-mcp` carries the Chrome-for-Testing download endpoints
(`storage.googleapis.com/chrome-for-testing-public`,
`googlechromelabs.github.io/chrome-for-testing`). If no suitable local Chrome is
present it will fetch a browser build. P1.2 should install a system
Chrome/Chromium and select it by channel, so the browser is a managed package
rather than a runtime download.

**Recommendation (mandatory).** Install `chrome-devtools-mcp` globally at an
exact pin, and export

```
CHROME_DEVTOOLS_AXI_MCP_PATH="<npm global prefix>/lib/node_modules/chrome-devtools-mcp/build/src/bin/chrome-devtools-mcp.js"
```

for every context that invokes the tool — profile *and* any scheduled
environment. This also removes the ~30 s npx bootstrap that races the bridge's
30 s readiness deadline, so it is a reliability fix as well as a G-2 fix.

### F-14 · `no-mistakes` installs a `systemd --user` unit and runs a daemon — **CONDITION C7**

`internal/daemon/service_systemd.go` writes
`~/.config/systemd/user/no-mistakes-daemon-<instance-suffix>.service`, then runs
`systemctl --user daemon-reload` and `systemctl --user enable`. On macOS the same
code writes a `~/Library/LaunchAgents/*.plist`; on Windows, a scheduled task. The
unit name is suffixed per `NM_HOME` so multiple homes cannot collide. The
upstream install script triggers this implicitly via its closing
`no-mistakes daemon restart`.

Two consequences for P1.2:

- **H-1's idempotency claim has to cover this.** A play that installs the binary
  but ignores the unit will look idempotent while the service drifts underneath
  it. The unit is *generated*, so the role must not template it — it should
  install the binary, invoke the daemon lifecycle deliberately, and assert the
  unit's state.
- **A headless bastion needs `loginctl enable-linger`** for the user, or a
  `systemd --user` instance will not exist outside a login session and the enable
  will not produce a running daemon. There is a `defaultServiceManagerBypassed()`
  path where the daemon is spawned as a plain child process instead — in that
  mode it *does* inherit the invoking environment, which changes the F-12
  mitigation. Decide which mode the bastion runs in and assert it, rather than
  discovering it.

### F-15 · Every tool ships an in-band pin-breaker — **CONDITION C8**

Two independent mechanisms, both reachable by any agent with a shell:

**`axi-sdk-js` reserves `update` as a built-in subcommand** (`dist/cli.js`). A
tool may shadow it; none of the four do. `runUpdate` (`dist/update.js`) fetches
`https://registry.npmjs.org`, detects the install method, and — with no `--check`
flag — **actually executes `npm install -g <pkg>@latest`** as a child process.
So `tasks-axi update` silently replaces a pinned install.

The good news: this is **explicit-only**. There is no background version check
and no auto-update on normal invocations — confirmed by call-site grep across
all four packages. The `update` path is entered only from `argv[0] === "update"`.

**`no-mistakes` does check in the background.** `cmd/no-mistakes/main.go:64`
calls `update.MaybeNotifyAndCheck` on **every** invocation except `update`,
`--version` and `-v`, which spawns a detached child that queries
`https://api.github.com` for the latest release and caches it. It is
**notify-only** — it prints "a new version is available" and never installs
unasked — but it is a second unrequested outbound call per run, on a tool agents
invoke in a polling loop. Opt-out: `NO_MISTAKES_NO_UPDATE_CHECK=1`.

The deliberate carve-out for `--version`/`-v` ("so that supervision scripts can
call it as an innocuous health check") is exactly the call `fm-bootstrap.sh`'s
floor gate makes — the two designs fit together correctly.

**Recommendation (mandatory).** Set `NO_MISTAKES_NO_UPDATE_CHECK=1` alongside the
telemetry opt-out (same two places, per F-12), and record in the workstation
runbook that `<tool> update` and `no-mistakes update` are forbidden — version
changes come from a P1.2 pin bump and a play re-run, never from inside a session.
This is the F-4 discipline applied to the tools that can undo it.

### F-16 · `setup hooks` rewrites `~/.claude/settings.json` — **NEEDS A DECISION, blocks nothing**

firstmate's install hints append `&& <tool> setup hooks` for `gh-axi`,
`chrome-devtools-axi` and `lavish-axi`. That command calls
`installSessionStartHooks` in `axi-sdk-js` (`dist/hooks.js:365-440`), which:

- reads, JSON-parses and **rewrites** `~/.claude/settings.json` and
  `~/.codex/hooks.json`, injecting a `SessionStart` hook (`type: command`,
  `timeout: 10`) that runs the tool for "ambient context";
- appends `[features] hooks = true` to `~/.codex/config.toml`;
- installs a managed OpenCode plugin under `~/.config/opencode/`.

It is idempotent by marker and it only ever touches its own entries. But the
rewrite is a full `JSON.stringify(..., 2)` round-trip: any formatting or comments
in the operator's `~/.claude/settings.json` are lost, and every Claude Code
session on the bastion — including our own harmony work — gains a hook that
executes a third-party binary at session start.

`tasks-axi` also exposes `setup hooks`; `quota-axi` does not.

**Recommendation.** Treat `setup hooks` as a separate, opt-in decision from
installing the binaries. If P1.2 runs it, it must back up `~/.claude/settings.json`
first and the injected hook must be listed in the workstation runbook — a
mystery `SessionStart` entry is a bad thing to meet during an incident. Nothing
in the pilot requires ambient context, so the safe default is: install the tools,
skip the hooks, revisit from P2.5 evidence.

### F-17 · `quota-axi` reads every local harness credential store — **KNOW IT, blocks nothing**

`quota-axi` is the only one of the four that makes network calls at all — seven
`fetch` sites, and by design: it reports subscription-window usage, which means
reading each harness's OAuth material locally and asking that vendor how much of
the plan is spent.

| Reads | Sends to |
|---|---|
| `~/.claude/.credentials.json` (and `CLAUDE_CONFIG_DIR`), macOS Keychain | `api.anthropic.com/api/oauth/usage`, `/api/oauth/profile` |
| `~/.codex` (`CODEX_HOME`) | `api.openai.com/auth/account_id`, `chatgpt.com/backend-api/codex/usage`, `/wham/usage` |
| `~/.config` GitHub Copilot `apps.json` | `api.github.com/copilot_internal/user` |
| `~/.cursor` (`CURSOR_CLI_CONFIG`, `CURSOR_STATE_DB`), macOS Keychain | `api2.cursor.sh` |
| `~/.grok` (`GROK_AUTH*`) | `grok.com`, `api.x.ai/v1/models` |
| `~/.kimi-code`, **`~/.pi/**/auth.json`** | `api.kimi.com/coding/v1/usages` |

Every credential goes **only to the vendor that issued it**. There is no
third-party sink, no telemetry host, and no analytics vocabulary anywhere in the
package. Writes are limited to `$XDG_CACHE_HOME/quota-axi/` — a `0600` cache
written temp-then-rename under a `0700` parent, plus keychain-consent markers.
macOS Keychain reads are **skipped until the user opts in** with
`--allow-keychain-prompt`, which is the right default.

Two things to carry forward anyway: this is the widest credential *read* surface
in the toolbelt, and it includes `~/.pi/`, which on our bastion is the harness
H-2 wires to the LiteLLM gateway. Nothing routes a gateway key anywhere — the pi
readers look only for `kimi-coding` and `xai` provider entries — but D-17's "no
new credentials on the bastion during the pilot" should be read as also meaning
*no new credential readers get added quietly*.

### F-18 · The pins are not hermetic — `axi-sdk-js` floats — **KNOW IT, blocks nothing**

All four axi packages declare `"axi-sdk-js": "^0.1.10"`. A global install
resolves that caret at install time, so `tasks-axi@0.2.5` installed tomorrow may
carry a different `axi-sdk-js` than the one read here. Today `^0.1.10` resolves
to exactly `0.1.10`. Since `axi-sdk-js` owns the `update` built-in (F-15), the
hook installer (F-16) and every tool's CLI dispatch, it is not an incidental
dependency.

`npm -g` has no lockfile, so a truly hermetic install means installing the exact
tarball URLs. That is heavier than it is worth for the pilot. The proportionate
answer: record `axi-sdk-js 0.1.10` as the read version in P1.2's defaults, and
have the role's smoke check assert the resolved version so drift is visible
rather than silent.

`@toon-format/toon` is a second shared transitive (`^2.1.0`, pinned exactly at
`2.1.0` by `quota-axi`); it is a serialization format library with no network or
filesystem surface.

### F-19 · Install-time behavior of the four npm packages — **CLEAN**

| | `tasks-axi@0.2.5` | `quota-axi@0.1.28` | `gh-axi@0.1.30` | `chrome-devtools-axi@0.1.29` |
|---|---|---|---|---|
| `preinstall`/`install`/`postinstall` | **none** | **none** | **none** | **none** |
| `prepare`/`prepack`/`prepublishOnly` | `prepack` | `prepublishOnly` | `prepublishOnly` | `prepublishOnly` |
| Registry signature | present | present | present | present |
| SLSA provenance | **present** | **present** | **present** | **present** |
| Publisher | npm trusted publisher (GitHub OIDC), `kunchenguid` | same | same | same |
| License | MIT | MIT | MIT | MIT |
| Runtime deps | 2 | 2 | 2 | 3 |
| Node engine | `>=20` | **`>=22.19`** | `>=20` | `>=20` |

**No install-time code execution in any of them.** `prepack` and
`prepublishOnly` run on pack/publish and on a *git* install, never on a registry
tarball install — and `scripts/` is not shipped, so they could not run anyway.
Install from the registry, never from a git URL.

`quota-axi` requires **Node ≥ 22.19** — the highest floor in the set, and the one
that determines the Node version P1.2 must provision.

### F-20 · Runtime behavior of the other three — **CLEAN**

- **`tasks-axi`** — zero network. Zero `child_process`. Reads and writes only the
  markdown backlog its `.tasks.toml` points at, via a lock file and atomic
  temp-then-rename writes. No telemetry vocabulary, no `process.env` reads at
  all. The quietest tool in the set.
- **`gh-axi`** — zero direct network. It shells out to `gh` and to
  `git remote get-url origin` via `execFile` with argument arrays (no shell
  string, so no injection seam). Its only write is a `mkdtemp` scratch file for
  `run` output. Its authority is therefore *exactly* the `gh` token's authority
  — which on our bastion includes repository write. Nothing new is granted; it is
  a different front door onto a credential we already accept.
- **`chrome-devtools-axi`** — beyond F-13, it reads no credentials and binds only
  `127.0.0.1` (bridge port 9224, per-session derived). `CHROME_DEVTOOLS_AXI_WS_HEADERS`
  accepts a JSON `Authorization` header for a remote `wss://` browser — relevant
  only if we ever point it at the cluster's browserless, which A3.2's
  interface-class doctrine says we should not.

### F-21 · What `no-mistakes` does to a repository — **THE POSTURE, read before P2.1**

Per D-05/O-4 the `no-mistakes` posture *is* this tool's pipeline, so its
authority surface is the posture's authority surface. Reading
`internal/pipeline/steps/`, that is: **intent → review → fix → document → test →
lint → rebase → push → PR → CI**.

- **Harness.** It drives a harness itself — adapters for claude, codex, copilot,
  opencode, pi, rovodev, acpx. And it launches them the same way firstmate does:
  `--dangerously-skip-permissions` (claude),
  `--dangerously-bypass-approvals-and-sandbox` (codex), unless the caller pins a
  permission mode. **F-1/C1 therefore covers two tools, not one** — the C1
  acceptance should be recorded as applying to the no-mistakes pipeline as well.
- **Headless.** Yes. `no-mistakes axi run --intent "…" --yes` auto-resolves every
  approval gate and drives to a terminal outcome. Without `--yes` it blocks at
  the first gate and an agent answers with `axi respond --action approve|fix|skip`.
- **Credentials.** `gh`/`GH_TOKEN`/`GITHUB_TOKEN` for GitHub, plus optional
  GitLab, Azure DevOps (`AZURE_DEVOPS_EXT_PAT`) and Bitbucket
  (`NO_MISTAKES_BITBUCKET_API_TOKEN`/`_EMAIL`/`_API_BASE_URL`) providers we do
  not use and should not configure.
- **What it does to the tree.** Commits agent fixes as
  `no-mistakes: apply agent fixes`, rebases, force-pushes, opens/updates a PR,
  and watches CI. The force-push is **not** a bare `--force-with-lease`: it
  anchors the lease to the exact verified remote head and refuses outright if the
  remote carries commits the pipeline never incorporated. There is also a
  HEAD-continuity guard that refuses to push a head that is not the
  review-approved commit or a descendant of it. These are real, and they are the
  reason this tool is safe to point at a repository at all.
- **Our own fork already constrains it.** `.no-mistakes.yaml` at the repo root
  sets `disable_project_settings: true`, which is honored **only from the
  default-branch copy** — a pushed branch cannot turn it off — so a gate agent
  never loads firstmate's fleet-captain `AGENTS.md` identity. Read alongside
  `bin/fm-gate-refuse-lib.sh`'s lifecycle refusal, that is a genuine two-layer
  authority boundary, and it is the model to copy when we register `harmony`
  under this posture in P2.1.

---

## 9. The pins

Exact versions, integrity hashes, and the floor each one clears. These are what
`ansible/roles/bastion/defaults/main.yml` carries.

| Package | Pin | Published | Integrity / digest | Floor cleared |
|---|---|---|---|---|
| `tasks-axi` | **0.2.5** | 2026-08-07 | `sha512-FxssEW7+MuUNHWJ7uhdGrRsBDev/Zw5NutUBHcf8r/npG6z9+NfUUIeXdcdDHrC9ixEKOqQ9Uomay2TLpDB6Eg==` | `0.2.4` ✓ |
| `quota-axi` | **0.1.28** | 2026-08-14 | `sha512-EwcjUA0bBo3QdBy2sKr3A/g9Wup8F4r0u2FRKH6wHs+raW+xyiXVbHVbkkyun39zGDsBHN6ocEN7YUJ/3rxx2A==` | `0.1.25` ✓ |
| `gh-axi` | **0.1.30** | 2026-08-07 | `sha512-4qw7+INJqdH5obm6NOUQnqBRALMG/BYQwTseVr9I7DHvccEytBtltc0EvB0SxrDzIUTKPshI9uKtfp83TjlBjA==` | `0.1.29` ✓ |
| `chrome-devtools-axi` | **0.1.29** | 2026-08-07 | `sha512-ILnqDZbAPylESC4tWsAPZNhzL1qXFsOeRO4D5YEyhAHAq3ulBfb43s4ZjLAZ+ykeJEi8XGyqVcX/MROhguuA9w==` | none declared |
| `no-mistakes` (**GitHub, not npm**) | **v1.48.0** | 2026-08-08 | `c67c65d6…5bc0` (linux-amd64; full table in F-11) | `1.31.2` ✓ |
| `chrome-devtools-mcp` (transitive, C6) | **1.7.0** | — | `sha512-6xFW7oiUxTxZuHcfyYBkKQtmttjCbfifKZMSEk5CV8H2FucvKweYiJr8CblddYHtYjA4C14K9VAs1r49906RBA==` | n/a |
| `axi-sdk-js` (transitive, F-18) | **0.1.10** (read; resolved from `^0.1.10`) | — | `sha512-mktHOya6qUgqDcMpmj5WsNDzArre15N2qfns8bY98nrHGTSqdBnH2Ok77c2zOA2jYbGHO/BhhVZtDGK/UTO70g==` | n/a |

Also required on the host: **Node ≥ 22.19** (`quota-axi`'s engine floor), `git`,
`gh`, and a system Chrome/Chromium (F-13).

Verify the npm pins with `npm audit signatures` after install — all six publish
both a registry signature and SLSA provenance, so a failure there is meaningful.

## 10. The environment P1.2 must bake in

Every one of these belongs in **both** the interactive shell profile **and** any
scheduled/`vigil` invocation environment — a routine inherits no login profile.
The two `systemd`-scoped ones additionally need
`~/.config/environment.d/*.conf`, because the no-mistakes daemon's generated
unit forwards only `HOME`, `PATH` and proxy variables (F-12).

| Variable | Value | Why | Scope |
|---|---|---|---|
| `GNHF_TELEMETRY` | `0` | A0.3 condition C2 | profile + scheduled |
| `LAVISH_AXI_TELEMETRY` | `0` | A0.3 condition C2 | profile + scheduled |
| **`NO_MISTAKES_TELEMETRY`** | **`0`** | **new, C5** — same Umami endpoint | profile + scheduled + **`environment.d`** |
| **`NO_MISTAKES_NO_UPDATE_CHECK`** | **`1`** | **new, C8** — stops the per-invocation GitHub check | profile + scheduled + **`environment.d`** |
| **`CHROME_DEVTOOLS_AXI_MCP_PATH`** | **absolute path to the pinned `chrome-devtools-mcp` build** | **new, C6** — removes the `npx …@latest` fallback | profile + scheduled |

Leave unset, deliberately: `LAVISH_AXI_HOST` (A0.3 — widening it exposes an
unauthenticated local file server), `NO_MISTAKES_UMAMI_HOST` /
`NO_MISTAKES_UMAMI_WEBSITE_ID` (they redirect telemetry, they do not disable it),
`CHROME_DEVTOOLS_AXI_BROWSER_URL` / `_WS_HEADERS` (A3.2 keeps local AXI browsing
and federated cluster browsing separate), and every
`NO_MISTAKES_BITBUCKET_*` / `AZURE_DEVOPS_EXT_PAT` variable.

Assert all of them by presence, never by echoing a value (G-3).

## 11. Not installable unattended, as shipped

| Thing | Why | Do instead |
|---|---|---|
| `curl -fsSL …/no-mistakes/main/docs/install.sh \| sh` | floating `releases/latest`, no checksum despite one being published, `sudo` escalation, implicit daemon start | pinned release + digest verify + user prefix (F-11) |
| `npm i -g no-mistakes` | **different publisher's package** — not the tool firstmate calls | never; there is no npm distribution of the real tool |
| `<tool> setup hooks` | rewrites `~/.claude/settings.json` and injects a `SessionStart` hook into every session on the box | separate opt-in decision; default off for the pilot (F-16) |
| `chrome-devtools-axi` with no `CHROME_DEVTOOLS_AXI_MCP_PATH` | runtime `npx -y chrome-devtools-mcp@latest` | pin + export the path (F-13) |
| `<tool> update` / `no-mistakes update` | really does `npm install -g …@latest`; undoes the pins from inside a session | forbidden in the runbook; bump pins in P1.2 and re-run (F-15) |

## 12. Answers to the three questions

| Question | `tasks-axi` | `quota-axi` | `gh-axi` | `chrome-devtools-axi` | `no-mistakes` |
|---|---|---|---|---|---|
| **Phones home?** | **No** — zero network | Vendor APIs only, by design (F-17); no third-party sink | **No** — delegates to `gh` | **No** — local `127.0.0.1` bridge | **Yes, by default** (F-12) + a GitHub update check (F-15) |
| **Writes outside its own home?** | No — only its configured backlog file | `$XDG_CACHE_HOME/quota-axi` (`0600`/`0700`) | `mkdtemp` scratch only | per-session local state | **Yes** — `~/.config/systemd/user/` unit (F-14); `setup hooks` targets are opt-in (F-16) |
| **Curl-pipes / fetch-executes remote code?** | No | No | No | **Yes** — `npx …@latest` fallback (F-13) | **Its documented install path does** (F-11); the binary itself does not |

## 13. Residual risks accepted

1. **The floors are a moving target by policy**, not a compatibility contract
   (§7). Our pins will fall below them on upstream's schedule and surface as
   `MISSING:` lines. That is fail-closed and fine — but it means a recurring bump,
   and it is the strongest argument for making the toolbelt versions a single
   reviewed block in `defaults/main.yml`.
2. **`no-mistakes` releases lag its tags.** Five tags past the newest release
   exist with no binaries. Do not pin a tag without confirming the release and
   its `checksums.txt` exist.
3. **`no-mistakes` moves fast** — 72 npm-side and 50+ tag-side versions in three
   months; `v1.53.0` landed the day this was written. The telemetry posture is a
   build-time constant (ld-flagged), so it can change silently between tags.
4. **Provenance is asymmetric.** The npm half of the toolbelt has SLSA
   attestations; the GitHub-released half has publisher checksums and no
   attestation, the same ceiling as herdr (F-10).
5. **F-18's caret** means "the pins" are five exact versions plus one resolved
   one. Assert, do not assume.

## 14. Re-read triggers

In addition to A0.3's triggers:

- Any toolbelt pin is bumped — telemetry and update posture are build-time
  constants and can change without a note.
- A floor in `fm-bootstrap.sh`, `fm-tasks-axi-lib.sh` or `fm-quota-axi-lib.sh`
  moves above one of our pins on an upstream merge (O-2).
- `axi-sdk-js` publishes a new `0.1.x` — it owns `update`, the hook installer and
  CLI dispatch for all four axi tools.
- We decide to run `setup hooks` (F-16), enable the no-mistakes daemon in a new
  mode (F-14), or point `chrome-devtools-axi` at a remote browser (F-20).
- `no-mistakes` gains a release for a tag beyond `v1.48.0` and we want it.

---

*Part 2 published for task P1.6 (H-1, G-2). Pins feed
`ansible/roles/bastion/defaults/main.yml` in P1.2. Linked from
ductiletoaster/harmony#512 and pixeloven/operator#1.*
