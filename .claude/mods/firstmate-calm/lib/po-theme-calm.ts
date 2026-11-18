// PixelOven theme wrapper for the Calm working animation (ADR-0020 decision 10, stage S4).
//
// Each harness constructs upstream's sprite in exactly one hooked line and passes it
// through poThemedSprite(), which consults the theme in force on every frame:
//   - nautical, or a theme with no `sprite.calm` asset: every call goes to upstream's
//     sprite untouched, so the frame stream is byte-identical to upstream's;
//   - a `glyphs` asset: upstream's sprite still owns motion, swell, freeze, and resume,
//     and only its boat-colored sail and hull runs take the asset's cells, which have
//     the same column counts;
//   - a `frames` asset: the wrapper paints the asset's frames itself, in upstream's
//     three color classes, looping on the asset's tick measured in scheduler time.
// An asset that does not parse falls back to upstream's sailboat with one warning.
//
// The asset is data in the strict `po-sprite/1` text format, never code;
// docs/pixeloven/persona-themes.md owns the format and `bin/po-theme.sh` validates it
// before `apply` copies it beside the values cache. This module re-parses it with the
// same rules before every use, since the copy is a home file anyone can edit.
//
// It lives inside the Claude Code plugin folder because Claude Code refuses a
// hooks-module import from outside it; Pi reaches it through the tracked symlink
// .pi/extensions/lib/po-theme-calm.ts. Like po-theme-values.ts it imports no harness
// and touches no file system: the theme arrives already loaded.
import {
  CALM_WORKING_SHIP_HULL,
  CALM_WORKING_SHIP_SAIL,
  CALM_WORKING_SHIP_TICK_MS,
  type CalmWorkingShipFrame,
  type CalmWorkingShipRun,
  type CalmWorkingShipSprite,
} from "./fm-calm-working-ship-sprite.ts";
import { poThemeAsset, poThemeInForce, type PoTheme } from "./po-theme-values.ts";

/** The theme key whose asset replaces the Calm working animation. */
export const PO_THEME_CALM_SPRITE_KEY = "sprite.calm";

/** The sprite format this module accepts. */
export const PO_SPRITE_SCHEMA = "po-sprite/1";

/** Limits of the `frames` kind (ADR-0020 decision 10). */
export const PO_SPRITE_MAX_FRAMES = 16;
export const PO_SPRITE_MAX_FRAME_CELLS = 12;
export const PO_SPRITE_TICK_MIN_MS = 120;
export const PO_SPRITE_TICK_MAX_MS = 1000;
/** Largest sprite file accepted, in UTF-8 bytes. */
export const PO_SPRITE_MAX_BYTES = 4096;

export type PoSprite =
  | { readonly kind: "glyphs"; readonly top: string; readonly base: string }
  | {
      readonly kind: "frames";
      readonly tickMs: number;
      readonly frames: readonly { readonly top: string; readonly base: string }[];
    };

export type PoSpriteParse =
  | { readonly ok: true; readonly sprite: PoSprite }
  | { readonly ok: false; readonly error: string };

const LINE = /^([a-z][a-z0-9_]*(?:\.[a-z0-9][a-z0-9_-]*)*)\s*=\s*"([^"\\]*)"\s*(?:#.*)?$/;
const FRAME_KEY = /^frame\.([1-9][0-9]?)\.(top|base)$/;

/** One terminal column under both harnesses: printable ASCII, box drawing, blocks, geometric shapes, braille. */
function allowedGlyph(codePoint: number): boolean {
  return (
    (codePoint >= 0x20 && codePoint <= 0x7e) ||
    (codePoint >= 0x2500 && codePoint <= 0x25ff) ||
    (codePoint >= 0x2800 && codePoint <= 0x28ff)
  );
}

/** The cells of a sprite row, or an error naming the first glyph outside the allow-list. */
function cellsOf(key: string, value: string): string[] | string {
  const cells = Array.from(value);
  for (const cell of cells) {
    const codePoint = cell.codePointAt(0) ?? 0;
    if (!allowedGlyph(codePoint)) {
      return `${key}: U+${codePoint.toString(16).toUpperCase().padStart(4, "0")} is not an allowed sprite glyph`;
    }
  }
  return cells;
}

/** Parse and validate `po-sprite/1` text with the rules `bin/po-theme.sh` applies. */
export function parsePoSprite(text: string): PoSpriteParse {
  const fail = (error: string): PoSpriteParse => ({ ok: false, error });
  let bytes = 0;
  for (const char of text) {
    const codePoint = char.codePointAt(0) ?? 0;
    bytes += codePoint < 0x80 ? 1 : codePoint < 0x800 ? 2 : codePoint < 0x10000 ? 3 : 4;
  }
  if (bytes > PO_SPRITE_MAX_BYTES) return fail(`larger than ${PO_SPRITE_MAX_BYTES} bytes`);
  const fields = new Map<string, string>();
  const lines = text.split("\n");
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index]!.replace(/\r$/, "");
    if (/^\s*(#|$)/.test(line)) continue;
    const match = LINE.exec(line);
    if (match === null) return fail(`line ${index + 1}: malformed (expected key = "value")`);
    const [, key, value] = match;
    if (fields.has(key!)) return fail(`line ${index + 1}: duplicate key ${key}`);
    fields.set(key!, value!);
  }
  if (fields.get("schema") !== PO_SPRITE_SCHEMA) return fail(`schema must be "${PO_SPRITE_SCHEMA}"`);
  const kind = fields.get("kind");
  if (kind === "glyphs") {
    for (const key of fields.keys()) {
      if (!["schema", "kind", "top", "base"].includes(key)) return fail(`unknown key for kind glyphs: ${key}`);
    }
    const top = cellsOf("top", fields.get("top") ?? "");
    if (typeof top === "string") return fail(top);
    const base = cellsOf("base", fields.get("base") ?? "");
    if (typeof base === "string") return fail(base);
    const sail = Array.from(CALM_WORKING_SHIP_SAIL).length;
    const hull = Array.from(CALM_WORKING_SHIP_HULL).length;
    if (top.length !== sail) return fail(`top must be exactly ${sail} cells`);
    if (base.length !== hull) return fail(`base must be exactly ${hull} cells`);
    return { ok: true, sprite: { kind: "glyphs", top: top.join(""), base: base.join("") } };
  }
  if (kind === "frames") {
    const rows = new Map<number, { top?: string; base?: string }>();
    for (const [key, value] of fields) {
      if (key === "schema" || key === "kind" || key === "tick_ms") continue;
      const frameKey = FRAME_KEY.exec(key);
      if (frameKey === null) return fail(`unknown key for kind frames: ${key}`);
      const number = Number(frameKey[1]);
      const cells = cellsOf(key, value);
      if (typeof cells === "string") return fail(cells);
      if (cells.length < 1 || cells.length > PO_SPRITE_MAX_FRAME_CELLS) {
        return fail(`${key} must be 1-${PO_SPRITE_MAX_FRAME_CELLS} cells`);
      }
      const row = rows.get(number) ?? {};
      row[frameKey[2] as "top" | "base"] = cells.join("");
      rows.set(number, row);
    }
    const tick = fields.get("tick_ms") ?? "";
    if (!/^[1-9][0-9]*$/.test(tick) || Number(tick) < PO_SPRITE_TICK_MIN_MS || Number(tick) > PO_SPRITE_TICK_MAX_MS) {
      return fail(`tick_ms must be a whole number of milliseconds from ${PO_SPRITE_TICK_MIN_MS} to ${PO_SPRITE_TICK_MAX_MS}`);
    }
    if (rows.size < 1 || rows.size > PO_SPRITE_MAX_FRAMES) return fail(`needs 1-${PO_SPRITE_MAX_FRAMES} frames`);
    const frames: { top: string; base: string }[] = [];
    for (let number = 1; number <= rows.size; number += 1) {
      const row = rows.get(number);
      if (row === undefined) return fail(`frames must be numbered 1-${rows.size} without gaps`);
      if (row.base === undefined) return fail(`frame.${number}.base is missing`);
      frames.push({ top: row.top ?? "", base: row.base });
    }
    return { ok: true, sprite: { kind: "frames", tickMs: Number(tick), frames } };
  }
  return fail('kind must be "glyphs" or "frames"');
}

/** The theme's parsed Calm sprite, or undefined for upstream's sailboat. */
type Resolved = { readonly text: string | undefined; readonly sprite: PoSprite | undefined };

/**
 * Wrap upstream's Calm sprite so it draws the theme's `sprite.calm` asset.
 *
 * `theme` is read on every frame, so a theme a harness loads after constructing the
 * sprite applies from the next frame on. The default is the theme its harness last
 * loaded through po-theme-values.ts. `warn` receives one line for each distinct asset
 * that fails to parse; the sprite then draws upstream's sailboat.
 */
export function poThemedSprite(
  inner: CalmWorkingShipSprite,
  theme: () => PoTheme = poThemeInForce,
  warn: (message: string) => void = (message) => {
    if (typeof console !== "undefined") console.warn(message);
  },
): CalmWorkingShipSprite {
  let resolved: Resolved = { text: undefined, sprite: undefined };
  // The frames kind keeps its own cadence beside upstream's, so freeze, resume, and
  // reset behave alike and a theme switch never needs to rewind upstream's sprite.
  let ticks = 0;
  let renderedTicks = 0;

  const current = (): PoSprite | undefined => {
    const text = poThemeAsset(theme(), PO_THEME_CALM_SPRITE_KEY);
    if (text === resolved.text) return resolved.sprite;
    let sprite: PoSprite | undefined;
    if (text !== undefined) {
      const parsed = parsePoSprite(text);
      if (parsed.ok) sprite = parsed.sprite;
      else warn(`PixelOven theme: the Calm sprite asset is invalid (${parsed.error}); drawing the sailboat`);
    }
    resolved = { text, sprite };
    return sprite;
  };

  const glyphsFrame = (frame: CalmWorkingShipFrame, sprite: { top: string; base: string }): CalmWorkingShipFrame =>
    frame.map((row) =>
      row.map((run): CalmWorkingShipRun => {
        if (run.color !== "boat") return run;
        if (run.text === CALM_WORKING_SHIP_SAIL) return { text: sprite.top, color: "boat" };
        if (run.text === CALM_WORKING_SHIP_HULL) return { text: sprite.base, color: "boat" };
        return run;
      }),
    );

  const framesFrame = (
    width: number,
    sprite: { tickMs: number; frames: readonly { top: string; base: string }[] },
  ): CalmWorkingShipFrame => {
    if (width <= 0) return [];
    const index = Math.floor((ticks * CALM_WORKING_SHIP_TICK_MS) / sprite.tickMs) % sprite.frames.length;
    const { top, base } = sprite.frames[index]!;
    const widest = Math.max(...sprite.frames.map((frame) => Math.max(Array.from(frame.top).length, Array.from(frame.base).length)));
    const water = (count: number): CalmWorkingShipRun[] =>
      Array.from({ length: Math.max(0, count) }, () => ({ text: "▁", color: "water" as const }));
    renderedTicks = ticks;
    // Too narrow for the widest frame: a deterministic single row of low water, as upstream does.
    if (width < widest) return [water(width)];
    const baseCells = Array.from(base).length;
    const bottom: CalmWorkingShipRun[] = [{ text: base, color: "boat" }, ...water(width - baseCells)];
    if (!sprite.frames.some((frame) => frame.top !== "")) return [bottom];
    return [top === "" ? [] : [{ text: top, color: "boat" }], bottom];
  };

  return {
    frame(width: number): CalmWorkingShipFrame {
      const sprite = current();
      if (sprite?.kind === "frames") {
        // Upstream's sprite still tracks the width so a switch back resumes cleanly.
        inner.clampToWidth(width);
        return framesFrame(width, sprite);
      }
      renderedTicks = ticks;
      const frame = inner.frame(width);
      return sprite?.kind === "glyphs" ? glyphsFrame(frame, sprite) : frame;
    },
    tick(): void {
      ticks += 1;
      inner.tick();
    },
    restoreLastRendered(): void {
      ticks = renderedTicks;
      inner.restoreLastRendered();
    },
    reset(): void {
      ticks = 0;
      renderedTicks = 0;
      inner.reset();
    },
    clampToWidth(width: number): void {
      inner.clampToWidth(width);
    },
    position: () => (current()?.kind === "frames" ? 0 : inner.position()),
    direction: () => (current()?.kind === "frames" ? 1 : inner.direction()),
    waterPhase: () => inner.waterPhase(),
  };
}
