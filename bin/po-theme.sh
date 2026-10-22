#!/usr/bin/env bash
# po-theme.sh - PixelOven persona and vocabulary theme layer (ADR-0016).
#
# Upstream firstmate text stays byte-identical. A theme changes only display
# words: what the agents call themselves and the user in chat, their seasoning,
# the fixed no-op reply, the vocabulary workers use in prose a person reads, and
# the slash commands a person types. It never renames an identifier (script,
# path, environment variable, skill directory, status verb, or a brief heading
# that code parses) and never changes what a rule means.
#
# Theme files are a strict TOML subset: one `key = "value"` per line, `#`
# comments, no tables, no escapes, so they parse with awk under Bash 3.2.
# Bundled themes live in .agents/skills/po-theme/themes/; a home may add its own
# as config/po-themes/<name>.theme. The bundled nautical theme is the schema:
# every theme defines exactly its keys, plus optional avoid.<word> entries.
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
#                                     missing, or unexpected)
#   po-theme.sh anchors               sync canary: every nautical value still matches
#                                     the upstream text it mirrors, every
#                                     user-invocable skill has an alias key, and the
#                                     ADR-0016 hook hunks are present
#   po-theme.sh address-alt           themed vocative for bin/fm-dod-lib.sh's
#                                     intent-address check: the applied Persona
#                                     block's, else the selection's (empty for nautical)
#   po-theme.sh worker-line           one-line worker vocabulary for the launch role
#                                     contract (empty for nautical)
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
START_MARK='<!-- po-theme:persona:start -->'
END_MARK='<!-- po-theme:persona:end -->'
VALUES_PREFIX='<!-- po-theme:values '
ALIAS_MARKER='.po-theme-alias'
EXCLUDE_START='# po-theme:aliases:start'
EXCLUDE_END='# po-theme:aliases:end'
TAB=$(printf '\t')

ROLE_KEYS='user self worker crew submate fleet scout_task ship_task'
STATUS_TOKENS='working done blocked paused failed needs-decision resolved note captain-held'
HARNESS_TOKENS='claude codex opencode pi pi-signed grok kimi cursor omp muse gemini rovo agy devin commandcode polytoken'
DENY_WORDS='merge approve approval override ignore instruction instructions force discard delete yolo authority permission rule rules must never always sudo token secret password'
# Role terms are a short noun shape that cannot carry a directive, and "force"
# is an ordinary noun in a role title such as "task force"; every other value
# keeps the full list.
ROLE_DENY_WORDS='merge approve approval override ignore instruction instructions discard delete yolo authority permission rule rules must never always sudo token secret password'

die() { printf 'po-theme: %s\n' "$*" >&2; exit 1; }

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

# parse <file>: key<TAB>value lines; malformed or duplicate lines are errors.
parse() {
  awk '
    /^[[:space:]]*(#|$)/ { next }
    {
      line = $0
      if (line !~ /^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_-]*)?[[:space:]]*=[[:space:]]*"[^"\\]*"[[:space:]]*(#.*)?$/) {
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
      while (match(line, /[a-z][a-z0-9_]*(\.[a-z][a-z0-9_-]*)?="[^"]*"/)) {
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

# resolve_active: sets ACTIVE_NAME, ACTIVE_SRC, ACTIVE_KV.
resolve_active() {
  local n
  if is_secondmate_home; then
    block_of "$SHARED" > "$TMPD/inherited.block"
    if [ -s "$TMPD/inherited.block" ]; then
      values_to_theme "$TMPD/inherited.block" > "$TMPD/inherited.theme" \
        || die "the inherited Persona block in $SHARED has no values line; rerun apply in the primary home"
      parse "$TMPD/inherited.theme" > "$TMPD/inherited.kv" 2>/dev/null || die "the inherited Persona values line is malformed"
      n=$(get "$TMPD/inherited.kv" name 2>/dev/null || true)
      valid_name "$n" || die "the inherited Persona values line has no valid name"
      load_file "$n" "$TMPD/inherited.theme" "$TMPD/active.kv"
      ACTIVE_NAME=$n ACTIVE_SRC="inherited:$SHARED" ACTIVE_KV="$TMPD/active.kv"
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
}

# check_values <name> <kv>: schema, shape, and safety findings that need no
# corpus, in one awk pass so per-spawn resolution stays cheap. Regexes avoid
# interval expressions, which mawk and older BSD awk do not support. Prints
# "error:" lines; returns 1 on any error.
check_values() {
  local name=$1 kv=$2 schema_kv="$TMPD/schema.kv" k v canon err=0
  [ -s "$schema_kv" ] || parse "$BUNDLED/nautical.theme" > "$schema_kv" || die "bundled nautical theme is malformed"
  LC_ALL=C awk -F '\t' -v name="$name" -v roles="$ROLE_KEYS" -v tokens="$STATUS_TOKENS $HARNESS_TOKENS relay" \
    -v deny="$DENY_WORDS" -v roledeny="$ROLE_DENY_WORDS" '
    function bad(m) { print "error: " m; failed = 1 }
    function isrole(k) { return (k in R) || k == "product" || k ~ /_plural$/ }
    function hasword(v, w,   s) { s = " " tolower(v) " "; gsub(/[^a-z0-9_]/, " ", s); return index(s, " " w " ") > 0 }
    NR == FNR { canon[$1] = $2; order[++n] = $1; next }
    { val[$1] = $2; keys[++m] = $1 }
    END {
      nr = split(roles, ra, " "); for (i = 1; i <= nr; i++) R[ra[i]] = 1
      nd = split(deny, D, " "); nrd = split(roledeny, RD, " "); nt = split(tokens, T, " ")
      if (val["schema"] != "po-theme/1") bad("schema must be \"po-theme/1\"")
      if (val["name"] != name) bad("name must equal the theme name (" name ")")
      for (i = 1; i <= n; i++) if (!(order[i] in val)) bad("missing key: " order[i])
      for (i = 1; i <= m; i++) { k = keys[i]; if (k !~ /^avoid\./ && !(k in canon)) bad("unknown key: " k) }
      for (i = 1; i <= m; i++) {
        k = keys[i]; v = val[k]
        if (v ~ /[`$<>{}|]/ || v ~ /\[/ || v ~ /\]/ || index(v, "://")) bad(k ": forbidden character or URL in value")
        if (v ~ /[^ -~]/) bad(k ": non-printable or non-ASCII character")
        if (isrole(k)) { for (j = 1; j <= nrd; j++) if (hasword(v, RD[j])) bad(k ": value contains the authority word '"'"'" RD[j] "'"'"'") }
        else { for (j = 1; j <= nd; j++) if (hasword(v, D[j])) bad(k ": value contains the authority word '"'"'" D[j] "'"'"'") }
        if (k == "schema" || k == "name") continue
        if (k == "description") { if (length(v) > 80) bad(k ": longer than 80 characters") }
        else if (isrole(k)) { if (v !~ /^[A-Za-z][A-Za-z -]*$/ || length(v) > 24) bad(k ": must be 1-24 letters, spaces, or hyphens") }
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
      }
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
  if [ "$(get "$TMPD/v.kv" product 2>/dev/null || true)" = "$(get "$TMPD/v.kv" user 2>/dev/null || true)" ] && [ "$name" != nautical ]; then
    echo "note: product and user share '$(get "$TMPD/v.kv" user)': chat must code-style the product (ADR-0004, G-7)"
  fi
  corpus_collisions "$name" "$TMPD/v.kv" || rc=1
  return $rc
}

values_line() {  # <kv>
  local k v
  printf '%s' "$VALUES_PREFIX"
  while IFS="$TAB" read -r k v; do printf '%s="%s" ' "$k" "$v"; done < "$1"
  printf -- '-->\n'
}

# shellcheck disable=SC2016  # backticks are literal Markdown code spans for the reading agent.
persona() {  # <name> <kv>
  local name=$1 kv=$2 k v seasoning
  [ "$name" = nautical ] && return 0
  t() { get "$kv" "$1"; }
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
  printf '| ship (a change task) | %s |\n\n' "$(t ship_task)"
  printf -- '- Wherever AGENTS.md or a skill requires or models addressing the captain, including example replies that open with "Captain,", address the user as "%s," instead, capitalized at the start of a chat line; every limit on that address, including chat only and never in commits, PRs, briefs, code, or comments, applies unchanged.\n' "$(t user_address)"
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
  printf -- '- Command aliases, generated in the primary home only (a second-mate home keeps the original command names):'
  while IFS="$TAB" read -r k v; do
    case "$k" in alias.*) [ "$v" = "${k#alias.}" ] || printf ' /%s = /%s;' "$v" "${k#alias.}" ;; esac
  done < "$kv"
  printf ' in the primary home, treat each alias exactly as its target.\n'
  printf -- '- Workers receive this vocabulary through their launch role contract; scout reports and other prose a person reads use the words on the right.\n'
  values_line "$kv"
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

write_aliases() {  # <name> <kv>
  local name=$1 kv=$2 a target exclude
  for a in $(generated_aliases); do rm -rf "${SKILLS:?}/$a"; done
  : > "$TMPD/excl"
  expected_aliases "$kv" > "$TMPD/expected-aliases"
  while read -r a target; do
    mkdir -p "$SKILLS/$a"
    : > "$SKILLS/$a/$ALIAS_MARKER"
    cat > "$SKILLS/$a/SKILL.md" <<EOF
---
name: $a
description: Alias of /$target in the $name theme. Use when the user invokes /$a.
user-invocable: true
metadata:
  internal: true
---

Load the \`$target\` skill and follow it exactly as if the user had invoked /$target with the same arguments.
EOF
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
  persona "$ACTIVE_NAME" "$ACTIVE_KV" > "$TMPD/block"
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
}

verify() {
  local drift=0 a target exclude
  resolve_active
  block_of "$SHARED" > "$TMPD/actual"
  if is_secondmate_home; then
    if [ -s "$TMPD/actual" ]; then
      persona "$ACTIVE_NAME" "$ACTIVE_KV" > "$TMPD/expected"
      cmp -s "$TMPD/expected" "$TMPD/actual" || { echo "drift: the inherited Persona block does not match its own values line (hand-edited)"; drift=1; }
    fi
    [ $drift -eq 0 ] && echo "verify: ok ($ACTIVE_NAME, inherited)"
    return $drift
  fi
  persona "$ACTIVE_NAME" "$ACTIVE_KV" > "$TMPD/expected"
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
  return $drift
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
      schema|name|description|*_plural|avoid.*) ;;
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
  [ $miss -eq 0 ] && echo "anchors: ok"
  return $miss
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
    if [ $# -ge 1 ]; then persona "$1" "$(load_named "$1")"; else resolve_active; persona "$ACTIVE_NAME" "$ACTIVE_KV"; fi ;;
  apply) apply ;;
  verify) verify ;;
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
    kv=$ACTIVE_KV
    printf 'Vocabulary for prose a person reads (reports, summaries): this home calls the captain "%s", firstmate "%s", crewmates "%s", the crew "%s", second mates "%s", the fleet "%s", ship tasks "%s", and scout tasks "%s"; identifiers and brief headings stay as written.\n' \
      "$(get "$kv" user)" "$(get "$kv" self)" "$(get "$kv" worker_plural)" "$(get "$kv" crew)" \
      "$(get "$kv" submate_plural)" "$(get "$kv" fleet)" "$(get "$kv" ship_task)" "$(get "$kv" scout_task)" ;;
  -h|--help|help|'') sed -n '2,/^set -eu$/p' "$0" | sed '$d; s/^# \{0,1\}//' ;;
  *) die "unknown command: $cmd" ;;
esac
