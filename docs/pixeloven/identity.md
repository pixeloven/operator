# Identity — what this project is called, and what stays named `fm`

- **Task:** A1.1
- **Satisfies:** **O-1** (soft fork: upstream edits are limited to ADR-0001 and ADR-0008) · **G-7**
  (in prose, "the operator" means the human; the project is written `operator`)
- **Decisions:** [ADR-0001](../adr/0001-soft-fork-of-firstmate.md) (additive-only),
  [ADR-0004](../adr/0004-the-name-operator.md) (the name),
  [ADR-0008](../adr/0008-documentation-audience-inventory-exception.md) (audience-inventory exception)

This page answers three questions a reader arrives with: *what is this called*,
*why does everything inside it still say `fm`*, and *how do I check that
somebody hasn't quietly broken either answer*.

---

## 1. The name

| | |
|---|---|
| Project | `operator` |
| Repository | `pixeloven/operator` |
| Upstream it forks | [`kunchenguid/firstmate`](https://github.com/kunchenguid/firstmate) |
| Release tags | `v0.1.0`+, semver, cut by us ([ADR-0006](../adr/0006-operator-cuts-its-own-release-tags.md)) |

`firstmate` is the name of the **upstream project**, and every mention of it in
PixelOven-authored text is an attribution or a reference to upstream behaviour —
never this project's own name. That distinction is asserted mechanically in §5.

## 2. The prose rule (G-7)

> **In prose, "the operator" means the human. The project is written `operator`,
> in code style, always lowercase, never capitalized as a proper noun.**

- *"Ask the operator", "the operator approves", "escalate to the operator"* — a
  **person**. This reading wins, unqualified and unhedged. The existing agent
  corpus stays correct without edits, which is the entire point.
- When the project is meant, code-style it: `operator`. If a sentence is still
  ambiguous, write "the `operator` project" or "the `operator` repo".
- **Never "Operator".** Capitalization is invisible at the start of a sentence —
  exactly where *"The operator should…"* appears — so it cannot carry the
  distinction. ADR-0004 rejected it for that reason.

Kubernetes "operators" (controllers reconciling a custom resource) are a third
sense, normally disambiguated by their neighbouring nouns. No mitigation beyond
awareness.

### The crew / crewmate overlap

This fork's lineage and the agent foundation both use the word **crew**, meaning
different things:

| Vocabulary | "crew" means | the human is | a worker is |
|---|---|---|---|
| firstmate lineage (this repo) | the **fleet of dispatched worker processes** in a running session | **the captain** | a **crewmate** / **secondmate** |
| the agent foundation (`pixeloven/crew`) | the **set of declarative agent roles** (lead, implementer, reviewer, …) | **the operator** | a dispatched **role** |

"The captain" and "the operator" denote the **same human** in a session that
spans both. Do not introduce a third name for that person, and never translate
between the two vocabularies silently — a crewmate is a running process in a git
worktree; a crew role is a capability definition.

**This repository does not own that resolution and does not restate it.** It
lives in the platform glossary skill, the single owner of the platform's shared
vocabulary: `skills/platform-glossary/SKILL.md` in
[`pixeloven/crew`](https://github.com/pixeloven/crew) — landed as
[PR #59](https://github.com/pixeloven/crew/pull/59), shipped in **crew v0.23.0**
(task A0.4). The repository was `ductiletoaster/harmony-crew` at the time that
merged; it transferred to `pixeloven/crew` in Phase 0.5 (M0.2).

## 3. What is deliberately *not* renamed

Nothing inside the upstream surface is renamed. Not the scripts, not the
environment variables, not the vocabulary, not the filenames.

| Surface | Scale at the fork point | Stays as-is |
|---|---|---|
| `bin/fm-*` script prefix | **138** scripts | yes |
| `FM_*` environment variables | **975** distinct `FM_*` identifiers across **306** tracked files | yes |
| `$FM_HOME` (the fleet home root) | referenced by **212** tracked files | yes |
| Vocabulary — captain / crewmate / secondmate / fleet | **6,888** occurrences across **277** files | yes |
| Upstream doc filenames (`docs/*.md`) | **41** files | yes |
| `.no-mistakes.yaml`, `.tasks.toml`, `.agents/skills/*` | tool config the upstream toolbelt reads by name | yes |

*(Measured on the fork point `6789876442d0` — **401** tracked files, upstream
only. Re-measure with the commands at the end of §5; they will drift as upstream
moves, and the `docs/*.md` pathspec is repo-wide so it counts our documents too
once they exist.)*

### Why

**Renaming any of it means editing upstream files outside the two bounded exceptions, which this fork does not do.**

1. **It breaks the merge contract (O-1 / O-2).** The soft fork is cheap *only*
   because our changes and upstream's changes never touch the same lines. A
   rename of `fm-` → `po-` would rewrite 138 filenames and ~300 files, turning
   every subsequent upstream merge from a fast-forward into a conflict
   resolution exercise across the whole tree — permanently, on every merge,
   forever. That cost recurs; the rename is paid once and then billed monthly.
2. **The names are load-bearing, not cosmetic.** `FM_HOME`, `FM_BACKEND`,
   `FM_SERIAL_LANE` and their ~970 siblings are the interface between the
   scripts, the test harness, the toolbelt (`.tasks.toml` *is* tasks-axi's
   config), and any agent session already running. `$FM_HOME` is a real
   directory on a real machine. Renaming an environment variable is an
   API break disguised as a find-and-replace.
3. **The benefit is zero.** No consumer types `fm-spawn.sh`; consumers pin
   `operator` release tags (O-3) and run what the distro provides. The user-facing
   identity is the repository name, the README banner, the tags, and these docs —
   all of which say `operator` already.
4. **Upstream vocabulary is upstream's to change.** captain/crewmate/secondmate
   is firstmate's product language. We consume it; we do not fork the dictionary.

### What *is* ours to name

Our surface is new files only, in namespaces upstream can never collide with:

| Surface | Path |
|---|---|
| Runtime backends | `bin/backends/` |
| Skills | `.agents/skills/po-*` |
| Documentation | `docs/pixeloven/` |
| Decisions | `docs/adr/` |
| CI we own | `.github/workflows/pixeloven-*.yml` |

Two bounded upstream-file exceptions exist: the delimited PixelOven banner block at the top of `README.md` under ADR-0001, and fork-prose classifications in `docs/documentation-audiences.json` under [ADR-0008](../adr/0008-documentation-audience-inventory-exception.md).
Anything outside this list needs a **new ADR**, not a silent change.
See [fork-contract.md](fork-contract.md).

## 4. Erratum on ADR-0004

ADRs are never edited after acceptance — a decision that changes gets a new ADR.
One factual reference inside an accepted ADR has since moved, and is corrected
here rather than in the ADR:

- **ADR-0004 names the identity tier `wetware`** (in its component list and its
  "alternatives considered" section). That name was **retracted** and was never
  operator-ratified. The identity tier is **`crew`** — `pixeloven/crew`, per
  program-plan decision **D-03** as amended 2026-08-17. `wetware` and `lifepath`
  remain recorded only as vetted-clean bench candidates.
- Nothing else in ADR-0004 is affected: the decision it records is about the name
  `operator` and the human/project prose rule, both of which stand unchanged.

## 5. Assertions — the grep evidence

These are the checks behind A1.1's "grep clean". They are **also run on every
pull request** by [`.github/workflows/pixeloven-gates.yml`](../../.github/workflows/pixeloven-gates.yml)
(job `fork-contract`), so this section is a description of a live gate rather
than a one-time claim.

Every command below is expected to print **nothing**. Any output is a finding.
The workflow runs exactly these, in this order, and fails the job on any output.

```sh
# The upstream commit our tree currently contains - NOT the frozen fork point.
# A4/A5 ask "what have WE changed on top of upstream", so the baseline has to
# move when we merge upstream; anchoring on the fork point reports upstream's
# own commits as our modifications. The A1.4 rehearsal found this the hard way
# (see upstream-merges.md). Every upstream-merge PR advances this file.
PIN=$(tr -d '[:space:]' < docs/pixeloven/upstream-pin)

# The PixelOven-authored prose corpus: the README banner block, NOTICE, and our
# two doc namespaces. The rest of README.md is upstream's and is not ours to
# police. Fenced code blocks are stripped, because this section quotes the very
# patterns the assertions look for and would otherwise match itself.
banner() { sed -n '/<!-- PIXELOVEN-FORK-BANNER:START -->/,/<!-- PIXELOVEN-FORK-BANNER:END -->/p' README.md; }
corpus() {
  { banner; cat NOTICE; find docs/pixeloven docs/adr -name '*.md' -exec cat {} +; } \
    | awk '/^```/{f=!f; next} !f'
}
```

**A1 — the project is never named `firstmate`.** No PixelOven-authored line
claims firstmate as this repository's own identity:

```sh
corpus | grep -niE 'pixeloven/firstmate|(this|the) (repo|repository|project) is (a |the )?firstmate|named? firstmate'
```

**A2 — every self-referential PixelOven URL points at a real PixelOven repo.**
Anchored on the host so that `docs/pixeloven/…` paths are not false positives:

```sh
corpus | grep -oE 'github\.com/pixeloven/[A-Za-z0-9._-]+' | sed 's/\.git$//' | sort -u \
       | grep -vE '^github\.com/pixeloven/(operator|crew|pulse|lattice|ci)$'
```

**A3 — the project is never capitalized as a proper noun** (G-7). Two files are
exempt because they *state* the rule and therefore quote the rejected form:
ADR-0004 and this page.

```sh
{ banner | grep -nE '\bOperator\b'
  grep -nE '\bOperator\b' NOTICE
  find docs/pixeloven docs/adr -name '*.md' \
       ! -name 'identity.md' ! -name '0004-the-name-operator.md' -print0 \
    | xargs -0 grep -nE '\bOperator\b'; }
```

**A4 — O-1: the diff against the current upstream pin touches only our
namespaces.** No second ref, so this covers the working tree as well as
committed history:

```sh
git diff --name-only "$PIN" \
  | grep -vE '^(docs/pixeloven/|docs/adr/|\.github/workflows/pixeloven-|bin/backends/|\.agents/skills/po-|README\.md$|NOTICE$|docs/documentation-audiences\.json$)'
```

**A4.1 - the ADR-0008 exception cannot broaden.**
The workflow parses the current and upstream inventories, requires every policy field and upstream surface to remain semantically identical, and permits added classifications only under `docs/adr/` and `docs/pixeloven/`.
It also requires the inventory path to retain its upstream regular-file mode before parsing it.
The executable assertion in `pixeloven-gates.yml` is the single owner of that comparison.

**A5 — the README exception stays one bounded block.** Strip the banner and what
remains is byte-identical to upstream's README at the pin:

```sh
git show "$PIN":README.md > /tmp/upstream-README.md
sed '/<!-- PIXELOVEN-FORK-BANNER:START -->/,/<!-- PIXELOVEN-FORK-BANNER:END -->/d' README.md \
  | sed '1{/^$/d}' \
  | diff - /tmp/upstream-README.md
```

**A6 — upstream's own repo invariant holds** (personal fleet paths untracked):

```sh
git ls-files -- data state config projects .no-mistakes
```

**A7 - the recorded upstream pin is real, contained in this tree, and on canonical upstream main.**
This stops a fork commit from becoming the baseline for A4, A4.1, and A5, and stops the pin from advancing without an actual upstream merge.

```sh
git cat-file -e "${PIN}^{commit}"
git merge-base --is-ancestor "$PIN" HEAD
git fetch --quiet --no-tags https://github.com/kunchenguid/firstmate.git refs/heads/main
git merge-base --is-ancestor "$PIN" FETCH_HEAD
```

### Why A4/A5 track a moving pin

`docs/pixeloven/upstream-pin` holds the upstream commit our tree currently
contains. It starts at the fork point and is advanced by **every upstream-merge
PR** — which is the point: the pin is the machine-readable half of
[`upstream-tracking.md`](upstream-tracking.md), so the ledger cannot silently go
stale while the gate keeps passing.
A7 refuses a pin that is not a real commit contained in this history and on canonical upstream main, so a fork commit cannot redefine the trusted baseline.

### Re-measuring §3

Run these against the fork point to reproduce the table exactly
(`git checkout 6789876442d0`), or against `HEAD` for current values:

```sh
git ls-files | wc -l                                                  # tracked files
git ls-files 'bin/fm-*' | wc -l                                       # fm-* scripts
git grep -hoE '\bFM_[A-Z0-9_]+' -- . | sort -u | wc -l                # distinct FM_* identifiers
git grep -lE  '\bFM_[A-Z0-9_]+' -- . | wc -l                          # files referencing them
git grep -lE  '\bFM_HOME\b'     -- . | wc -l                          # files referencing $FM_HOME
git grep -ioE '\b(captain|crewmate|secondmate|fleet)' -- . | wc -l    # vocabulary occurrences
git grep -liE '\b(captain|crewmate|secondmate|fleet)' -- . | wc -l    # files using it (union)
git ls-files 'docs/*.md' | wc -l                                      # doc files (pathspec is repo-wide)
```
