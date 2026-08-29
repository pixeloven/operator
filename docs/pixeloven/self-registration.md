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

Preconditions: the fleet home is a clone of this repository at a release tag, and the `no-mistakes` binary is installed from the exact PixelOven fork source selected by [`bin/fm-install-pixeloven-tool.sh`](../../bin/fm-install-pixeloven-tool.sh).
It is a Go binary, **not** the npm package of the same name.
See [`tool-distribution.md`](tool-distribution.md) for the current source contract and [`supply-chain-read.md`](supply-chain-read.md) for the upstream package audit.

```sh
mkdir -p "$FM_HOME/data" "$FM_HOME/projects"
# add the registry line above to $FM_HOME/data/projects.md
gh-axi repo clone pixeloven/operator "$FM_HOME/projects/operator"
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
| `Require no-mistakes` | `.github/workflows/no-mistakes-required.yml` (inherited, with ADR-0010's bounded PixelOven action source) | **Server-side refusal** of any PR whose body lacks the pipeline signature |

The third is the one that cannot be bypassed by a mistake on the workstation, and it is
the reason O-4 is a property of the repository rather than of one machine's configuration.
It remains upstream-owned except for ADR-0010's exact reusable-action source hunk.

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

### 5.1 Pipeline validation — runs headlessly, blocked on host git config

A1.3's acceptance asks for a test agent-authored change routed through the pipeline. It was
attempted, on this document's own branch. The result is worth recording precisely, because
it is half a pass.

**The headless path exists and works.** `no-mistakes axi` is explicitly non-interactive —
*"prints token-efficient TOON to stdout and is driven entirely by flags (no interactive
prompts)"* — with `run`, `respond`, `status`, `logs`, `abort`, and a guarded `sync`.
`git push no-mistakes <branch>` returned **exit 0** and started a pipeline with no TTY
attached, and `no-mistakes axi run --yes --intent …` drives gates without a human.

**The pipeline genuinely reviews.** On the first attempt the `review` step ran a real agent
review for **248 s** against this document, verifying its claims — including reading
`bin/fm-project-mode.sh` to confirm the `--raw` mapping described in §2. It ended only
because the harness hit its subscription session limit.

**It cannot currently complete on this host.** Re-run after that limit reset, the pipeline
fails at `rebase`, before review:

```console
$ no-mistakes axi status
    intent,completed,0,6
    rebase,failed,0,1533
    review,pending,0,0
error: step rebase failed: git rebase origin/main: exit status 128:
       fatal: either user.signingkey or gpg.ssh.defaultKeyCommand needs to be configured
```

The cause is host git configuration, not the tool. Globally this machine sets
`commit.gpgsign=true`, `gpg.format=ssh`, and `gpg.ssh.program=/opt/1Password/op-ssh-sign` —
but **`user.signingkey` is unset**, and the 1Password SSH agent holds no identities in a
non-interactive context (`ssh-add -L` → *"The agent has no identities"*). Existing repos on
this box work around it individually; harmony's clone carries a local
`commit.gpgsign=false`.

Setting the same locally in the project clone **does not** fix the pipeline, and the reason
matters: the daemon rebases in its own gate repository under `~/.no-mistakes/repos/`, which
inherits the **global** config. That gate repo also has **no `user.email`**, so an
"Author identity unknown" failure waits immediately behind the signing one.

**Status: the posture is registered and enforced; the pipeline check is pending first real
use.** Two host-level gaps have to close first. Both belong to the provisioning task
(harmony's `ansible/roles/bastion/tasks/agentic.yml`), and one needs a human decision that
should not be made silently:

1. **Commit signing.** Either unlock the 1Password SSH agent and set `user.signingkey` from
   `ssh-add -L` — the intent the global config already expresses — or deliberately exempt
   agent-authored commits from signing. Disabling signing machine-wide to unblock a robot
   changes a human's commit provenance across every repository on the box, so it is the
   human's call, not the role's.
2. **Git identity for agent-created clones.** Neither the fleet home nor the gate repo
   inherits a `user.name` / `user.email`, and this host sets none globally. Every fresh
   clone the fleet creates starts unable to commit, and it fails late — inside an agent
   session, at commit time.

Neither is a defect in `no-mistakes`, in the registration, or in the posture itself. Both
would otherwise have surfaced during the first real overnight run, which is the argument
for having attempted the validation rather than asserting it.

Two environment settings are required on any host that runs the gate, and are baked into
the bastion role rather than left to the shell:

- `NO_MISTAKES_TELEMETRY=0` — the tool ships default-on analytics. The variable must reach
  the **daemon**, whose generated unit forwards only `HOME`, `PATH`, and proxy variables;
  exporting it in a login shell alone does not disable it.
- `NO_MISTAKES_NO_UPDATE_CHECK=1` — `no-mistakes update` performs a floating upgrade, and
  the tool background-checks for releases on nearly every invocation. A single update
  silently un-pins the fleet, which G-2 forbids.
