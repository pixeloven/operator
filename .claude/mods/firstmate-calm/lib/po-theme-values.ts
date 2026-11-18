// PixelOven theme values for the Calm mod and the Pi extensions (ADR-0020 decision 6).
//
// One reader of the values cache `bin/po-theme.sh refresh` writes to
// state/po-theme/values (its format is owned there and by bin/po-theme-lib.sh), shared
// by the Claude Code mod and, through the tracked symlink
// .pi/extensions/lib/po-theme-values.ts, by the Pi extensions. It lives inside the mod's
// plugin folder because Claude Code refuses a hooks-module import from outside it.
//
// The module imports nothing and touches no file system: each harness passes its own
// reader (Claude Code's `$.fs.read`, Pi's `readFileSync`), so it stays pure and runs
// under Node in tests. Every registered upstream hook calls it with upstream's own
// literal as the fallback, so a nautical home - no selection, `nautical` selected, a
// secondmate home with no inherited Persona block, or any cache that is missing, stale,
// or of another format - returns that literal untouched.
//
// Supervision-note glyphs are themed at display time only: the stored note, the outcome
// store, and every message the model reads keep upstream's ⛵ and ⚓, so a note written
// under any theme, or before a theme was applied, still renders styled with the glyph
// of the theme in force.

/** The cache format this reader accepts; `bin/po-theme.sh refresh` writes it. */
export const PO_THEME_VALUES_CACHE = "po-theme-values/3";

/** Upstream's supervision-note glyphs, which every hook keeps in what it stores. */
export const PO_THEME_NAUTICAL_GLYPHS = { ship: "⛵", anchor: "⚓" } as const;

export type PoThemeGlyph = keyof typeof PO_THEME_NAUTICAL_GLYPHS;

export type PoTheme = { readonly values: ReadonlyMap<string, string> };

export type PoThemeEnvironment = {
  readonly FM_HOME?: string | undefined;
  readonly FM_ROOT_OVERRIDE?: string | undefined;
  readonly FM_CONFIG_OVERRIDE?: string | undefined;
  readonly FM_DATA_OVERRIDE?: string | undefined;
  readonly FM_STATE_OVERRIDE?: string | undefined;
};

export type PoThemeFiles = {
  /** state/po-theme/values. */
  readonly values: string;
  /** config/po-theme, the primary home's selection. */
  readonly selection: string;
  /** The secondmate-home marker, whose presence makes the inherited Persona block authoritative. */
  readonly secondmate: string;
  /** data/captain-shared.md, which carries a secondmate home's inherited Persona block. */
  readonly persona: string;
};

export const PO_THEME_NAUTICAL: PoTheme = { values: new Map() };

/** The home files the theme in force is read from, resolved as the Calm preference path is. */
export function poThemeFiles(env: PoThemeEnvironment, codeRoot: string): PoThemeFiles {
  const home = env.FM_HOME || env.FM_ROOT_OVERRIDE || codeRoot;
  return {
    values: `${env.FM_STATE_OVERRIDE || `${home}/state`}/po-theme/values`,
    selection: `${env.FM_CONFIG_OVERRIDE || `${home}/config`}/po-theme`,
    secondmate: `${home}/.fm-secondmate-home`,
    persona: `${env.FM_DATA_OVERRIDE || `${home}/data`}/captain-shared.md`,
  };
}

/**
 * The theme in force from the three files' contents (undefined when absent). The cache
 * counts only when it is in this reader's format and was written for this home's
 * current source: a primary home's selection naming the cached theme, or a secondmate
 * home's inherited block. Anything else reads as nautical.
 */
export function parsePoTheme(
  values: string | undefined,
  selection: string | undefined,
  secondmate: boolean,
): PoTheme {
  if (values === undefined) return PO_THEME_NAUTICAL;
  const fields = new Map<string, string>();
  for (const line of values.split("\n")) {
    const tab = line.indexOf("\t");
    if (tab > 0 && line.slice(tab + 1) !== "") fields.set(line.slice(0, tab), line.slice(tab + 1));
  }
  if (fields.get("cache") !== PO_THEME_VALUES_CACHE) return PO_THEME_NAUTICAL;
  if (secondmate) return fields.get("kind") === "secondmate" ? { values: fields } : PO_THEME_NAUTICAL;
  const selected = (selection ?? "").split("\n")[0]!.replace(/\s/g, "");
  if (selected === "" || selected === "nautical") return PO_THEME_NAUTICAL;
  return fields.get("kind") === "primary" && fields.get("name") === selected ? { values: fields } : PO_THEME_NAUTICAL;
}

/** Pi: read the theme in force with a synchronous reader that may throw on an absent file. */
export function poThemeLoadSync(read: (path: string) => string, env: PoThemeEnvironment, codeRoot: string): PoTheme {
  const files = poThemeFiles(env, codeRoot);
  const text = (path: string): string | undefined => {
    try {
      return read(path);
    } catch {
      return undefined;
    }
  };
  // The selection or the inherited Persona block decides first, so a nautical home reads nothing more.
  const secondmate = text(files.secondmate) !== undefined;
  const selection = secondmate ? undefined : text(files.selection);
  if (secondmate ? !poThemeInherited(text(files.persona)) : !poThemeSelected(selection)) return PO_THEME_NAUTICAL;
  return parsePoTheme(text(files.values), selection, secondmate);
}

/**
 * Claude Code: the same, from the mod's asynchronous reader (undefined for an absent
 * file) and plugin root, which sits three directories below the tracked code root.
 */
export async function poThemeLoad(
  read: (path: string) => Promise<string | undefined>,
  env: PoThemeEnvironment,
  pluginRoot: string,
): Promise<PoTheme> {
  const files = poThemeFiles(env, codeRootOfPlugin(pluginRoot));
  const text = async (path: string): Promise<string | undefined> => {
    try {
      return await read(path);
    } catch {
      return undefined;
    }
  };
  const secondmate = (await text(files.secondmate)) !== undefined;
  const selection = secondmate ? undefined : await text(files.selection);
  if (secondmate ? !poThemeInherited(await text(files.persona)) : !poThemeSelected(selection)) return PO_THEME_NAUTICAL;
  return parsePoTheme(await text(files.values), selection, secondmate);
}

function poThemeSelected(selection: string | undefined): boolean {
  const selected = (selection ?? "").split("\n")[0]!.replace(/\s/g, "");
  return selected !== "" && selected !== "nautical";
}

function poThemeInherited(persona: string | undefined): boolean {
  return (persona ?? "").split("\n").includes("<!-- po-theme:persona:start -->");
}

function codeRootOfPlugin(pluginRoot: string): string {
  let path = pluginRoot.replace(/\/+$/, "");
  for (let up = 0; up < 3; up++) path = path.slice(0, Math.max(path.lastIndexOf("/"), 0)) || "/";
  return path;
}

/** The themed display string for a registered `str.<name>` key, else upstream's literal. */
export function poThemeStr(theme: PoTheme, name: string, nautical: string): string {
  return theme.values.get(`str.${name}`) ?? nautical;
}

/** The themed glyph for a supervision-note glyph, else upstream's. */
export function poThemeGlyph(theme: PoTheme, name: PoThemeGlyph): string {
  return theme.values.get(`glyph.${name}`) ?? PO_THEME_NAUTICAL_GLYPHS[name];
}

/**
 * A supervision note as displayed: a leading ⛵ or ⚓ (or the glyph the theme in force
 * uses for it) becomes the theme's glyph; any other text is returned unchanged.
 */
export function poThemeNoteLine(theme: PoTheme, line: string): string {
  for (const name of Object.keys(PO_THEME_NAUTICAL_GLYPHS) as PoThemeGlyph[]) {
    const themed = poThemeGlyph(theme, name);
    for (const glyph of [PO_THEME_NAUTICAL_GLYPHS[name], themed]) {
      if (line.startsWith(glyph)) return `${themed}${line.slice(glyph.length)}`;
    }
  }
  return line;
}
