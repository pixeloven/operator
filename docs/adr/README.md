# Architecture Decision Records

Durable decisions for `operator`. One file per decision, numbered, never edited
after acceptance — a decision that changes gets a **new** ADR that supersedes
the old one.

Format follows the PixelOven decision-record convention:
Context → Decision → Consequences → Alternatives considered.
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
| [0010](0010-pixeloven-companion-forks-own-distribution.md) | PixelOven companion forks own distribution | Superseded by ADR-0015 | `operator` upstream synchronization and companion-fork migration |
| [0011](0011-operator-github-hosted-runner-routing.md) | `operator` CI uses standard GitHub-hosted runners | Accepted (Node.js provisioning clause superseded by ADR-0015) | Hosted-runner remediation after PR #11 |
| [0012](0012-notification-reconciliation.md) | Notification reconciliation may modify bounded upstream surfaces | Accepted | Process-result notification reliability reconciliation |
| [0013](0013-archived-captain-hold-completion.md) | Archived captain-hold completion may modify bounded upstream surfaces | Accepted | Captain-approved archived answer compatibility |
| [0014](0014-stale-lock-publication-serialization.md) | Stale-lock publication serialization may modify bounded upstream surfaces | Withdrawn 2026-10-22 | Hosted stale-lock scheduling race correction |
| [0015](0015-companion-tools-from-upstream-sources.md) | Companion tools are acquired from upstream sources | Accepted | Captain decisions for the five-stage upstream synchronization |
| [0016](0016-persona-themed-at-the-edge.md) | Persona and vocabulary are themed at the edge, never rewritten in place | Accepted | Captain decisions on persona customization |
| [0017](0017-go-public-criteria.md) | Go-public criteria for every public PixelOven repository | Accepted | ADR-0003 go-public review; retroactive review of `operator` |
| [0018](0018-security-policy-file.md) | PixelOven claims `.github/SECURITY.md` for its security policy | Accepted | Go-public review decision D5 |
| [0019](0019-crew-machine-level-delivery.md) | `crew` reaches workers through the machine-level install that dotfiles maintains | Accepted | Crew-everywhere investigation; closes the parked crew delivery decisions |
| [0020](0020-themes-first-class.md) | Themes are a first-class feature | Accepted | operator decisions on persona completion; amends ADR-0016 |
| [0021](0021-carry-upstream-herdr-slash-popup-fix.md) | Carry upstream's Herdr slash-popup composer fix until a sync brings it | Accepted | Herdr send-failure investigation; self-retiring upstream carry |
| [0022](0022-delivery-lane-github-credential-helper.md) | The delivery lane may carry an operator-configured GitHub credential helper | Accepted | Worker GitHub credentials from a non-personal source |
| [0023](0023-repeatable-allow-red-waiver.md) | The merge script accepts several named red-check waivers | Accepted | Two-check waived merge stopped on the single-waiver limit |
| [0024](0024-worker-connector-deny-list.md) | Claude workers honor config/crew-exclude-tools | Proposed | Worker tooling investigation; operator review chose one local list |
| [0025](0025-remote-test-timing-deflake.md) | Carry a timing deflake for two inherited remote tests | Proposed | "Behavior portable serial 5" CI shard failing on main and pull requests |

Exceptions to ADR-0017's go-public criteria that the operator has approved are recorded in
[`0017-go-public-exceptions.md`](0017-go-public-exceptions.md).

## Conventions

- **Status** is `Proposed`, `Accepted`, or `Superseded by ADR-XXXX`.
- Requirement IDs (`G-n`, `O-n`, `P-n`, `V-n`, `H-n`) and decision IDs (`D-nn`)
  refer to the *PixelOven Agent Stack — Program Plan*.
- Any deviation from that plan is a new ADR, never a silent change.
