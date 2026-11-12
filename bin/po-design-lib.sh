#!/usr/bin/env bash
# po-design-lib.sh - the PixelOven design-system layer, sourced by
# bin/po-theme.sh (ADR-0031). It is not run directly.
#
# A design system supplies the look of generated pages; a theme supplies the
# words. The two are selected independently and meet only where a component
# prints a theme word, such as a status chip's label.
#
# A design system is a directory holding:
#   design.toml   required: schema, name, description, and, when tokens.css is
#                 present, vendored.package, vendored.version (semver),
#                 vendored.source, vendored.sha256, vendored.license
#   adapter.css   required: declarations of the role names in
#                 .agents/skills/po-theme/designs/roles only
#   tokens.css    optional: a vendored stylesheet, pinned by vendored.sha256
# Bundled design systems live in .agents/skills/po-theme/designs/<name>/; a
# home may add its own as config/po-designs/<name>/, which shadows a bundled
# one of the same name except firstmate. Both stylesheets are validated as data:
# only :root, :root[data-theme=...], and prefers-color-scheme blocks; only
# custom properties and color-scheme; values only of color, length, number,
# font-name, keyword, or var() shape; and in adapter.css only, Google Fonts
# @import lines before any rule. docs/pixeloven/design-systems.md owns the
# format and the role contract's meaning.
#
# Selection: the first line of config/po-design in the primary home; absent,
# empty, or firstmate means the Firstmate Default, for which apply writes
# nothing. For any other selection, apply writes the resolved stylesheet to
# state/po-design/po-ds.css with its record in state/po-design/meta, and one
# marker line in data/captain-shared.md beside the Persona block, outside it.
# A secondmate home ignores any local selection and resolves the design system
# its inherited marker names.
#
# Callers provide from bin/po-theme.sh: die, valid_name, parse, get, TMPD,
# CONFIG, DATA, STATE, SHARED, SKILLS, TAB, is_secondmate_home.

PD_DEFAULT=firstmate
PD_BUNDLED="$SKILLS/po-theme/designs"
PD_ROLES="$PD_BUNDLED/roles"
PD_COMPONENTS="$PD_BUNDLED/components.css"
PD_LOCAL="$CONFIG/po-designs"
PD_STATE="$STATE/po-design"
PD_MARK_PREFIX='<!-- po-design: '

pd_sha256() {  # <file>
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

pd_roles() { awk '/^--[a-z0-9-]+$/ { print }' "$PD_ROLES"; }

# pd_dir <name>: the design system's directory; a local one
# shadows a bundled one, except firstmate.
pd_dir() {
  valid_name "$1" || die "invalid design system name: $1"
  if [ "$1" != "$PD_DEFAULT" ] && [ -f "$PD_LOCAL/$1/adapter.css" ]; then
    printf '%s\n' "$PD_LOCAL/$1"
  elif [ -f "$PD_BUNDLED/$1/adapter.css" ]; then
    printf '%s\n' "$PD_BUNDLED/$1"
  else
    die "design system not found: $1"
  fi
}

pd_source_of() {  # <dir>: local or bundled
  case "$1" in "$PD_LOCAL"/*) echo local ;; *) echo bundled ;; esac
}

# pd_selected: the primary home's selection (the first line of config/po-design).
pd_selected() {
  local n=''
  [ -f "$CONFIG/po-design" ] && n=$(head -n 1 "$CONFIG/po-design" | tr -d '[:space:]')
  printf '%s\n' "${n:-$PD_DEFAULT}"
}

# pd_marker_field <field>: one field of the design marker in $SHARED; fails
# when there is no marker or the field is absent.
pd_marker_field() {
  [ -f "$SHARED" ] || return 1
  awk -v p="$PD_MARK_PREFIX" -v f="$1" '
    index($0, p) == 1 {
      if (match($0, " " f "=\"[^\"]*\"")) { v = substr($0, RSTART + length(f) + 3, RLENGTH - length(f) - 4); print v; found = 1 }
      exit
    }
    END { exit !found }
  ' "$SHARED"
}

pd_has_marker() { [ -f "$SHARED" ] && grep -q "^$PD_MARK_PREFIX" "$SHARED"; }

# pd_css_check <file> <adapter|vendored> <defs-out> <refs-out>: validate one
# stylesheet as data. Prints "error: ..." lines and fails on any; writes the
# custom properties it defines (adapter: those in the plain :root block, tagged
# "root") and every var() it references.
pd_css_check() {
  LC_ALL=C awk -v mode="$2" -v defs="$3" -v refs="$4" -v fname="$1" -v sq="'" '
    function err(m) { printf "error: %s: %s\n", fname, m; bad = 1 }
    function trim(x) { sub(/^[[:space:]]+/, "", x); sub(/[[:space:]]+$/, "", x); return x }
    function norm(x) { gsub(/[[:space:]]+/, " ", x); gsub(sq, "\"", x); gsub(/\( /, "(", x); gsub(/ \)/, ")", x); return trim(x) }
    function check_value(prop, v,    t, n, i, toks, r) {
      if (prop == "color-scheme") {
        if (v !~ /^(light|dark|normal|light dark|dark light)$/) err("color-scheme value is not light, dark, or normal: " v)
        return
      }
      while (match(v, /var\(--[a-z0-9-]+\)/)) {
        r = substr(v, RSTART + 4, RLENGTH - 5); print r > refs
        v = substr(v, 1, RSTART - 1) " V " substr(v, RSTART + RLENGTH)
      }
      while (match(v, /"[A-Za-z0-9 ._-]+"/)) v = substr(v, 1, RSTART - 1) " Q " substr(v, RSTART + RLENGTH)
      while (match(v, /(rgb|rgba|hsl|hsla|cubic-bezier)\([-0-9.%, \/V]*\)/)) v = substr(v, 1, RSTART - 1) " F " substr(v, RSTART + RLENGTH)
      if (v ~ /[()"]/) { err(prop ": value has a function, quote, or parenthesis outside the allowed shapes"); return }
      gsub(/[,\/]/, " ", v)
      n = split(v, toks, " ")
      if (n == 0) { err(prop ": empty value"); return }
      for (i = 1; i <= n; i++) {
        t = toks[i]
        if (t ~ /^[QVF]$/) continue
        if (t ~ /^#[0-9a-fA-F]+$/ && (length(t) == 4 || length(t) == 5 || length(t) == 7 || length(t) == 9)) continue
        if (t ~ /^-?[0-9]*\.?[0-9]+(px|rem|em|%|ms|s|deg|ch)?$/) continue
        if (t ~ /^-?[a-zA-Z][a-zA-Z0-9-]*$/ && tolower(t) !~ /expression|javascript|behavior|binding/) continue
        err(prop ": value token is not an allowed shape: " t)
      }
    }
    {
      line = $0; tl = trim(line)
      if (tl ~ /^@import/) {
        if (mode != "adapter") { err("@import is allowed only in adapter.css"); next }
        if (seen_rule) { err("@import must come before every rule"); next }
        if (tl !~ /^@import url\("https:\/\/fonts\.googleapis\.com\/css2\?[A-Za-z0-9+:;@,.=&_%-]*"\);$/) {
          err("@import is not a Google Fonts css2 stylesheet: " tl); next
        }
        next
      }
      if (index(line, "{")) seen_rule = 1
      s = s line "\n"
    }
    END {
      # strip comments; a "/*" inside a quoted string opens no comment in a
      # browser, so skip strings, or the checks below would miss what it hides
      out = ""
      while (match(s, "[\"/" sq "]")) {
        c = substr(s, RSTART, 1)
        if (c == "/" && substr(s, RSTART + 1, 1) == "*") {
          out = out substr(s, 1, RSTART - 1); s = substr(s, RSTART + 2)
          j = index(s, "*/"); if (j == 0) { err("unterminated comment"); s = ""; break }
          s = substr(s, j + 2)
          continue
        }
        out = out substr(s, 1, RSTART); s = substr(s, RSTART + 1)
        if (c == "/") continue
        j = index(s, c); nl = index(s, "\n")
        if (j == 0 || (nl > 0 && nl < j)) j = nl
        if (j == 0) j = length(s)
        out = out substr(s, 1, j); s = substr(s, j + 1)
      }
      s = out s
      if (s ~ /[\200-\377]/) err("non-ASCII text outside comments")
      low = tolower(s)
      if (index(low, "url(")) err("url() is not allowed")
      if (index(low, "@import")) err("@import is allowed only as a leading Google Fonts line")
      if (index(low, "expression")) err("expression is not allowed")
      if (index(low, "javascript")) err("javascript is not allowed")
      if (index(s, "\\")) err("backslash escapes are not allowed")
      if (index(s, "<") || index(s, ">")) err("markup characters are not allowed")
      if (index(s, "!")) err("!important is not allowed")
      rest = low; gsub(/@media[[:space:]]/, "", rest)
      if (match(rest, /@[a-z-]*/)) err("at-rule " substr(rest, RSTART, RLENGTH) " is not allowed")
      gsub(/[{};]/, "\n&\n", s)
      n = split(s, part, "\n")
      depth = 0; pending = ""
      for (k = 1; k <= n; k++) {
        p = trim(part[k])
        if (p == "") continue
        if (p == "{") {
          sel = norm(pending); pending = ""
          if (depth == 0) {
            if (sel == ":root" || sel == ":root[data-theme=\"dark\"]" || sel == ":root[data-theme=\"light\"]") { stack[1] = "rule"; ctx = sel }
            else if (sel == "@media (prefers-color-scheme: dark)" || sel == "@media (prefers-color-scheme: light)") stack[1] = "media"
            else { err("selector is not allowed: " sel); stack[1] = "bad" }
          } else if (depth == 1 && stack[1] == "media") {
            if (sel == ":root" || sel == ":root:not([data-theme=\"light\"])" || sel == ":root:not([data-theme=\"dark\"])") { stack[2] = "rule"; ctx = "media" }
            else { err("selector inside @media is not allowed: " sel); stack[2] = "bad" }
          } else { err("nested block is not allowed: " sel); stack[depth + 1] = "bad" }
          depth++
          continue
        }
        if (p == "}" || p == ";") {
          if (pending != "") {
            d = trim(pending); pending = ""
            if (depth == 0 || stack[depth] == "media") err("declaration outside a rule: " d)
            else if (stack[depth] == "rule") {
              c = index(d, ":")
              if (c == 0) err("malformed declaration: " d)
              else {
                prop = trim(substr(d, 1, c - 1)); val = trim(substr(d, c + 1))
                if (prop !~ /^--[a-z0-9-]+$/ && prop != "color-scheme") err("only custom properties and color-scheme are allowed: " prop)
                else if (val == "") err(prop ": empty value")
                else {
                  check_value(prop, val)
                  if (prop != "color-scheme") print (ctx == ":root" && depth == 1 ? "root " : "other ") prop > defs
                }
              }
            }
          }
          if (p == "}") { if (depth == 0) err("unbalanced }"); else depth-- }
          continue
        }
        pending = pending " " p
      }
      if (depth != 0) err("unbalanced {")
      if (trim(pending) != "") err("trailing text outside a rule: " trim(pending))
      exit bad
    }
  ' "$1"
}

# pd_toml_check <name> <kv> <has-tokens>: design.toml fields.
pd_toml_check() {
  local name=$1 kv=$2 has_tokens=$3 k v rc=0
  [ "$(get "$kv" schema 2>/dev/null || true)" = po-design/1 ] || { echo "error: design.toml: schema must be \"po-design/1\""; rc=1; }
  [ "$(get "$kv" name 2>/dev/null || true)" = "$name" ] || { echo "error: design.toml: name must be \"$name\""; rc=1; }
  v=$(get "$kv" description 2>/dev/null || true)
  case "$v" in ''|*[!A-Za-z0-9\ .,:\;\'@/+_-]*) echo "error: design.toml: description must be plain text"; rc=1 ;; esac
  while IFS="$TAB" read -r k v; do
    case "$k" in
      schema|name|description) ;;
      vendored.package) case "$v" in ''|*[!a-z0-9@/._-]*) echo "error: design.toml: vendored.package is not a package name"; rc=1 ;; esac ;;
      vendored.version) printf '%s\n' "$v" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$' || { echo "error: design.toml: vendored.version is not a semver version"; rc=1; } ;;
      vendored.source) printf '%s\n' "$v" | grep -Eq '^https://[A-Za-z0-9./_#@+-]+$' || { echo "error: design.toml: vendored.source is not an https URL"; rc=1; } ;;
      vendored.sha256) printf '%s\n' "$v" | grep -Eq '^[0-9a-f]{64}$' || { echo "error: design.toml: vendored.sha256 is not a lowercase SHA-256"; rc=1; } ;;
      vendored.license) case "$v" in ''|*[!A-Za-z0-9.+-]*) echo "error: design.toml: vendored.license is not a license identifier"; rc=1 ;; esac ;;
      *) echo "error: design.toml: unknown key $k"; rc=1 ;;
    esac
  done < "$kv"
  if [ "$has_tokens" = 1 ]; then
    for k in package version source sha256 license; do
      get "$kv" "vendored.$k" >/dev/null 2>&1 || { echo "error: design.toml: tokens.css is present but vendored.$k is missing"; rc=1; }
    done
  elif grep -q '^vendored\.' "$kv"; then
    echo "error: design.toml: vendored.* keys are set but there is no tokens.css"; rc=1
  fi
  return $rc
}

# pd_validate_dir <name> <dir>: every check; prints findings, fails on any error.
pd_validate_dir() {
  local name=$1 dir=$2 rc=0 has_tokens=0 want got
  local kv="$TMPD/pd.$name.kv" defs="$TMPD/pd.$name.defs" refs="$TMPD/pd.$name.refs" vdefs="$TMPD/pd.$name.vdefs"
  : > "$defs"; : > "$refs"; : > "$vdefs"
  [ -f "$dir/tokens.css" ] && has_tokens=1
  if [ ! -f "$dir/design.toml" ]; then
    echo "error: $dir: design.toml is missing"; rc=1
  elif parse "$dir/design.toml" > "$kv" 2> "$TMPD/pd.parse.err"; then
    pd_toml_check "$name" "$kv" "$has_tokens" || rc=1
  else
    sed 's/^/error: design.toml: /' "$TMPD/pd.parse.err"; rc=1
  fi
  if [ "$has_tokens" = 1 ]; then
    want=$(get "$kv" vendored.sha256 2>/dev/null || true)
    got=$(pd_sha256 "$dir/tokens.css")
    [ -z "$want" ] || [ "$want" = "$got" ] \
      || { echo "error: tokens.css: SHA-256 $got does not match vendored.sha256 $want (a changed vendored copy)"; rc=1; }
    pd_css_check "$dir/tokens.css" vendored "$vdefs" "$TMPD/pd.$name.vrefs" || rc=1
  fi
  pd_css_check "$dir/adapter.css" adapter "$defs" "$refs" || rc=1
  pd_roles > "$TMPD/pd.roles"
  awk '
    FILENAME == ARGV[1] { role[$1] = 1; order[++n] = $1; next }
    FILENAME == ARGV[2] { if ($1 == "root") root[$2] = 1
                          if (!($2 in role) && !(($2) in told)) { told[$2] = 1; printf "error: adapter.css: %s is not a role name (designs/roles)\n", $2; bad = 1 }
                          next }
    FILENAME == ARGV[3] { vdef[$2] = 1; next }
    { if (!($1 in role) && !($1 in vdef) && !($1 in seen)) { seen[$1] = 1; printf "error: adapter.css: var(%s) is neither a role nor defined by tokens.css\n", $1; bad = 1 } }
    END {
      for (i = 1; i <= n; i++) if (!(order[i] in root)) { printf "error: adapter.css: role %s is not supplied in the plain :root block\n", order[i]; bad = 1 }
      exit bad
    }
  ' "$TMPD/pd.roles" "$defs" "$vdefs" "$refs" || rc=1
  return $rc
}

pd_validate() {  # <name>
  pd_validate_dir "$1" "$(pd_dir "$1")"
}

# pd_build <name> <dir> <out>: the resolved page stylesheet: the adapter's font
# imports first, then the vendored tokens, the adapter, and the component sheet.
pd_build() {
  local name=$1 dir=$2 out=$3
  {
    printf '/* po-design: %s (%s) - generated by bin/po-theme.sh ds-css; link it at the document root and do not edit. */\n' \
      "$name" "$(pd_source_of "$dir")"
    grep -E '^[[:space:]]*@import ' "$dir/adapter.css" | sed 's/^[[:space:]]*//' || true
    if [ -f "$dir/tokens.css" ]; then
      printf '\n/* ---- vendored tokens.css ---- */\n'
      cat "$dir/tokens.css"
    fi
    printf '\n/* ---- adapter.css ---- */\n'
    grep -vE '^[[:space:]]*@import ' "$dir/adapter.css" || true
    printf '\n/* ---- components.css ---- */\n'
    cat "$PD_COMPONENTS"
  } > "$out"
}

# pd_resolve_fresh <name> <out>: validate and build; dies on a finding.
pd_resolve_fresh() {
  local dir
  dir=$(pd_dir "$1")
  if ! pd_validate_dir "$1" "$dir" > "$TMPD/pd.findings"; then
    grep '^error:' "$TMPD/pd.findings" >&2 || true
    die "design system $1 failed validation"
  fi
  pd_build "$1" "$dir" "$2"
  PD_SOURCE=$(pd_source_of "$dir")
}

pd_marker_line() {  # <name> <source> <sha>
  printf '%sname="%s" source="%s" sha256="%s" - generated by bin/po-theme.sh apply from config/po-design; rerun apply rather than editing -->\n' \
    "$PD_MARK_PREFIX" "$1" "$2" "$3"
}

# pd_write_marker <line-file>: replace the marker in $SHARED, place it right
# after the Persona block (or at the end) when absent, and remove it when
# <line-file> is empty; a file left empty is deleted, since only apply wrote it.
pd_write_marker() {
  local f=$SHARED line=$1 tmp="$TMPD/pd.shared"
  if pd_has_marker; then
    awk -v p="$PD_MARK_PREFIX" -v l="$line" '
      index($0, p) == 1 { while ((getline x < l) > 0) print x; next } { print }
    ' "$f" > "$tmp"
  elif [ -s "$line" ]; then
    if [ -f "$f" ] && grep -qxF "$END_MARK" "$f"; then
      awk -v e="$END_MARK" -v l="$line" '
        { print } $0 == e { while ((getline x < l) > 0) print x }
      ' "$f" > "$tmp"
    else
      {
        if [ -s "$f" ]; then cat "$f"; [ -z "$(tail -c 1 "$f")" ] || printf '\n'; fi
        cat "$line"
      } > "$tmp"
    fi
  else
    return 0
  fi
  if [ -s "$tmp" ]; then
    mkdir -p "$(dirname "$f")"
    cat "$tmp" > "$f"
  else
    rm -f "$f"
  fi
}

# pd_apply: the design-system half of `apply` (primary home only); apply has
# already resolved the selection into $TMPD/pd.apply.css before any write.
pd_apply() {
  local name sha
  name=$(pd_selected)
  if [ "$name" = "$PD_DEFAULT" ]; then
    : > "$TMPD/pd.line"
    pd_write_marker "$TMPD/pd.line"
    rm -rf "$PD_STATE"
    echo "design: $PD_DEFAULT - nothing to write"
    return 0
  fi
  sha=$(pd_sha256 "$TMPD/pd.apply.css")
  mkdir -p "$PD_STATE"
  cp "$TMPD/pd.apply.css" "$PD_STATE/po-ds.css.$$"
  mv "$PD_STATE/po-ds.css.$$" "$PD_STATE/po-ds.css"
  printf 'name\t%s\nsource\t%s\nsha256\t%s\n' "$name" "$PD_SOURCE" "$sha" > "$PD_STATE/meta.$$"
  mv "$PD_STATE/meta.$$" "$PD_STATE/meta"
  pd_marker_line "$name" "$PD_SOURCE" "$sha" > "$TMPD/pd.line"
  pd_write_marker "$TMPD/pd.line"
  echo "design: $name stylesheet written to $PD_STATE/po-ds.css; marker written to $SHARED"
}

# pd_in_force: sets PD_NAME and PD_ORIGIN (applied, inherited, or default).
pd_in_force() {
  if is_secondmate_home; then
    if PD_NAME=$(pd_marker_field name 2>/dev/null); then PD_ORIGIN=inherited; return 0; fi
  elif [ -f "$PD_STATE/meta" ]; then
    PD_NAME=$(awk -F '\t' '$1 == "name" { print $2 }' "$PD_STATE/meta"); PD_ORIGIN=applied; return 0
  fi
  PD_NAME=$PD_DEFAULT PD_ORIGIN=default
}

# pd_css [name]: print the resolved stylesheet of the named design system, or
# of the one in force: the applied copy in a primary home, the inherited
# marker's in a secondmate home, else the Firstmate Default.
pd_css() {
  local want got
  if [ $# -ge 1 ]; then
    pd_resolve_fresh "$1" "$TMPD/pd.css"; cat "$TMPD/pd.css"; return 0
  fi
  pd_in_force
  case "$PD_ORIGIN" in
    applied)
      want=$(awk -F '\t' '$1 == "sha256" { print $2 }' "$PD_STATE/meta")
      [ -f "$PD_STATE/po-ds.css" ] || die "design system $PD_NAME is applied but $PD_STATE/po-ds.css is missing; rerun apply"
      got=$(pd_sha256 "$PD_STATE/po-ds.css")
      [ "$got" = "$want" ] || die "$PD_STATE/po-ds.css does not match its applied checksum (hand-edited); rerun apply"
      cat "$PD_STATE/po-ds.css" ;;
    inherited)
      valid_name "$PD_NAME" || die "the design marker in $SHARED has no valid name"
      if ( pd_dir "$PD_NAME" ) >/dev/null 2>&1; then
        pd_resolve_fresh "$PD_NAME" "$TMPD/pd.css"
      else
        printf 'po-theme: design system %s is not available in this home; printed %s instead\n' "$PD_NAME" "$PD_DEFAULT" >&2
        pd_resolve_fresh "$PD_DEFAULT" "$TMPD/pd.css"
      fi
      cat "$TMPD/pd.css" ;;
    *)
      pd_resolve_fresh "$PD_DEFAULT" "$TMPD/pd.css"; cat "$TMPD/pd.css" ;;
  esac
}

# pd_active: true when this home has any design-system state worth checking,
# so an unthemed, default home pays nothing at session start.
pd_active() {
  pd_has_marker && return 0
  is_secondmate_home && return 1
  [ -d "$PD_STATE" ] && return 0
  [ "$(pd_selected)" != "$PD_DEFAULT" ]
}

# pd_verify: drift lines, each opening "design drift: "; prints "design: ok
# (<name>)" when a non-default design system is in force and current.
pd_verify() {
  local drift=0 sel name src sha m
  if is_secondmate_home; then
    pd_has_marker || return 0
    name=$(pd_marker_field name 2>/dev/null || true)
    sha=$(pd_marker_field sha256 2>/dev/null || true)
    if ! valid_name "$name" || ! ( pd_dir "$name" ) >/dev/null 2>&1; then
      echo "design drift: the inherited design system $name is not available in this home; pages get $PD_DEFAULT"
      return 1
    fi
    if ! ( pd_resolve_fresh "$name" "$TMPD/pd.v.css" ) >/dev/null 2>&1; then
      echo "design drift: the inherited design system $name does not validate in this home"; return 1
    fi
    pd_resolve_fresh "$name" "$TMPD/pd.v.css"
    [ "$(pd_sha256 "$TMPD/pd.v.css")" = "$sha" ] \
      || { echo "design drift: design system $name here differs from the primary home's applied copy; update this home or rerun apply in the primary home"; return 1; }
    echo "design: ok ($name, inherited)"
    return 0
  fi
  sel=$(pd_selected)
  pd_in_force
  if [ "$sel" != "$PD_NAME" ]; then
    echo "design drift: config/po-design selects $sel but $PD_NAME is applied; run apply"; return 1
  fi
  if [ "$PD_ORIGIN" = default ]; then
    pd_has_marker && { echo "design drift: $PD_DEFAULT is selected but $SHARED still has a design marker; run apply"; return 1; }
    return 0
  fi
  if ! ( pd_resolve_fresh "$sel" "$TMPD/pd.v.css" ) 2> "$TMPD/pd.v.err" >/dev/null; then
    echo "design drift: design system $sel no longer validates: $(grep -m 1 '^error:' "$TMPD/pd.v.err" || tail -n 1 "$TMPD/pd.v.err")"; return 1
  fi
  pd_resolve_fresh "$sel" "$TMPD/pd.v.css"
  sha=$(pd_sha256 "$TMPD/pd.v.css")
  src=$PD_SOURCE
  [ "$(awk -F '\t' '$1 == "sha256" { print $2 }' "$PD_STATE/meta")" = "$sha" ] \
    || { echo "design drift: design system $sel changed since apply; run apply"; drift=1; }
  [ -f "$PD_STATE/po-ds.css" ] && [ "$(pd_sha256 "$PD_STATE/po-ds.css")" = "$sha" ] \
    || { echo "design drift: $PD_STATE/po-ds.css is missing, stale, or hand-edited; run apply"; drift=1; }
  pd_marker_line "$sel" "$src" "$sha" > "$TMPD/pd.v.line"
  m=$(grep "^$PD_MARK_PREFIX" "$SHARED" 2>/dev/null || true)
  [ "$m" = "$(cat "$TMPD/pd.v.line")" ] \
    || { echo "design drift: the design marker in $SHARED is missing, stale, or hand-edited; run apply"; drift=1; }
  [ $drift -eq 0 ] && echo "design: ok ($sel)"
  return $drift
}

# pd_labels: "<status><TAB><label>" for the status chips, in the theme's words:
# the needs-decision chip names the user's call; every other status shows its
# own verb. Reads the active theme's kv from $ACTIVE_KV.
pd_labels() {
  local u s
  u=$(get "$ACTIVE_KV" user)
  for s in working needs-decision blocked paused "done" failed; do
    if [ "$s" = needs-decision ]; then printf '%s\t%s'\''s call\n' "$s" "$u"; else printf '%s\t%s\n' "$s" "$s"; fi
  done
}
