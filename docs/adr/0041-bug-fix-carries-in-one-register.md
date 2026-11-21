# ADR-0041: Bug-fix carries are rows in one carry register

- **Status:** Accepted
- **Date:** 2026-11-20
- **Deciders:** The operator
- **Source:** Architecture review of upstream synchronization and upstream offers; navigator fixes in [pull request #78](https://github.com/pixeloven/operator/pull/78) and [pull request #79](https://github.com/pixeloven/operator/pull/79) blocked by gates A4 and A9
- **Amends:** [ADR-0001](0001-soft-fork-of-firstmate.md), whose option (c) needed a new ADR for every bounded edit to an upstream file, and decision 9 of [ADR-0020](0020-themes-first-class.md), whose gate A9 accepted nothing but registered hooks in a theme-hook file.

## Context

[ADR-0001](0001-soft-fork-of-firstmate.md) makes the fork additive and leaves three ways to change upstream behavior: an extension point, an upstream contribution, or a new ADR that allows a bounded edit to a named upstream file.
Every carried fix so far took the third way, so each one cost an ADR plus a hand edit to gate A4's path list.

Gate A4 compared every path that differs from the upstream pin against one hand-maintained regular expression of about 120 entries.
The workflow and [`identity.md`](../pixeloven/identity.md) each held a copy, and the two copies had already drifted apart.
Gate A9 held every changed line in the 23 upstream files that carry theme hooks to the hook registry, so a bug fix in one of those files could not pass at all, whatever ADR named it.
Pull request #78 fixed navigator restarts in `bin/backends/herdr.sh`, and pull request #79 fixed navigator liveness in `bin/fm-session-start.sh`; both are theme-hook files, and gates A4 and A9 blocked both pull requests.
While this decision was pending, both fixes landed as ADR carries: #79 as ADR-0039, whose lines in `bin/fm-session-start.sh` are registered as `lib` rows in the hook registry, and #78 as ADR-0040, whose logic moved into a PixelOven library, `bin/po-herdr-regroup-lib.sh`.

Three carries have already retired because an upstream synchronization brought an equivalent change: ADR-0021, ADR-0024, and ADR-0030.
That happened by luck; offering each fix upstream makes it happen on purpose.

The operator also set the standing principle for how this fork changes upstream behavior, in these words:

> consider whether our approach to these enhancements makes sense. Fixes sure should patch existing files. Features should aim to minmize changes but not at the expense of progress. Firstmates architectual, patterns and design should be respected but still up for being challenged. What we do that could benefit others should be shared.

## Decision

1. **One carry register.**
   `docs/pixeloven/carries.tsv` lists every path the fork may change relative to the upstream pin: the PixelOven namespaces, each file an accepted ADR claims, and each bug-fix carry.
   It has one row per path and owner, with the owner, the retire condition, and the upstream offer link.
   Its header owns the row format, and `bin/po-carries.sh` owns the checks that read it.
   Every entry of the former A4 expression moved into it with an unchanged verdict for every path.
2. **Gate A4 reads the register.**
   `bin/po-carries.sh check-paths` replaces the expression: every path that differs from the pin must match a register row or be an upstream file the hook registry lists.
3. **A bug fix needs a register row, not an ADR.**
   A bug fix patches the upstream file in place, in the shape upstream could take as is, and adds one `fix` row per changed file with a note saying what it fixes.
   A bug fix corrects behavior that is wrong by upstream's own contract, such as a defect, a flaky test, or a Bash or platform incompatibility, and keeps upstream's design, contracts, and defaults.
   Anything else stays a decision that needs an ADR: a feature, a PixelOven-only behavior, a changed contract or default, or a new namespace.
4. **Gate A9 accepts a fix carry in a theme-hook file.**
   In an upstream file the hook registry lists, changed lines that are not registered hooks are accepted when a `fix` row names the file.
   That file's hooks are still counted, and each must still replace its registered upstream line.
   An ADR's row does not relax A9: an ADR that carries lines in a theme-hook file still registers them as plumbing rows in the hook registry.
   ADR-0016's exact checks on `AGENTS.md` and `bin/fm-dod-lib.sh` are unchanged.
5. **Carries retire themselves.**
   When an upstream synchronization brings an equivalent change, the merge takes upstream's version of the file and drops the carry's row.
   A4 fails on a `fix` row whose file no longer differs from the pin, and prints a note for an ADR's self-retiring row in that state.
   A4's check is whole-file, and a theme-hook file still differs by its hooks after its fix is spent, so A9 also fails on a `fix` row whose theme-hook file changes no line beyond its registered hooks.
   Together they keep a spent fix carry from lingering unnoticed.
   Where an accepted ADR says the A4 allowlist drops a path, the merge drops that ADR's row.
6. **Fixes are offered upstream, each offer approved on its own.**
   A fix carry stays minimal, so the carried change and the upstream contribution are the same diff.
   Each offer to `kunchenguid/firstmate` needs the operator's approval for that one offer, as G-5 already requires, and its link then goes in the row's `upstream` column.
   This decision publishes nothing.
7. **The contribution principle.**
   The operator's principle above is standing guidance for every change to upstream behavior, and [`fork-contract.md`](../pixeloven/fork-contract.md#the-contribution-principle) states its operating form.

## Consequences

- A bug fix in any upstream file, theme-hook files included, ships as a carry with one register row per changed file; the register records both the ADR-0039 and ADR-0040 carries as ADR rows, and a later bug fix of the same kind needs only fix rows.
- ADRs stay for decisions, and the ADR index no longer grows by one record per fix.
- Gate A4's path list has one owner instead of two drifting copies.
- While a fix carry covers a theme-hook file, A9 cannot tell a fix line from an unregistered theme line in that file; the file's registered hooks are still counted, A10 still finds a lost hook, and the exposure ends when the carry retires, which A9 enforces once the fix no longer changes any line beyond the file's hooks.
- The `bin/backends/` namespace keeps admitting every path under it, as the expression did, so upstream's own adapters there pass A4 through it; their carries are still named by their ADR rows.
- Every upstream synchronization has the register to review: rows whose file upstream changed, and rows the check notes as back at upstream bytes.

## Verification

`tests/po-carries.test.sh` covers the register checks, the retirement rules, and the A9 exception, including that an ADR row does not relax A9, that a fix-covered file's hooks are still held to their rows, and that A9 fails a spent fix carry in a theme-hook file.
The old expression in effect when the migration landed gave the same A4 verdict as the register for every path in the proof corpus: every path tracked at the new head and at the upstream pin, every path differing from the pin, the paths of pull requests #78 and #79, and boundary paths around every namespace and every named file.

## Alternatives considered

- **Keep one ADR per carry and teach A9 to subtract ADR-listed lines.**
  Rejected because every fix would still cost an ADR and a hand edit to the expression, and an exact-line list cannot attribute the repeated `fi` and `}` lines of a fix that adds a function.
- **Scope a fix carry in a theme-hook file by line range or by marker comments.**
  Rejected because line ranges move with every upstream merge, and markers would put PixelOven text into the diff offered upstream, so the carry and the offer would stop being the same diff.
- **Move fixes into PixelOven-owned scripts that call upstream's functions.**
  Rejected because upstream cannot take a `po-*` script, so every offer would become a rewrite, and the script would depend on upstream internals that can change without a merge conflict to warn us.
- **Wait for upstream to merge each fix before using it.**
  Rejected as the default because upstream review can take weeks while the bug stays; the offer is still made.
- **Shell glob patterns for the namespace rows.**
  Rejected because a glob's `*` also matches `/`, so `bin/po-*.sh` would admit `bin/po-x/y.sh`, which A4 refused; whole-path extended regular expressions keep every verdict.
