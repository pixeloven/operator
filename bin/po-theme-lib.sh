#!/usr/bin/env bash
# po-theme-lib.sh - sourceable workspace-label hooks for the PixelOven theme
# layer (ADR-0020 decisions 5 and 6). Bash 3.2; defines functions only.
#
# Upstream-owned files call these from single registered hook lines
# (.agents/skills/po-theme/surfaces.tsv). A home is nautical when it selects no
# theme (primary) or inherits no Persona block (secondmate); every function then
# returns upstream's own literal without reading a theme file, so labels and
# matching stay byte-identical. The only nautical-home read is
# state/po-theme/history, which exists only after a theme was applied.
#
# A themed home reads state/po-theme/values, which `bin/po-theme.sh refresh`
# (run by `apply`, or here on first use or when a source is newer) builds from
# the selected theme or, in a secondmate home, from the inherited Persona
# values line. When a theme cannot be resolved, every function falls back to
# the nautical literal, which every matcher always accepts.
#
# Matching uses an accept-set: the canonical word, the active theme's word, and
# every word this home applied earlier (state/po-theme/history), so a live
# workspace named under an older theme is still found. `bin/po-theme.sh
# relabel` renames recorded live workspaces and retires unused history.
#
# Home paths are read at call time: FM_HOME, FM_CONFIG_OVERRIDE,
# FM_DATA_OVERRIDE, and FM_STATE_OVERRIDE, so a caller that shadows FM_HOME for
# a secondmate home gets that home's labels.
#
# Functions:
#   po_label <primary|submate|afk>  the themed label word for a role
#   po_home_label <canonical-label>  firstmate -> primary label, 2ndmate-<id> ->
#                                    <submate label>-<id>; anything else unchanged
#   po_home_accept <home-label>      newline accept-set for one home's workspace
#                                    label, canonical first
#   po_label_same <a> <b>            true when <a> is in <b>'s accept-set
#   po_owner_strip <task-id>         drop a themed or historical owner prefix
#                                    ("<home-label>/") from a task id
#   po_jq_labels                     JSON for jq --argjson: {"primary": regex of
#                                    accepted primary labels, "submate": regex of
#                                    accepted secondmate label prefixes}

PO_THEME_LIB_ROOT="$(d=${BASH_SOURCE[0]%/*}; [ "$d" != "${BASH_SOURCE[0]}" ] || d=.; cd "${d:-/}/.." && pwd)"

po__home() { printf '%s' "${FM_HOME:-$PO_THEME_LIB_ROOT}"; }
po__state() { printf '%s' "${FM_STATE_OVERRIDE:-$(po__home)/state}/po-theme"; }

po__canonical() {  # <role>
  case "$1" in
    primary) printf 'firstmate' ;;
    submate) printf '2ndmate' ;;
    afk) printf 'firstmate-afk-daemon' ;;
  esac
}

# po__nautical: true when this home resolves to nautical without reading a theme.
po__nautical() {
  local home sel
  home=$(po__home)
  if [ -e "$home/.fm-secondmate-home" ]; then
    grep -qxF '<!-- po-theme:persona:start -->' "${FM_DATA_OVERRIDE:-$home/data}/captain-shared.md" 2>/dev/null && return 1
    return 0
  fi
  [ -f "${FM_CONFIG_OVERRIDE:-$home/config}/po-theme" ] || return 0
  sel=$(head -n 1 "${FM_CONFIG_OVERRIDE:-$home/config}/po-theme" | tr -d '[:space:]')
  case "$sel" in ''|nautical) return 0 ;; esac
  return 1
}

# po__fresh <values-file>: true when the cache still matches its sources.
po__fresh() {
  local vals=$1 home k v name='' src='' kind='' sel
  [ -f "$vals" ] || return 1
  while IFS="$(printf '\t')" read -r k v; do
    case "$k" in name) name=$v ;; source) src=$v ;; kind) kind=$v ;; esac
  done < "$vals"
  home=$(po__home)
  if [ -e "$home/.fm-secondmate-home" ]; then
    [ "$kind" = secondmate ] || return 1
    [ "${FM_DATA_OVERRIDE:-$home/data}/captain-shared.md" -nt "$vals" ] && return 1
    return 0
  fi
  [ "$kind" = primary ] || return 1
  sel=$(head -n 1 "${FM_CONFIG_OVERRIDE:-$home/config}/po-theme" 2>/dev/null | tr -d '[:space:]')
  [ "$sel" = "$name" ] || return 1
  [ "${FM_CONFIG_OVERRIDE:-$home/config}/po-theme" -nt "$vals" ] && return 1
  [ -n "$src" ] && [ "$src" -nt "$vals" ] && return 1
  return 0
}

# po__current <role>: the active theme's label for <role>; canonical when
# nautical or when the theme cannot be resolved.
po__current() {
  local role=$1 vals k v
  if ! po__nautical; then
    vals="$(po__state)/values"
    if { po__fresh "$vals" || "$PO_THEME_LIB_ROOT/bin/po-theme.sh" refresh >/dev/null 2>&1; } && [ -f "$vals" ]; then
      while IFS="$(printf '\t')" read -r k v; do
        [ "$k" = "label.$role" ] && [ -n "$v" ] && { printf '%s' "$v"; return 0; }
      done < "$vals"
    fi
  fi
  po__canonical "$role"
}

# po__words <role>: the accept-set words for <role>, one per line, canonical first.
po__words() {
  local role=$1 hist k v seen
  hist="$(po__state)/history"
  seen=$(po__canonical "$role")
  printf '%s\n' "$seen"
  v=$(po__current "$role")
  case "
$seen
" in *"
$v
"*) ;; *) printf '%s\n' "$v"; seen="$seen
$v" ;; esac
  [ -f "$hist" ] || return 0
  while IFS="$(printf '\t')" read -r k v; do
    [ "$k" = "$role" ] && [ -n "$v" ] || continue
    case "
$seen
" in *"
$v
"*) continue ;; esac
    printf '%s\n' "$v"
    seen="$seen
$v"
  done < "$hist"
}

po_label() {  # <primary|submate|afk>
  case "${1:-}" in primary|submate|afk) ;; *) return 1 ;; esac
  po__current "$1"
}

po_home_label() {  # <canonical-home-label>
  case "$1" in
    firstmate) po__current primary ;;
    2ndmate-?*) printf '%s-%s' "$(po__current submate)" "${1#2ndmate-}" ;;
    *) printf '%s' "$1" ;;
  esac
}

po_home_accept() {  # <home-label>
  local label=$1 words w id=''
  words=$(po__words primary)
  case "
$words
" in *"
$label
"*) printf '%s\n' "$words"; return 0 ;; esac
  words=$(po__words submate)
  while IFS= read -r w; do
    case "$label" in "$w"-?*) id=${label#"$w"-}; break ;; esac
  done <<EOF
$words
EOF
  if [ -z "$id" ]; then
    printf '%s\n' "$label"
    return 0
  fi
  while IFS= read -r w; do printf '%s-%s\n' "$w" "$id"; done <<EOF
$words
EOF
}

po_label_same() {  # <a> <b>
  [ "$1" = "$2" ] && return 0
  po_home_accept "$2" | grep -qxF -- "$1"
}

po_owner_strip() {  # <task-id>
  local task=$1 owner
  case "$task" in */*) owner=${task%%/*} ;; *) printf '%s' "$task"; return 0 ;; esac
  case "$owner" in
    firstmate|2ndmate-?*) ;;
    *) [ -z "$(po__canonical_of "$owner")" ] || task=${task#*/} ;;
  esac
  printf '%s' "$task"
}

# po__canonical_of <home-label>: the canonical form of a themed or historical
# home label this home accepts, or empty for any other label.
po__canonical_of() {
  local set
  set=$(po_home_accept "$1")
  case "$set" in *"
"*) printf '%s' "${set%%
*}" ;; esac
}

po_jq_labels() {
  local p s
  p=$(po__words primary | paste -sd '|' -)
  s=$(po__words submate | paste -sd '|' -)
  printf '{"primary":"^(%s)$","submate":"^(%s)-"}' "$p" "$s"
}
