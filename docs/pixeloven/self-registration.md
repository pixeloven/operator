# Self-registration: `operator` is a project in its own fleet

**Task A1.3** · satisfies **O-4** ([ADR-0005](../adr/0005-agent-self-improvement-is-pr-gated.md)) · registered 2026-08-17

`operator` registers **its own repository** in **its own** project registry, at delivery
posture **`no-mistakes`**. Every agent-authored change to this repository — including an
overnight autonomous run — therefore arrives as a pull request that has been through the
full validation pipeline. Humans merge. There is no path by which the fleet edits itself
without review.

This document records what that means concretely, where the state lives, and how to
reproduce it on a new machine.

---

## 1. Why the registration is not in this repository

The registry is `data/projects.md` **in the fleet home**, and it is deliberately not
tracked by git. Upstream's own CI enforces that:

```console
$ git ls-files -- data state config projects .no-mistakes
(no output)
```

The `invariants` job in `.github/workflows/ci.yml` fails the build if any of those paths
becomes tracked. That is correct and we keep it. A fleet registry is **machine-local
state**: it names the projects *this* operator instance works on, on *this* machine, with
*this* human's postures. Committing it would publish one machine's working set as though
it were the project's configuration, and would collide on every merge.

So: the **policy** (posture `no-mistakes`, and why) is version-controlled — here, and in
ADR-0005. The **instance** of that policy is provisioned per machine, by the harmony
bastion role (`ansible/roles/bastion/tasks/agentic.yml`, task P1.2).

Note the shape this produces, which surprises people: the fleet home *is* a clone of this
repository — firstmate's model is that the cloned repo is the distro — and it then holds a
**second** clone of the same repository under `projects/operator`. That is intended. The
first is the tool; the second is a project the tool works on.

## 2. What is registered

`$FM_HOME/data/projects.md`:

```markdown
- operator [no-mistakes] - the fleet distro itself (pixeloven/operator); self-improvement is PR-gated (O-4, ADR-0005) (added 2026-08-17)
```

The registry format and its parser contract are owned by the header of
`bin/fm-project-mode.sh` — do not restate them elsewhere. Verify a registration by asking
the parser rather than by reading the file:

```console
$ bin/fm-project-mode.sh operator
no-mistakes off

$ bin/fm-project-mode.sh --raw operator
no-mistakes off
```

`--raw` matters when a project is registered under the conditional policy
`no-mistakes-prod-only`: the mechanical output maps it to its most rigorous leg, and only
`--raw` shows the annotation itself. `operator` is registered as a **flat** `no-mistakes`,
not the conditional policy, because O-4 admits no "internal-only" exemption for this
repository — the fleet's own code is never the low-stakes case.

`+yolo` is **off**, and stays off. It is a separate axis from the delivery mode and is
enabled only on the human's explicit instruction.

## 3. Provisioning it

Preconditions: the fleet home is a clone of this repository at a release tag, and the
`no-mistakes` binary is installed from a pinned GitHub release (it is a Go binary — **not**
the npm package of the same name; see [`supply-chain-read.md`](supply-chain-read.md)).

```sh
mkdir -p "$FM_HOME/data" "$FM_HOME/projects"
# add the registry line above to $FM_HOME/data/projects.md
gh repo clone pixeloven/operator "$FM_HOME/projects/operator"
cd "$FM_HOME/projects/operator" && no-mistakes init && no-mistakes doctor
```

`no-mistakes init` is required for `no-mistakes` and `no-mistakes-prod-only` projects and
is skipped for `direct-PR` and `local-only` ones. It configures a local gate remote and
installs the agent-facing skill at user level; it does **not** vendor anything into the
project, and it must not produce a commit.

An `origin` remote is mandatory — a `no-mistakes` project without one cannot deliver.

## 4. What "the posture is active" actually means

Three independent mechanisms have to agree, and it is worth knowing which does what,
because only one of them is visible in this repository:

| Mechanism | Where it lives | What it enforces |
|---|---|---|
| Registry posture | `$FM_HOME/data/projects.md` (machine-local) | What the fleet *intends* — consumed by `fm-fleet-sync.sh`, `fm-home-seed.sh`, and `fm-spawn.sh`'s registry-deviation notice |
| The gate itself | `no-mistakes init` state under `~/.no-mistakes/` | The pipeline a change must pass to become a PR |
| `Require no-mistakes` | `.github/workflows/no-mistakes-required.yml` (upstream, in-repo) | **Server-side refusal** of any PR whose body lacks the pipeline signature |

The third is the one that cannot be bypassed by a mistake on the workstation, and it is
the reason O-4 is a property of the repository rather than of one machine's configuration.
It is an upstream file and is never edited.

A useful consequence, observed during Phase 1: PRs raised by hand — including this
program's own bootstrap PRs — show that check **red**. That is the control working, not a
defect. A red `Require no-mistakes` on a hand-raised PR is evidence the gate is live.

## 5. Verification

Registration and gate initialisation were verified on the harmony bastion, 2026-08-17:

```console
$ no-mistakes doctor
  System
  ✓ git             git version 2.53.0
  ✓ gh              ok
  ✓ data directory  /home/operator/.no-mistakes
  ✓ database        ok
  ✓ daemon          running
  Agents
  ✓ claude          ✓ codex          ✓ pi
  ✓ gate validation  claude is runnable
```

`no-mistakes` runs a persistent daemon under a `systemd --user` unit. Any host that
provisions this posture owns that daemon's lifecycle, and an idempotent bootstrap must
converge the unit and the daemon, not merely the binary.

Two environment settings are required on any host that runs the gate, and are baked into
the bastion role rather than left to the shell:

- `NO_MISTAKES_TELEMETRY=0` — the tool ships default-on analytics. The variable must reach
  the **daemon**, whose generated unit forwards only `HOME`, `PATH`, and proxy variables;
  exporting it in a login shell alone does not disable it.
- `NO_MISTAKES_NO_UPDATE_CHECK=1` — `no-mistakes update` performs a floating upgrade, and
  the tool background-checks for releases on nearly every invocation. A single update
  silently un-pins the fleet, which G-2 forbids.
