# Design systems

A design system supplies the look of the pages the agents generate: color, type, shape, and spacing, in light and dark.
A [persona theme](persona-themes.md) supplies the words.
The two are chosen independently, so any theme works with any design system, and they meet only where a component prints a theme word, such as a status chip's label.
[ADR-0031](../adr/0031-design-systems-independent-of-themes.md) owns the decision; `bin/po-theme.sh --help` and the header of `bin/po-design-lib.sh` own the exact commands and mechanics; the agent-only `po-theme` skill owns when the agent runs them.
This page owns the role contract's meaning, the format of a design system, its validation rules, and the component markup.

| | Theme (`config/po-theme`) | Design system (`config/po-design`) |
|---|---|---|
| Owns | the user's name and address, role nouns, the no-op reply, display strings | color, type, shape, spacing, light and dark |
| Default | `nautical` (upstream's words) | `firstmate` (upstream's look) |
| Bundled | `nautical`, `operator` | `firstmate`, `pixeloven` |
| A home's own | `config/po-themes/<name>.theme` | `config/po-designs/<name>/` |

## Bundled design systems

- **`firstmate`, the Firstmate Default.** The Bearings board's own tokens as shipped, plus a dark mode that follows the operating system unless a page sets `data-theme="light"` or `data-theme="dark"` on its root element.
  Upstream's `--status-warn` and `--status-info` measure 3.6:1 and 4.4:1 on a card, under the 4.5:1 that small text needs, so they stay as fills and borders while the text-safe `--status-warn-ink` and `--status-info-ink` carry chip and label text.
  Its fonts load from Google Fonts when the page is online and fall back to system fonts offline.
- **`pixeloven`, the PixelOven design system.** `@pixeloven/tokens` 0.6.0 from the `pixeloven/design` repository, vendored as its prebuilt `tokens.css` with the version, source, license, and SHA-256 in `design.toml`, plus an adapter that supplies every color, radius, type, and shadow role by `var(--pxo-*)` reference only, following PixelOven's rule that a consumer never defines its own values.
  The package has no spacing scale and its consumers use a 4px grid, so the adapter's spacing roles are that grid.
  It is dark by default and follows the operating system's light scheme unless the page's root sets `data-theme`.
  A version bump is a reviewed re-vendor: rebuild `tokens.css` from the release tag, replace it, and update every `vendored.*` key in the same change.
  Known gap, to be fixed in the `pixeloven/design` tokens: in PixelOven's light scheme, `--status-info-ink` (`--pxo-accent-soft`) measures 4.31:1 on its soft ground, so the working chip is under 4.5:1, and `--status-danger-ink` (`--pxo-status-danger`) measures 4.37:1, so the blocked and failed chips are under 4.5:1.
  No accent or status token in 0.6.0 reaches 4.5:1 on those grounds in both schemes, and the adapter may not define its own values, so the mapping stays until a token release closes the gap. PixelOven's dark scheme reaches 4.5:1 on every pair.

## Selecting a design system

```sh
bin/po-theme.sh ds-validate pixeloven   # data checks
printf 'pixeloven\n' > config/po-design
bin/po-theme.sh apply                   # primary home only
bin/po-theme.sh verify                  # exit 1 on any drift
```

The selection is the first line of the gitignored `config/po-design`; absent, empty, or `firstmate` means the Firstmate Default, for which `apply` writes nothing and removes anything it wrote earlier.
For any other selection, `apply` validates the design system and writes the resolved stylesheet to `state/po-design/po-ds.css`, its record to `state/po-design/meta`, and one marker line to `data/captain-shared.md` right after the Persona block and outside it, so a theme change never rewrites the design choice and the reverse.
The theme file has no design key.
Second mates resolve the design system the inherited marker names and ignore any selection of their own; a bundled one resolves from their own checkout.
A home's own design system exists only in that home, so a second mate that inherits a marker naming one it does not have gets the Firstmate Default, with a warning from `ds-css` and a drift line from `verify` and `headline`.
`verify` reports a selection that differs from the applied one, a source changed since `apply`, a hand-edited stylesheet copy or marker, and a vendored copy whose checksum no longer matches, and `headline` prints the first such line at session start as `design drift: ...`; `ds-css` refuses to print a hand-edited copy.

## Generated pages

Before writing a Lavish page or a generated HTML report, copy the design system in force beside the page and link it at the document root:

```sh
bin/po-theme.sh ds-css > <artifact-dir>/po-ds.css
```

The page's `<head>` carries one stylesheet link to `po-ds.css`, and its `<body>` carries `class="po-page"`.
`lavish-axi export` inlines a local stylesheet, so an exported page stays self-contained.
Link exactly one design system per page, at its root: PixelOven's tokens support document-root opt-in only.
Write every word on the page, including chip labels, in the active theme's words; `bin/po-theme.sh ds-labels` prints the status-chip labels.

## The role contract

[`designs/roles`](../../.agents/skills/po-theme/designs/roles) lists the custom properties the component sheet reads and every design system's adapter supplies in its plain `:root` block.
They are the Bearings board's own semantic names, so the board can later change look by having a design system re-supply its own names with no template change, plus these additions:

- `--accent` and `--accent-ink`: an emphasis fill and the text that sits on it.
- `--status-online|warn|danger|info-ink`: status text, beside the fill (`--status-*`) and the soft ground (`--status-*-soft`). In the Firstmate Default every ink reaches 4.5:1 on the card and on its soft ground, in light and dark. PixelOven's light scheme falls short on the info and danger inks, a known gap listed under bundled design systems.
- Shape roles: `--radius-card`, `--radius-chip`, `--radius-control`, `--card-shadow`, `--display-weight`, `--display-tracking`.
- `--space-1` through `--space-6`: the spacing steps, 4px to 32px in both bundled design systems.

## Components

One shared component sheet serves every design system because it reads only role names.
Its classes are prefixed `po-` so a page's own styles do not collide with them.

- **Status chip:** `<span class="po-chip" data-status="needs-decision">captain's call</span>`, where `data-status` is the architectural status verb (`working`, `needs-decision`, `blocked`, `paused`, `done`, or `failed`), never themed, and keys the color and a shape mark so the state is not color-only; `data-kind="recommended"` or `data-kind="risk"` marks a non-status chip.
- **Decision card:** a `po-card` holding a `po-title` (type chip and noun-phrase title), a `<dl class="po-rows">` with "about" and "decide" rows, a `<fieldset class="po-options">` of `<label class="po-option">` native radios with `<b>` and `<small>` hint, and a `po-foot` with one `<button class="po-button">` that queues the answer once with `window.lavish.queuePrompt`, keyed by `data-lavish-question`.
- **Checklist:** `<ul class="po-checklist">` items with `data-state="done|pending|blocked"`, a `<span class="po-mark">` carrying a text mark, a `<code>` id, and the item text with an optional evidence link.
- **Review row:** `<div class="po-review">` of `po-review-row` rows, each a `<code>` id, the change in `<b>`, the rationale in `<p>`, a `po-meta` row of risk and recommend chips, and a `po-choice` pair of approve and decline radios; a page of rows ends with one batch submit that sends every disposition with its id.

## A home's own design system

A home adds one as `config/po-designs/<name>/`, which shadows a bundled one of the same name except `firstmate`:

- `design.toml` (required): `schema = "po-design/1"`, `name`, and a plain-text `description`, in the theme format's `key = "value"` subset.
- `adapter.css` (required): declarations of role names only, supplying every role in its plain `:root` block.
- `tokens.css` (optional): a vendored stylesheet, which requires `vendored.package`, `vendored.version` (semver), `vendored.source` (an https URL), `vendored.sha256`, and `vendored.license` in `design.toml`; a changed copy fails validation until it is reviewed and the checksum updated.

## Validation

`ds-validate` and `apply` treat both stylesheets as data, not code, like themes:

- The only blocks are `:root`, `:root[data-theme="dark"]`, `:root[data-theme="light"]`, and `@media (prefers-color-scheme: dark|light)` around `:root` or `:root:not([data-theme="light"|"dark"])`.
- The only declarations are custom properties and `color-scheme`; `adapter.css` may declare only role names.
- A value is built only from hex colors, `rgb()`, `rgba()`, `hsl()`, `hsla()`, and `cubic-bezier()` of numbers, lengths and numbers, quoted font names, plain keywords, and `var()` references; an adapter reference must name a role or a property the vendored `tokens.css` defines.
- `url()`, `@font-face` and every other at-rule, `expression`, `javascript`, `!important`, backslash escapes, markup characters, and non-ASCII text outside comments are refused.
- `adapter.css` alone may open with Google Fonts `@import url("https://fonts.googleapis.com/css2?...")` lines, before any rule; `ds-css` hoists them to the top of the page stylesheet.

## Not covered here

The Bearings board does not change: its template stays upstream-identical, and injecting the selected design system into it is a later stage.
Terminal surfaces, such as Calm, notes, and the herdr sidebar, are not CSS and take their words from the theme.
Markdown reports stay plain.
Pictures and icons belong to the theme's asset slots, not to a design system.
