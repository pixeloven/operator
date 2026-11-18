// firstmate-calm under `claude plugin test`: the PixelOven theme layer's values reader
// (ADR-0020 stage S3). Under nautical the supervision notes and the /calm description
// are upstream's own; under a theme the note glyphs and the description follow the
// values cache `bin/po-theme.sh refresh` writes, and a cache that does not belong to the
// home's current selection reads as nautical.
import { describe, expect, test } from "claude-code/testing";
import type { On } from "claude-code";
import { HOME, world } from "./support.ts";
import {
  PO_THEME_NAUTICAL,
  parsePoTheme,
  poThemeGlyph,
  poThemeLoadSync,
  poThemeNoteLine,
  poThemeStr,
} from "../lib/po-theme-values.ts";

const sessionStart = { cwd: "/work", surface: "terminal" as const, isInteractive: true };
const STATE = `${HOME}/state`;
const SELECTION = `${HOME}/config/po-theme`;
const VALUES = `${STATE}/po-theme/values`;
const NAUTICAL_CALM = "Toggle Firstmate's Calm transcript presentation and working ship.";
const OPERATOR_CALM = "Toggle Operator's Calm transcript presentation and working animation.";

function cache(fields: Record<string, string>): string {
  return Object.entries(fields)
    .map(([key, value]) => `${key}\t${value}\n`)
    .join("");
}

const OPERATOR_VALUES = cache({
  cache: "po-theme-values/3",
  kind: "primary",
  name: "operator",
  source: "/code/.agents/skills/po-theme/themes/operator.theme",
  "label.primary": "spotter",
  "str.calm.command": OPERATOR_CALM,
  "glyph.ship": "▸",
  "glyph.anchor": "⚑",
});

function tail(): string {
  return [
    { seq: 1, epoch: 100, task: "fm-b", wake: "", verdict: "captain", summary: "decision waiting", silent: false },
    { seq: 2, epoch: 100, task: "fm-c", wake: "", verdict: "routine", summary: "worker healthy", silent: false },
  ]
    .map((row) => `${JSON.stringify({ ...row, statusEndpoint: 0, statusIdent: "-" })}\n`)
    .join("");
}

/** `on` with every `$.command.register` description recorded as the shared mock answers it. */
function watchDescriptions(on: On): { on: On; descriptions: string[] } {
  const descriptions: string[] = [];
  const watched = ((event: string, ...rest: unknown[]) => {
    const handler = rest[rest.length - 1] as (...args: unknown[]) => unknown;
    if (event === "command.register") {
      rest[rest.length - 1] = (...args: unknown[]) => {
        descriptions.push((args[1] as { description?: string }).description ?? "");
        return handler(...args);
      };
    }
    return (on as unknown as (...args: unknown[]) => unknown)(event, ...rest);
  }) as unknown as On;
  return { on: watched, descriptions };
}

describe("theme values in the Calm mod", () => {
  test("a nautical home keeps upstream's note glyphs and /calm description", async ($, on) => {
    const { on: watched, descriptions } = watchDescriptions(on);
    const { files, journal } = world(watched);
    files.set(`${STATE}/.branch-outcomes-tail.jsonl`, tail());
    // A values cache left behind by an earlier theme is ignored once nautical is selected.
    files.set(SELECTION, "nautical\n");
    files.set(VALUES, OPERATOR_VALUES);
    await $.session.start(sessionStart);
    expect(journal.logs).toEqual(["⚓ [seq 1] fm-b: decision waiting", "⛵ fm-c: worker healthy"]);
    expect(descriptions).toEqual([NAUTICAL_CALM]);
  });

  test("a themed home shows the theme's note glyphs and /calm description", async ($, on) => {
    const { on: watched, descriptions } = watchDescriptions(on);
    const { files, journal } = world(watched);
    files.set(`${STATE}/.branch-outcomes-tail.jsonl`, tail());
    files.set(SELECTION, "operator\n");
    files.set(VALUES, OPERATOR_VALUES);
    await $.session.start(sessionStart);
    expect(journal.logs).toEqual(["⚑ [seq 1] fm-b: decision waiting", "▸ fm-c: worker healthy"]);
    expect(descriptions).toEqual([OPERATOR_CALM]);
  });

  test("the theme's latch notes take its glyph too", async ($, on) => {
    const { clock, files, journal } = world(on);
    files.set(SELECTION, "operator\n");
    files.set(VALUES, OPERATOR_VALUES);
    files.set(`${STATE}/.supervision-host-health`, "key=k1\nerrors=0\ncooldown=0\nretry_after=0\n");
    await $.session.start(sessionStart);
    files.set(`${STATE}/.supervision-host-health`, "key=k1\nerrors=2\ncooldown=60\nretry_after=0\n");
    await clock.advance(3000);
    expect(journal.logs).toEqual([
      "▸ Supervision session paused after repeated engine errors; main will handle wakes while it cools down.",
    ]);
  });
});

describe("the values reader", () => {
  const operator = parsePoTheme(OPERATOR_VALUES, "operator\n", false);

  test("a stored upstream note renders with the theme's glyph, and other text is untouched", () => {
    expect(poThemeNoteLine(operator, "⛵ fm-a: written before the theme")).toBe("▸ fm-a: written before the theme");
    expect(poThemeNoteLine(operator, "⚓ [seq 4] fm-a: old captain row")).toBe("⚑ [seq 4] fm-a: old captain row");
    expect(poThemeNoteLine(operator, "▸ fm-a: already themed")).toBe("▸ fm-a: already themed");
    expect(poThemeNoteLine(operator, "no glyph here")).toBe("no glyph here");
    expect(poThemeNoteLine(PO_THEME_NAUTICAL, "⛵ fm-a: kept")).toBe("⛵ fm-a: kept");
  });

  test("strings fall back to upstream's literal for a missing key or a nautical home", () => {
    expect(poThemeStr(operator, "calm.command", NAUTICAL_CALM)).toBe(OPERATOR_CALM);
    expect(poThemeStr(operator, "calm.name", "Firstmate Calm")).toBe("Firstmate Calm");
    expect(poThemeStr(PO_THEME_NAUTICAL, "calm.command", NAUTICAL_CALM)).toBe(NAUTICAL_CALM);
    expect(poThemeGlyph(PO_THEME_NAUTICAL, "anchor")).toBe("⚓");
  });

  test("only a cache for the home's current source counts", () => {
    expect(parsePoTheme(OPERATOR_VALUES, "other\n", false)).toBe(PO_THEME_NAUTICAL);
    expect(parsePoTheme(OPERATOR_VALUES, undefined, false)).toBe(PO_THEME_NAUTICAL);
    expect(parsePoTheme(OPERATOR_VALUES.replace("po-theme-values/3", "po-theme-values/2"), "operator", false)).toBe(
      PO_THEME_NAUTICAL,
    );
    expect(parsePoTheme(OPERATOR_VALUES, undefined, true)).toBe(PO_THEME_NAUTICAL);
    const inherited = parsePoTheme(OPERATOR_VALUES.replace("kind\tprimary", "kind\tsecondmate"), undefined, true);
    expect(poThemeGlyph(inherited, "ship")).toBe("▸");
  });

  test("Pi's synchronous loader reads the same home files and never throws", () => {
    const files = new Map([
      ["/fm/pi/config/po-theme", "operator\n"],
      ["/fm/pi/state/po-theme/values", OPERATOR_VALUES],
    ]);
    const read = (path: string): string => {
      const text = files.get(path);
      if (text === undefined) throw new Error(`ENOENT: ${path}`);
      return text;
    };
    expect(poThemeGlyph(poThemeLoadSync(read, { FM_HOME: "/fm/pi" }, "/code"), "anchor")).toBe("⚑");
    expect(poThemeLoadSync(read, {}, "/code")).toBe(PO_THEME_NAUTICAL);
  });

  test("a secondmate home trusts its cache only while it inherits a Persona block", () => {
    const files = new Map([
      ["/fm/mate/.fm-secondmate-home", "gfm\n"],
      ["/fm/mate/state/po-theme/values", OPERATOR_VALUES.replace("kind\tprimary", "kind\tsecondmate")],
      ["/fm/mate/data/captain-shared.md", "# Shared\n<!-- po-theme:persona:start -->\n## Persona\n<!-- po-theme:persona:end -->\n"],
      ["/fm/shared/captain-shared.md", "# Shared\n"],
    ]);
    const read = (path: string): string => {
      const text = files.get(path);
      if (text === undefined) throw new Error(`ENOENT: ${path}`);
      return text;
    };
    expect(poThemeGlyph(poThemeLoadSync(read, { FM_HOME: "/fm/mate" }, "/code"), "ship")).toBe("▸");
    expect(poThemeLoadSync(read, { FM_HOME: "/fm/mate", FM_DATA_OVERRIDE: "/fm/shared" }, "/code")).toBe(PO_THEME_NAUTICAL);
    files.set("/fm/mate/data/captain-shared.md", "# Shared\n");
    expect(poThemeLoadSync(read, { FM_HOME: "/fm/mate" }, "/code")).toBe(PO_THEME_NAUTICAL);
  });
});
