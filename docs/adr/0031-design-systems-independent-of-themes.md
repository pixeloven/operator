# ADR-0031: Design systems are chosen independently of themes

- **Status:** Accepted
- **Date:** 2026-11-12
- **Deciders:** the operator
- **Source:** the operator's approval of design-system rows DS1-DS9 of the op-themes-review-ds investigation (2026-11-04, as revised after the round-1 review); this record covers DS1-DS5 and DS7-DS9, and DS6, the board injection, ships later with stage S5 of [ADR-0020](0020-themes-first-class.md)

## Context

Pages the agents generate, such as Lavish review pages and HTML reports, had no house look, because Lavish deliberately injects none.
Two design systems already existed: the Bearings board inlines upstream's Firstmate tokens, and PixelOven publishes `@pixeloven/tokens`, whose usage rules say a consumer never defines its own token values and a consumer without a bundler vendors the prebuilt stylesheet at a pinned version.
A first proposal tied the look to a theme key.
The operator asked instead for a Firstmate Default design system based on upstream's behavior and a PixelOven design system based on pixeloven/design, so that anyone can choose or create their own and the connection between themes and design systems stays minimal.
The PixelOven packages publish to GitHub Packages, which needs a token even to read, and the release carries no CSS asset.

## Decision

1. **Two independent selections.**
   A theme supplies words and a design system supplies the look.
   `config/po-design` selects the design system, separately from `config/po-theme`, and no theme key names a design system.
   They meet only where a component prints a theme word.
2. **The role contract.**
   Components read only role names, and every design system supplies them.
   The role names are the Bearings board's own semantic token names plus `--accent`, `--accent-ink`, `--status-*-ink`, shape roles, and `--space-*`, so the board can later change look by value with no template change.
3. **Two bundled design systems.**
   `firstmate` is the default: the board's tokens as shipped, plus a dark mode, with text-safe warn and info inks for chip and label text while upstream's fills stay.
   `pixeloven` vendors `@pixeloven/tokens` 0.6.0's `tokens.css`, built from its release tag and pinned by semver and SHA-256, behind an adapter whose color, radius, type, and shadow roles are `--pxo-*` references only.
4. **Resolution and reach.**
   `apply` resolves a non-default selection into `state/po-design/` and one marker line in `data/captain-shared.md` beside the Persona block, outside it; the default writes nothing.
   `bin/po-theme.sh ds-css` prints the design system in force for a page, and second mates resolve the marker they inherit.
5. **One component sheet.**
   A decision card, checklist, review row, and status chips read only role names; the words come from the theme.
6. **Discoverable from pages.**
   The `po-theme` skill tells the agent to copy `ds-css` into the artifact directory and link it at the document root before writing a Lavish page or generated HTML report.
7. **A home's own design system is data.**
   `config/po-designs/<name>/` holds a required adapter and an optional vendored stylesheet pinned by checksum, and validation admits only root-scoped custom-property declarations of plain value shapes, refusing `url()`, at-rules other than prefers-color-scheme media, imports other than leading Google Fonts lines, and script.
8. **Namespaces.**
   This record claims `bin/po-design-lib.sh`, `.agents/skills/po-theme/designs/`, `tests/po-design.test.sh`, and `docs/pixeloven/design-systems.md`, all inside existing PixelOven namespaces; it adds no upstream hook.

## Consequences

- Any theme works with any design system, and changing one never rewrites the other's record.
- Under the defaults, `nautical` and `firstmate`, a home writes nothing new and the board stays byte-identical to upstream.
- The vendored PixelOven stylesheet is about 31 KB, and each version bump is a reviewed re-vendor with a new checksum.
- A home's own design system exists only in that home, so a second mate inheriting a marker that names one it lacks falls back to the Firstmate Default and reports drift.
- PixelOven has no spacing scale, so its adapter's spacing roles are the 4px grid its consumers already use.
- The validator, not review, is what keeps a home's design system from carrying code.

## Alternatives considered

- **A `ds` key in the theme.** Rejected by the operator in review: it locks the look to the words.
- **A third, invented palette.** Rejected: two design systems already existed.
- **Installing `@pixeloven/tokens` from GitHub Packages.** Rejected: it needs a read token on every machine, and pixeloven/design's own guidance for a consumer without a bundler is to vendor the built file.
- **Defining PixelOven literal values in the adapter.** Rejected: it breaks pixeloven/design's rule that a consumer never defines its own values and would drift from the package.
- **Injecting the design system into the board now.** Deferred to stage S5 (DS6), so this change touches no upstream file.
