# Architecture Decision Records

Durable decisions for `operator`. One file per decision, numbered, never edited
after acceptance — a decision that changes gets a **new** ADR that supersedes
the old one.

Format follows [`pixeloven/lattice`](https://github.com/pixeloven/lattice)'s
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
| [0007](0007-pixeloven-ci-in-its-own-workflow-namespace.md) | PixelOven CI lives in its own workflow namespace | Accepted | Task A1.2; O-1, G-2, G-6 |
| [0008](0008-autonomous-delivery-lane.md) | Autonomous delivery lane | Accepted | Separate interactive human signing from autonomous delivery |
| [0009](0009-operator-arc-runner-routing.md) | `operator` Linux CI routes through the PixelOven ARC pool | Superseded by ADR-0011 | PR #10 remediation |
| [0010](0010-pixeloven-companion-forks-own-distribution.md) | PixelOven companion forks own distribution | Accepted | `operator` upstream synchronization and companion-fork migration |
| [0011](0011-operator-github-hosted-runner-routing.md) | `operator` CI uses standard GitHub-hosted runners | Accepted | Hosted-runner remediation after PR #11 |

## Conventions

- **Status** is `Proposed`, `Accepted`, or `Superseded by ADR-XXXX`.
- Requirement IDs (`G-n`, `O-n`, `P-n`, `V-n`, `H-n`) and decision IDs (`D-nn`)
  refer to the *PixelOven Agent Stack — Program Plan*.
- Any deviation from that plan is a new ADR, never a silent change.
