// firstmate-calm under `claude plugin test`: the PixelOven theme's Calm sprite asset
// (ADR-0020 stage S4). The mod loads the asset `apply` copied beside the values cache
// at session start; a `glyphs` asset redraws only the boat over upstream's motion, a
// `frames` asset loops on its own tick, and an asset that does not parse leaves
// upstream's sailboat. tests/po-theme-calm.test.sh owns the long frame-stream sweeps.
import { describe, expect, test } from "claude-code/testing";
import { HOME, decodeCells, rasterOf, spinner, world } from "./support.ts";

const sessionStart = { cwd: "/work", surface: "terminal" as const, isInteractive: true };
const SELECTION = `${HOME}/config/po-theme`;
const VALUES = `${HOME}/state/po-theme/values`;
const ASSET = `${HOME}/state/po-theme/assets/test.sprite`;
const SAIL = "◿│◣";
const HULL = "╲▁▁▁╱";
const BOAT = 0xd77757;
const TICK = 220;

const CACHE = [
  "cache\tpo-theme-values/3",
  "kind\tprimary",
  "name\tart",
  "source\t/fm/home/config/po-themes/art.theme",
  "sprite.calm\ttest.sprite",
  "",
].join("\n");

const GLYPHS = 'schema = "po-sprite/1"\nkind = "glyphs"\ntop = "/#+"\nbase = "[===]"\n';

const FRAMES = [
  'schema = "po-sprite/1"',
  'kind = "frames"',
  'tick_ms = "440"',
  'frame.1.top = "<>"',
  'frame.1.base = "AB"',
  'frame.2.top = "><"',
  'frame.2.base = "CD"',
  "",
].join("\n");

function themed(files: Map<string, string>, asset: string): void {
  files.set(SELECTION, "art\n");
  files.set(VALUES, CACHE);
  files.set(ASSET, asset);
}

describe("the themed Calm sprite", () => {
  test("a glyphs asset replaces the sail and hull at upstream's columns", async ($, on) => {
    const { files } = world(on, { preference: "on\n" });
    themed(files, GLYPHS);
    await $.session.start(sessionStart);
    const raster = rasterOf(await $.ui.render(spinner("agent-main", { columns: 40, rows: 24 })));
    expect(raster!.rows).toBe(2);
    const { glyphs, foregrounds } = decodeCells(raster!.cells, 38, 2);
    expect(glyphs[0]!.indexOf("/#+")).toBe(1);
    expect(glyphs[1]!.indexOf("[===]")).toBe(0);
    expect(glyphs[0]!.includes(SAIL)).toBe(false);
    expect(foregrounds[1]!.slice(0, 5)).toEqual([BOAT, BOAT, BOAT, BOAT, BOAT]);
    expect(glyphs[1]!.slice(5)).toMatch(/^[▁▂▃▄]+$/);
  });

  test("a frames asset loops on its own tick through the mocked clock", async ($, on) => {
    const { clock, files } = world(on, { preference: "on\n" });
    themed(files, FRAMES);
    await $.session.start(sessionStart);
    const draw = async (): Promise<string[]> => {
      const raster = rasterOf(await $.ui.render(spinner("agent-main", { columns: 12, rows: 24 })));
      return decodeCells(raster!.cells, 10, raster!.rows).glyphs.map((row) => row.trimEnd());
    };
    expect(await draw()).toEqual(["<>", "AB▁▁▁▁▁▁▁▁"]);
    await clock.advance(TICK);
    expect(await draw()).toEqual(["<>", "AB▁▁▁▁▁▁▁▁"]);
    await clock.advance(TICK);
    expect(await draw()).toEqual(["><", "CD▁▁▁▁▁▁▁▁"]);
    await clock.advance(2 * TICK);
    expect(await draw()).toEqual(["<>", "AB▁▁▁▁▁▁▁▁"]);
  });

  test("an asset that does not parse leaves upstream's sailboat", async ($, on) => {
    const { files } = world(on, { preference: "on\n" });
    themed(files, 'schema = "po-sprite/1"\nkind = "glyphs"\ntop = "⛵ab"\nbase = "abcde"\n');
    await $.session.start(sessionStart);
    const raster = rasterOf(await $.ui.render(spinner("agent-main", { columns: 40, rows: 24 })));
    const { glyphs } = decodeCells(raster!.cells, 38, 2);
    expect(glyphs[0]!.indexOf(SAIL)).toBe(1);
    expect(glyphs[1]!.indexOf(HULL)).toBe(0);
  });

  test("a nautical selection ignores an asset left behind by an earlier theme", async ($, on) => {
    const { files } = world(on, { preference: "on\n" });
    themed(files, GLYPHS);
    files.set(SELECTION, "nautical\n");
    await $.session.start(sessionStart);
    const raster = rasterOf(await $.ui.render(spinner("agent-main", { columns: 40, rows: 24 })));
    const { glyphs } = decodeCells(raster!.cells, 38, 2);
    expect(glyphs[0]!.indexOf(SAIL)).toBe(1);
  });
});
