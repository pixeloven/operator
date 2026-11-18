#!/usr/bin/env bash
# tests/po-theme-calm.test.sh - the PixelOven theme's pictures and animation
# (ADR-0020 decision 10, stage S4): the Calm sprite wrapper both harnesses
# construct, the picture keys, their validators, and the asset copy refresh and
# apply make beside the values cache.
#
# Coverage:
#   - nautical: through the wrapper, with no theme or a theme that names no
#     sprite, the frame stream and motion state are identical to upstream's
#     sprite for 1,000 ticks at every width from 8 to 120, and Pi's real
#     working-ship animation paints exactly upstream's frame in ANSI
#   - a `glyphs` asset keeps upstream's motion, swell, row count, and every
#     row's column count, and changes only the boat's cells
#   - a `frames` asset loops at its own tick in scheduler time, freezes and
#     resumes with the presentation, resets, and falls back to water when
#     narrower than its widest frame
#   - an asset that does not parse draws upstream's sailboat, with one warning
#   - Pi loads the theme and its copied asset from a home `refresh` wrote, and
#     never reads a cache-named asset outside state/po-theme/assets
#   - the po-sprite/1 validator in bin/po-theme.sh and the parser in
#     po-theme-calm.ts agree on a corpus of valid and invalid sprites; the icon
#     and image validators and the picture-key checks refuse what they must
#   - refresh copies valid assets, leaves out an invalid one with a warning,
#     prunes assets the theme no longer names, and nautical removes them; apply
#     (in a throwaway code root) copies the asset and refuses an invalid one
#
# The Claude Code mod's engine-bound behavior is
# .claude/mods/firstmate-calm/tests/po-theme-calm.test.ts under
# tests/fm-calm-claude-mod-plugin.test.sh.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PT="$ROOT/bin/po-theme.sh"
LIB="$ROOT/.claude/mods/firstmate-calm/lib"
PI_LIB="$ROOT/.pi/extensions/lib"
TMP_ROOT=$(fm_test_tmproot po-theme-calm-tests)
FM_TEST_CLEANUP_DIRS+=("$TMP_ROOT")
trap fm_test_cleanup EXIT
fm_git_identity fmtest fmtest@example.invalid

command -v node >/dev/null 2>&1 || { echo "skip: node not found for the Calm sprite checks"; exit 0; }

GLYPHS_ASSET='schema = "po-sprite/1"
kind = "glyphs"
top = "/#+"
base = "[===]"'

FRAMES_ASSET='# three frames, one without a top row
schema = "po-sprite/1"
kind = "frames"
tick_ms = "440"
frame.1.top = "<>"
frame.1.base = "AB"
frame.2.base = "CD"
frame.3.top = "⠿"
frame.3.base = "▚▞"'

# js <script>: run a module script with LIB and PI_LIB in the environment.
js() {
  LIB="$LIB" PI_LIB="$PI_LIB" node --input-type=module - "$@" 2>&1
}

# art_home <name> <asset-text> [<key-lines>]: a primary home selecting a local
# theme "art" (the bundled operator theme renamed) whose sprite.calm names
# test.sprite, carrying <asset-text> as that asset. Echoes the home.
art_home() {
  local home="$TMP_ROOT/$1"
  mkdir -p "$home/config/po-themes/assets" "$home/data" "$home/state"
  sed 's/^name = "operator"/name = "art"/' "$ROOT/.agents/skills/po-theme/themes/operator.theme" > "$home/config/po-themes/art.theme"
  printf '%s\n' "${3:-sprite.calm = \"test.sprite\"}" >> "$home/config/po-themes/art.theme"
  printf '%s\n' "$2" > "$home/config/po-themes/assets/test.sprite"
  printf 'art\n' > "$home/config/po-theme"
  printf '%s\n' "$home"
}

test_nautical_stream_identical() {
  local out
  out=$(js <<'JS'
import { pathToFileURL } from "node:url";
const core = await import(pathToFileURL(`${process.env.LIB}/fm-calm-working-ship-sprite.ts`).href);
const calm = await import(pathToFileURL(`${process.env.LIB}/po-theme-calm.ts`).href);
const values = await import(pathToFileURL(`${process.env.LIB}/po-theme-values.ts`).href);
const pi = await import(pathToFileURL(`${process.env.PI_LIB}/fm-calm-working-ship.ts`).href);
const check = (ok, message) => { if (!ok) throw new Error(message); };
const noSprite = values.parsePoTheme("cache\tpo-theme-values/3\nkind\tprimary\nname\tart\nglyph.ship\t▸\n", "art\n", false);
check(noSprite.values.get("glyph.ship") === "▸", "the theme without a sprite did not parse");
const ESC = "\u001b";
const ANSI = { water: `${ESC}[34m`, boat: `${ESC}[33m` };
const paint = (row) => row.map((run) => (run.color === "plain" ? run.text : `${ANSI[run.color]}${run.text}${ESC}[39m`)).join("");
let frames = 0;
for (let width = 8; width <= 120; width += 1) {
  const upstream = core.createCalmWorkingShipSprite();
  const nautical = calm.poThemedSprite(core.createCalmWorkingShipSprite(), () => values.PO_THEME_NAUTICAL);
  const unthemed = calm.poThemedSprite(core.createCalmWorkingShipSprite(), () => noSprite);
  const animation = pi.createCalmWorkingShipAnimation();
  for (let tick = 0; tick < 1000; tick += 1) {
    const want = JSON.stringify(upstream.frame(width));
    const state = [upstream.position(), upstream.direction(), upstream.waterPhase()].join();
    for (const [name, sprite] of [["nautical", nautical], ["no-sprite", unthemed]]) {
      check(JSON.stringify(sprite.frame(width)) === want, `${name} frame diverged at width ${width} tick ${tick}`);
      check([sprite.position(), sprite.direction(), sprite.waterPhase()].join() === state, `${name} motion diverged at width ${width} tick ${tick}`);
      sprite.tick();
    }
    check(JSON.stringify(animation.render(width)) === JSON.stringify(JSON.parse(want).map(paint)), `Pi's animation diverged at width ${width} tick ${tick}`);
    animation.tick();
    upstream.tick();
    frames += 1;
  }
}
console.log(`nautical-ok frames=${frames}`);
JS
)
  assert_contains "$out" "nautical-ok frames=113000" "the nautical frame stream is not upstream's: $out"
  pass "nautical: the wrapper's frame stream and motion match upstream's sprite for 1,000 ticks at widths 8-120, and Pi's animation paints exactly upstream's frames"
}

test_glyphs_keep_motion_and_columns() {
  local out
  out=$(ASSET="$GLYPHS_ASSET" js <<'JS'
import { pathToFileURL } from "node:url";
const core = await import(pathToFileURL(`${process.env.LIB}/fm-calm-working-ship-sprite.ts`).href);
const calm = await import(pathToFileURL(`${process.env.LIB}/po-theme-calm.ts`).href);
const check = (ok, message) => { if (!ok) throw new Error(message); };
const theme = { values: new Map([["sprite.calm", "test.sprite"]]), assets: new Map([["sprite.calm", process.env.ASSET]]) };
const cells = (row) => row.reduce((sum, run) => sum + Array.from(run.text).length, 0);
let boats = 0;
for (let width = 1; width <= 120; width += 1) {
  const upstream = core.createCalmWorkingShipSprite();
  const sprite = calm.poThemedSprite(core.createCalmWorkingShipSprite(), () => theme, (m) => { throw new Error(m); });
  for (let tick = 0; tick < 400; tick += 1) {
    const want = upstream.frame(width);
    const got = sprite.frame(width);
    check([sprite.position(), sprite.direction(), sprite.waterPhase()].join() === [upstream.position(), upstream.direction(), upstream.waterPhase()].join(), `motion diverged at width ${width} tick ${tick}`);
    check(got.length === want.length, `row count changed at width ${width}`);
    for (let row = 0; row < want.length; row += 1) {
      check(cells(got[row]) === cells(want[row]), `row ${row} changed its column count at width ${width} tick ${tick}`);
      check(got[row].length === want[row].length, `row ${row} changed its runs at width ${width}`);
      for (let index = 0; index < want[row].length; index += 1) {
        const [a, b] = [want[row][index], got[row][index]];
        check(a.color === b.color, `a run changed color at width ${width}`);
        if (a.text === core.CALM_WORKING_SHIP_SAIL) { check(b.text === "/#+", "the sail was not replaced"); boats += 1; }
        else if (a.text === core.CALM_WORKING_SHIP_HULL) { check(b.text === "[===]", "the hull was not replaced"); boats += 1; }
        else check(a.text === b.text, `a non-boat run changed at width ${width} tick ${tick}`);
      }
    }
    upstream.tick();
    sprite.tick();
  }
}
check(boats > 0, "no boat was drawn");
console.log("glyphs-ok");
JS
)
  assert_contains "$out" "glyphs-ok" "a glyphs asset changed more than the boat: $out"
  pass "a glyphs asset keeps upstream's motion, swell, rows, and column counts, and redraws only the sail and hull"
}

test_frames_loop_at_tick() {
  local out
  out=$(ASSET="$FRAMES_ASSET" js <<'JS'
import { pathToFileURL } from "node:url";
const core = await import(pathToFileURL(`${process.env.LIB}/fm-calm-working-ship-sprite.ts`).href);
const calm = await import(pathToFileURL(`${process.env.LIB}/po-theme-calm.ts`).href);
const check = (ok, message) => { if (!ok) throw new Error(message); };
const make = (asset) => calm.poThemedSprite(core.createCalmWorkingShipSprite(),
  () => ({ values: new Map([["sprite.calm", "t.sprite"]]), assets: new Map([["sprite.calm", asset]]) }), (m) => { throw new Error(m); });
const text = (frame) => frame.map((row) => row.map((run) => run.text).join("")).join("|");
check(core.CALM_WORKING_SHIP_TICK_MS === 220, "upstream's scheduler period changed; recompute the expected loops");
// tick_ms 440 over a 220 ms scheduler: each frame holds two ticks, and three frames loop every six.
const sprite = make(process.env.ASSET);
const seen = [];
for (let tick = 0; tick < 12; tick += 1) { seen.push(text(sprite.frame(8))); sprite.tick(); }
const [a, b, c] = ["<>|AB▁▁▁▁▁▁", "|CD▁▁▁▁▁▁", "⠿|▚▞▁▁▁▁▁▁"];
check(JSON.stringify(seen) === JSON.stringify([a, a, b, b, c, c, a, a, b, b, c, c]), `440 ms frames: ${JSON.stringify(seen)}`);
// Colors: the figure is boat-colored and the rest of the base row is water.
const frame = make(process.env.ASSET).frame(8);
check(frame.length === 2 && frame[0][0].color === "boat" && frame[1][0].color === "boat" && frame[1].slice(1).every((run) => run.color === "water"), "frames are not in upstream's color classes");
// tick_ms 1000: the loop is measured in scheduler time, 220 ms per tick.
const slow = make(process.env.ASSET.replace('tick_ms = "440"', 'tick_ms = "1000"'));
const indexes = [];
for (let tick = 0; tick < 14; tick += 1) { indexes.push([a, b, c].indexOf(text(slow.frame(8)))); slow.tick(); }
check(JSON.stringify(indexes) === JSON.stringify(Array.from({ length: 14 }, (_, t) => Math.floor((t * 220) / 1000) % 3)), `1000 ms frames: ${indexes}`);
// Freeze and resume: ticks after the last painted frame are discarded; reset restarts the loop.
const frozen = make(process.env.ASSET);
for (let tick = 0; tick < 2; tick += 1) frozen.tick();
check(text(frozen.frame(8)) === b, "the third tick did not show frame 2");
for (let tick = 0; tick < 3; tick += 1) frozen.tick();
frozen.restoreLastRendered();
check(text(frozen.frame(8)) === b, "restore did not return to the last painted frame");
frozen.reset();
check(text(frozen.frame(8)) === a, "reset did not restart the loop");
// One row when no frame has a top; water alone when narrower than the widest frame.
const flat = make('schema = "po-sprite/1"\nkind = "frames"\ntick_ms = "220"\nframe.1.base = "ABC"\nframe.2.base = "DE"\n');
check(text(flat.frame(5)) === "ABC▁▁", "a top-less asset did not paint one row");
flat.tick();
check(text(flat.frame(5)) === "DE▁▁▁", "a 220 ms asset did not advance every tick");
check(text(flat.frame(2)) === "▁▁" && flat.frame(0).length === 0, "a narrow width did not fall back to water");
console.log("frames-ok");
JS
)
  assert_contains "$out" "frames-ok" "a frames asset does not loop at its tick: $out"
  pass "a frames asset loops at its tick in scheduler time, freezes, resumes, resets, and falls back to water when too narrow"
}

test_invalid_asset_falls_back() {
  local out
  out=$(js <<'JS'
import { pathToFileURL } from "node:url";
const core = await import(pathToFileURL(`${process.env.LIB}/fm-calm-working-ship-sprite.ts`).href);
const calm = await import(pathToFileURL(`${process.env.LIB}/po-theme-calm.ts`).href);
const check = (ok, message) => { if (!ok) throw new Error(message); };
const invalid = [
  "",
  "kind = glyphs",
  'schema = "po-sprite/1"\nkind = "glyphs"\ntop = "⛵ab"\nbase = "abcde"',
  'schema = "po-sprite/1"\nkind = "glyphs"\ntop = "ab"\nbase = "abcde"',
  'schema = "po-sprite/1"\nkind = "frames"\ntick_ms = "100"\nframe.1.base = "a"',
  'schema = "po-sprite/1"\nkind = "script"\nbody = "x"',
];
for (const asset of invalid) {
  const warnings = [];
  const theme = { values: new Map([["sprite.calm", "t.sprite"]]), assets: new Map([["sprite.calm", asset]]) };
  const sprite = calm.poThemedSprite(core.createCalmWorkingShipSprite(), () => theme, (m) => warnings.push(m));
  const upstream = core.createCalmWorkingShipSprite();
  for (let tick = 0; tick < 50; tick += 1) {
    check(JSON.stringify(sprite.frame(40)) === JSON.stringify(upstream.frame(40)), `an invalid asset drew something other than the sailboat: ${JSON.stringify(asset)}`);
    sprite.tick(); upstream.tick();
  }
  check(warnings.length === 1 && /Calm sprite asset is invalid/.test(warnings[0]), `expected one warning for ${JSON.stringify(asset)}, got ${JSON.stringify(warnings)}`);
}
console.log("fallback-ok");
JS
)
  assert_contains "$out" "fallback-ok" "an invalid asset did not fall back: $out"
  pass "an asset that does not parse draws upstream's sailboat, with exactly one warning"
}

test_pi_loads_asset_from_home() {
  local home out
  home=$(art_home pi "$GLYPHS_ASSET")
  FM_HOME="$home" "$PT" refresh >/dev/null 2>&1 || fail "refresh failed for the art theme"
  assert_equals "test.sprite" "$(awk -F '\t' '$1 == "sprite.calm" { print $2 }' "$home/state/po-theme/values")" "the cache does not name the sprite"
  out=$(FM_HOME="$home" js "$ROOT" <<'JS'
import { readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
const root = process.argv[2];
const values = await import(pathToFileURL(`${process.env.PI_LIB}/po-theme-values.ts`).href);
const pi = await import(pathToFileURL(`${process.env.PI_LIB}/fm-calm-working-ship.ts`).href);
const check = (ok, message) => { if (!ok) throw new Error(message); };
const load = () => values.poThemeLoadSync((path) => readFileSync(path, "utf8"), process.env, root);
// fm-calm.ts loads the theme after it builds the animation; the next frame follows it.
const animation = pi.createCalmWorkingShipAnimation();
check(animation.render(20)[0].includes("◿│◣"), "the animation drew a theme before any load");
load();
const rows = animation.render(20);
check(rows[0].includes("/#+") && rows[1].includes("[===]"), `Pi did not draw the copied asset: ${JSON.stringify(rows)}`);
// A cache naming a path outside assets/ is never read.
const cache = `${process.env.FM_HOME}/state/po-theme/values`;
writeFileSync(`${process.env.FM_HOME}/state/po-theme/escape.sprite`, readFileSync(`${process.env.FM_HOME}/state/po-theme/assets/test.sprite`));
writeFileSync(cache, readFileSync(cache, "utf8").replace("sprite.calm\ttest.sprite", "sprite.calm\t../escape.sprite"));
check(values.poThemeAsset(load(), "sprite.calm") === undefined, "the reader followed a cache path outside assets/");
check(animation.render(20)[0].includes("◿│◣"), "the animation did not return to the sailboat");
console.log("pi-ok");
JS
)
  assert_contains "$out" "pi-ok" "Pi does not load the asset from the home: $out"
  pass "Pi loads the theme and its copied asset from the home refresh wrote, picks it up on the next frame, and never reads outside assets/"
}

# sprite_verdicts <home> <asset-file>...: "<file> ok|error" from bin/po-theme.sh validate and
# from po-theme-calm.ts's parser, one line each, in that order.
sprite_verdicts() {
  local home=$1 f
  shift
  for f in "$@"; do
    cp "$f" "$home/config/po-themes/assets/test.sprite"
    if FM_HOME="$home" "$PT" validate art >/dev/null 2>&1; then echo "${f##*/} ok"; else echo "${f##*/} error"; fi
  done
}

test_validators_and_parity() {
  local home dir out bash_v ts_v f
  home=$(art_home validate "$GLYPHS_ASSET")
  dir="$TMP_ROOT/corpus"
  mkdir -p "$dir"
  printf '%s\n' "$GLYPHS_ASSET" > "$dir/ok-glyphs.sprite"
  printf '%s\n' "$FRAMES_ASSET" > "$dir/ok-frames.sprite"
  printf 'schema = "po-sprite/1"\nkind = "glyphs"\ntop = "◿│◣"\nbase = "╲▁▁▁╱"  # upstream'"'"'s own boat\n' > "$dir/ok-upstream.sprite"
  { printf 'schema = "po-sprite/1"\nkind = "frames"\ntick_ms = "1000"\n'; for f in $(seq 1 16); do printf 'frame.%s.base = "abcdefghijkl"\n' "$f"; done; } > "$dir/ok-sixteen.sprite"
  printf 'schema = "po-sprite/1"\nkind = "frames"\ntick_ms = "120"\nframe.1.base = "⣿"\n' > "$dir/ok-braille.sprite"
  printf 'schema = "po-sprite/1"\nkind = "glyphs"\ntop = "ab"\nbase = "abcde"\n' > "$dir/bad-short-top.sprite"
  printf 'schema = "po-sprite/1"\nkind = "glyphs"\ntop = "⛵ab"\nbase = "abcde"\n' > "$dir/bad-emoji.sprite"
  printf 'schema = "po-sprite/1"\nkind = "glyphs"\ntop = "abc"\nbase = "abcde"\ntick_ms = "200"\n' > "$dir/bad-extra-key.sprite"
  printf 'schema = "po-sprite/2"\nkind = "glyphs"\ntop = "abc"\nbase = "abcde"\n' > "$dir/bad-schema.sprite"
  printf 'schema = "po-sprite/1"\nkind = "code"\n' > "$dir/bad-kind.sprite"
  printf 'schema = po-sprite/1\n' > "$dir/bad-malformed.sprite"
  printf 'schema = "po-sprite/1"\nschema = "po-sprite/1"\nkind = "glyphs"\ntop = "abc"\nbase = "abcde"\n' > "$dir/bad-duplicate.sprite"
  printf 'schema = "po-sprite/1"\nkind = "frames"\ntick_ms = "100"\nframe.1.base = "a"\n' > "$dir/bad-fast.sprite"
  printf 'schema = "po-sprite/1"\nkind = "frames"\ntick_ms = "0440"\nframe.1.base = "a"\n' > "$dir/bad-tick-shape.sprite"
  printf 'schema = "po-sprite/1"\nkind = "frames"\ntick_ms = "440"\nframe.1.base = "a"\nframe.3.base = "b"\n' > "$dir/bad-gap.sprite"
  printf 'schema = "po-sprite/1"\nkind = "frames"\ntick_ms = "440"\nframe.1.base = "a"\nframe.2.top = "b"\n' > "$dir/bad-no-base.sprite"
  printf 'schema = "po-sprite/1"\nkind = "frames"\ntick_ms = "440"\nframe.1.base = "abcdefghijklm"\n' > "$dir/bad-wide.sprite"
  printf 'schema = "po-sprite/1"\nkind = "frames"\ntick_ms = "440"\nframe.0.base = "a"\n' > "$dir/bad-frame-zero.sprite"
  { printf 'schema = "po-sprite/1"\nkind = "frames"\ntick_ms = "1000"\n'; for f in $(seq 1 17); do printf 'frame.%s.base = "a"\n' "$f"; done; } > "$dir/bad-seventeen.sprite"
  { printf 'schema = "po-sprite/1"\nkind = "glyphs"\ntop = "abc"\nbase = "abcde"\n'; for f in $(seq 1 120); do printf '# %s\n' "padding the sprite past its size limit"; done; } > "$dir/bad-large.sprite"
  bash_v=$(sprite_verdicts "$home" "$dir"/*.sprite)
  ts_v=$(js "$dir" <<'JS'
import { readdirSync, readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
const calm = await import(pathToFileURL(`${process.env.LIB}/po-theme-calm.ts`).href);
const dir = process.argv[2];
for (const name of readdirSync(dir).filter((n) => n.endsWith(".sprite")).sort()) {
  console.log(`${name} ${calm.parsePoSprite(readFileSync(`${dir}/${name}`, "utf8")).ok ? "ok" : "error"}`);
}
JS
)
  bash_v=$(printf '%s\n' "$bash_v" | LC_ALL=C sort)
  assert_equals "$bash_v" "$(printf '%s\n' "$ts_v" | LC_ALL=C sort)" "bin/po-theme.sh and po-theme-calm.ts disagree on a sprite"
  for f in "$dir"/*.sprite; do
    case "${f##*/}" in
      ok-*) assert_contains "$bash_v" "${f##*/} ok" "a valid sprite was refused: ${f##*/}" ;;
      bad-*) assert_contains "$bash_v" "${f##*/} error" "an invalid sprite was accepted: ${f##*/}" ;;
    esac
  done

  # Icons and images: each refusal names its reason.
  printf '%s\n' "$GLYPHS_ASSET" > "$home/config/po-themes/assets/test.sprite"
  printf 'icon.brand = "brand.svg"\nimage.banner = "banner.png"\nimage.poster = "poster.svg"\n' >> "$home/config/po-themes/art.theme"
  printf '<path d="M12 6v16"/>\n<path d="m19 13 2-1a9 9 0 0 1-18 0l2 1" />\n<circle cx="12" cy="4" r="2"/>\n<polyline points="1,2 3,4"/><rect x="2" y="2" width="20" height="20" rx="2"/><line x1="0" y1="0" x2="24" y2="24"/>\n' > "$home/config/po-themes/assets/brand.svg"
  printf '\211PNG\r\n\032\n\000\000\000\rIHDR' > "$home/config/po-themes/assets/banner.png"
  printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 2 2"><a href="#x"><rect width="2" height="2"/></a></svg>\n' > "$home/config/po-themes/assets/poster.svg"
  out=$(FM_HOME="$home" "$PT" validate art 2>&1) || fail "valid icon and image assets were refused: $out"
  icon_refuses() {  # <fragment> <reason>
    printf '%s' "$1" > "$home/config/po-themes/assets/brand.svg"
    out=$(FM_HOME="$home" "$PT" validate art 2>&1) && fail "an invalid icon was accepted: $1"
    assert_contains "$out" "$2" "the icon refusal for $1 does not say why"
  }
  icon_refuses '<script>alert(1)</script>' "not a fragment of self-closing"
  icon_refuses '<path d="M1 1" style="fill:red"/>' "<path> may not carry style"
  icon_refuses '<circle cx="1" cy="1" r="1" onload="x"/>' "<circle> may not carry onload"
  icon_refuses '<circle cx="1" cy="30" r="1"/>' "<circle> cy must be a number from 0 to 24"
  icon_refuses '<image href="x.png"/>' "element <image> is not allowed"
  icon_refuses '<path d="url(#a)"/>' "<path> d is not path data"
  icon_refuses '' "holds no element"
  printf '<path d="M1 1"/>' > "$home/config/po-themes/assets/brand.svg"
  printf 'GIF89a' > "$home/config/po-themes/assets/banner.png"
  out=$(FM_HOME="$home" "$PT" validate art 2>&1) && fail "a non-PNG banner was accepted"
  assert_contains "$out" "not a PNG file" "the banner refusal does not say why"
  printf '\211PNG\r\n\032\n' > "$home/config/po-themes/assets/banner.png"
  for f in '<svg><script>x</script></svg>' '<svg><image href="https://example.invalid/a.png"/></svg>' \
           '<svg onclick="x"></svg>' '<svg><rect fill="url(#p)"/></svg>' '<svg><use xlink:href="data:image/png;base64,AA"/></svg>' \
           $'<svg><rect\nonload="x"/></svg>' '<svg><image href="//example.invalid/a.png"/></svg>' \
           '<svg><use href="../x.svg#a"/></svg>' '<?xml-stylesheet href="x.css"?><svg/>' \
           '<svg xmlns:s="http://www.w3.org/2000/svg"><s:script>x</s:script></svg>' '<svg><rect x:onload="x"/><use s:href="x.svg"/></svg>'; do
    printf '%s' "$f" > "$home/config/po-themes/assets/poster.svg"
    out=$(FM_HOME="$home" "$PT" validate art 2>&1) && fail "an unsafe SVG image was accepted: $f"
    assert_contains "$out" "may not carry script" "the image refusal for $f does not say why"
  done
  printf '<svg/>' > "$home/config/po-themes/assets/poster.svg"

  # Picture keys: a known key, a plain file name of the right kind, schema 2, and an existing asset.
  key_refuses() {  # <theme-line> <reason>
    local theme="$home/config/po-themes/art.theme"
    cp "$theme" "$theme.keep"
    printf '%s\n' "$1" >> "$theme"
    out=$(FM_HOME="$home" "$PT" validate art 2>&1) && fail "a bad picture key was accepted: $1"
    assert_contains "$out" "$2" "the refusal for $1 does not say why"
    mv "$theme.keep" "$theme"
  }
  sed -i.bak '/^sprite.calm/d' "$home/config/po-themes/art.theme"
  key_refuses 'sprite.calm = "test.svg"' "sprite.calm: 'test.svg' must be an asset file name"
  key_refuses 'sprite.calm = "../test.sprite"' "sprite.calm: '../test.sprite' must be an asset file name"
  key_refuses 'sprite.other = "test.sprite"' "unknown key: sprite.other"
  key_refuses 'sprite.calm = "absent.sprite"' "sprite.calm: no asset named absent.sprite"
  sed -i.bak 's/^schema = "po-theme\/2"/schema = "po-theme\/1"/; /^label\./d; /^str\./d; /^glyph\./d' "$home/config/po-themes/art.theme"
  key_refuses 'sprite.calm = "test.sprite"' "sprite.calm: needs schema po-theme/2"
  pass "the sprite validator and the TypeScript parser agree on a corpus; icon, image, and picture-key checks refuse what they must, naming why"
}

test_refresh_copies_and_prunes() {
  local home out dir
  home=$(art_home refresh "$GLYPHS_ASSET" 'sprite.calm = "test.sprite"
icon.brand = "brand.svg"')
  printf '<path d="M1 1"/>' > "$home/config/po-themes/assets/brand.svg"
  dir="$home/state/po-theme"
  FM_HOME="$home" "$PT" refresh >/dev/null 2>&1 || fail "refresh failed"
  assert_equals "$GLYPHS_ASSET" "$(cat "$dir/assets/test.sprite")" "refresh did not copy the sprite"
  assert_equals "brand.svg
test.sprite" "$(ls "$dir/assets")" "refresh did not copy exactly the named assets"
  assert_equals "sprite.calm	test.sprite
icon.brand	brand.svg" "$(grep -E '^(sprite|icon|image)[.]' "$dir/values")" "the cache does not name the assets"
  # An asset broken after validation is left out, with a warning, and pruned.
  printf 'kind = "glyphs"\n' > "$home/config/po-themes/assets/test.sprite"
  out=$(FM_HOME="$home" "$PT" refresh 2>&1) || fail "refresh failed over an invalid asset: $out"
  assert_contains "$out" "warn: sprite.calm: asset test.sprite is missing or invalid" "refresh did not warn about the invalid asset"
  assert_equals "icon.brand	brand.svg" "$(grep -E '^(sprite|icon|image)[.]' "$dir/values")" "the cache still names the invalid asset"
  assert_absent "$dir/assets/test.sprite" "refresh kept an asset the cache no longer names"
  assert_equals "▸" "$(awk -F '\t' '$1 == "glyph.ship" { print $2 }' "$dir/values")" "the rest of the cache was not written"
  printf 'nautical\n' > "$home/config/po-theme"
  FM_HOME="$home" "$PT" refresh >/dev/null 2>&1 || fail "refresh failed under nautical"
  assert_absent "$dir/assets" "nautical kept the theme's assets"
  pass "refresh copies valid assets beside the cache, leaves out and prunes an invalid one with a warning, and nautical removes them"
}

test_apply_copies_in_code_root() {
  local code home out s
  code="$TMP_ROOT/apply/code"
  mkdir -p "$code/bin" "$code/.agents/skills"
  cp "$PT" "$ROOT/bin/po-design-lib.sh" "$code/bin/"
  cp -R "$ROOT/.agents/skills/po-theme" "$code/.agents/skills/"
  cp "$ROOT/AGENTS.md" "$ROOT/VISION.md" "$code/"
  for s in afk ahoy bearings lavish-url quiet stow updatefirstmate; do
    mkdir -p "$code/.agents/skills/$s"
    printf -- '---\nname: %s\nuser-invocable: true\n---\n' "$s" > "$code/.agents/skills/$s/SKILL.md"
  done
  git init -q -b main "$code"
  git -C "$code" add -A
  git -C "$code" commit -q -m seed
  home=$(art_home apply "$GLYPHS_ASSET")
  out=$(FM_HOME="$home" "$code/bin/po-theme.sh" apply 2>&1) || fail "apply failed: $out"
  assert_equals "$GLYPHS_ASSET" "$(cat "$home/state/po-theme/assets/test.sprite")" "apply did not copy the sprite beside the cache"
  printf 'kind = "glyphs"\n' > "$home/config/po-themes/assets/test.sprite"
  out=$(FM_HOME="$home" "$code/bin/po-theme.sh" apply 2>&1) && fail "apply accepted an invalid sprite"
  assert_contains "$out" "theme art failed validation" "apply did not refuse the invalid sprite"
  assert_equals "$GLYPHS_ASSET" "$(cat "$home/state/po-theme/assets/test.sprite")" "a refused apply changed the copied asset"
  pass "apply copies the theme's sprite beside the values cache and refuses an invalid one without touching the copy"
}

test_nautical_stream_identical
test_glyphs_keep_motion_and_columns
test_frames_loop_at_tick
test_invalid_asset_falls_back
test_pi_loads_asset_from_home
test_validators_and_parity
test_refresh_copies_and_prunes
test_apply_copies_in_code_root
