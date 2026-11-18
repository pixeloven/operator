#!/usr/bin/env bash
# po-theme.sh - PixelOven persona and vocabulary theme layer (ADR-0016,
# amended by ADR-0020).
#
# Upstream firstmate text stays byte-identical. A theme changes only display
# words: what the agents call themselves and the user in chat, their seasoning,
# the fixed no-op reply, the vocabulary workers use in prose a person reads, the
# slash commands a person types, the herdr and Paseo workspace labels, and the
# registered display strings (the herdr sidebar state, the wedge-alarm title,
# the /bearings digest section names the Persona block maps, the Calm and
# supervision menu descriptions and Calm notice, the Bearings board's words, the
# fleet view's headings, and the human inbox commands' words), the
# supervision-note glyphs, the voice relay's spoken words, the alias skills'
# menu descriptions, and the pictures a theme names as validated data assets
# (the Calm working animation, the board icons, and the docs pictures a later
# stage draws).
# It never renames an identifier (script, path, environment variable,
# skill directory, status verb, board payload key, or a brief heading that code
# parses) and never changes what a rule means.
#
# Theme files are a strict TOML subset: one `key = "value"` per line, `#`
# comments, no tables, no escapes, so they parse with awk under Bash 3.2.
# Bundled themes live in .agents/skills/po-theme/themes/; a home may add its own
# as config/po-themes/<name>.theme. The bundled nautical theme is the schema:
# every theme defines exactly its keys, plus optional avoid.<word> entries;
# the label.* and str.* keys are optional under schema po-theme/2 and derive
# from the role words when absent.
#
# Selection: the first line of config/po-theme in the primary home; absent means
# nautical, which writes nothing, so a home without a selection is byte-for-byte
# upstream. A secondmate home (.fm-secondmate-home marker) ignores any local
# selection and resolves the theme from the values line of the Persona block it
# inherits read-only through data/captain-shared.md, so custom themes that exist
# only in the primary's config/po-themes/ still resolve there.
#
# Home paths follow upstream's resolution: FM_HOME, else FM_ROOT_OVERRIDE, else
# this script's code root; FM_CONFIG_OVERRIDE and FM_DATA_OVERRIDE are honored.
# Bundled themes, skills, aliases, and anchors always use this script's code root.
#
# Usage:
#   po-theme.sh resolve               print "<name> <source>" for the active theme
#   po-theme.sh term <key> [--theme T]
#                                     print one value of the active (or named) theme
#   po-theme.sh validate [T]          schema, shape, safety, and corpus-collision
#                                     checks; exit 1 on any error
#   po-theme.sh persona [T]           print the Persona block (empty for nautical)
#   po-theme.sh apply                 primary home only: write or remove the Persona
#                                     block in data/captain-shared.md and regenerate
#                                     the slash-command alias skills, hidden through
#                                     a delimited block of .git/info/exclude
#   po-theme.sh verify                exit 1 when the Persona block or aliases drifted
#                                     from the selected theme (stale, hand-edited,
#                                     missing, or unexpected); in a secondmate home,
#                                     when the inherited block is hand-edited,
#                                     lacks keys this checkout's schema added, or
#                                     differs from the bundled theme of its name
#   po-theme.sh headline              the session-start head lines: the applied
#                                     block's address word, no-op reply, and role
#                                     words, a pointer to the full block, and one
#                                     "persona drift" line when verify fails
#                                     (empty for nautical)
#   po-theme.sh anchors               sync canary: every nautical value still matches
#                                     the upstream text it mirrors, every
#                                     user-invocable skill has an alias key, the
#                                     ADR-0016 hook hunks are present, and the
#                                     surface canary finds no person-facing
#                                     producer line with a nautical word that is
#                                     neither a registered hook nor residue
#   po-theme.sh address-alt           themed vocative for bin/fm-dod-lib.sh's
#                                     intent-address check: the applied Persona
#                                     block's, else the selection's (empty for nautical)
#   po-theme.sh worker-line           one-line worker vocabulary for the launch role
#                                     contract (empty for nautical)
#   po-theme.sh wake-line             one-line vocabulary for the supervision branch's
#                                     per-wake prompt, so its outcome notes use the
#                                     theme's words (empty for nautical; the system
#                                     prompt never carries it)
#   po-theme.sh voice-line            one-line vocabulary bin/fm-voice-relay.py adds
#                                     after the voice model's system text, so its
#                                     spoken answers use the theme's words (empty
#                                     for nautical)
#   po-theme.sh render-board <template>
#                                     print the Bearings board template in this
#                                     home's theme and design system for
#                                     bin/fm-bearings-board.sh: the registered
#                                     template lines with the theme's strings and
#                                     validated icons from the values cache, and a
#                                     design system other than the Firstmate Default
#                                     as one style element after the template's
#                                     own; byte for byte under nautical and the
#                                     Firstmate Default, and unthemed on any failure
#   po-theme.sh label <role>          the workspace label for primary, submate, or
#                                     afk (bin/po-theme-lib.sh po_label)
#   po-theme.sh refresh               rebuild state/po-theme/values for this home,
#                                     copy the theme's valid picture assets into
#                                     state/po-theme/assets (warning on an invalid
#                                     one, which keeps nautical's picture), and
#                                     record its labels in state/po-theme/history;
#                                     nautical removes the values file and assets
#                                     and keeps history
#   po-theme.sh relabel [--session S] [--hc] [--dry-run]
#                                     needs --session, --hc, or both.
#                                     herdr: rename this home's recorded workspaces in
#                                     session S (ids from state/*.meta) whose label
#                                     is in the home's accept-set to the current
#                                     label (a primary home's kind=secondmate record:
#                                     that secondmate's label, only once its own
#                                     home's checkout resolves it and accepts the current one), then
#                                     retire history words no live
#                                     workspace of this home still uses (herdr
#                                     sessions S and those its task records name,
#                                     and every Paseo workspace, plus the Herdr
#                                     app's spaces when this home has hc
#                                     records); an unlistable one keeps every
#                                     history word.
#                                     --hc: rename this home's Herdr app spaces
#                                     (hc-spaces below) in the open app window
#   po-theme.sh hc-spaces <task-id>   name the Herdr app spaces an hc spawn of
#                                     <task-id> touched: its terminal's space under
#                                     the home's label (a primary home's
#                                     kind=secondmate record: that secondmate's
#                                     label) and the launching supervisor's own
#                                     terminal's space under the home's label. A
#                                     space is renamed only while it carries the
#                                     app's automatic name or one of the labels'
#                                     accept-set words; a name a person chose is
#                                     kept. A closed window is a silent no-op.
#   po-theme.sh registry files        upstream-owned files that carry theme hooks
#   po-theme.sh registry check-diff <ref>
#                                     gate A9: every line a registered upstream-owned
#                                     file changes against <ref> is its registered hook
#   po-theme.sh ds-resolve            print "<name> <origin>" for the design system in
#                                     force (applied, inherited, or default)
#   po-theme.sh ds-validate [D]       data checks for a design system (default: the
#                                     selection); exit 1 on any error
#   po-theme.sh ds-css [D]            print the resolved page stylesheet of the design
#                                     system in force, or of D
#   po-theme.sh ds-labels             "<status><TAB><label>" status-chip labels in the
#                                     active theme's words
#
# The design-system layer (ADR-0034) is bin/po-design-lib.sh, whose header owns
# its format and selection: config/po-design picks the look independently of
# config/po-theme, `apply` resolves it into state/po-design/ and a marker line in
# data/captain-shared.md, and `verify` and `headline` report its drift.
#
# The hook registry is .agents/skills/po-theme/surfaces.tsv: one tab-separated
# row per hook line - key, class (T themed, D dual, - plumbing), file, owner
# (upstream or pixeloven), the hook line exactly as written (leading
# whitespace ignored), and the upstream line it replaces (empty for an added
# line). `anchors` checks that every hook line is present and, when the upstream
# pin is in this clone, that every replaced line still exists upstream at the pin.
# The surface canary's residue list is .agents/skills/po-theme/residue.tsv; its
# header owns the row format.
#
# Exit status: 0 on success; 1 on a validation, drift, or anchor finding, an
# unknown theme, a malformed theme, or a usage error.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$CODE_ROOT}}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
DATA="${FM_DATA_OVERRIDE:-$FM_HOME/data}"
SKILLS="$CODE_ROOT/.agents/skills"
BUNDLED="$SKILLS/po-theme/themes"
LOCAL_THEMES="$CONFIG/po-themes"
SHARED="$DATA/captain-shared.md"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
REGISTRY="$SKILLS/po-theme/surfaces.tsv"
RESIDUE="$SKILLS/po-theme/residue.tsv"
START_MARK='<!-- po-theme:persona:start -->'
END_MARK='<!-- po-theme:persona:end -->'
VALUES_PREFIX='<!-- po-theme:values '
ALIAS_MARKER='.po-theme-alias'
EXCLUDE_START='# po-theme:aliases:start'
EXCLUDE_END='# po-theme:aliases:end'
TAB=$(printf '\t')
RSQUO=$(printf '\342\200\231')  # U+2019, the curly apostrophe a model may typeset

ROLE_KEYS='user self worker crew submate fleet scout_task ship_task'
# Upstream's supervision-note glyphs and the curated glyph.* allow-list (ADR-0020
# decision 8): single code points with no directive meaning, from Geometric
# Shapes and a few symbols.
GLYPH_SHIP=$(printf '\342\233\265')    # U+26F5 sailboat
GLYPH_ANCHOR=$(printf '\342\232\223')  # U+2693 anchor
GLYPH_ALLOW="$GLYPH_SHIP $GLYPH_ANCHOR $(printf '\342\227\206 \342\227\207 \342\227\217 \342\227\213 \342\227\211 \342\227\216 \342\226\240 \342\226\241 \342\226\262 \342\226\263 \342\226\266 \342\226\267 \342\226\270 \342\226\271 \342\227\210 \342\232\221 \342\232\220 \342\230\205 \342\230\206 \342\234\246 \342\234\247 \342\214\226')"
# The picture keys (ADR-0020 decision 10): each names an asset file; absent
# keeps nautical's built-in picture, which is upstream's own drawing. Bundled
# assets live in ASSETS; a local theme's own assets in LOCAL_THEMES/assets come
# first. docs/pixeloven/persona-themes.md owns the asset formats.
ASSET_KEYS='sprite.calm icon.brand icon.underway image.banner image.poster'
ASSETS="$SKILLS/po-theme/assets"
SPRITE_KEY_RE='[a-z][a-z0-9_]*([.][a-z0-9][a-z0-9_-]*)*'
STATUS_TOKENS='working done blocked paused failed needs-decision resolved note captain-held'
HARNESS_TOKENS='claude codex opencode pi pi-signed grok kimi cursor omp muse gemini rovo agy devin commandcode polytoken'
DENY_WORDS='merge approve approval override ignore instruction instructions force discard delete yolo authority permission rule rules must never always sudo token secret password'
# Role terms are a short noun shape that cannot carry a directive, and "force"
# is an ordinary noun in a role title such as "task force"; every other value
# keeps the full list.
ROLE_DENY_WORDS='merge approve approval override ignore instruction instructions discard delete yolo authority permission rule rules must never always sudo token secret password'

die() { printf 'po-theme: %s\n' "$*" >&2; exit 1; }

# shellcheck source=bin/po-design-lib.sh
. "$SCRIPT_DIR/po-design-lib.sh"

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/po-theme.XXXXXX")
trap 'rm -rf "$TMPD"' EXIT

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

is_secondmate_home() { [ -e "$FM_HOME/.fm-secondmate-home" ]; }

valid_name() {
  case "$1" in ''|*[!a-z0-9-]*) return 1 ;; esac
  return 0
}

theme_file() {  # <name>: a local theme shadows a bundled one, except nautical
  valid_name "$1" || die "invalid theme name: $1"
  if [ "$1" != nautical ] && [ -f "$LOCAL_THEMES/$1.theme" ]; then
    printf '%s\n' "$LOCAL_THEMES/$1.theme"
  elif [ -f "$BUNDLED/$1.theme" ]; then
    printf '%s\n' "$BUNDLED/$1.theme"
  else
    die "theme not found: $1"
  fi
}

# parse <file> [<key-regex>]: key<TAB>value lines; malformed or duplicate lines
# are errors. Theme keys are the default shape; a sprite asset passes its own,
# whose segments may start with a digit (frame.1.top).
parse() {
  awk -v keyre="${2:-[a-z][a-z0-9_]*([.][a-z][a-z0-9_-]*)*}" '
    /^[[:space:]]*(#|$)/ { next }
    {
      line = $0
      if (line !~ ("^" keyre "[[:space:]]*=[[:space:]]*\"[^\"\\\\]*\"[[:space:]]*(#.*)?$")) {
        printf "line %d: malformed (expected key = \"value\"): %s\n", NR, line > "/dev/stderr"; bad = 1; next
      }
      key = line; sub(/[[:space:]]*=.*/, "", key)
      val = line; sub(/^[^"]*"/, "", val); sub(/".*$/, "", val)
      if (key in seen) { printf "line %d: duplicate key %s\n", NR, key > "/dev/stderr"; bad = 1; next }
      seen[key] = 1
      printf "%s\t%s\n", key, val
    }
    END { exit bad }
  ' "$1"
}

get() {  # <kv-file> <key>
  awk -F '\t' -v k="$2" '$1 == k { print $2; found = 1 } END { exit !found }' "$1"
}

# The Persona block of a captain-shared file, markers included; empty when absent.
block_of() {  # <file>
  [ -f "$1" ] || return 0
  awk -v s="$START_MARK" -v e="$END_MARK" '
    $0 == s { inb = 1 } inb { print } $0 == e { inb = 0 }
  ' "$1"
}

# values_to_theme <block-file>: the block's values line back in theme syntax.
values_to_theme() {
  awk -v p="$VALUES_PREFIX" '
    index($0, p) == 1 {
      line = substr($0, length(p) + 1); sub(/ -->$/, "", line)
      while (match(line, /[a-z][a-z0-9_]*(\.[a-z][a-z0-9_-]*)*="[^"]*"/)) {
        pair = substr(line, RSTART, RLENGTH); line = substr(line, RSTART + RLENGTH)
        eq = index(pair, "=")
        printf "%s = %s\n", substr(pair, 1, eq - 1), substr(pair, eq + 1)
      }
      found = 1; exit
    }
    END { exit !found }
  ' "$1"
}

# load_file <name> <theme-file> <out>: parse and safety-check into a kv file.
load_file() {
  parse "$2" > "$3" 2> "$TMPD/parse.err" || die "$2: $(tr '\n' ' ' < "$TMPD/parse.err")"
  if ! check_values "$1" "$3" > "$TMPD/check.out"; then
    grep '^error:' "$TMPD/check.out" >&2 || true
    die "theme $1 failed validation"
  fi
}

load_named() {  # <name> -> kv path on stdout
  local f
  f=$(theme_file "$1")
  load_file "$1" "$f" "$TMPD/$1.kv"
  printf '%s\n' "$TMPD/$1.kv"
}

# active_is_nautical: true when this home resolves to nautical without loading
# a theme, so the per-spawn hooks cost nothing in an unthemed home.
active_is_nautical() {
  if is_secondmate_home; then
    [ -f "$SHARED" ] && grep -qxF "$START_MARK" "$SHARED" && return 1
    return 0
  fi
  [ -f "$CONFIG/po-theme" ] || return 0
  case "$(head -n 1 "$CONFIG/po-theme" | tr -d '[:space:]')" in ''|nautical) return 0 ;; esac
  return 1
}

# shared_address: print the vocative the Persona block in $SHARED tells the agent
# to use, so the intent-address guard follows the words actually in force even
# when the selection no longer resolves; fail when there is no usable block.
shared_address() {
  local v
  [ -f "$SHARED" ] && grep -qxF "$START_MARK" "$SHARED" || return 1
  block_of "$SHARED" > "$TMPD/shared.block"
  values_to_theme "$TMPD/shared.block" > "$TMPD/shared.theme" 2>/dev/null || return 1
  parse "$TMPD/shared.theme" > "$TMPD/shared.kv" 2>/dev/null || return 1
  v=$(get "$TMPD/shared.kv" user_address 2>/dev/null) || return 1
  case "$v" in [A-Z]*) ;; *) return 1 ;; esac
  case "$v" in *[!A-Za-z-]*) return 1 ;; esac
  [ ${#v} -le 24 ] || return 1
  printf '%s\n' "$v"
}

# load_block <block-file> <out-kv>: the values line of a Persona block, role
# words read in lowercase, safety-checked into a kv file; sets BLOCK_NAME.
# A block written by an older apply lacks keys this checkout's schema added
# since; each missing key is filled from this checkout's bundled theme of the
# block's name (nautical for a custom or unknown theme) so the inherited theme
# still resolves, and BLOCK_FILLED names the filled keys for verify to report.
load_block() {
  local n src
  BLOCK_FILLED=''
  values_to_theme "$1" > "$TMPD/block.raw" \
    || die "the Persona block in $SHARED has no values line; rerun apply in the primary home"
  parse "$TMPD/block.raw" > "$TMPD/block.rawkv" 2>/dev/null || die "the Persona values line in $SHARED is malformed"
  n=$(get "$TMPD/block.rawkv" name 2>/dev/null || true)
  valid_name "$n" || die "the Persona values line in $SHARED has no valid name"
  src="$BUNDLED/nautical.theme"
  [ -n "$(block_src "$1")" ] || [ ! -f "$BUNDLED/$n.theme" ] || src="$BUNDLED/$n.theme"
  parse "$BUNDLED/nautical.theme" > "$TMPD/block.schema" || die "bundled nautical theme is malformed"
  parse "$src" > "$TMPD/block.fill" || die "$src is malformed"
  BLOCK_FILLED=$(awk -F '\t' '
    FILENAME == ARGV[1] { have[$1] = 1; next }
    FILENAME == ARGV[2] { fill[$1] = $2; next }
    $1 !~ /^(label|str)\./ && !($1 in have) && ($1 in fill) { print $1 }
  ' "$TMPD/block.rawkv" "$TMPD/block.fill" "$TMPD/block.schema")
  if [ -n "$BLOCK_FILLED" ]; then
    printf '%s\n' "$BLOCK_FILLED" | while IFS= read -r k; do
      printf '%s = "%s"\n' "$k" "$(get "$TMPD/block.fill" "$k")"
    done >> "$TMPD/block.raw"
    BLOCK_FILLED=$(printf '%s' "$BLOCK_FILLED" | paste -sd ' ' -)
  fi
  awk -v roles="$ROLE_KEYS" '
    BEGIN { n = split(roles, ra, " "); for (i = 1; i <= n; i++) R[ra[i]] = 1 }
    { k = $1; if ((k in R) || k == "product" || k ~ /_plural$/) $0 = tolower($0); print }
  ' "$TMPD/block.raw" > "$TMPD/block.theme"
  load_file "$n" "$TMPD/block.theme" "$2"
  BLOCK_NAME=$n
}

# src_of <theme-file>: "local" for a theme from config/po-themes, else empty.
src_of() {
  case "$1" in "$LOCAL_THEMES"/*) echo local ;; esac
}

# block_src <block-file>: "local" when the block's values line records a local theme.
block_src() {
  grep -F "$VALUES_PREFIX" "$1" 2>/dev/null | grep -qF ' source=local -->' && echo local
  return 0
}

# resolve_active: sets ACTIVE_NAME, ACTIVE_SRC, ACTIVE_KV, ACTIVE_ORIGIN.
resolve_active() {
  local n
  if is_secondmate_home; then
    block_of "$SHARED" > "$TMPD/inherited.block"
    if [ -s "$TMPD/inherited.block" ]; then
      load_block "$TMPD/inherited.block" "$TMPD/active.kv"
      ACTIVE_NAME=$BLOCK_NAME ACTIVE_SRC="inherited:$SHARED" ACTIVE_KV="$TMPD/active.kv"
      ACTIVE_ORIGIN=$(block_src "$TMPD/inherited.block")
      return 0
    fi
    n=nautical
  elif [ -f "$CONFIG/po-theme" ]; then
    n=$(head -n 1 "$CONFIG/po-theme" | tr -d '[:space:]')
    [ -n "$n" ] || n=nautical
  else
    n=nautical
  fi
  ACTIVE_NAME=$n
  ACTIVE_SRC=$(theme_file "$n")
  ACTIVE_KV=$(load_named "$n")
  ACTIVE_ORIGIN=$(src_of "$ACTIVE_SRC")
}

# strs_of <kv>: "<key><TAB><string>" for every registered str.* key, using the
# derived default for an absent key: the needs state is "needs-" and the user
# word lowercased with spaces as hyphens, the wedge title opens with the
# product word, the digest's call section is the address word's "<Address>'s
# Call", the other digest sections keep their nautical names, and the Calm and
# supervision menu descriptions and the Calm notice name the product (capitalized
# where upstream capitalizes it) and call the Calm figure the working animation.
# The Bearings board names itself after the /bearings alias ("<Alias> - <fleet>
# board", wordmark "<alias>") and uses the user and self words where upstream
# says "captain" and "firstmate"; the fleet view's title and second-mate
# heading title-case the fleet and submate_plural words, and its Under Way
# heading keeps its name; the human inbox commands use the self word where
# upstream says "firstmate" and say "no <workers> active" for an idle home.
strs_of() {
  awk -F '\t' '
    function d(k, def) { return (k in v) ? v[k] : def }
    function cap(w) { return toupper(substr(w, 1, 1)) substr(w, 2) }
    function title(w,   n, i, part, out) { n = split(w, part, " "); out = ""; for (i = 1; i <= n; i++) out = out (i > 1 ? " " : "") cap(part[i]); return out }
    { v[$1] = $2 }
    END {
      u = tolower(v["user"]); gsub(/ /, "-", u)
      p = v["product"]; P = cap(p)
      b = v["alias.bearings"]
      printf "str.sidebar.needs\t%s\n", d("str.sidebar.needs", "needs-" u)
      printf "str.alert.wedge_title\t%s\n", d("str.alert.wedge_title", v["product"] ": away-mode escalations WEDGED")
      printf "str.digest.call\t%s\n", d("str.digest.call", v["user_address"] "\047s Call")
      printf "str.digest.underway\t%s\n", d("str.digest.underway", "Underway")
      printf "str.digest.landed\t%s\n", d("str.digest.landed", "Recently Landed")
      printf "str.digest.charted\t%s\n", d("str.digest.charted", "Charted Next")
      printf "str.calm.name\t%s\n", d("str.calm.name", P " Calm")
      printf "str.calm.command\t%s\n", d("str.calm.command", "Toggle " P "\047s Calm transcript presentation and working animation.")
      printf "str.calm.pi_command\t%s\n", d("str.calm.pi_command", "Toggle " P "\047s supported conversation-only transcript presentation.")
      printf "str.branch.model_command\t%s\n", d("str.branch.model_command", "Pick the model and reasoning effort " P "\047s Pi supervision branch uses, or follow main\047s.")
      printf "str.watch.arm_command\t%s\n", d("str.watch.arm_command", "Arm " p " watcher supervision through the Pi extension instead of foreground bash.")
      printf "str.board.title\t%s\n", d("str.board.title", cap(b) " - " v["fleet"] " board")
      printf "str.board.brand\t%s\n", d("str.board.brand", b)
      printf "str.board.user\t%s\n", d("str.board.user", v["user"])
      printf "str.board.self\t%s\n", d("str.board.self", v["self"])
      printf "str.fleet.title\t%s\n", d("str.fleet.title", title(v["fleet"]) " View")
      printf "str.fleet.underway\t%s\n", d("str.fleet.underway", "Under Way")
      printf "str.fleet.secondmates\t%s\n", d("str.fleet.secondmates", title(v["submate_plural"]))
      printf "str.inbox.agent\t%s\n", d("str.inbox.agent", v["self"])
      printf "str.inbox.idle\t%s\n", d("str.inbox.idle", "no " v["worker_plural"] " active")
    }
  ' "$1"
}

# check_strs <kv>: ADR-0020 decision 8 for every str.* string, given or
# derived: at most 80 characters, no architectural token (a status verb,
# FIRSTMATE_OP, a brief heading, or an fm- prefix), no % or & (inbox strings
# sit in a printf format, board strings in a page), a sidebar state that is
# a herdr token value distinct from the other group states, digest and fleet
# view section names that are short headings, distinct from each other within
# their surface, and board strings of plain words that can close no quote,
# comment, or tag of the page they are written into. A slash-command menu
# description (a key ending in "command") is a sentence no code reads back, so
# it may run to 120 characters and use a status verb as an English word
# ("working"), as upstream's own descriptions do.
check_strs() {
  strs_of "$1" | LC_ALL=C awk -F '\t' -v tokens="$STATUS_TOKENS" '
    function bad(m) { print "error: " m; failed = 1 }
    BEGIN { nt = split(tokens, T, " ") }
    {
      k = $1; v = $2; menu = (k ~ /command$/)
      if (length(v) > (menu ? 120 : 80)) bad(k ": longer than " (menu ? 120 : 80) " characters")
      s = " " v " "; gsub(/[^A-Za-z0-9_-]/, " ", s)
      for (j = 1; j <= nt; j++) if (!menu && index(s, " " T[j] " ")) bad(k ": '"'"'" v "'"'"' contains the status verb " T[j])
      if (index(v, "FIRSTMATE_OP") || index(v, "##") || index(s, " fm-")) bad(k ": '"'"'" v "'"'"' contains an architectural token")
      if (index(v, "%") || index(v, "&")) bad(k ": '"'"'" v "'"'"' contains % or &")
      if (k == "str.sidebar.needs") {
        if (v !~ /^[a-z0-9][a-z0-9-]*[a-z0-9]$/ || length(v) > 24) bad(k ": '"'"'" v "'"'"' must be 2-24 lowercase letters, digits, or hyphens, starting and ending with a letter or digit")
        else if (v == "running" || v == "problem" || v == "done") bad(k ": '"'"'" v "'"'"' equals another herdr group state")
      }
      if (k ~ /^str\.(digest|fleet)\./) {
        if (v !~ /^[A-Za-z0-9]/ || v ~ /[^A-Za-z0-9 '"'"'-]/ || v ~ /[ ]$/ || length(v) > 32) bad(k ": '"'"'" v "'"'"' must be a heading of at most 32 letters, digits, spaces, hyphens, or apostrophes, starting with a letter or digit")
        sec = k; sub(/\.[^.]*$/, "", sec); lv = sec SUBSEP tolower(v)
        if (lv in heading) bad(k " and " heading[lv] " share the section name '"'"'" v "'"'"'")
        else heading[lv] = k
      }
      if (k ~ /^str\.board\./ && (v !~ /^[A-Za-z0-9]/ || v ~ /[^A-Za-z0-9 .'"'"'-]/ || v ~ /[ ]$/ || length(v) > 48)) bad(k ": '"'"'" v "'"'"' must be at most 48 letters, digits, spaces, periods, hyphens, or apostrophes, starting with a letter or digit")
    }
    END { exit failed }
  '
}

# glyphs_of <kv>: "<key><TAB><glyph>" for every glyph.* key, upstream's
# supervision-note glyph when the theme leaves it out.
glyphs_of() {
  awk -F '\t' -v ship="$GLYPH_SHIP" -v anchor="$GLYPH_ANCHOR" '
    { v[$1] = $2 }
    END {
      printf "glyph.ship\t%s\n", ("glyph.ship" in v) ? v["glyph.ship"] : ship
      printf "glyph.anchor\t%s\n", ("glyph.anchor" in v) ? v["glyph.anchor"] : anchor
    }
  ' "$1"
}

# check_glyphs <kv>: ADR-0020 decision 8 for glyph.* values: each is one code
# point from GLYPH_ALLOW, and the routine and captain notes stay distinguishable
# (their glyphs differ, and neither takes the other's upstream glyph).
check_glyphs() {
  local k v g ok ship anchor err=0
  while IFS="$TAB" read -r k v; do
    ok=0
    for g in $GLYPH_ALLOW; do [ "$v" = "$g" ] && ok=1; done
    [ "$ok" = 1 ] || { echo "error: $k: '$v' is not one glyph from the allow-list ($GLYPH_ALLOW)"; err=1; }
  done < <(glyphs_of "$1")
  ship=$(glyphs_of "$1" | get /dev/stdin glyph.ship) anchor=$(glyphs_of "$1" | get /dev/stdin glyph.anchor)
  if [ "$ship" = "$anchor" ]; then
    echo "error: glyph.ship and glyph.anchor share the glyph '$ship'"; err=1
  elif [ "$ship" = "$GLYPH_ANCHOR" ] || [ "$anchor" = "$GLYPH_SHIP" ]; then
    echo "error: glyph.ship and glyph.anchor must not swap upstream's note glyphs"; err=1
  fi
  return $err
}

# asset_file <file-name> <origin>: the asset file a theme names, from a local
# theme's own config/po-themes/assets first, then the bundled assets; fails
# when neither has it.
asset_file() {
  if [ "$2" = local ] && [ -f "$LOCAL_THEMES/assets/$1" ]; then
    printf '%s\n' "$LOCAL_THEMES/assets/$1"
  elif [ -f "$ASSETS/$1" ]; then
    printf '%s\n' "$ASSETS/$1"
  else
    return 1
  fi
}

# sprite_cells <text>: the cell count of a sprite row, failing on any glyph
# outside the sprite allow-list (printable ASCII, U+2500-U+25FF, U+2800-U+28FF),
# all of which are one terminal column under both harnesses. Bytes are matched
# in the C locale, so it needs no Unicode-aware awk.
sprite_cells() {
  local e2 rest
  e2=$(printf '\342')
  rest=$(printf '%s' "$1" | LC_ALL=C sed "s/${e2}[$(printf '\224')-$(printf '\227')][$(printf '\200')-$(printf '\277')]/x/g; s/${e2}[$(printf '\240')-$(printf '\243')][$(printf '\200')-$(printf '\277')]/x/g")
  if printf '%s' "$rest" | LC_ALL=C grep -q '[^ -~]'; then return 1; fi
  printf '%s\n' "${#rest}"
}

# sprite_check <file>: the po-sprite/1 validator; prints "error:" lines.
# .claude/mods/firstmate-calm/lib/po-theme-calm.ts parses with the same rules
# before every use.
sprite_check() {
  local f=$1 kv="$TMPD/sprite.kv" kind k v n cells err=0 frames=0 tick
  [ "$(wc -c < "$f" | tr -d ' ')" -le 4096 ] || { echo "error: $f: larger than 4096 bytes"; return 1; }
  parse "$f" "$SPRITE_KEY_RE" > "$kv" 2> "$TMPD/sprite.err" || { sed "s|^|error: $f: |" "$TMPD/sprite.err"; return 1; }
  [ "$(get "$kv" schema 2>/dev/null || true)" = po-sprite/1 ] || { echo "error: $f: schema must be \"po-sprite/1\""; return 1; }
  kind=$(get "$kv" kind 2>/dev/null || true)
  case "$kind" in
    glyphs)
      while IFS="$TAB" read -r k v; do
        case "$k" in schema|kind|top|base) ;; *) echo "error: $f: unknown key for kind glyphs: $k"; err=1 ;; esac
      done < "$kv"
      for k in top:3 base:5; do
        v=$(get "$kv" "${k%:*}" 2>/dev/null || true)
        if ! cells=$(sprite_cells "$v"); then echo "error: $f: ${k%:*} has a glyph outside the sprite allow-list"; err=1
        elif [ "$cells" != "${k#*:}" ]; then echo "error: $f: ${k%:*} must be exactly ${k#*:} cells"; err=1; fi
      done ;;
    frames)
      : > "$TMPD/sprite.frames"
      while IFS="$TAB" read -r k v; do
        case "$k" in schema|kind|tick_ms) continue ;; esac
        n=$(printf '%s\n' "$k" | awk -F . 'NF == 3 && $1 == "frame" && $2 ~ /^[1-9][0-9]?$/ && ($3 == "top" || $3 == "base") { print $2 " " $3 }')
        [ -n "$n" ] || { echo "error: $f: unknown key for kind frames: $k"; err=1; continue; }
        printf '%s\n' "$n" >> "$TMPD/sprite.frames"
        if ! cells=$(sprite_cells "$v"); then echo "error: $f: $k has a glyph outside the sprite allow-list"; err=1
        elif [ "$cells" -lt 1 ] || [ "$cells" -gt 12 ]; then echo "error: $f: $k must be 1-12 cells"; err=1; fi
      done < "$kv"
      tick=$(get "$kv" tick_ms 2>/dev/null || true)
      case "$tick" in ''|0*|*[!0-9]*) tick=0 ;; esac
      if [ "${#tick}" -gt 4 ] || [ "$tick" -lt 120 ] || [ "$tick" -gt 1000 ]; then
        echo "error: $f: tick_ms must be a whole number of milliseconds from 120 to 1000"; err=1
      fi
      frames=$(awk '{ print $1 }' "$TMPD/sprite.frames" | sort -un | wc -l | tr -d ' ')
      if [ "$frames" -lt 1 ] || [ "$frames" -gt 16 ]; then
        echo "error: $f: needs 1-16 frames"; err=1
      else
        n=1
        while [ "$n" -le "$frames" ]; do
          grep -qx "$n base" "$TMPD/sprite.frames" || { awk '{ print $1 }' "$TMPD/sprite.frames" | grep -qx "$n" \
            && echo "error: $f: frame.$n.base is missing" || echo "error: $f: frames must be numbered 1-$frames without gaps"; err=1; }
          n=$((n + 1))
        done
      fi ;;
    *) echo "error: $f: kind must be \"glyphs\" or \"frames\""; err=1 ;;
  esac
  return $err
}

# icon_check <file>: a 24x24 SVG fragment of self-closing path, circle, line,
# polyline, and rect elements whose attributes are numbers from 0 to 24 (path
# data for path); nothing else, so no script, style, or link can ride along.
icon_check() {
  local f=$1
  [ "$(wc -c < "$f" | tr -d ' ')" -le 8192 ] || { echo "error: $f: larger than 8192 bytes"; return 1; }
  tr '\n\r\t' '   ' < "$f" | LC_ALL=C awk -v file="$f" '
    function bad(m) { print "error: " file ": " m; failed = 1 }
    function inbox(v) { return v ~ /^-?[0-9]+([.][0-9]+)?$/ && v + 0 >= 0 && v + 0 <= 24 }
    { s = s $0 }
    END {
      allow["path"] = " d "; allow["circle"] = " cx cy r "; allow["line"] = " x1 y1 x2 y2 "
      allow["polyline"] = " points "; allow["rect"] = " x y width height rx ry "
      while (!failed) {
        sub(/^ +/, "", s); if (s == "") break
        if (!match(s, /^<[a-z]+( +[a-z0-9-]+="[^"]*")* *\/>/)) { bad("not a fragment of self-closing path, circle, line, polyline, and rect elements"); break }
        el = substr(s, 2, RLENGTH - 3); s = substr(s, RLENGTH + 1)
        name = el; sub(/ .*$/, "", name)
        if (!(name in allow)) { bad("element <" name "> is not allowed"); break }
        if (++n > 32) { bad("more than 32 elements"); break }
        rest = substr(el, length(name) + 1); split("", seen)
        while (match(rest, /[a-z0-9-]+="[^"]*"/)) {
          pair = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
          eq = index(pair, "="); a = substr(pair, 1, eq - 1); v = substr(pair, eq + 2); v = substr(v, 1, length(v) - 1)
          if (!index(allow[name], " " a " ")) { bad("<" name "> may not carry " a); continue }
          if (a in seen) bad("<" name "> repeats " a)
          seen[a] = 1
          if (a == "d") { if (v !~ /^[MmLlHhVvCcSsQqTtAaZz0-9 .,-]+$/) bad("<path> d is not path data") }
          else if (a == "points") {
            p = v; gsub(/,/, " ", p); np = split(p, P, " ")
            if (np < 4 || np % 2) bad("<polyline> points must be coordinate pairs")
            for (j = 1; j <= np; j++) if (!inbox(P[j])) { bad("<polyline> points must be numbers from 0 to 24"); break }
          }
          else if (!inbox(v)) bad("<" name "> " a " must be a number from 0 to 24")
        }
      }
      if (!failed && n == 0) bad("holds no element")
      exit failed
    }'
}

# image_check <file>: a docs-view picture: a PNG of at most 1 MiB, or an SVG
# document of at most 256 KiB with no script, style, embedded document, entity,
# character reference beyond the five predefined XML ones, backslash escape,
# event handler, animation, or reference to anything outside itself.
image_check() {
  local f=$1 size
  size=$(wc -c < "$f" | tr -d ' ')
  case "$f" in
    *.png)
      [ "$size" -le 1048576 ] || { echo "error: $f: larger than 1 MiB"; return 1; }
      [ "$(head -c 8 "$f" | od -An -tx1 | tr -d ' \n')" = 89504e470d0a1a0a ] || { echo "error: $f: not a PNG file"; return 1; } ;;
    *.svg)
      [ "$size" -le 262144 ] || { echo "error: $f: larger than 256 KiB"; return 1; }
      LC_ALL=C tr '[:upper:]' '[:lower:]' < "$f" | LC_ALL=C tr '\n\t\r' '   ' > "$TMPD/image.svg"
      grep -q '<svg' "$TMPD/image.svg" || { echo "error: $f: not an SVG document"; return 1; }
      if sed -E 's/&(amp|lt|gt|quot|apos);//g' "$TMPD/image.svg" | grep -q '[&\\]' ||
        grep -Eq '<([a-z0-9_.-]+:)?(script|style|foreignobject|iframe|object|embed|set|animate|discard|handler|listener)|<(!entity|!doctype|[?]xml-stylesheet)|javascript:|@import|[[:space:]"'"'"'/]([a-z0-9_.-]+:)?on[a-z]+[[:space:]]*=|attributename[[:space:]]*=[[:space:]]*["'"'"']?([a-z0-9_.-]+:)?href' "$TMPD/image.svg" ||
        ! awk '
          function same_doc(v) { gsub(/[[:space:]"'"'"'\\]/, "", v); return substr(v, 1, 1) == "#" }
          {
            t = $0
            while ((i = index(t, "url(")) > 0) {
              pre = i > 1 ? substr(t, i - 1, 1) : ""; t = substr(t, i + 4)
              if (pre ~ /[a-z0-9_.-]/) continue
              if (!(j = index(t, ")")) || !same_doc(substr(t, 1, j - 1))) exit 1
            }
            t = $0
            while (match(t, /href[[:space:]]*=[[:space:]]*/)) {
              t = substr(t, RSTART + RLENGTH); q = substr(t, 1, 1)
              if (q == "\"" || q == "'"'"'") { t = substr(t, 2); if (!(j = index(t, q))) exit 1; v = substr(t, 1, j - 1) }
              else { if (!match(t, /[[:space:]>]/)) exit 1; v = substr(t, 1, RSTART - 1) }
              if (!same_doc(v)) exit 1
            }
          }' "$TMPD/image.svg"; then
        echo "error: $f: an SVG image may not carry script, style, an embedded document, an entity, a character reference, an escape, an event handler, an animation, or an outside reference"; return 1
      fi ;;
    *) echo "error: $f: an image is a .png or .svg file"; return 1 ;;
  esac
}

# asset_check <key> <file>: the validator for the key's asset kind.
asset_check() {
  case "$1" in
    sprite.*) sprite_check "$2" ;;
    icon.*) icon_check "$2" ;;
    image.*) image_check "$2" ;;
  esac
}

# asset_rows <kv>: "<key><TAB><file-name>" for every picture key the theme sets
# with a well-formed name (check_values reports the others).
asset_rows() {
  awk -F '\t' -v assets=" $ASSET_KEYS " 'index(assets, " " $1 " ") && $2 ~ /^[a-z0-9][a-z0-9-]*[.](sprite|svg|png)$/' "$1"
}

# check_assets <kv> <origin>: every picture the theme names exists and passes
# its validator.
check_assets() {
  local k v f err=0
  while IFS="$TAB" read -r k v; do
    if ! f=$(asset_file "$v" "$2"); then
      echo "error: $k: no asset named $v in ${2:+$LOCAL_THEMES/assets or }$ASSETS"; err=1; continue
    fi
    asset_check "$k" "$f" | sed "s/^error: /error: $k: /" | grep . && err=1
  done < <(asset_rows "$1")
  return $err
}

# check_values <name> <kv>: schema, shape, and safety findings that need no
# corpus, in one awk pass so per-spawn resolution stays cheap. Regexes avoid
# interval expressions, which mawk and older BSD awk do not support. Prints
# "error:" lines; returns 1 on any error.
check_values() {
  local name=$1 kv=$2 schema_kv="$TMPD/schema.kv" k v canon err=0
  [ -s "$schema_kv" ] || parse "$BUNDLED/nautical.theme" > "$schema_kv" || die "bundled nautical theme is malformed"
  LC_ALL=C awk -F '\t' -v name="$name" -v roles="$ROLE_KEYS" -v tokens="$STATUS_TOKENS $HARNESS_TOKENS relay" \
    -v deny="$DENY_WORDS" -v roledeny="$ROLE_DENY_WORDS" -v assets="$ASSET_KEYS" '
    function bad(m) { print "error: " m; failed = 1 }
    function isrole(k) { return (k in R) || k == "product" || k ~ /_plural$/ }
    function dashed(v) { v = tolower(v); gsub(/ /, "-", v); return v }
    function pre(a, b) { return index(b, a) == 1 }
    function label(k, v) {
      if (v !~ /^[a-z0-9][a-z0-9-]*[a-z0-9]$/ || length(v) > 24) bad(k ": '"'"'" v "'"'"' must be 2-24 lowercase letters, digits, or hyphens, starting and ending with a letter or digit")
      else if (v ~ /^fm-/) bad(k ": '"'"'" v "'"'"' must not start with fm-")
    }
    function overlap(ka, a, kb, b) {
      if (a == b) bad(ka " equals " kb " ('"'"'" a "'"'"')")
      else if (pre(a, b) || pre(b, a)) bad(ka " '"'"'" a "'"'"' and " kb " '"'"'" b "'"'"' overlap as prefixes")
    }
    function hasword(v, w,   s) { s = " " tolower(v) " "; gsub(/[^a-z0-9_]/, " ", s); return index(s, " " w " ") > 0 }
    NR == FNR { canon[$1] = $2; order[++n] = $1; next }
    { val[$1] = $2; keys[++m] = $1 }
    END {
      nr = split(roles, ra, " "); for (i = 1; i <= nr; i++) R[ra[i]] = 1
      na = split(assets, aa, " "); for (i = 1; i <= na; i++) A[aa[i]] = 1
      nd = split(deny, D, " "); nrd = split(roledeny, RD, " "); nt = split(tokens, T, " ")
      if (val["schema"] != "po-theme/1" && val["schema"] != "po-theme/2") bad("schema must be \"po-theme/1\" or \"po-theme/2\"")
      if (val["name"] != name) bad("name must equal the theme name (" name ")")
      for (i = 1; i <= n; i++) if (!(order[i] in val) && order[i] !~ /^(label|str|glyph)\./) bad("missing key: " order[i])
      for (i = 1; i <= m; i++) { k = keys[i]; if (k !~ /^avoid\./ && !(k in canon) && !(k in A)) bad("unknown key: " k) }
      for (i = 1; i <= m; i++) {
        k = keys[i]; v = val[k]
        if (v ~ /[`$<>{}|]/ || v ~ /\[/ || v ~ /\]/ || index(v, "://")) bad(k ": forbidden character or URL in value")
        if (v ~ /[^ -~]/ && k !~ /^glyph\./) bad(k ": non-printable or non-ASCII character")
        if (isrole(k)) { for (j = 1; j <= nrd; j++) if (hasword(v, RD[j])) bad(k ": value contains the authority word '"'"'" RD[j] "'"'"'") }
        else { for (j = 1; j <= nd; j++) if (hasword(v, D[j])) bad(k ": value contains the authority word '"'"'" D[j] "'"'"'") }
        if (k == "schema" || k == "name") continue
        if (k == "description") { if (length(v) > 80) bad(k ": longer than 80 characters") }
        else if (isrole(k)) { if (v !~ /^[a-z][a-z -]*$/ || length(v) > 24) bad(k ": must be 1-24 lowercase letters, spaces, or hyphens") }
        else if (k == "user_address") { if (v !~ /^[A-Z][A-Za-z-]*$/ || length(v) > 24) bad(k ": must be one capitalized word of at most 24 characters") }
        else if (k == "seasoning") {
          np = split(v, parts, ", "); ok = (np >= 1 && np <= 6)
          for (j = 1; j <= np; j++) if (parts[j] !~ /^[a-z][a-z ]*$/ || length(parts[j]) > 16) ok = 0
          if (!ok) bad(k ": must be 1-6 comma-separated lowercase words")
        }
        else if (k == "noop_reply" || k == "bad_news_example") {
          if (length(v) > 60) bad(k ": longer than 60 characters")
          if (index(v, val["user_address"] ", ") != 1) bad(k ": must open with the user_address followed by a comma")
        }
        else if (k ~ /^alias\./) { if (v !~ /^[a-z][a-z0-9-]+$/ || length(v) > 31) bad(k ": alias must be 2-31 lowercase letters, digits, or hyphens") }
        else if (k ~ /^avoid\./) { if (length(v) > 120) bad(k ": longer than 120 characters") }
        else if (k in A) {
          if (val["schema"] == "po-theme/1") bad(k ": needs schema po-theme/2")
          ext = (k ~ /^sprite\./) ? "sprite" : (k ~ /^icon\./) ? "svg" : "(png|svg)"
          if (v !~ ("^[a-z0-9][a-z0-9-]*[.]" ext "$") || length(v) > 64) bad(k ": '"'"'" v "'"'"' must be an asset file name of at most 64 lowercase letters, digits, or hyphens ending in ." (ext == "(png|svg)" ? "png or .svg" : ext))
        }
        else if (k ~ /^(label|str|glyph)\./) { if (val["schema"] == "po-theme/1") bad(k ": needs schema po-theme/2") }
      }
      lp = ("label.primary" in val) ? val["label.primary"] : dashed(val["self"])
      ls = ("label.submate" in val) ? val["label.submate"] : dashed(val["submate"])
      la = ("label.afk" in val) ? val["label.afk"] : lp "-afk-daemon"
      label("label.primary", lp); label("label.submate", ls); label("label.afk", la)
      overlap("label.primary", lp, "label.submate", ls)
      overlap("label.primary", lp, "the canonical secondmate label", "2ndmate")
      overlap("label.submate", ls, "the canonical primary label", "firstmate")
      if (la == lp || la == ls || la == "firstmate" || la == "2ndmate") bad("label.afk: '"'"'" la "'"'"' equals a home label")
      else if (pre(ls, la) || pre("2ndmate", la)) bad("label.afk: '"'"'" la "'"'"' would read as a secondmate label")
      else if (pre(la, lp) || pre(la, ls) || pre(la, "firstmate") || pre(la, "2ndmate")) bad("label.afk: '"'"'" la "'"'"' is a prefix of a home label")
      for (i = 1; i <= nr; i++) {
        k = ra[i]; if (!(k in val)) continue
        lv = tolower(val[k])
        for (j = 1; j <= nr; j++) {
          o = ra[j]; if (o == k) continue
          if (j > i && (o in val) && lv == tolower(val[o])) bad(k " and " o " share the term '"'"'" val[k] "'"'"'")
          if (lv == canon[o]) bad(k " uses '"'"'" val[k] "'"'"', which is the canonical word for " o)
        }
        for (j = 1; j <= nt; j++) if (lv == T[j]) bad(k " uses '"'"'" val[k] "'"'"', a protocol or harness token")
      }
      exit failed
    }
  ' "$schema_kv" "$kv" || err=1
  check_strs "$kv" || err=1
  check_glyphs "$kv" || err=1

  : > "$TMPD/aliases"
  while IFS="$TAB" read -r k v; do
    case "$k" in alias.*) ;; *) continue ;; esac
    canon=${k#alias.}
    [ -f "$SKILLS/$canon/SKILL.md" ] || { echo "error: $k: no upstream skill named $canon"; err=1; }
    [ "$v" = "$canon" ] && continue
    if [ -e "$SKILLS/$v" ] && [ ! -f "$SKILLS/$v/$ALIAS_MARKER" ]; then
      echo "error: $k: alias '$v' shadows an existing skill"; err=1
    fi
    if grep -qxF -- "$v" "$TMPD/aliases"; then echo "error: $k: alias '$v' used twice"; err=1; fi
    printf '%s\n' "$v" >> "$TMPD/aliases"
  done < "$kv"
  return $err
}

# corpus_collisions <name> <kv>: a theme role word the upstream text (every
# tracked file outside PixelOven's own namespaces) already uses with another meaning needs avoid.<word> so chat never blurs the two.
corpus_collisions() {
  local name=$1 kv=$2 err=0 k v lv canon n
  [ "$name" != nautical ] || return 0
  git -C "$CODE_ROOT" rev-parse --git-dir >/dev/null 2>&1 || { echo "note: $CODE_ROOT is not a git checkout; corpus collisions not counted"; return 0; }
  for k in $ROLE_KEYS; do
    v=$(get "$kv" "$k"); lv=$(lower "$v"); canon=$(get "$TMPD/schema.kv" "$k")
    [ "$lv" = "$canon" ] && continue
    n=$(git -C "$CODE_ROOT" grep -i -w -o -F -e "$lv" -- . \
          ':!.agents/skills/po-*' ':!bin/po-*' ':!tests/po-*' ':!docs/adr/' ':!docs/pixeloven/' \
          ':!.claude/mods/firstmate-calm/lib/po-*' ':!.claude/mods/firstmate-calm/tests/po-*' ':!.pi/extensions/lib/po-*' \
          2>/dev/null | wc -l | tr -d ' ')
    [ "$n" -gt 0 ] || continue
    if get "$kv" "avoid.$lv" >/dev/null 2>&1; then
      echo "note: $k '$v' already appears $n times upstream; avoid.$lv covers it"
    elif [ "$k" = user ] || [ "$k" = self ]; then
      echo "error: $k '$v' already appears $n times upstream with another meaning; add avoid.$lv"; err=1
    else
      echo "warn: $k '$v' already appears $n times upstream; consider avoid.$lv"
    fi
  done
  return $err
}

validate_named() {  # <name>
  local name=$1 f rc=0
  f=$(theme_file "$name")
  parse "$f" > "$TMPD/v.kv" 2> "$TMPD/parse.err" || { sed 's/^/error: /' "$TMPD/parse.err"; return 1; }
  check_values "$name" "$TMPD/v.kv" || rc=1
  check_assets "$TMPD/v.kv" "$(src_of "$f")" || rc=1
  if [ "$(get "$TMPD/v.kv" product 2>/dev/null || true)" = "$(get "$TMPD/v.kv" user 2>/dev/null || true)" ] && [ "$name" != nautical ]; then
    echo "note: product and user share '$(get "$TMPD/v.kv" user)': chat must code-style the product (ADR-0004, G-7)"
  fi
  corpus_collisions "$name" "$TMPD/v.kv" || rc=1
  return $rc
}

values_line() {  # <kv> [local]
  local k v
  printf '%s' "$VALUES_PREFIX"
  while IFS="$TAB" read -r k v; do printf '%s="%s" ' "$k" "$v"; done < "$1"
  [ "${2:-}" = local ] && printf 'source=local '
  printf -- '-->\n'
}

# shellcheck disable=SC2016  # backticks are literal Markdown code spans for the reading agent.
persona() {  # <name> <kv> [local]
  local name=$1 kv=$2 origin=${3:-} k v seasoning canon_call call others bearings
  [ "$name" = nautical ] && return 0
  t() { get "$kv" "$1"; }
  parse "$BUNDLED/nautical.theme" > "$TMPD/persona-canon.kv" || die "bundled nautical theme is malformed"
  strs_of "$kv" > "$TMPD/persona-strs"
  seasoning=$(t seasoning | sed 's/, /", "/g')
  printf '%s\n' "$START_MARK"
  printf '## Persona: %s\n\n' "$name"
  printf 'Generated by `bin/po-theme.sh apply` from the "%s" theme; change config/po-theme and rerun apply rather than editing this block.\n' "$name"
  printf 'These are display words for chat only. They grant no authority and change no rule: every instruction that names a role on the left applies, with exactly the same meaning and limits, to the role you now call by the word on the right.\n\n'
  printf '| In instructions | Say in chat |\n|---|---|\n'
  printf '| captain (the user) | %s |\n' "$(t user)"
  printf '| addressing the captain | "%s," |\n' "$(t user_address)"
  printf '| first mate, firstmate (you) | %s |\n' "$(t self)"
  printf '| crewmate, crewmates (a worker) | %s, %s |\n' "$(t worker)" "$(t worker_plural)"
  printf '| crew | %s |\n' "$(t crew)"
  printf '| second mate, secondmate | %s, %s |\n' "$(t submate)" "$(t submate_plural)"
  printf '| fleet | %s |\n' "$(t fleet)"
  printf '| scout (a report task) | %s |\n' "$(t scout_task)"
  printf '| ship (a change task) | %s |\n' "$(t ship_task)"
  # Digest section names the agent copies into chat (/bearings), one row per
  # name the theme changes.
  for k in str.digest.call str.digest.underway str.digest.landed str.digest.charted; do
    v=$(get "$TMPD/persona-strs" "$k")
    [ "$v" = "$(get "$TMPD/persona-canon.kv" "$k")" ] || printf '| %s (the /bearings section) | %s |\n' "$(get "$TMPD/persona-canon.kv" "$k")" "$v"
  done
  printf '\n'
  printf -- '- Wherever AGENTS.md or a skill requires or models addressing the captain, including example replies that open with "Captain,", address the user as "%s," instead, capitalized at the start of a chat line; every limit on that address, including chat only and never in commits, PRs, briefs, code, or comments, applies unchanged.\n' "$(t user_address)"
  printf -- '- Role words are common nouns: write them lowercase except where a sentence starts; only the address word is capitalized, at the start of a chat line.\n'
  printf -- '- The optional seasoning words are "%s", under the same fit-only, never-for-bad-news limits as the nautical ones they replace.\n' "$seasoning"
  printf -- '- Wherever AGENTS.md requires the exact reply `Captain, shipshape.`, reply exactly `%s` under exactly the same conditions; a bad-news opening reads like "%s".\n' "$(t noop_reply)" "$(t bad_news_example)"
  if [ "$(lower "$(t product)")" = "$(lower "$(t user)")" ]; then
    printf -- '- The product is also named %s: write the product in code style as `%s` and the person in plain prose, never capitalized mid-sentence.\n' "$(t product)" "$(t product)"
  fi
  while IFS="$TAB" read -r k v; do
    case "$k" in
      avoid.*) printf -- '- Where the instructions use "%s" with another meaning, say %s in chat, so "%s" only ever names its role.\n' "${k#avoid.}" "$v" "${k#avoid.}" ;;
    esac
  done < "$kv"
  printf -- "- Identifiers never change: script names, paths, environment variables, skill names, status verbs, and brief headings such as \`## Captain's intent\` stay exactly as written.\n"
  # The digest's call heading is a display string, not a fixed title: say so
  # outright, since the identifiers rule above otherwise reads as keeping it.
  canon_call=$(get "$TMPD/persona-canon.kv" str.digest.call) call=$(get "$TMPD/persona-strs" str.digest.call)
  if [ "$call" != "$canon_call" ]; then
    others='other digest headings stay as written'
    for k in str.digest.underway str.digest.landed str.digest.charted; do
      [ "$(get "$TMPD/persona-strs" "$k")" = "$(get "$TMPD/persona-canon.kv" "$k")" ] || others='other digest headings stay as written unless the table above maps them'
    done
    bearings=Bearings
    [ "$(t alias.bearings)" = bearings ] || bearings="Bearings/$(t alias.bearings)"
    printf -- '- The %s digest heading `%s` reads `%s`; %s.\n' "$bearings" "$canon_call" "$call" "$others"
  fi
  printf -- '- Command aliases, generated in the primary home only (a second-mate home keeps the original command names):'
  while IFS="$TAB" read -r k v; do
    case "$k" in alias.*) [ "$v" = "${k#alias.}" ] || printf ' /%s = /%s;' "$v" "${k#alias.}" ;; esac
  done < "$kv"
  printf ' in the primary home, treat each alias exactly as its target.\n'
  printf -- '- Workers receive this vocabulary through their launch role contract; scout reports and other prose a person reads use the words on the right.\n'
  values_line "$kv" "$origin"
  printf '%s\n' "$END_MARK"
}

# replace_block <file> <block-file>: swap the delimited block in place, append it
# when absent, and remove it when <block-file> is empty. The file keeps its inode
# and mode; a file left empty by a removal is deleted, since only apply wrote it.
replace_block() {
  local f=$1 blk=$2 tmp="$TMPD/replace.out"
  if [ -f "$f" ] && grep -qxF "$START_MARK" "$f"; then
    awk -v s="$START_MARK" -v e="$END_MARK" -v blk="$blk" '
      $0 == s { while ((getline l < blk) > 0) print l; skip = 1; next }
      skip && $0 == e { skip = 0; next }
      !skip { print }
    ' "$f" > "$tmp"
  elif [ -s "$blk" ]; then
    {
      if [ -s "$f" ]; then
        cat "$f"
        [ -z "$(tail -c 1 "$f")" ] || printf '\n'
      fi
      cat "$blk"
    } > "$tmp"
  else
    return 0
  fi
  if [ -s "$tmp" ]; then
    cat "$tmp" > "$f"
  else
    rm -f "$f"
  fi
}

# Generated alias directories: marker present and nothing tracked inside.
generated_aliases() {
  local d
  for d in "$SKILLS"/*/; do
    [ -f "$d$ALIAS_MARKER" ] || continue
    [ -z "$(git -C "$CODE_ROOT" ls-files -- "$d" 2>/dev/null)" ] || continue
    basename "$d"
  done
}

exclude_path() {
  local p
  p=$(git -C "$CODE_ROOT" rev-parse --git-path info/exclude 2>/dev/null) || return 1
  case "$p" in /*) ;; *) p="$CODE_ROOT/$p" ;; esac
  printf '%s\n' "$p"
}

expected_aliases() {  # <kv>: "<alias> <target>" lines
  local k v
  while IFS="$TAB" read -r k v; do
    case "$k" in alias.*) [ "$v" = "${k#alias.}" ] || printf '%s %s\n' "$v" "${k#alias.}" ;; esac
  done < "$1"
}

# alias_summary <kv> <target>: the slash-menu sentence for an alias of
# <target> in the theme's own words (ADR-0020 G6); empty for a command with no
# summary yet, whose alias then reads only as an alias.
alias_summary() {
  local kv=$1
  case "$2" in
    afk) printf 'Hand supervision to the %s while the %s is away. ' "$(get "$kv" self)" "$(get "$kv" user)" ;;
    ahoy) printf 'Recap this session and walk the %s through its unanswered decisions. ' "$(get "$kv" user)" ;;
    bearings) printf 'Pick up where you left off: the %s digest in chat, a file, or a live board. ' "$(get "$kv" fleet)" ;;
    lavish-url) printf 'Capture a web page as an annotatable Lavish review. ' ;;
    quiet) printf 'Quiet supervision with fewer routine updates while the %s stays in the session. ' "$(get "$kv" user)" ;;
    stow) printf 'Save what the %s learned this session and file its open work. ' "$(get "$kv" self)" ;;
    updatefirstmate) printf 'Update this %s home and its %s to the latest version. ' "$(get "$kv" product)" "$(get "$kv" submate_plural)" ;;
  esac
}

# alias_skill <name> <kv> <alias> <target>: the generated SKILL.md of one alias.
alias_skill() {
  cat <<EOF
---
name: $3
description: "$(alias_summary "$2" "$4")Alias of /$4 in the $1 theme. Use when the user invokes /$3."
user-invocable: true
metadata:
  internal: true
---

Load the \`$4\` skill and follow it exactly as if the user had invoked /$4 with the same arguments.
EOF
}

write_aliases() {  # <name> <kv>
  local name=$1 kv=$2 a target exclude
  for a in $(generated_aliases); do rm -rf "${SKILLS:?}/$a"; done
  : > "$TMPD/excl"
  expected_aliases "$kv" > "$TMPD/expected-aliases"
  while read -r a target; do
    mkdir -p "$SKILLS/$a"
    : > "$SKILLS/$a/$ALIAS_MARKER"
    alias_skill "$name" "$kv" "$a" "$target" > "$SKILLS/$a/SKILL.md"
    printf '/.agents/skills/%s/\n' "$a" >> "$TMPD/excl"
    echo "alias: /$a -> /$target"
  done < "$TMPD/expected-aliases"
  # Keep generated aliases out of `git status --porcelain`, which the guarded
  # self-update treats as dirty (bin/fm-ff-lib.sh dirty_status).
  exclude=$(exclude_path) || return 0
  awk -v s="$EXCLUDE_START" -v e="$EXCLUDE_END" '$0 == s { skip = 1; next } skip && $0 == e { skip = 0; next } !skip' \
    "$exclude" > "$TMPD/ex" 2>/dev/null || : > "$TMPD/ex"
  if [ -s "$TMPD/excl" ]; then
    { printf '%s\n' "$EXCLUDE_START"; cat "$TMPD/excl"; printf '%s\n' "$EXCLUDE_END"; } >> "$TMPD/ex"
  fi
  if [ -f "$exclude" ] || [ -s "$TMPD/ex" ]; then
    mkdir -p "$(dirname "$exclude")"
    cat "$TMPD/ex" > "$exclude"
  fi
}

apply() {
  if is_secondmate_home; then
    die "this is a secondmate home: the persona is primary-authoritative and arrives with data/captain-shared.md"
  fi
  resolve_active
  if ! validate_named "$ACTIVE_NAME" > "$TMPD/findings"; then
    cat "$TMPD/findings" >&2
    die "theme $ACTIVE_NAME failed validation"
  fi
  pd_resolve_fresh "$(pd_selected)" "$TMPD/pd.apply.css"
  persona "$ACTIVE_NAME" "$ACTIVE_KV" "$ACTIVE_ORIGIN" > "$TMPD/block"
  if [ -s "$TMPD/block" ]; then
    mkdir -p "$DATA"
    replace_block "$SHARED" "$TMPD/block"
    echo "persona: $ACTIVE_NAME block written to $SHARED"
  elif [ -f "$SHARED" ] && grep -qxF "$START_MARK" "$SHARED"; then
    replace_block "$SHARED" "$TMPD/block"
    echo "persona: nautical - block removed"
  else
    echo "persona: nautical - nothing to write"
  fi
  write_aliases "$ACTIVE_NAME" "$ACTIVE_KV"
  refresh
  pd_apply
}

# labels_of <kv>: "<role><TAB><label>" for primary, submate, and afk, using the
# derived default for an absent label.* key (check_values validated both).
labels_of() {
  awk -F '\t' '
    { v[$1] = $2 }
    END {
      lp = ("label.primary" in v) ? v["label.primary"] : v["self"]
      ls = ("label.submate" in v) ? v["label.submate"] : v["submate"]
      lp = tolower(lp); ls = tolower(ls); gsub(/ /, "-", lp); gsub(/ /, "-", ls)
      la = ("label.afk" in v) ? v["label.afk"] : lp "-afk-daemon"
      printf "primary\t%s\nsubmate\t%s\nafk\t%s\n", lp, ls, la
    }
  ' "$1"
}

# refresh: the values cache bin/po-theme-lib.sh and the Calm mod's
# lib/po-theme-values.ts read (labels, str.* strings, glyph.* glyphs, and the
# file names of the theme's pictures, tagged with the cache format both readers
# require), the pictures themselves copied into assets/ beside it, plus the
# history of labels this home applied, which keeps older workspace names
# matchable. A picture that is missing or fails its validator is left out with
# a warning, so that surface keeps nautical's built-in picture.
refresh() {
  local dir="$STATE/po-theme" kind=primary src role v canon k f
  is_secondmate_home && kind=secondmate
  resolve_active
  if [ "$ACTIVE_NAME" = nautical ]; then
    rm -f "$dir/values"
    rm -rf "$dir/assets"
    echo "values: nautical - no cache"
    return 0
  fi
  mkdir -p "$dir/assets"
  src=${ACTIVE_SRC#inherited:}
  labels_of "$ACTIVE_KV" > "$TMPD/labels"
  # Assets land before the cache that names them, each replaced atomically.
  : > "$TMPD/asset.rows"
  while IFS="$TAB" read -r k v; do
    if f=$(asset_file "$v" "$ACTIVE_ORIGIN") && asset_check "$k" "$f" > "$TMPD/asset.err"; then
      cp "$f" "$dir/assets/$v.$$" && mv "$dir/assets/$v.$$" "$dir/assets/$v"
      printf '%s\t%s\n' "$k" "$v" >> "$TMPD/asset.rows"
    else
      echo "warn: $k: asset $v is missing or invalid, so nautical's built-in picture stays" >&2
    fi
  done < <(asset_rows "$ACTIVE_KV")
  {
    printf 'cache\tpo-theme-values/3\nkind\t%s\nname\t%s\nsource\t%s\n' "$kind" "$ACTIVE_NAME" "$src"
    sed 's/^/label./' "$TMPD/labels"
    strs_of "$ACTIVE_KV"
    glyphs_of "$ACTIVE_KV"
    cat "$TMPD/asset.rows"
  } > "$dir/values.$$"
  mv "$dir/values.$$" "$dir/values"
  # Prune pictures the theme no longer names; another refresh's temporary copy is not one.
  for f in "$dir/assets"/*; do
    case "${f##*/}" in *.sprite|*.svg|*.png) ;; *) continue ;; esac
    awk -F '\t' '{ print $2 }' "$TMPD/asset.rows" | grep -qxF -- "${f##*/}" || rm -f "$f"
  done
  while IFS="$TAB" read -r role v; do
    case "$role" in primary) canon=firstmate ;; submate) canon=2ndmate ;; *) continue ;; esac
    [ "$v" != "$canon" ] || continue
    grep -qxF "$role$TAB$v" "$dir/history" 2>/dev/null || printf '%s\t%s\n' "$role" "$v" >> "$dir/history"
  done < "$TMPD/labels"
  echo "values: $ACTIVE_NAME labels and strings written to $dir/values"
}

verify() {
  local drift=0 a target exclude
  resolve_active
  block_of "$SHARED" > "$TMPD/actual"
  if is_secondmate_home; then
    if [ -s "$TMPD/actual" ] && [ -n "${BLOCK_FILLED:-}" ]; then
      echo "persona drift: inherited block predates this checkout's theme keys ($BLOCK_FILLED); rerun apply in the primary home"
      drift=1
    elif [ -s "$TMPD/actual" ]; then
      persona "$ACTIVE_NAME" "$ACTIVE_KV" "$ACTIVE_ORIGIN" > "$TMPD/expected"
      cmp -s "$TMPD/expected" "$TMPD/actual" || { echo "drift: the inherited Persona block does not match its own values line (hand-edited)"; drift=1; }
      # A block from a bundled theme should match this checkout's bundled theme
      # of the same name; a custom theme of the primary home, whether it has no
      # bundled file or a local one shadows it (source=local), is not compared.
      if [ $drift -eq 0 ] && [ -z "$ACTIVE_ORIGIN" ] && [ -f "$BUNDLED/$ACTIVE_NAME.theme" ]; then
        load_file "$ACTIVE_NAME" "$BUNDLED/$ACTIVE_NAME.theme" "$TMPD/bundled.kv"
        persona "$ACTIVE_NAME" "$TMPD/bundled.kv" > "$TMPD/bundled"
        cmp -s "$TMPD/bundled" "$TMPD/actual" \
          || { echo "persona drift: inherited block differs from the bundled $ACTIVE_NAME theme; rerun apply in the primary home (or update this home if it is newer)"; drift=1; }
      fi
    fi
    [ $drift -eq 0 ] && echo "verify: ok ($ACTIVE_NAME, inherited)"
    pd_verify || drift=1
    return $drift
  fi
  persona "$ACTIVE_NAME" "$ACTIVE_KV" "$ACTIVE_ORIGIN" > "$TMPD/expected"
  if [ -s "$TMPD/expected" ] && [ ! -s "$TMPD/actual" ]; then
    echo "drift: theme $ACTIVE_NAME is selected but $SHARED has no Persona block; run apply"; drift=1
  elif [ ! -s "$TMPD/expected" ] && [ -s "$TMPD/actual" ]; then
    echo "drift: nautical is selected but $SHARED still has a Persona block; run apply"; drift=1
  elif ! cmp -s "$TMPD/expected" "$TMPD/actual"; then
    echo "drift: the Persona block in $SHARED is stale or hand-edited; run apply"; drift=1
  fi
  expected_aliases "$ACTIVE_KV" | sort > "$TMPD/want"
  generated_aliases | sort > "$TMPD/have"
  while read -r a target; do
    grep -qxF -- "$a" "$TMPD/have" || { echo "drift: alias /$a for /$target is missing; run apply"; drift=1; }
  done < "$TMPD/want"
  while read -r a; do
    awk '{ print $1 }' "$TMPD/want" | grep -qxF -- "$a" || { echo "drift: generated alias /$a is not in theme $ACTIVE_NAME; run apply"; drift=1; }
  done < "$TMPD/have"
  if [ -s "$TMPD/want" ] && exclude=$(exclude_path); then
    while read -r a target; do
      awk -v s="$EXCLUDE_START" -v e="$EXCLUDE_END" '$0 == s { inb = 1; next } $0 == e { inb = 0 } inb' "$exclude" 2>/dev/null \
        | grep -qxF "/.agents/skills/$a/" || { echo "drift: alias /$a is not excluded from git status; run apply"; drift=1; }
    done < "$TMPD/want"
  fi
  [ $drift -eq 0 ] && echo "verify: ok ($ACTIVE_NAME)"
  pd_verify || drift=1
  return $drift
}

# headline: the persona in force, in two lines for the head of the session-start
# digest, which a harness that spills a large digest still shows inline; then
# one drift line when verify finds drift. Prints nothing under nautical unless
# a stale Persona block is left in $SHARED, where it prints only the drift line.
# shellcheck disable=SC2016  # backticks are literal Markdown code spans for the reading agent.
headline() {
  local kv="$TMPD/headline.kv" nautical=0
  if active_is_nautical; then
    { [ -f "$SHARED" ] && grep -qxF "$START_MARK" "$SHARED"; } || pd_active || return 0
    nautical=1
  fi
  block_of "$SHARED" > "$TMPD/headline.block"
  if [ $nautical -eq 0 ] && [ -s "$TMPD/headline.block" ] && ( load_block "$TMPD/headline.block" "$kv" ) 2>/dev/null; then
    t() { get "$kv" "$1"; }
    printf 'PERSONA (%s theme, chat words only): address the user as "%s,"; the exact no-op reply is `%s`; say %s for captain, %s for first mate, %s for crewmate, %s for crew, %s for second mate, %s for fleet, %s for ship, %s for scout.\n' \
      "$(t name)" "$(t user_address)" "$(t noop_reply)" "$(t user)" "$(t self)" "$(t worker)" "$(t crew)" \
      "$(t submate)" "$(t fleet)" "$(t ship_task)" "$(t scout_task)"
    printf 'The full Persona block is in %s, printed under CONTEXT below; if this output was cut off, read that file before your next reply.\n' "$SHARED"
  fi
  ( verify ) > "$TMPD/headline.verify" 2>/dev/null && return 0
  if grep -v '^design ' "$TMPD/headline.verify" | grep -q 'drift'; then
    grep -m 1 '^persona drift: ' "$TMPD/headline.verify" || echo "persona drift: rerun apply in the primary home"
  fi
  grep -m 1 '^design drift: ' "$TMPD/headline.verify" || true
}

anchors() {
  local kv k v miss=0 w s first
  kv=$(load_named nautical)
  chk() {
    if grep -qF -- "$2" "$CODE_ROOT/$1" 2>/dev/null; then :; else
      printf 'anchor missing: %s not found in %s\n' "$2" "$1"; miss=1
    fi
  }
  while IFS="$TAB" read -r k v; do
    case "$k" in
      schema|name|description|*_plural|avoid.*|label.*) ;;
      # A digest heading may be typeset with a straight (U+0027) or curly
      # (U+2019) apostrophe; either spelling anchors it.
      str.digest.*)
        grep -qF -- "**$(printf '%s' "$v" | sed "s/'/$RSQUO/g")**" "$CODE_ROOT/.agents/skills/bearings/SKILL.md" 2>/dev/null \
          || chk .agents/skills/bearings/SKILL.md "**$v**" ;;
      # Upstream's note glyphs are the Claude mod's note constants, which the
      # theme reader replaces at display time.
      glyph.*) chk .claude/mods/firstmate-calm/lib/fm-branch-notes.ts "\"$v\"" ;;
      str.*)
        registry_rows | awk -F '\t' -v k="$k" -v v="$v" '$1 == k && index($6, v) { found = 1 } END { exit !found }' \
          || { printf 'anchor missing: nautical %s is not in the upstream line of any registered %s hook\n' "$k" "$k"; miss=1; } ;;
      seasoning)
        printf '%s\n' "$v" | tr ',' '\n' | sed 's/^ *//' > "$TMPD/season"
        while read -r w; do chk AGENTS.md "\"$w\""; done < "$TMPD/season" ;;
      alias.*) [ -f "$SKILLS/${k#alias.}/SKILL.md" ] || { printf 'anchor missing: skill %s\n' "${k#alias.}"; miss=1; } ;;
      crew) chk VISION.md "$v" ;;
      ship_task|scout_task)
        first=$(printf '%s' "$v" | cut -c1 | tr '[:lower:]' '[:upper:]')
        chk AGENTS.md "**$first$(printf '%s' "$v" | cut -c2-)**" ;;
      user_address|noop_reply|bad_news_example) chk AGENTS.md "$v" ;;
      *) grep -qiF -- "$v" "$CODE_ROOT/AGENTS.md" || { printf 'anchor missing: %s not found in AGENTS.md\n' "$v"; miss=1; } ;;
    esac
  done < "$kv"
  chk AGENTS.md 'Address the user as "captain"'
  chk bin/fm-dod-lib.sh "## Captain's intent"
  # Every user-invocable upstream skill needs an alias key, so a new upstream
  # command is a reviewed theme decision rather than a silent nautical leftover.
  for s in "$SKILLS"/*/SKILL.md; do
    w=$(basename "$(dirname "$s")")
    case "$w" in po-*) continue ;; esac
    [ -f "$SKILLS/$w/$ALIAS_MARKER" ] && continue
    grep -qx 'user-invocable: true' "$s" || continue
    get "$kv" "alias.$w" >/dev/null 2>&1 || { printf 'anchor missing: user-invocable skill %s has no alias.%s key\n' "$w" "$w"; miss=1; }
  done
  # The ADR-0016 hook hunks survived the merge.
  grep -q '^Persona: ' "$CODE_ROOT/AGENTS.md" || { echo 'anchor missing: the ADR-0016 Persona line in AGENTS.md'; miss=1; }
  chk bin/fm-dod-lib.sh 'po-theme.sh" worker-line'
  chk bin/fm-dod-lib.sh 'po-theme.sh" address-alt'
  # ADR-0020 hooks: every registered hook line is present, and every upstream
  # line a hook replaces still exists upstream at the pin.
  local pin file hook up
  pin=$(tr -d '[:space:]' < "$CODE_ROOT/docs/pixeloven/upstream-pin" 2>/dev/null || true)
  if [ -n "$pin" ] && git -C "$CODE_ROOT" cat-file -e "$pin^{commit}" 2>/dev/null; then :; else
    echo "note: upstream pin ${pin:-?} is not in this clone; replaced upstream lines not checked"; pin=''
  fi
  while IFS="$TAB" read -r k w file s hook up; do
    trim < "$CODE_ROOT/$file" 2>/dev/null | grep -qxF -- "$hook" || { printf 'anchor missing: hook %s not found in %s: %s\n' "$k" "$file" "$hook"; miss=1; }
    [ -n "$pin" ] && [ -n "$up" ] || continue
    git -C "$CODE_ROOT" show "$pin:$file" 2>/dev/null | trim | grep -qxF -- "$up" \
      || { printf 'anchor missing: upstream line for hook %s no longer in %s at the pin: %s\n' "$k" "$file" "$up"; miss=1; }
  done < <(registry_rows)
  canary "$kv" || miss=1
  [ $miss -eq 0 ] && echo "anchors: ok"
  return $miss
}

# producer_files: the tracked files the surface canary scans - script, module,
# and page sources outside tests and docs.
producer_files() {
  git -C "$CODE_ROOT" ls-files | grep -E '\.(sh|ts|tsx|js|mjs|cjs|html)$' \
     | grep -vE '(^|/)(tests?|node_modules)/|\.test\.|^docs/' \
     | while IFS= read -r f; do [ -f "$CODE_ROOT/$f" ] && printf '%s\n' "$f"; done | sort
}

# canary <nautical-kv>: ADR-0020's surface canary. Scans upstream's
# person-facing producer patterns - ui.notify, $.ui.toast, and $.ui.log calls,
# command-registration descriptions, notification titles, and board page text -
# for the nautical theme's role, product, label, and seasoning words, and fails
# on any match whose line is neither a registered hook line nor covered by a
# residue row. Residue rows (RESIDUE) are tab-separated: file, a fixed substring
# of the producer line, and why it stays nautical, opening with the ADR-0020
# rule (R1-R5) or the stage that will theme it (S1-S7), then a colon.
canary() {
  local kv=$1 k v bad=0
  : > "$TMPD/words"
  while IFS="$TAB" read -r k v; do
    case "$k" in
      user|user_plural|self|self_plural|product|worker|worker_plural|crew|submate|submate_plural|fleet|ship_task|scout_task|label.submate)
        lower "$v" >> "$TMPD/words"; printf '\n' >> "$TMPD/words" ;;
      seasoning) printf '%s\n' "$v" | tr ',' '\n' | sed 's/^ *//; s/ *$//' >> "$TMPD/words" ;;
    esac
  done < "$1"
  [ -f "$RESIDUE" ] || { echo "surface canary: no residue list at $RESIDUE"; return 1; }
  awk -F '\t' '!/^#/ && NF > 0' "$RESIDUE" > "$TMPD/residue"
  if awk -F '\t' 'NF != 3 || $1 == "" || $2 == "" || $3 !~ /^(R[1-5]|S[1-7]):/ { printf "surface canary: malformed residue row (want file, text, and a reason opening with R1-R5 or S1-S7 and a colon): %s\n", $0; bad = 1 } END { exit bad }' "$TMPD/residue"; then :; else
    bad=1
  fi
  registry_rows | awk -F '\t' '{ print $3 "\t" $5 }' > "$TMPD/hooks"
  producer_files > "$TMPD/producers"
  [ -s "$TMPD/producers" ] || { echo "surface canary: no producer files under $CODE_ROOT"; return 1; }
  # Pass 1: every producer line that carries a nautical word, as
  # file<TAB>line<TAB>kind<TAB>word<TAB>trimmed text.
  # shellcheck disable=SC2016  # awk program text: $0 and the $.ui pattern are awk's.
  ( cd "$CODE_ROOT" && tr '\n' '\0' < "$TMPD/producers" | xargs -0 awk -v words="$TMPD/words" '
    BEGIN { while ((getline w < words) > 0) if (w != "") nw[++n] = w }
    function scan(line, kind,   l, i, t) {
      l = tolower(line)
      for (i = 1; i <= n; i++)
        if (match(l, "(^|[^a-z0-9_])" nw[i] "s?([^a-z0-9_]|$)")) {
          t = line; sub(/^[[:space:]]+/, "", t); sub(/[[:space:]]+$/, "", t)
          printf "%s\t%d\t%s\t%s\t%s\n", FILENAME, FNR, kind, nw[i], t
          return
        }
    }
    FNR == 1 { depth = 0; desc = 0; descnext = 0; style = 0; cmt = 0; html = (FILENAME ~ /\.html$/); sh = (FILENAME ~ /\.sh$/) }
    html {
      line = $0
      if (line ~ /<style[ >]/) style = 1
      if (style) { if (line ~ /<\/style>/) style = 0; next }
      gsub(/<!--([^-]|-[^-])*-->/, "", line); gsub(/\/\*([^*]|\*[^\/])*\*\//, "", line)
      if (cmt) { if (line ~ /\*\/|-->/) { sub(/^.*(\*\/|-->)/, "", line); cmt = 0 } else next }
      if (line ~ /\/\*|<!--/) { sub(/(\/\*|<!--).*$/, "", line); cmt = 1 }
      sub(/(^|[[:space:]])\/\/.*$/, "", line)
      scan(line, "board text"); next
    }
    /^[[:space:]]*(#|\/\/|\*)/ { next }
    /display notification|notification show|terminal-notifier|notify-send/ { scan($0, "notification title"); next }
    sh { next }
    depth > 0 || /ui(\?)?\.notify(\?\.)?\(|\$\.ui(\?)?\.(toast|log)(\?\.)?\(/ {
      if (depth == 0) lines = 0
      scan($0, "notify call")
      o = gsub(/\(/, "(", $0); c = gsub(/\)/, ")", $0); depth += o - c
      if (++lines >= 8 || depth <= 0) depth = 0
      next
    }
    /registerCommand(\?\.)?\(|command\.register(\?\.)?\(/ { desc = 6 }
    desc > 0 {
      desc--
      if (descnext) { scan($0, "command description"); descnext = 0; desc = 0; next }
      if ($0 ~ /description:/) {
        if ($0 ~ /description:[[:space:]]*$/) descnext = 1
        else { scan($0, "command description"); desc = 0 }
      }
    }
  ' ) > "$TMPD/canary.hits" || { echo "surface canary: the producer scan failed"; return 1; }
  # Pass 2: drop registered hook lines and residue; report the rest and note
  # residue rows that no longer match anything.
  awk -F '\t' -v hooks="$TMPD/hooks" -v residue="$TMPD/residue" '
    BEGIN {
      while ((getline l < hooks) > 0) { p = index(l, "\t"); hook[substr(l, 1, p - 1) SUBSEP substr(l, p + 1)] = 1 }
      while ((getline l < residue) > 0) { split(l, f, "\t"); nr++; rf[nr] = f[1]; rt[nr] = f[2] }
    }
    {
      if (($1 SUBSEP $5) in hook) next
      for (i = 1; i <= nr; i++) if (rf[i] == $1 && index($5, rt[i])) { used[i] = 1; next_row = 1; break }
      if (next_row) { next_row = 0; next }
      printf "surface canary: nautical \"%s\" (%s) at %s:%d is neither a registered hook nor residue: %s\n", $4, $3, $1, $2, $5
      bad = 1
    }
    END {
      for (i = 1; i <= nr; i++) if (!used[i]) printf "note: residue row matches no producer line; remove it: %s\t%s\n", rf[i], rt[i]
      exit bad
    }
  ' "$TMPD/canary.hits" || bad=1
  return $bad
}

# herdr_cli <session> <args...>: the herdr adapter's own session-scoped CLI
# wrapper, so relabel uses the same client selection and --session flag.
herdr_cli() {
  FM_HOME="$FM_HOME" bash -c '. "$1/bin/backends/herdr.sh"; shift; fm_backend_herdr_cli "$@"' _ "$CODE_ROOT" "$@"
}

# paseo_workspaces: the Paseo adapter's `workspace ls --json` through its own
# CLI resolution, or `[]` when no Paseo client is installed.
paseo_workspaces() {
  FM_HOME="$FM_HOME" bash -c '. "$1/bin/backends/paseo.sh"; fm_backend_paseo_bin >/dev/null 2>&1 || { printf "[]"; exit 0; }; fm_backend_paseo_cli workspace ls --json 2>/dev/null' _ "$CODE_ROOT"
}

# live_labels <session> <list-json>: every live workspace label the history
# protects - <list-json> for <session>, each other herdr session this home's
# task records name, and every Paseo workspace, whatever its cwd. Fails
# when any of them cannot be listed.
live_labels() {
  local session=$1 s l
  printf '%s' "$2" | jq -r '.result.workspaces[]?.label | strings' 2>/dev/null || return 1
  while IFS= read -r s; do
    [ -n "$s" ] && [ "$s" != "$session" ] || continue
    l=$(herdr_cli "$s" workspace list 2>/dev/null) || return 1
    printf '%s' "$l" | jq -r '.result.workspaces[]?.label | strings' 2>/dev/null || return 1
  done < <(sed -n 's/^herdr_session=//p' "$STATE"/*.meta 2>/dev/null | sort -u)
  l=$(paseo_workspaces) && printf '%s' "$l" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$l" | jq -r '.[].name | strings' 2>/dev/null
  # Herdr app space names live only in the app, so they count once this home
  # has hc records and the app's CLI is installed; a closed window keeps all.
  grep -qx 'backend=hc' "$STATE"/*.meta 2>/dev/null || return 0
  hc_backend fm_backend_hc_app_bin >/dev/null 2>&1 || return 0
  l=$(hc_backend fm_backend_hc_app_spaces) || return 1
  printf '%s' "$l" | jq -r '.spaces[]?.name | strings' 2>/dev/null
}

# mate_accept <home> <canonical-label>: <canonical-label>'s accept-set as that
# secondmate home resolves it itself; fails when the home is not a readable
# local secondmate home. A local secondmate home is its own firstmate checkout
# whose workers spawn from its own bin/, and its Persona block propagates
# independently of that checkout's code, so the set comes from the home's own
# label library; a checkout without one matches only the canonical label.
mate_accept() {
  case "$1" in /*) ;; *) return 1 ;; esac
  [ -r "$1/.fm-secondmate-home" ] || return 1
  [ -f "$1/bin/po-theme-lib.sh" ] || { printf '%s\n' "$2"; return 0; }
  # shellcheck disable=SC2016
  env -u FM_CONFIG_OVERRIDE -u FM_DATA_OVERRIDE -u FM_STATE_OVERRIDE FM_HOME="$1" \
    bash -c '. "$1/bin/po-theme-lib.sh"; po_home_accept "$2"' _ "$1" "$2"
}

# hc_backend <function> <args...>: one hc adapter function, sourced through
# bin/fm-backend.sh exactly as the spawn sources it.
hc_backend() {
  # shellcheck disable=SC2016
  FM_HOME="$FM_HOME" bash -c '. "$1/bin/fm-backend.sh" && fm_backend_source hc || exit 1; shift; "$@"' _ "$CODE_ROOT" "$@"
}

# meta_field <file> <key>: one key=value field of a task record.
meta_field() {
  awk -F= -v k="$2" '$1 == k { print substr($0, index($0, "=") + 1); exit }' "$1"
}

# hc_home_canonical: this home's canonical label.
hc_home_canonical() {
  if is_secondmate_home; then
    printf '2ndmate-%s' "$(tr -d '[:space:]' < "$FM_HOME/.fm-secondmate-home")"
  else
    printf 'firstmate'
  fi
}

# hc_space_plan [task-id]: "<space-id><TAB><canonical-label>" lines for the
# Herdr app spaces this home's hc records show in, or [task-id]'s record only.
# The launching supervisor's own terminal comes first, under the home's label,
# then each record's terminal that still carries this home's and that record's
# own task labels (a stale address reused by another terminal is skipped): a
# primary home's kind=secondmate record under that secondmate's label, any
# other under the home's. A space keeps the first label it gets, so the
# supervisor living in a space names it.
hc_space_plan() {
  local only=${1:-} canon f id session term space sessions='' s caller
  canon=$(hc_home_canonical)
  : > "$TMPD/hc-plan"
  for f in "$STATE"/*.meta; do
    [ -f "$f" ] || continue
    id=$(basename "$f" .meta)
    [ -z "$only" ] || [ "$id" = "$only" ] || continue
    [ "$(meta_field "$f" backend)" = hc ] || continue
    session=$(meta_field "$f" hc_session)
    term=$(meta_field "$f" hc_terminal)
    [ -n "$session" ] && [ -n "$term" ] || continue
    sessions="$sessions$session
"
    case "$(hc_backend fm_backend_hc_endpoint_state "$session:$term" "fm-$id")" in
      ready | finished) ;;
      *) continue ;;
    esac
    space=$(hc_backend fm_backend_hc_terminal_space "$session:$term") || continue
    if ! is_secondmate_home && [ "$(meta_field "$f" kind)" = secondmate ]; then
      printf '%s\t2ndmate-%s\n' "$space" "$id" >> "$TMPD/hc-plan"
    else
      printf '%s\t%s\n' "$space" "$canon" >> "$TMPD/hc-plan"
    fi
  done
  [ -n "${HC_TERMINAL_ID:-}" ] || sessions=''
  [ -z "$sessions" ] || sessions="$sessions${HC_SESSION:-default}
"
  printf '%s' "$sessions" | awk 'NF && !seen[$0]++' > "$TMPD/hc-sessions"
  while IFS= read -r s; do
    caller=$(hc_backend fm_backend_hc_caller_terminal "$s") || continue
    space=$(hc_backend fm_backend_hc_terminal_space "$s:$caller") || continue
    printf '%s\t%s\n' "$space" "$canon"
    break
  done < "$TMPD/hc-sessions"
  cat "$TMPD/hc-plan"
}

# hc_spaces_apply <dry> <verbose> [task-id]: rename each planned space that
# still carries the app's automatic name or one of its label's accept-set
# words. A space the window does not show yet is re-read briefly, because the
# app projects a new terminal's space a moment after the spawn creates it.
hc_spaces_apply() {
  local dry=$1 verbose=$2 only=${3:-} spaces id canon want accept cur rc tries
  hc_space_plan "$only" | awk -F "$TAB" 'NF && !seen[$1]++' > "$TMPD/hc-spaces"
  if [ ! -s "$TMPD/hc-spaces" ]; then
    [ "$verbose" -eq 0 ] || echo "relabel: no Herdr app space recorded for this home"
    return 0
  fi
  spaces=$(hc_backend fm_backend_hc_app_spaces) || {
    [ "$verbose" -eq 0 ] || echo "relabel: no open Herdr app window answered; its spaces were not renamed"
    return 0
  }
  while IFS="$TAB" read -r id canon; do
    want=$(po_home_label "$canon")
    accept=$(po_home_accept "$want")
    tries=${FM_HC_SPACE_WAIT_TRIES:-3}
    while :; do
      rc=0
      cur=$(hc_backend fm_backend_hc_space_name_state "$spaces" "$id" "$accept") || rc=$?
      [ "$rc" -eq 1 ] && [ "$tries" -gt 0 ] && [ -n "$only" ] || break
      tries=$((tries - 1))
      sleep 0.3
      spaces=$(hc_backend fm_backend_hc_app_spaces) || break
    done
    case "$rc" in
      0) ;;
      1) [ "$verbose" -eq 0 ] || echo "relabel: Herdr app space $id is not in the open window; skipped"; continue ;;
      *) [ "$verbose" -eq 0 ] || echo "relabel: Herdr app space $id is named '$cur' by a person, not by this home; kept"; continue ;;
    esac
    [ "$cur" != "$want" ] || continue
    [ "$verbose" -eq 0 ] || echo "relabel: Herdr app space $id '$cur' -> '$want'"
    [ "$dry" -eq 1 ] || hc_backend fm_backend_hc_space_rename "$id" "$want" || return 1
  done < "$TMPD/hc-spaces"
}

# relabel [--session <name>] [--hc] [--dry-run]
relabel() {
  local session='' dry=0 hc=0 ids='' id home want list cur role w f mid mhome accept renamed=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --session) [ $# -ge 2 ] || die "usage: relabel [--session <name>] [--hc] [--dry-run]"; session=$2; shift 2 ;;
      --hc) hc=1; shift ;;
      --dry-run) dry=1; shift ;;
      *) die "relabel: unknown argument: $1" ;;
    esac
  done
  [ -n "$session" ] || [ "$hc" -eq 1 ] || die "relabel needs --session <herdr session>, --hc, or both; it never guesses one"
  command -v jq >/dev/null 2>&1 || die "relabel needs jq"
  # shellcheck source=bin/po-theme-lib.sh
  . "$SCRIPT_DIR/po-theme-lib.sh"
  # shellcheck source=bin/fm-secondmate-registry-lib.sh
  . "$SCRIPT_DIR/fm-secondmate-registry-lib.sh"
  if [ "$hc" -eq 1 ]; then
    hc_spaces_apply "$dry" 1 || die "relabel: the Herdr app refused a space rename"
  fi
  [ -n "$session" ] || return 0
  if is_secondmate_home; then
    home=$(po_home_label "2ndmate-$(tr -d '[:space:]' < "$FM_HOME/.fm-secondmate-home")")
  else
    home=$(po_home_label firstmate)
  fi
  # A primary home's kind=secondmate record names that secondmate's own
  # workspace, so its target is the secondmate's label, not this home's.
  for f in "$STATE"/*.meta; do
    [ -f "$f" ] || continue
    [ "$(awk -F= '$1 == "herdr_session" { print substr($0, index($0, "=") + 1); exit }' "$f")" = "$session" ] || continue
    id=$(awk -F= '$1 == "herdr_workspace_id" { print substr($0, index($0, "=") + 1); exit }' "$f")
    [ -n "$id" ] || continue
    mid='' mhome=''
    if ! is_secondmate_home && grep -qx 'kind=secondmate' "$f"; then
      mid=$(basename "$f" .meta)
      mhome=$(awk -F= '$1 == "home" { print substr($0, index($0, "=") + 1); exit }' "$f")
      if [ -n "$(awk -F= '$1 == "remote_host" { print substr($0, index($0, "=") + 1); exit }' "$f")" ]; then
        mhome=''
      elif [ -z "$mhome" ]; then
        mhome=$(secondmate_registry_field "$DATA/secondmates.md" "$mid" home || true)
        [ "$(secondmate_registry_field "$DATA/secondmates.md" "$mid" remote || true)" != 1 ] || mhome=''
      fi
      want=$(po_home_label "2ndmate-$mid")
    else
      want=$home
    fi
    ids="$ids$id$TAB$want$TAB$mid$TAB$mhome
"
  done
  list=$(herdr_cli "$session" workspace list) || die "relabel: could not list herdr workspaces in session '$session'"
  printf '%s' "$ids" | awk -F "$TAB" 'NF && !seen[$1]++' > "$TMPD/ids"
  while IFS="$TAB" read -r id want mid mhome; do
    cur=$(printf '%s' "$list" | jq -r --arg id "$id" '.result.workspaces[]? | select(.workspace_id == $id) | .label // empty' 2>/dev/null)
    [ -n "$cur" ] || { echo "relabel: $id is not live in session '$session'; skipped"; continue; }
    [ "$cur" != "$want" ] || continue
    if [ -n "$mid" ]; then
      accept=$(mate_accept "$mhome" "2ndmate-$mid") || { echo "relabel: $id skipped: second mate $mid's home cannot be read locally"; continue; }
      printf '%s\n' "$accept" | grep -qxF -- "$cur" || { echo "relabel: $id is labeled '$cur', not one of second mate $mid's labels; skipped"; continue; }
      printf '%s\n' "$accept" | grep -qxF -- "$want" || { echo "relabel: $id skipped: second mate $mid does not resolve the current theme in its own checkout yet; rerun after the theme and code propagate"; continue; }
    else
      po_home_accept "$want" | grep -qxF -- "$cur" || { echo "relabel: $id is labeled '$cur', not one of this home's labels; skipped"; continue; }
    fi
    echo "relabel: $id '$cur' -> '$want'"
    renamed=1
    [ "$dry" -eq 1 ] || herdr_cli "$session" workspace rename "$id" "$want" >/dev/null || die "relabel: herdr refused to rename $id"
  done < "$TMPD/ids"
  [ "$renamed" -eq 1 ] || echo "relabel: nothing to rename"
  [ -f "$STATE/po-theme/history" ] || return 0
  [ "$dry" -eq 1 ] || list=$(herdr_cli "$session" workspace list) || die "relabel: could not re-list herdr workspaces in session '$session'"
  live_labels "$session" "$list" > "$TMPD/live" || { echo "relabel: could not list every workspace this home may still use; history kept"; return 0; }
  : > "$TMPD/history"
  while IFS="$TAB" read -r role w; do
    if { [ "$role" = primary ] && grep -qxF -- "$w" "$TMPD/live"; } \
      || { [ "$role" = submate ] && awk -v p="$w-" 'index($0, p) == 1 { f = 1 } END { exit !f }' "$TMPD/live"; } \
      || [ "$w" = "$(po_label "$role")" ]; then
      printf '%s\t%s\n' "$role" "$w" >> "$TMPD/history"
    else
      echo "relabel: history retired $role '$w'"
    fi
  done < "$STATE/po-theme/history"
  [ "$dry" -eq 1 ] || cat "$TMPD/history" > "$STATE/po-theme/history"
}

# BOARD_TEMPLATE: the registry's file name for the Bearings board template.
# Its rows register template lines whose hook equals the upstream line, because
# the template stays upstream-identical and render-board themes it at build time.
BOARD_TEMPLATE=.agents/skills/bearings/assets/board-template.html

# board_subs <out>: render-board's substitutions, one
# "<hook><TAB><kind><TAB><from><TAB><to>" line per registered template row the
# active theme changes: kind str replaces the nautical value with the theme's
# string from the values cache, and kind icon puts the theme's validated icon
# fragment inside the line's <svg> element. Reads the cache through
# bin/po-theme-lib.sh, so a theme that cannot be resolved changes nothing.
board_subs() {
  local out=$1 k file hook canon v f
  : > "$out"
  # shellcheck source=bin/po-theme-lib.sh
  . "$SCRIPT_DIR/po-theme-lib.sh"
  po__nautical && return 0
  parse "$BUNDLED/nautical.theme" > "$TMPD/board.canon" || die "bundled nautical theme is malformed"
  while IFS="$TAB" read -r k _ file _ hook _; do
    [ "$file" = "$BOARD_TEMPLATE" ] || continue
    case "$k" in
      str.*)
        canon=$(get "$TMPD/board.canon" "$k") || continue
        v=$(po__value "$k") || continue
        [ "$v" = "$canon" ] || printf '%s\tstr\t%s\t%s\n' "$hook" "$canon" "$v" >> "$out" ;;
      icon.*)
        v=$(po__value "$k") || continue
        f="$(po__state)/assets/$v"
        if [ -f "$f" ] && icon_check "$f" > "$TMPD/board.icon.err"; then
          printf '%s\ticon\t\t%s\n' "$hook" "$(tr '\n\r\t' '   ' < "$f" | sed 's/  */ /g; s/^ //; s/ $//')" >> "$out"
        else
          echo "warn: $k: icon $v is missing or invalid, so the board keeps nautical's icon" >&2
        fi ;;
    esac
  done < <(registry_rows)
}

# board_css <out>: the stylesheet of the design system in force, or nothing for
# the Firstmate Default, the board's own look (ADR-0034, DS6). A design system
# this home cannot resolve, or a sheet that could close the page's style
# element, injects nothing.
board_css() {
  local out=$1
  : > "$out"
  pd_in_force
  [ "$PD_NAME" != "$PD_DEFAULT" ] || return 0
  if ( pd_dir "$PD_NAME" ) >/dev/null 2>&1 && ( pd_css ) > "$TMPD/board.css.raw" 2> "$TMPD/board.css.err" \
    && ! LC_ALL=C grep -qi '</' "$TMPD/board.css.raw"; then
    cat "$TMPD/board.css.raw" > "$out"
  else
    echo "warn: design system $PD_NAME could not be resolved for the board, so the board keeps its own look" >&2
  fi
}

# render_board <template>: the Bearings board template in this home's theme and
# design system, on stdout, for bin/fm-bearings-board.sh to inject its payload
# into. Only registered template lines change, each matched whole; the design
# system's stylesheet follows the template's own style element, after its
# tokens, so its role values win. Under nautical words and the Firstmate
# Default the template is printed byte for byte, and any failure to theme
# prints it unthemed rather than stopping the build.
render_board() {
  local tpl=$1 subs="$TMPD/board.subs" css="$TMPD/board.css"
  [ -f "$tpl" ] || die "board template not found: $tpl"
  ( board_subs "$subs" ) 2> "$TMPD/board.subs.err" || { echo "warn: the board's theme strings could not be resolved, so it keeps nautical's words" >&2; : > "$subs"; }
  grep '^warn: ' "$TMPD/board.subs.err" >&2 || true
  ( board_css "$css" ) || { echo "warn: the board's design system could not be resolved, so it keeps its own look" >&2; : > "$css"; }
  if [ ! -s "$subs" ] && [ ! -s "$css" ]; then
    cat "$tpl"
    return 0
  fi
  registry_rows | awk -F '\t' -v t="$BOARD_TEMPLATE" '$3 == t && $1 == "design.css" { print $5 }' > "$TMPD/board.cssat"
  LC_ALL=C awk -v subs="$subs" -v css="$css" -v cssat="$TMPD/board.cssat" '
    function lit(s, a, b,   i, out) {
      out = ""
      while (a != "" && (i = index(s, a)) > 0) { out = out substr(s, 1, i - 1) b; s = substr(s, i + length(a)) }
      return out s
    }
    BEGIN {
      FS = "\t"
      while ((getline l < subs) > 0) { split(l, f, "\t"); n++; h[n] = f[1]; kind[n] = f[2]; from[n] = f[3]; to[n] = f[4] }
      while ((getline l < cssat) > 0) at[l] = 1
      while ((getline l < css) > 0) sheet = sheet l "\n"
    }
    {
      line = $0; t = line; sub(/^[[:space:]]+/, "", t)
      for (i = 1; i <= n; i++) {
        if (h[i] != t) continue
        if (kind[i] == "str") line = lit(line, from[i], to[i])
        else if ((a = index(line, "<svg")) > 0 && (e = index(line, "</svg>")) > a) {
          o = index(substr(line, a), ">"); line = substr(line, 1, a + o - 1) to[i] substr(line, e)
        } else { match(line, /^[[:space:]]*/); line = substr(line, 1, RLENGTH) to[i] }
      }
      print line
      if (sheet != "" && (t in at)) { printf "<style id=\"po-design\">\n%s</style>\n", sheet; sheet = "" }
    }
  ' "$tpl"
}

# registry_rows: the registry without comments or blank lines.
registry_rows() {
  [ -f "$REGISTRY" ] || die "no hook registry at $REGISTRY"
  awk -F '\t' '!/^#/ && NF >= 5' "$REGISTRY"
}

# vocabulary <kv>: the role-word mapping both vocabulary lines carry.
vocabulary() {
  printf 'this home calls the captain "%s", firstmate "%s", crewmates "%s", the crew "%s", second mates "%s", the fleet "%s", ship tasks "%s", and scout tasks "%s"' \
    "$(get "$1" user)" "$(get "$1" self)" "$(get "$1" worker_plural)" "$(get "$1" crew)" \
    "$(get "$1" submate_plural)" "$(get "$1" fleet)" "$(get "$1" ship_task)" "$(get "$1" scout_task)"
}

registry_files() {
  registry_rows | awk -F '\t' '$4 == "upstream" && !seen[$3]++ { print $3 }'
}

trim() { sed 's/^[[:space:]]*//'; }

# registry_check_diff <ref>: gate A9 for every registered upstream-owned file.
registry_check_diff() {
  local ref=$1 f bad=0
  git -C "$CODE_ROOT" rev-parse --verify -q "$ref^{commit}" >/dev/null || die "registry check-diff: unknown ref $ref"
  for f in $(registry_files); do
    git -C "$CODE_ROOT" diff -U0 "$ref" -- "$f" | grep -E '^[-+]' | grep -vE '^(\+\+\+ |--- )' > "$TMPD/d" || true
    grep '^+' "$TMPD/d" | cut -c2- | trim > "$TMPD/added" || true
    grep '^-' "$TMPD/d" | cut -c2- | trim > "$TMPD/removed" || true
    registry_rows | awk -F '\t' -v f="$f" '$3 == f { print $5 "\t" $6 }' > "$TMPD/rows"
    awk -F '\t' -v f="$f" -v rows="$TMPD/rows" -v removed="$TMPD/removed" '
      BEGIN {
        while ((getline l < rows) > 0) { n = index(l, "\t"); h = substr(l, 1, n - 1); hook[h]++; up[h] = substr(l, n + 1) }
        while ((getline l < removed) > 0) rem[l]++
      }
      {
        if (!($0 in hook)) { printf "A9: %s: unregistered changed line: %s\n", f, $0; bad = 1; next }
        if (++used[$0] > hook[$0]) { printf "A9: %s: hook line appears more times than it is registered: %s\n", f, $0; bad = 1; next }
        if (up[$0] != "") {
          if (rem[up[$0]] > 0) rem[up[$0]]--
          else { printf "A9: %s: hook does not replace its registered upstream line: %s\n", f, $0; bad = 1 }
        }
      }
      END {
        for (l in rem) if (rem[l] > 0) { printf "A9: %s: unregistered removed line: %s\n", f, l; bad = 1 }
        exit bad
      }
    ' "$TMPD/added" || bad=1
    if git -C "$CODE_ROOT" diff --summary "$ref" -- "$f" | grep -q 'mode change'; then
      echo "A9: $f: a theme hook changed the file mode"; bad=1
    fi
  done
  [ $bad -eq 0 ] && echo "registry: every hook line in the registered upstream files matches its row"
  return $bad
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case "$cmd" in
  resolve)
    resolve_active
    printf '%s %s\n' "$ACTIVE_NAME" "$ACTIVE_SRC" ;;
  term)
    [ $# -ge 1 ] || die "usage: term <key> [--theme T]"
    key=$1
    if [ "${2:-}" = --theme ]; then
      [ $# -ge 3 ] || die "usage: term <key> [--theme T]"
      kv=$(load_named "$3")
    else
      resolve_active; kv=$ACTIVE_KV
    fi
    get "$kv" "$key" || die "no key $key in the theme" ;;
  validate)
    if [ $# -ge 1 ]; then n=$1; else resolve_active; n=$ACTIVE_NAME; fi
    validate_named "$n" || exit 1
    echo "validate: $n ok" ;;
  persona)
    if [ $# -ge 1 ]; then persona "$1" "$(load_named "$1")" "$(src_of "$(theme_file "$1")")"; else resolve_active; persona "$ACTIVE_NAME" "$ACTIVE_KV" "$ACTIVE_ORIGIN"; fi ;;
  apply) apply ;;
  refresh) refresh ;;
  label)
    [ $# -eq 1 ] || die "usage: label <primary|submate|afk>"
    # shellcheck source=bin/po-theme-lib.sh
    . "$SCRIPT_DIR/po-theme-lib.sh"
    po_label "$1" || die "unknown label role: $1"
    printf '\n' ;;
  relabel) relabel "$@" ;;
  hc-spaces)
    [ $# -eq 1 ] || die "usage: hc-spaces <task-id>"
    command -v jq >/dev/null 2>&1 || die "hc-spaces needs jq"
    # shellcheck source=bin/po-theme-lib.sh
    . "$SCRIPT_DIR/po-theme-lib.sh"
    hc_spaces_apply 0 0 "$1" ;;
  registry)
    case "${1:-}" in
      files) registry_files ;;
      check-diff) [ $# -eq 2 ] || die "usage: registry check-diff <ref>"; registry_check_diff "$2" ;;
      *) die "usage: registry files | registry check-diff <ref>" ;;
    esac ;;
  verify) verify ;;
  headline) headline ;;
  anchors) anchors ;;
  address-alt)
    shared_address && exit 0
    active_is_nautical && exit 0
    resolve_active
    [ "$ACTIVE_NAME" = nautical ] || get "$ACTIVE_KV" user_address ;;
  worker-line)
    active_is_nautical && exit 0
    resolve_active
    [ "$ACTIVE_NAME" = nautical ] && exit 0
    printf 'Vocabulary for prose a person reads (reports, summaries): %s; identifiers and brief headings stay as written.\n' "$(vocabulary "$ACTIVE_KV")" ;;
  wake-line)
    active_is_nautical && exit 0
    resolve_active
    [ "$ACTIVE_NAME" = nautical ] && exit 0
    printf 'Vocabulary for the outcome summaries a person reads: %s; tool names, verdict values, identifiers, and every rule above keep their exact words and meaning.\n' "$(vocabulary "$ACTIVE_KV")" ;;
  voice-line)
    active_is_nautical && exit 0
    resolve_active
    [ "$ACTIVE_NAME" = nautical ] && exit 0
    printf 'Vocabulary for everything you say aloud: %s; tool names keep their exact words, and every rule above keeps its meaning.\n' "$(vocabulary "$ACTIVE_KV")" ;;
  render-board)
    [ $# -eq 1 ] || die "usage: render-board <template>"
    render_board "$1" ;;
  ds-resolve)
    pd_in_force
    printf '%s %s\n' "$PD_NAME" "$PD_ORIGIN" ;;
  ds-validate)
    if [ $# -ge 1 ]; then n=$1; else n=$(pd_selected); fi
    pd_validate "$n" || exit 1
    echo "ds-validate: $n ok" ;;
  ds-css)
    if [ $# -ge 1 ]; then pd_css "$1"; else pd_css; fi ;;
  ds-labels)
    resolve_active
    pd_labels ;;
  -h|--help|help|'') sed -n '2,/^set -eu$/p' "$0" | sed '$d; s/^# \{0,1\}//' ;;
  *) die "unknown command: $cmd" ;;
esac
