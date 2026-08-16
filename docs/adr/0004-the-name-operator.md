# ADR-0004: The name `operator`, and "the operator" is the human

- **Status:** Accepted
- **Date:** 2026-08-16
- **Deciders:** Brian Gebel (the operator), with Claude Code
- **Source:** Program plan decision **D-03**; requirement **G-7**

## Context

The PixelOven stack names five components on a single theme, all singular:
`operator` · `vigil` · `pulse` · `wetware` · `lattice`.

`operator` is a knowingly overloaded word. Two collisions were identified and
accepted rather than avoided:

1. **Kubernetes operators.** In the platform that hosts this stack, "operator"
   already means a controller that reconciles a custom resource. Harmony runs
   several.
2. **"The operator" as a person.** Across this program's own documents, agent
   contracts, and prompts, "the operator" already means *the human being who
   directs the work* — the person an agent escalates to. That usage predates
   the component name and is load-bearing in agent instructions.

The second collision is the dangerous one. An agent reading "ask the operator"
must escalate to a human, not invoke a program. Left unresolved, this is a
class of instruction-following bug that would surface as agents doing something
plausible and wrong.

A related vocabulary collision exists one layer up: this fork's upstream lineage
uses **crew / crewmate / captain** for dispatched workers and the human, while
harmony-crew uses **crew** to mean *the set of agent roles* (Lead, Reviewer,
Implementer, …). The two meanings of "crew" are close enough to be confused and
different enough to matter.

## Decision

- The project is named **`operator`**, always lowercase, always code-styled in
  prose (`operator`), never capitalized as a proper noun mid-sentence.
- **In prose, "the operator" means the human.** This meaning wins. It is not
  qualified, hedged, or disambiguated at each use — it is the default reading.
- When the *project* is meant, it is written in code style: `operator`. If a
  sentence would be ambiguous even then, the project is called
  "the `operator` project" or "the `operator` repo", never "Operator".
- The crew/crewmate/captain ↔ crew-as-roles overlap is resolved in the
  harmony-crew **platform glossary**, which is the single owner of the
  platform's shared vocabulary. This repository does not restate it (task A0.4).

## Consequences

- Documentation, ADRs, commit messages, and agent-facing prose in this repo must
  hold the code-style convention. It is cheap to hold and expensive to lose:
  once "Operator" appears as a proper noun, the human/project distinction is gone.
- Agent instructions that say "escalate to the operator" need no change and no
  disambiguation, which is the point — the existing corpus stays correct.
- Kubernetes "operator" collides only in platform contexts where the k8s meaning
  is obvious from surrounding nouns (CRD, controller, reconcile). No mitigation
  beyond awareness is warranted.
- Anyone searching a codebase for the string `operator` gets noise. Accepted.

## Alternatives considered

- **A name with no collisions.** The evaluated set was rejected on evidence
  rather than taste: `engram` (two active agent-memory projects, one ~6k★),
  `ghost` (established blogging platform), `stack` (unusably overloaded),
  `netwatch` (~2.5k★ project), `graveyard` (reads as archival/abandonment).
  `lifepath` and `wetware` had the cleanest namespaces of everything checked;
  `wetware` was subsequently taken by the identity tier, and `lifepath` remains
  the benched alternative.
- **Capitalize the project as "Operator" to distinguish it from the human.**
  Rejected: capitalization is invisible at the start of a sentence, which is
  exactly where "The operator should…" appears. It fails in the one position
  that matters.
- **Rename the human role instead** (e.g. "the captain", inherited from
  upstream's vocabulary). Rejected: "the operator" for the human is already
  embedded in the agent corpus, the memory substrate, and the operator's own
  usage. Renaming the human to protect a program name inverts the priority.
