# ADR-0018: PixelOven claims `.github/SECURITY.md` for its security policy

- **Status:** Accepted
- **Date:** 2026-10-26
- **Deciders:** Brian Gebel (the operator)
- **Source:** Go-public review decision D5

## Context

The repository is going public and has no security policy, so reporters have no stated private channel.
GitHub private vulnerability reporting is enabled, but GitHub surfaces a `SECURITY.md` only at the repository root, in `.github/`, or in `docs/`.
None of those locations is in the [fork contract](../pixeloven/fork-contract.md#where-our-code-goes)'s namespace inventory, and assertion A4 rejects any path outside it.

## Decision

PixelOven claims exactly one new path, `.github/SECURITY.md`, which points reporters to GitHub private vulnerability reporting and asks them not to file public issues.
The fork contract inventory and assertion A4 list that path.

## Consequences

- GitHub shows the policy on the Security tab and when people open new issues.
- Upstream firstmate has no `SECURITY.md` anywhere, so the path does not collide with upstream merges today; if upstream adds one, the next merge resolves it under this ADR.
- No upstream file is edited.

## Alternatives considered

- **Root `SECURITY.md`:** equally visible, but adds a file at the most collision-prone level of the upstream tree.
- **`docs/pixeloven/SECURITY.md`:** already inside our namespace, but GitHub does not surface it as the security policy.
- **No policy:** leaves reporters without a stated private channel on a public repository.
