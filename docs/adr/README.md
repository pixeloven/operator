# Architecture Decision Records

Durable decisions for `operator`. One file per decision, numbered, never edited
after acceptance — a decision that changes gets a **new** ADR that supersedes
the old one.

Format follows [`ductiletoaster/lattice`](https://github.com/ductiletoaster/lattice)'s
`docs/decisions/`: Context → Decision → Consequences → Alternatives considered.
Use [`_template.md`](_template.md).

## Index

| ADR | Title | Status | Source |
|-----|-------|--------|--------|
| [0001](0001-soft-fork-of-firstmate.md) | Soft fork of firstmate, additive-only | Accepted | Program plan D-01, O-1, O-2 |
| [0002](0002-seeded-with-full-upstream-history.md) | Seeded with full upstream history at the pin | Accepted | Task A0.1 |
| [0003](0003-pixeloven-org-private-until-review.md) | PixelOven org, private until a go-public review | Accepted | Program plan D-02, G-6 |
| [0004](0004-the-name-operator.md) | The name `operator`, and "the operator" is the human | Accepted | Program plan D-03, G-7 |
| [0005](0005-agent-self-improvement-is-pr-gated.md) | Agent self-improvement is PR-gated | Accepted | Program plan D-05, O-4 |
| [0006](0006-operator-cuts-its-own-release-tags.md) | operator cuts its own release tags | Accepted | Program plan O-3 |

## Conventions

- **Status** is `Proposed`, `Accepted`, or `Superseded by ADR-XXXX`.
- Requirement IDs (`G-n`, `O-n`, `P-n`, `V-n`, `H-n`) and decision IDs (`D-nn`)
  refer to the *PixelOven Agent Stack — Program Plan*.
- Any deviation from that plan is a new ADR, never a silent change.
