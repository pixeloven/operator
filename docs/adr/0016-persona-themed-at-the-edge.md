# ADR-0016: Persona and vocabulary are themed at the edge, never rewritten in place

- **Status:** Accepted
- **Date:** 2026-10-21
- **Deciders:** Brian Gebel (the operator)
- **Source:** Captain decisions of 2026-10-21 on the persona customization design (questions Q1 through Q5)
- **Supersedes:** the vocabulary clause of [`identity.md`](../pixeloven/identity.md) §3 ("Nothing inside the upstream surface is renamed ... not the vocabulary") and the matching sentence in [`fork-contract.md`](../pixeloven/fork-contract.md); ADR-0001's additive default and ADR-0004's name and prose rule stand.

## Context

The operator wants the agents' persona and vocabulary to be completely replaceable, so that a home can trade the nautical captain, first mate, crewmate, and fleet voice for another one while upstream synchronizations stay cheap.
The chosen replacement for `operator` itself is a military voice rather than a cyberpunk one.

Upstream shipped 477 commits in the 50 days before this decision, about 9.5 a day, and its nautical vocabulary grew from 6,888 to 15,340 occurrences in two months.
Replaying that history week by week showed an in-place rename conflicting on 26 to 112 files a week, and 9 to 39 files a week for prose alone.

The vocabulary is also three different things: identifiers that code parses, canonical instruction text that the agent reads and that states every authority rule, and display words that a person reads or types.
Rewriting the instruction text is the riskiest change available, because "operator" already carries about 460 other meanings in upstream text, including the user/operator role of a home.

Upstream already prints `data/captain-shared.md` in every session-start digest and propagates it read-only to every second mate, already makes the agent translate internal words before speaking, and already limits the address rule to chat.
Nearly everything a person reads in a session is written by the agent, so changing what the agent says covers almost every surface without touching what it reads.

## Decision

1. Upstream text, identifiers, and record formats stay byte-identical.
   A theme never renames an identifier and never rewrites an upstream file.
2. A home selects a theme in the gitignored `config/po-theme`; bundled themes live in `.agents/skills/po-theme/themes/`, and local ones in `config/po-themes/`.
   `nautical` is the code default, mirrors upstream's literals, and writes nothing, so a home without a selection is byte-for-byte upstream.
3. `bin/po-theme.sh apply` renders the selected theme into a delimited Persona block in the primary home's `data/captain-shared.md`.
   The block changes display words for chat only, grants no authority, and changes no rule.
   It carries a machine-readable values line, so a second mate's scripts resolve the same theme, including a custom theme that exists only in the primary home, and validate it before use.
4. Exactly these upstream hunks are permitted, and nothing else:
   - one inserted line in `AGENTS.md`, beginning `Persona: `, after "This file is your entire job description.", making the block authoritative for chat words;
   - in `bin/fm-dod-lib.sh`, one worker-vocabulary call in `fm_brief_worker_role` (H4), which prints nothing under `nautical`;
   - in `bin/fm-dod-lib.sh`, the themed vocative in `fm_brief_intent_address_line` (H5), so the guard that keeps direct address out of no-mistakes intent does not weaken under a theme.
5. Slash-command aliases are generated per primary home as alias skills, never tracked, and excluded through a delimited block of `.git/info/exclude`, so the guarded self-update still sees a clean tree.
6. Theme values are validated before every use: complete keys against the `nautical` schema, no authority words, markup, URLs, or control characters, distinct roles, no protocol or harness tokens, and an explicit `avoid.<word>` entry wherever the user or self term already has another meaning upstream.
7. This ADR claims the namespaces `bin/po-*` and `tests/po-*`, the skill directory `.agents/skills/po-theme/`, and the documentation-audience entry for that skill.
8. Gates: A4 admits exactly these paths, A9 keeps the three hunks bounded, and A10 runs `anchors` and `validate`, so an upstream change to any mirrored literal, a new user-invocable upstream skill, or a lost hook fails the merge PR.

The bundled `operator` theme uses the operator's chosen military terms:

| Role | Nautical | `operator` theme |
|---|---|---|
| the user | captain | operator, addressed by the capitalized word at the start of a chat line |
| the supervising agent | first mate | Spotter |
| a worker | crewmate | Specialist |
| a group of workers | crew | squad |
| a persistent domain delegate | second mate | Navigator |
| all work under way | fleet | Task Force |
| a change task | ship | deploy |
| a report task | scout | recon |
| seasoning | aye, on deck, shipshape, under way, ahoy | copy, online, nominal, live, ping |
| commands | `/bearings`, `/ahoy`, `/stow`, `/updatefirstmate` | `/sitrep`, `/debrief`, `/flush`, `/updateoperator` |

`/afk` and `/quiet` are unchanged.
The theme's exact no-op reply and bad-news example live in `operator.theme`, so this record does not restate them.
"operator" and "deploy" already carry other meanings upstream, so the theme declares `avoid.operator` and `avoid.deploy`, and the block tells the agent which plain words to use for those other meanings.

## Consequences

- Chat, commands, and worker prose are themed; the measured merge cost of the three hunks is zero conflicts in seven of seven weekly windows and in the full 50-day window.
- A nautical home is byte-for-byte upstream, and the worker role contract is unchanged there.
- Some surfaces stay nautical on purpose, such as identifiers, parsed brief headings, the tmux session name, the Calm sailing-boat animation, the wedge-alarm title, the Bearings board, and upstream docs as browsed; [`persona-themes.md`](../pixeloven/persona-themes.md) lists them.
- The agent reads nautical text and speaks themed words, so occasional leakage is possible; it is checked by a recorded smoke test, not by a mechanical gate.
- A themed home spends about 1,150 estimated tokens of its startup memory on the block, about 15% of the default 7,500-token budget.
- Every merge PR must keep `anchors` passing, and the `Persona: ` line may conflict if upstream edits the sentence it follows.
- The platform glossary in `pixeloven/crew` should record the theme's words so the two vocabularies are never translated silently; that is a separate follow-up.

## Alternatives considered

- **In-place rename with a scripted re-apply.** 26 to 112 conflicted files a week; identifiers cannot be renamed safely; about 895 test assertions touch the words; authority rules become ambiguous; it violates O-1 and empties A4 and A5.
- **Rendered copies of `AGENTS.md` and skills.** Harnesses load `AGENTS.md` by path, so a render must sit in place, which dirties the tree and makes the self-update skip the home, and the render must learn dozens to hundreds of new identifier-shaped tokens a week.
  A rendered read-only docs view remains a possible later addition.
- **A lookup helper at every script output site.** 3 to 21 conflicted `bin/` files a week for output the agent mostly reads and already translates.
- **A preference in `data/captain.md` only.** It conflicts with the mandatory address rule, which only a current instruction may override, and leaves the intent-address check blind to the new vocative.
- **Waiting for upstream.** Upstream has closed every persona or voice change so far; a narrow opt-in voice knob may be offered later and would retire H1 and H5 if accepted.
