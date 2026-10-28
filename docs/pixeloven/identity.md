# Identity — what this project is called, and what stays named `fm`

- **Task:** A1.1
- **Satisfies:** **O-1** (soft fork: additions by default, with the bounded existing-file exceptions listed in [`fork-contract.md`](fork-contract.md)) · **G-7**
  (in prose, "the operator" means the human; the project is written `operator`)
- **Decisions:** [ADR-0001](../adr/0001-soft-fork-of-firstmate.md) (additive default), [ADR-0004](../adr/0004-the-name-operator.md) (the name), and [ADR-0015](../adr/0015-companion-tools-from-upstream-sources.md) (companion tools acquired as upstream does)

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

A persona theme's worker and crew words (for example the bundled `operator`
theme's specialist and squad) are an explicit, documented display translation of
this repository's crewmate and crew, never of a `pixeloven/crew` role; the theme
files and [`persona-themes.md`](persona-themes.md) record them, and the platform
glossary should record them too.

**This repository does not own that resolution and does not restate it.** It
lives in the platform glossary skill, the single owner of the platform's shared
vocabulary: `skills/platform-glossary/SKILL.md` in
[`pixeloven/crew`](https://github.com/pixeloven/crew) — landed as
[PR #59](https://github.com/pixeloven/crew/pull/59), shipped in **crew v0.23.0**
(task A0.4). The repository was `ductiletoaster/harmony-crew` at the time that
merged; it transferred to `pixeloven/crew` in Phase 0.5 (M0.2).

## 3. What is never renamed, and what may be themed

Nothing inside the upstream surface is renamed or rewritten in place - not the scripts, the environment variables, the filenames, the skill names, the record formats, or the vocabulary in upstream text.
What agents say and what people type is themed per home through [ADR-0016](../adr/0016-persona-themed-at-the-edge.md)'s theme layer, which changes display words only, grants no authority, and claims exactly the upstream hunks that ADR lists.

| Surface | Scale at the upstream pin `0e82f3ee` | Stays as-is |
|---|---|---|
| `bin/fm-*` script prefix | **218** scripts | yes |
| `FM_*` environment variables | **1,963** distinct `FM_*` identifiers across **523** tracked files | yes |
| `$FM_HOME` (the fleet home root) | referenced by **352** tracked files | yes |
| Vocabulary in upstream text - captain / crewmate / secondmate / fleet | **15,340** occurrences across **500** files | stays byte-identical in the source; display words themed per home ([ADR-0016](../adr/0016-persona-themed-at-the-edge.md)) |
| Upstream doc filenames (top-level `docs/*.md`) | **38** files | yes |
| `.no-mistakes.yaml`, `.tasks.toml`, `.agents/skills/*` | tool config the upstream toolbelt reads by name | yes; themed slash commands are generated aliases beside the originals |

*(Measured on the upstream pin `0e82f3ee` - **705** tracked files, upstream
only. At the fork point `6789876442d0` the same rows read 138 scripts, 975
identifiers in 306 files, 212 files, 6,888 occurrences in 277 files, and 41
docs. Re-measure with the commands at the end of §5; they drift as upstream
moves.)*

### Why

**Renaming any of it would be a broad upstream rewrite, which remains outside every bounded ADR exception.**

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
4. **Upstream vocabulary is upstream's to change.** We still do not fork the
   dictionary: every upstream file keeps upstream's words, and a theme is a
   per-home display mapping applied at the edge ([ADR-0016](../adr/0016-persona-themed-at-the-edge.md)).

### What *is* ours to name

Our default surface is new files in namespaces upstream can never collide with, while [`fork-contract.md`](fork-contract.md#where-our-code-goes) owns the exact current surface inventory and ADR exceptions.

The delimited PixelOven banner at the top of `README.md` remains ADR-0001's identity exception.
ADRs 0008, 0011 through 0013, 0015, 0016, 0021, and 0022 add exact existing-file allowlists for autonomous delivery, hosted-runner routing, notification reconciliation, archived captain-hold completion, documentation-audience ownership, persona themes, the carried upstream Herdr slash-popup fix, and Claude support for worker tool exclusions.
ADR-0014 is withdrawn and carries no hunks.
Anything outside those lists needs a **new ADR**, not a silent change.

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

Except for A7's affirmative lineage report, A9's affirmative registry report, and A10's and A11's affirmative theme reports, every command below is expected to print **nothing**; any other output is a finding.
The workflow runs exactly these, in this order, and fails the job when a check reports a finding.

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

**A4 - O-1: the diff against the current upstream pin touches only our namespaces and accepted ADR override paths.**
No second ref means this covers the working tree as well as committed history.
An upstream-owned file that carries [ADR-0020](../adr/0020-themes-first-class.md) theme hooks is admitted because the hook registry lists it, and A9 then holds every changed line in it to its registered hook:

```sh
git diff --name-only "$PIN" \
  | grep -vxF -f <(bin/po-theme.sh registry files) \
  | grep -vE '^(docs/pixeloven/|docs/adr/|\.github/workflows/pixeloven-|\.github/SECURITY\.md$|bin/backends/|\.agents/skills/po-|bin/po-[a-z0-9-]+\.sh$|tests/po-[a-z0-9-]+\.test\.sh$|AGENTS\.md$|bin/fm-pixeloven-upstream-check\.sh$|tests/fm-pixeloven-upstream-check\.test\.sh$|\.github/workflows/(ci|no-mistakes-required)\.yml$|bin/(fm-captain-hold|fm-composer-lib|fm-dod-lib|fm-exclude-tools-lib|fm-spawn|fm-delivery-lane|fm-procevent-lib|fm-procevent|fm-wake-lib|fm-watch)\.sh$|docs/examples/crew-exclude-tools$|tests/(fm-backend-herdr|fm-backend-herdr-presentation-e2e|fm-captain-hold-lifecycle|fm-composer-lib|fm-herdr-submit-confirm-live-e2e|fm-lint-workflows|fm-task-delivery|fm-pi-watch-extension|fm-procevent|fm-spawn-dispatch-profile|fm-wake-queue|fm-watch-triage)\.test\.sh$|docs/(captain-hold-lifecycle\.md|configuration\.md|documentation-audiences\.json|remote-secondmates\.md|verification/delivery-lane\.md)$|tests/captures/claude-2\.1\.291-slash-popup/|README\.md$|NOTICE$)'
```

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

**A7 - the operator upstream pin is a canonical upstream ancestor and is contained in this tree.**
This prevents a locally injected or foreign commit from becoming the baseline for A4 and A5.
The lineage check rejects a malformed pin before network access, ignores ambient Git configuration, fetches only the ancestry of `kunchenguid/firstmate`'s default branch, and fails when canonical evidence is unavailable or ambiguous:

```sh
git cat-file -e "${PIN}^{commit}" &&
git merge-base --is-ancestor "$PIN" HEAD &&
bin/fm-pixeloven-upstream-check.sh
```

**A8 - companion tools come from upstream's published sources, never a PixelOven fork** ([ADR-0015](../adr/0015-companion-tools-from-upstream-sources.md)).
Outside the decision and documentation history in `docs/adr/` and `docs/pixeloven/`, no tracked file may name the retired fork installer or select a PixelOven companion-fork repository:

```sh
git grep -nE 'fm-install-pixel''oven-tool|pixeloven/(gh-axi|chrome-devtools-axi|lavish-axi|tasks-axi|quota-axi|no-mistakes)([^A-Za-z0-9._-]|$)' \
  -- . ':!docs/adr/' ':!docs/pixeloven/'
```

The installer name is split in the pattern so the gate's own source cannot match itself.

**A9 - the persona hunks stay exactly as [ADR-0016](../adr/0016-persona-themed-at-the-edge.md) lists them, and every theme hook matches its registry row ([ADR-0020](../adr/0020-themes-first-class.md)).**
`AGENTS.md` may differ from the pin by exactly one added line beginning `Persona: `, and `bin/fm-dod-lib.sh` only by ADR-0016's exact added and removed lines, each at most once, with no mode change on either file:

```sh
changed() { git diff -U0 "$PIN" -- "$1" | grep -E '^[-+]' | grep -vE '^(\+\+\+ b/|--- a/)'; }
changed AGENTS.md | grep -vE '^\+Persona: '
[ "$(changed AGENTS.md | grep -cE '^\+Persona: ')" -le 1 ] || echo 'more than one Persona line'
cat > /tmp/a9-allowed <<'A9'
+EOF
+  "${BASH_SOURCE[0]%/*}/po-theme.sh" worker-line 2>/dev/null || true
+  cat <<'EOF'
-  fm_brief_task_heading_body "$1" "## Captain's intent" | awk '
+  local po_alt; po_alt=$("${BASH_SOURCE[0]%/*}/po-theme.sh" address-alt 2>/dev/null || true)
+  fm_brief_task_heading_body "$1" "## Captain's intent" | awk -v alt="$po_alt" '
+    alt != "" && $0 ~ ("^[[:space:]]*" alt "[:,]") { print; found = 1; exit }
A9
changed bin/fm-dod-lib.sh | grep -vxF -f /tmp/a9-allowed
changed bin/fm-dod-lib.sh | sort | uniq -d
git diff --summary "$PIN" -- AGENTS.md bin/fm-dod-lib.sh | grep 'mode change'
```

In each upstream-owned file `bin/po-theme.sh registry files` lists, every added line must be exactly one row's hook line, at most once, and every removed line must be the upstream line a row says its hook replaces; `registry check-diff` reports an affirmative line when they all match:

```sh
bin/po-theme.sh registry check-diff "$PIN"
```

**A10 - the theme canary** ([ADR-0016](../adr/0016-persona-themed-at-the-edge.md)).
`anchors` fails when upstream changes a literal the `nautical` theme mirrors, adds a user-invocable skill with no alias key, a merge drops a hook line or a registered theme hook, or upstream at the pin no longer has a line a registered hook replaces; `validate` re-checks every bundled theme against the current upstream text.
Both report affirmatively, with notes and warnings, and fail only on a finding:

```sh
bin/po-theme.sh anchors
for t in .agents/skills/po-theme/themes/*.theme; do bin/po-theme.sh validate "$(basename "$t" .theme)"; done
```

**A11 - architectural invariance** ([ADR-0020](../adr/0020-themes-first-class.md)).
In scratch primary and secondmate homes, the hometag, the cmux, zellij, and Paseo routing names, the zellij and herdr session names, the worker role contract without its theme vocabulary line, and the generated definition of done are produced under every bundled theme and must be byte-identical.
It reports affirmatively and fails only on a difference:

```sh
bash tests/po-theme-labels.test.sh a11
```

### Why A4/A5 track a moving pin

`docs/pixeloven/upstream-pin` holds the upstream commit our tree currently
contains. It starts at the fork point and is advanced by **every upstream-merge
PR** — which is the point: the pin is the machine-readable half of
[`upstream-tracking.md`](upstream-tracking.md), so the ledger cannot silently go
stale while the gate keeps passing.
A7 requires this pin to be a real commit contained in this history and an ancestor of the canonical upstream default branch.

### Re-measuring §3

Run these against the upstream pin to reproduce the table exactly
(`git checkout 0e82f3ee`), or against `HEAD` for current values.
They use `git grep -P`, because POSIX ERE has no `\b` and `git grep -E '\b...'` prints 0 on some platforms:

```sh
git ls-files | wc -l                                                  # tracked files
git ls-files 'bin/fm-*' | wc -l                                       # fm-* scripts
git grep -hoP '\bFM_[A-Z0-9_]+' -- . | sort -u | wc -l                # distinct FM_* identifiers
git grep -lP  '\bFM_[A-Z0-9_]+' -- . | wc -l                          # files referencing them
git grep -lP  '\bFM_HOME\b'     -- . | wc -l                          # files referencing $FM_HOME
git grep -ioP '\b(captain|crewmate|secondmate|fleet)' -- . | wc -l    # vocabulary occurrences
git grep -liP '\b(captain|crewmate|secondmate|fleet)' -- . | wc -l    # files using it (union)
git ls-files 'docs/*.md' | grep -c '^docs/[^/]*\.md$'                # top-level doc files
```
