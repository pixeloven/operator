# Team setup: dotfiles, herdr, and `operator`

This page is the onboarding guide for an engineer new to the PixelOven agent setup.
It walks the stack in the order it is built: the machine (`pixeloven/dotfiles`), the workspace (herdr), and the agents (`operator`), plus the pieces that run through all three: `crew` with its skill packs and plugin catalogue, and no-mistakes.
It explains how the parts fit and points at each part's own documentation, which stays the owner of exact commands and settings.
Appendix A is a script for a live demo of the whole stack.

## 1. The stack in one picture

One person runs a team of AI coding agents from one chat.
That person is the operator.
The stack has three layers, and each layer installs or configures the next:

```
+---------------------------------------------------------------------------+
| 1. MACHINE - dotfiles (chezmoi + Homebrew)                                |
|    minimal default: terminal, shell, herdr, agent CLIs, git tooling       |
|    opt-ins you choose: tool sets (voice, aws, kubernetes, ...),           |
|    workstation apps (Blender, Comfy Desktop, ...), machine settings       |
|    also installs crew and its packs into every agent CLI                  |
+---------------------------------------------------------------------------+
| 2. WORKSPACE - herdr (agent-aware terminal multiplexer)                   |
|    one workspace per supervising agent, one tab per worker,               |
|    live busy / idle / needs-you state in the sidebar                      |
+---------------------------------------------------------------------------+
| 3. AGENTS - operator (an agent distro, a soft fork of firstmate)          |
|    you <-> spotter (one chat)                                             |
|              |-- specialists (one per task, each in its own git worktree) |
|              |-- navigators  (optional long-lived spotters with own home) |
|    work ships through no-mistakes -> PR -> your merge decision            |
+---------------------------------------------------------------------------+
  Running through all three: crew (method skills + roles) and its four skill packs,
  released together on one crew tag and installed by dotfiles.
```

| Piece | What it is | Where it comes from |
|---|---|---|
| dotfiles | Machine setup as code, with chezmoi and a Homebrew `Brewfile` | `pixeloven/dotfiles` |
| herdr | A terminal workspace that shows each agent pane's state natively | [herdr.dev](https://herdr.dev), configured by dotfiles |
| Agent CLIs | Claude Code, Codex, and pi, the harnesses the agents run in | Installed by dotfiles |
| `operator` | An agent distro: a cloned directory of instructions, skills, and scripts that turns an agent CLI started inside it into your spotter | [`pixeloven/operator`](https://github.com/pixeloven/operator), a soft fork of firstmate |
| treehouse | Gives every task its own disposable git worktree | Required by `operator` |
| no-mistakes | A local git proxy that runs a validation pipeline before code reaches the remote | Required by `operator` |
| `crew` and packs | Methodology skills and role definitions for every agent, plus four domain skill packs under `packs/` | [`pixeloven/crew`](https://github.com/pixeloven/crew) |
| Plugin catalogue | The `pixeloven` marketplace that serves `crew` and its packs; adding it at a release tag pins them all together | `.claude-plugin/marketplace.json` in `pixeloven/crew`; the old `pixeloven/marketplace` repository is retired and points there |

## 2. Vocabulary

`operator` is a soft fork of the open-source firstmate project, which speaks in nautical words.
PixelOven homes usually run the bundled operator persona theme, which changes only the words the agents say and the slash commands you type.
Rules, file names, and script names keep the upstream words, so you will see both sets.
[Persona themes](persona-themes.md) owns the theme format, and `.agents/skills/po-theme/themes/operator.theme` holds these words.

| operator theme | nautical default | Meaning |
|---|---|---|
| operator | captain | You, the person in charge |
| spotter | first mate | The one agent you talk to; it plans, dispatches, supervises, and reports |
| specialist | crewmate | A worker agent doing one task in its own worktree |
| squad | crew | All of the spotter's workers |
| navigator | second mate | An optional long-lived spotter with its own home and scope |
| task force | fleet | Everything in flight |
| deploy | ship task | A task that changes code and ends in a PR or merge |
| recon | scout task | A task that ends in a written report and never a PR |
| `/sitrep` | `/bearings` | Where did I leave off: what is in flight, what needs you, what is next |
| `/debrief` | `/ahoy` | Recap this session and walk through decisions still waiting on you |
| `/flush` | `/stow` | Save what this session learned into durable memory |
| `/updateoperator` | `/updatefirstmate` | Update the distro and restart cleanly |

Three naming rules prevent confusion:

- "The operator" is a person; the project is always written `operator`, in code style and lowercase ([identity](identity.md)).
- "Deploy" is a task type; shipping software to an environment is a release or a rollout.
- `crew` always means the PixelOven plugin, because the operator theme calls the workers a squad.

In herdr's sidebar the theme also renames workspaces: `spotter` for the main home and `navigator-<id>` for each navigator.

## 3. Layer 1 - the machine: dotfiles

### 3.1 Start minimal, then choose

A fresh install gives you a minimal default, and everything heavier is a named opt-in that you turn on only if you want it.
dotfiles does this with chezmoi's own data keys and two small commands, `toolsets` and `workstation-apps`.
The dotfiles README section "What a fresh install gets" owns the exact lists.

| Group | Fresh install | Turn on or off |
|---|---|---|
| Terminal and shell: Ghostty (or your Linux terminal), JetBrains Mono, zsh with Starship and its plugins, fzf, zoxide, eza, bat, git-delta, glow, tmux | Always | Not optional |
| Tooling the agents and `operator` lean on: `gh`, `jq`, Node through fnm, `uv`, the 1Password CLI, and `bats-core`, `shellcheck`, `gitleaks` | Always | Not optional |
| herdr CLI, Claude Code, Codex | On (ticked by default) | `workstation-apps enable <app>` / `disable <app>` |
| `crew` and its four packs from `pixeloven/crew` at its release tag, plus the Impeccable design skill, in every installed agent CLI | On | `agentPlugins = false` opts out |
| Tool set `voice`: VoiceInk on macOS, ffmpeg, and on Linux the audio and local speech-to-text packages for spoken alerts and `dictate` | Off | `toolsets on voice` / `toolsets off voice` |
| Tool set `aws`: the AWS CLI | Off | `toolsets on aws` / `toolsets off aws` |
| Tool sets `kubernetes`, `talos`, `terraform`, `ansible`, `containers` | Off | `toolsets on <set>` / `toolsets off <set>` |
| Workstation apps: Herdr desktop, the Claude and ChatGPT desktop apps | Off | `workstation-apps enable <app>` |
| Workstation apps: Blender and Comfy Desktop | Off | `workstation-apps enable blender comfyui` |
| Linux machine settings: NFS network shares with FS-Cache, Comfy Desktop model folders | Off | `~/.config/dotfiles/settings.toml`, checked by `dotfiles-settings check` |
| Persona theme for an `operator` home | Off | `operatorPersona` in your chezmoi config |

How the choices behave:

- `chezmoi init` asks the tool sets and workstation apps once, as checkboxes, and saves the answers in your untracked `~/.config/chezmoi/chezmoi.toml`.
- Every later `chezmoi apply` installs exactly that selection, so rebuilding a machine is one command.
- Turning something off never uninstalls it; `toolsets off <set> --uninstall` removes a set's tools as well.
- Blender and Comfy Desktop are pinned and checksum-checked where dotfiles installs them from a vendor tarball or package, and no models are downloaded.
- A machine set up before `voice` and `aws` became tool sets keeps those packages; `toolsets on voice aws` keeps them managed.

### 3.2 What else dotfiles manages

- herdr's config, `~/.config/herdr/config.toml`.
- Claude Code and Codex settings, patched key by key so your own settings are never overwritten.
- Spoken "done" and "needs you" alerts, muted with `voice mute`.
- `/lastreply`, which renders an agent's replies in a side pane, and `/codify`, which records a hand-made config change back into the repo.
- No secrets: files that can hold them are blocked by a pre-commit hook and by CI, and secrets come from 1Password or the OS keychain.

### 3.3 Install

On a Mac:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install chezmoi
chezmoi init --apply --source ~/Development/dotfiles pixeloven
```

Then follow the dotfiles `RUNBOOK.md` for the steps a script cannot do: Ghostty permissions, oh-my-zsh, Node through fnm and the global npm tools, and your git name and email, which dotfiles never sets.
On Linux, including inside a distrobox, start at RUNBOOK section 9.
RUNBOOK section 1's "Done when" check is the proof: `bats ~/Development/dotfiles/tests/` passes, and `lib/agent-plugins.sh check` and `lib/impeccable.sh check` print nothing.

### 3.4 Day to day

- `chezmoi diff` shows the repo against your machine, and `chezmoi apply` makes the machine match the repo.
- Changed something by hand: run `/codify` in Claude Code; a new session also tells you when there is something to codify.
- `toolsets` and `workstation-apps preview` show your opt-ins and their install state.

## 4. Layer 2 - the workspace: herdr

herdr is an agent-native terminal multiplexer: like tmux, but it knows when the agent in a pane is busy, idle, or waiting for you, and shows that in its sidebar.

- dotfiles writes its config; run `herdr integration install claude` once, and `herdr integration install pi` if you use pi.
- After editing the config, `herdr server reload-config` and `herdr config check` apply and verify it.
- Start the spotter inside herdr and `operator` selects herdr as its runtime backend automatically; [the herdr backend page](../herdr-backend.md) owns selection, versions, and limits.
- The spotter and each navigator have a workspace, and each specialist gets its own tab or, on newer herdr, its own one-task workspace.
- Opt-in project groups tag and sort tasks by project in the sidebar.
- You can click into any specialist's tab to watch it work, but you rarely need to: the spotter reads specialist state for you.
- Typing into a specialist's pane yourself counts as your instruction, and the spotter reconciles it at its next review.

The `herdr` CLI multiplexer is the backend `operator` drives by default.
The Herdr desktop app and its core are a separate preview product with an experimental backend ([hc backend](../hc-backend.md)), and dotfiles offers the desktop app as an opt-in.

## 5. Layer 3 - the agents: `operator`

### 5.1 What it is

`operator` is an agent distro: a portable directory of instructions, skills, tooling, policies, and state conventions that turns a general-purpose agent CLI into a specialized one.
There is no app to install; the cloned repository is the distro, and starting an agent CLI inside it makes that agent your spotter.
It is a soft fork of firstmate under a written [fork contract](fork-contract.md), it cuts its own semver tags ([releases](releases.md)), and its PixelOven additions are prefixed `po-`.

### 5.2 Install and launch

```sh
gh auth login
git clone https://github.com/pixeloven/operator ~/Development/operator
git -C ~/Development/operator checkout <latest release tag>
cd ~/Development/operator && claude
```

Run the last line inside a herdr pane.
`~/Development/operator` is the default home dotfiles looks for when it applies a persona theme or the `crew` fence.
Claude Code, Grok, and pi are the co-recommended agent CLIs for the spotter, and the upstream README lists every other supported one.

At startup the spotter checks its tools and prints one line for each missing or outdated tool, with its install command, and offers to install after you approve.
The toolchain section of [configuration](../configuration.md) owns the required list, which includes no-mistakes, treehouse for the herdr backend, and the `gh-axi`, `chrome-devtools-axi`, `tasks-axi`, and `quota-axi` agent tools.
dotfiles does not install those; the spotter's offer is the supported path.

### 5.3 The home

The clone is your home.
Its tracked files are the shared instructions; everything personal is gitignored and stays on your machine:

| Path | Holds |
|---|---|
| `config/` | Local choices such as the backend, theme, design system, and optional monitors |
| `data/` | Durable records: the backlog, the project registry, recon reports, and preferences |
| `state/` | Runtime records such as each task's status log |
| `projects/` | Read-only clones of the projects the spotter manages |

All state lives on disk and in the terminal backend, so a restarted spotter reconciles from those records rather than from chat memory.

### 5.4 The spotter's rules

These rules are why a team can trust the setup; section 1 of [`AGENTS.md`](../../AGENTS.md) and [`VISION.md`](../../VISION.md) own them.

1. You talk only to the spotter, and specialists report to the spotter, never to you.
2. The spotter reads your projects but never edits them; every change is a specialist's job in an isolated worktree.
3. No PR merges without your explicit word, unless you opted that project into `yolo` merge autonomy, which covers only green, in-scope work.
4. Unlanded work is never thrown away without your explicit say-so.
5. The spotter reports outcomes, consequences, and decisions you need to make, with PR links, not internal mechanics.

### 5.5 How a request flows

```
you: "fix the flaky login test in project X"
  -> spotter picks the project, classifies the work (deploy or recon),
     writes the instructions, files a backlog item
  -> spawns a specialist in a fresh treehouse worktree, in a new herdr tab
  -> a zero-token watcher wakes the spotter only when something changes
  -> specialist implements, then follows the project's delivery mode
  -> spotter: "fix is ready, PR <url>, checks green - merge?"
  -> you: "merge"  -> spotter merges through its guarded path and cleans up
```

Each project's delivery mode lives in the home's project registry:

| Mode | What the specialist does |
|---|---|
| `no-mistakes` | Runs the full validation pipeline through to a PR and green CI |
| `direct-PR` | Pushes and opens a PR without the pipeline |
| `local-only` | Leaves a clean local branch, which the spotter fast-forwards after your approval |

`+yolo` is a separate per-project flag that hands merge authority for green, in-scope work to the spotter.

### 5.6 Navigators

A navigator is a persistent spotter with its own isolated home: its own backlog, projects, records, and lock.
It has a written scope, the main spotter routes in-scope work to it, and it is idle until work arrives.
Navigators separate work areas, such as open-source work and day-job work, so each keeps its own records and allowed tools.
Ask the spotter to create one rather than building one by hand; navigators can also run on another machine you reach over SSH ([remote second mates](../remote-secondmates.md)).

### 5.7 Commands you will use

| You type | What happens |
|---|---|
| Plain English | Most of the time: ask for a fix, an investigation, a plan, or a review |
| `/sitrep` | Status digest |
| `/afk`, `/quiet` | You are stepping away; the spotter keeps supervising and escalates only what needs you |
| `/flush` | Save what this session learned before a reset |
| `/updateoperator` | Update the distro and its navigators |

## 6. Running through every layer: `crew`, its packs, and the catalogue

`crew` is PixelOven's portable agent foundation: one catalogue of methodology skills (planning, plan validation, orchestration, PR review, seam detection, decision records, incident runbooks, onboarding, and more) and shared role definitions such as lead, implementer, investigator, researcher, reviewer, and triage.
It works in Claude Code, Codex, and pi.

The `pixeloven/crew` repository also holds four skill packs under `packs/<name>`, each still its own plugin that ships skills only:

| Pack | Covers |
|---|---|
| `infra-skills` | Terraform, Ansible, Kubernetes, and GitHub Actions conventions, infrastructure seams, Kubernetes diagnostics, go-public review |
| `planning-skills` | Idea shaping, requirements review, readiness gates, story breakdown, cross-functional review, tracker sync |
| `identity-skills` | Auth seams, flow tracing, funnel signatures, account investigation, vendor config review |
| `language-skills` | One skill per language, Python first |

`crew` and every pack share one semver release line, and one release tag such as `v0.67.0` pins them all together.
The plugin catalogue, the `pixeloven` marketplace, is `crew`'s own `.claude-plugin/marketplace.json`.
Claude Code and Codex add that marketplace from `pixeloven/crew` pinned to a release tag, and pi installs the `crew` package, which carries the packs, from the tag directly.
The tag is the release gate: a machine that followed the default branch instead would receive every change as it merges.
Each release's CHANGELOG section opens with "Consumer impact", which says whether moving to that tag needs any action.
Plugin names such as `crew@pixeloven` and `infra-skills@pixeloven`, and every skill name, are the same as before the packs moved into `crew`.

dotfiles installs `crew` and all four packs at user scope for every installed agent CLI, from `pixeloven/crew` at its release tag, so every specialist has them in every project.
`crew` also documents enabling packs per project to trim each session's skill listing; that is an option, and the setup's default is user-wide.

| Step | Owner |
|---|---|
| Install `crew` and the packs at the release tag on every `chezmoi apply` | dotfiles |
| Move a machine to a new `crew` release tag | `~/Development/dotfiles/lib/agent-plugins.sh update`, run by hand |
| Keep `crew` out of the spotter's own session, so the supervisor stays a supervisor | `bin/po-crew.sh fence` in the home, which dotfiles runs |
| Prove it | `bin/po-crew.sh check`, read-only and token-free, or `/crew:doctor` inside a session |

Never run `claude plugin marketplace remove pixeloven` to fix or move the catalogue, because it uninstalls every `crew` plugin; dotfiles' update command moves the tag safely.

[`crew` on every machine](crew.md) and [ADR-0019](../adr/0019-crew-machine-level-delivery.md) own this delivery path.

## 7. The validation pipeline: no-mistakes

no-mistakes is a local git proxy that validates code before it reaches the remote.

- In a `no-mistakes` project the specialist runs the pipeline instead of pushing: code review, tests, lint, and docs, then push, PR, and CI.
- The pipeline applies its own fixes; nobody hand-edits the branch while a run is active.
- A finding only a human can decide goes to the spotter, never back to the specialist that wrote the code.
- One daemon serves every task on the machine, and only the spotter manages it.
- You can use it on your own branches too: `no-mistakes init` once per repository, or `/no-mistakes` in Claude Code.

## 8. Other parts you will meet

- treehouse: a pool of disposable git worktrees, one per task, so parallel tasks in one repository never collide.
- The agent tools: `gh-axi` for GitHub, `chrome-devtools-axi` for a browser, `tasks-axi` for the backlog, `quota-axi` for usage limits, and the optional `lavish-axi` for interactive review pages.
- Design systems: generated pages such as status boards take their look from a selectable [design system](design-systems.md).
- Voice: spoken alerts are on by default, and push-to-talk dictation comes with the `voice` tool set; dotfiles RUNBOOK sections 4 and 5 own the setup.

## 9. Your first day

1. Machine: run the dotfiles bootstrap, keep the minimal default, and tick only the opt-ins you need; RUNBOOK section 1's "Done when" passes.
2. Sign-ins: `gh auth login`, each agent CLI, and your git name and email by hand.
3. herdr: start it and run `herdr integration install claude`.
4. Distro: clone `operator` at a release tag, start `claude` in it inside herdr, and approve the tool installs the spotter offers.
5. Theme, optional: set `operatorPersona = "operator"` under `[data]` in your chezmoi config and run `chezmoi apply`; dotfiles calls the home's own `bin/po-theme.sh`.
6. Prove it: `bin/po-crew.sh check` shows no `fail` row, `/sitrep` answers, and one small recon on a repository you know makes a specialist tab appear in herdr.
7. Projects: ask the spotter to add one, for example "add project owner/repo as direct-PR"; it clones the project read-only and records its delivery mode.
8. Later, if useful: ask the spotter for a navigator for a separate work area.

Your home's backlog, reports, learnings, and preferences are a personal record, not setup, so they never transfer between people.

## 10. When something looks wrong

| Symptom | Check |
|---|---|
| A tool is missing | The spotter's startup lines name it with its install command |
| A specialist lacks `crew` skills | `bin/po-crew.sh check`: `not installed` needs `chezmoi apply`, and `behind` needs `lib/agent-plugins.sh update` |
| The spotter itself lists `crew:` skills | The fence is missing: `bin/po-crew.sh fence` |
| herdr ignores a config change | `herdr config check` |
| The machine drifted from the repo | `/codify`, or `~/Development/dotfiles/bin/drift` |
| Theme words look stale | `bin/po-theme.sh verify`, then `apply` in the main home |

## Appendix A - live demo script

About 25 minutes.

Prepare beforehand, so nothing in the demo pushes to a real project:

- A machine with the stack installed and the operator theme applied.
- A sandbox repository registered as `local-only`, with a tiny planted change such as a README typo.
- Optionally a second sandbox registered as `no-mistakes`, with a PR the pipeline already took to green, so the result shows without waiting on CI live.
- herdr open on the `spotter` workspace with an empty task force.

| # | Show | Point | Time |
|---|---|---|---|
| 1 | The stack picture and the vocabulary | Three layers, each installs the next; our words and upstream's | 3 min |
| 2 | `toolsets`, then `workstation-apps preview` | The default is minimal; Blender, Comfy, voice, and cluster tools are opt-ins; off never uninstalls | 3 min |
| 3 | `chezmoi diff`, then the herdr config | The machine is code, and `/codify` catches hand edits | 2 min |
| 4 | herdr's sidebar, then `cd ~/Development/operator && claude` | One startup check of tools, records, and work in flight | 3 min |
| 5 | `/sitrep` | One digest of what needs me | 1 min |
| 6 | "in sandbox, fix the README typo" | A specialist tab appears, working in its own worktree | 5 min |
| 7 | The spotter reports a ready branch; answer "merge" | Nothing lands without my word, except projects I opt into `yolo` | 2 min |
| 8 | The pre-greened PR in the `no-mistakes` sandbox | Review, tests, lint, docs, and CI ran before a human looked | 3 min |
| 9 | `/crew:doctor` in a specialist pane, then `bin/po-crew.sh check` in the home | Every agent has the same method skills; the spotter is fenced | 2 min |
| 10 | The first-day checklist | Hand out this page | 1 min |

If the live run stalls, fall back to screenshots of steps 6 to 8 captured during a dry run.
Never fix the demo by hand inside a specialist's worktree, because that is exactly what the setup is designed to avoid.
