# ADR-0023: The merge script accepts several named red-check waivers

- **Status:** Accepted
- **Date:** 2026-10-29
- **Deciders:** The operator
- **Source:** A merge approved with two required checks waived by name stopped on the single-waiver limit

## Context

`bin/fm-pr-merge.sh` lets an attended merge waive a red required check by passing `--allow-red <check-name>`.
The inherited script accepts that flag only once, refusing a second with "--allow-red may be specified only once".
The operator approved a merge with two required checks waived by name, both failing on the default branch independently of the pull request, and the merge could not proceed.

ADR-0001 otherwise prohibits editing upstream files, and no existing exception covers the merge script.

## Decision

ADR-0001 remains the default, and the following inherited files may carry this one bounded change:

- `bin/fm-pr-merge.sh`: `--allow-red` may be repeated, each occurrence adding one exact check name to the waived set, with its header comment and usage line describing the repeatable flag
- `tests/fm-pr-merge.test.sh`: the cases covering several named waivers, a red check left unnamed, an empty name, and a repeated name

Every other guard is unchanged.
Each name is still a separate argument, an empty name is still refused, the flag is still refused while the away-posture record exists, every check not named must still be green, the merge is still bound to the verified head, and the flag still does not apply on GitLab or Forgejo.
A repeated name is accepted and waives nothing more than the name once.
`--allow-missing` stays single-use.

The change is kept minimal so it can be offered upstream.
When an upstream synchronization brings an equivalent change, that merge takes upstream's version of both files, the A4 allowlist drops them, and this ADR is superseded by that merge.

## Consequences

An attended merge can waive every named red check the operator approved in one call, rather than failing or needing a different path.
Each waiver still names an exact check, so a merge never waives a check nobody named.
Until an upstream synchronization brings an equivalent change, every synchronization has these two files as an explicit contact surface to review.

## Verification

`tests/fm-pr-merge.test.sh` exercises the public script: two red checks both named merge, two red checks with one named refuse naming the other, and the existing single-waiver, wrong-name, equals-form, away-posture, GitLab, and Forgejo cases still hold.
The fork-contract workflow rejects any path outside the PixelOven namespaces and accepted ADR exceptions.

## Alternatives considered

- **Accept a comma-separated list in one flag.** Rejected because a check name may itself contain a comma, and a separate argument per name keeps each waiver exact.
- **Refuse a repeated name.** Rejected because naming the same check twice waives nothing extra, so refusing it would only fail an otherwise approved merge.
- **Merge the pull request outside the script.** Rejected because the script is the only path that records the merge and refuses an unproved one.
