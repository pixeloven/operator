#!/usr/bin/env bash
# po-crew.sh - PixelOven crew delivery helper (ADR-0019).
#
# Crew and its skill packs reach every Specialist through the machine-level,
# user-scope install that dotfiles maintains for Claude Code, Codex, and pi,
# pinned by the commit SHAs in the pixeloven marketplace catalogue. Operator
# installs nothing itself. This helper checks that install and applies the one
# per-home choice operator owns: the supervising home's own session is fenced
# off from crew, while its workers keep it.
#
# The fence is five `"<plugin>@pixeloven": false` entries under enabledPlugins
# in the home's untracked .claude/settings.local.json. `fence` merges exactly
# those entries and keeps every other key in the file, such as permission rules;
# it backs the file up once before its first change, is a no-op when the entries
# are already present, and keeps the file and its backup out of `git status`
# through the repository's .git/info/exclude when nothing ignores them yet.
# A secondmate home (.fm-secondmate-home marker) is skipped: its Claude settings
# come from the parent home's spawn, not from this file.
#
# `check` is read-only. It prints one row per item and exits 1 when any row is
# `fail`; a tool that is not installed prints `skip` rows instead.
#   - the catalogue lists a pin for every plugin
#   - Claude Code, Codex, and pi each have every plugin installed at user scope,
#     enabled (Claude Code and Codex), and at the catalogue pin
#   - the home fence is present (Claude Code lists all five disabled from the
#     home); a secondmate home skips it
#
# Home paths follow upstream's resolution: an explicit [home] argument, else
# FM_HOME, else FM_ROOT_OVERRIDE, else this script's code root. Tool state paths
# follow each tool's own variables: CLAUDE_CONFIG_DIR (~/.claude), CODEX_HOME
# (~/.codex), and PI_CODING_AGENT_DIR (~/.pi/agent).
#
# Usage:
#   po-crew.sh fence [home]   merge the crew fence into <home>/.claude/settings.local.json
#   po-crew.sh check [home]   report the machine install and the home fence; exit 1 on a failure
#
# Exit status: 0 on success; 1 on a failed check row, malformed settings, a
# missing jq, or a usage error.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MARKET=pixeloven
PLUGINS='crew infra-skills planning-skills identity-skills language-skills'
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
PI_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
CATALOGUE="$CLAUDE_DIR/plugins/marketplaces/$MARKET/.claude-plugin/marketplace.json"
REL_SETTINGS='.claude/settings.local.json'

die() { printf 'po-crew: %s\n' "$*" >&2; exit 1; }

home_dir() {  # [home]
  local h="${1:-${FM_HOME:-${FM_ROOT_OVERRIDE:-$CODE_ROOT}}}"
  [ -d "$h" ] || die "home not found: $h"
  (cd "$h" && pwd)
}

is_secondmate_home() { [ -e "$1/.fm-secondmate-home" ]; }

fence_json() {
  local p out='{}'
  for p in $PLUGINS; do
    out=$(printf '%s' "$out" | jq --arg k "$p@$MARKET" '. + {($k): false}')
  done
  printf '%s\n' "$out"
}

# exclude_settings <home>: keep the file and its backup out of git status when
# the home is a work tree and nothing ignores them yet.
exclude_settings() {
  local excl rel
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  excl=$(git -C "$1" rev-parse --git-path info/exclude 2>/dev/null || true)
  [ -n "$excl" ] || return 0
  case "$excl" in /*) ;; *) excl="$1/$excl" ;; esac
  for rel in "$REL_SETTINGS" "$REL_SETTINGS.po-crew-backup"; do
    git -C "$1" check-ignore -q "$rel" 2>/dev/null && continue
    mkdir -p "$(dirname "$excl")"
    grep -qxF "$rel" "$excl" 2>/dev/null || printf '%s\n' "$rel" >> "$excl"
  done
}

fence() {
  local home file want cur tmp
  home=$(home_dir "${1:-}")
  if is_secondmate_home "$home"; then
    echo "fence: skipped, $home is a secondmate home"
    return 0
  fi
  file="$home/$REL_SETTINGS"
  want=$(fence_json)
  if [ -f "$file" ]; then
    cur=$(jq -c . "$file" 2>/dev/null) || die "malformed JSON, left unchanged: $file"
    printf '%s' "$cur" | jq -e 'type == "object" and ((.enabledPlugins // {}) | type == "object")' >/dev/null \
      || die "unexpected settings shape, left unchanged: $file"
    if printf '%s' "$cur" | jq -e --argjson w "$want" '(.enabledPlugins // {}) as $e | all($w | to_entries[]; $e[.key] == false)' >/dev/null; then
      exclude_settings "$home"
      echo "fence: already present in $file"
      return 0
    fi
    [ -e "$file.po-crew-backup" ] || cp -p "$file" "$file.po-crew-backup"
  else
    mkdir -p "$home/.claude"
    cur='{}'
  fi
  tmp=$(mktemp "$home/.claude/.settings.local.json.XXXXXX")
  printf '%s' "$cur" | jq --argjson w "$want" '.enabledPlugins = ((.enabledPlugins // {}) + $w)' > "$tmp" \
    || { rm -f "$tmp"; die "could not write $file"; }
  # Rewrite in place so an existing file keeps its mode and inode.
  if [ -f "$file" ]; then cat "$tmp" > "$file" && rm -f "$tmp"; else mv "$tmp" "$file"; fi
  exclude_settings "$home"
  echo "fence: applied to $file"
}

FAILED=0
row() {  # <ok|fail|skip> <item> <detail>
  printf '%-4s  %-34s %s\n' "$1" "$2" "$3"
  [ "$1" != fail ] || FAILED=1
}

pin_of() {  # <plugin>: the catalogue SHA, empty when unknown
  jq -r --arg p "$1" '[.plugins[]? | select(.name == $p) | .source.sha // empty][0] // empty' "$CATALOGUE" 2>/dev/null || true
}

short() { printf '%s' "$1" | cut -c1-7; }

# at_pin <tool> <plugin> <installed-sha> <state-detail>
at_pin() {
  local want
  want=$(pin_of "$2")
  if [ -z "$want" ]; then
    row fail "$1 $2@$MARKET" "$4, but the catalogue has no pin to compare"
  elif [ -z "$3" ]; then
    row fail "$1 $2@$MARKET" "$4, installed commit unreadable"
  elif [ "$3" = "$want" ]; then
    row ok "$1 $2@$MARKET" "$4, at the catalogue pin $(short "$want")"
  else
    row fail "$1 $2@$MARKET" "$4, behind: $(short "$3") installed, catalogue pins $(short "$want"); run the dotfiles plugin update"
  fi
}

check_catalogue() {
  local p
  if [ ! -f "$CATALOGUE" ]; then
    row fail catalogue "not found at $CATALOGUE; add the $MARKET marketplace through dotfiles"
    return 0
  fi
  for p in $PLUGINS; do
    [ -n "$(pin_of "$p")" ] || { row fail catalogue "no pin for $p"; return 0; }
  done
  row ok catalogue "pins for all five plugins"
}

check_claude() {
  local list p entry sha neutral
  if ! command -v claude >/dev/null 2>&1; then
    row skip claude "not installed"
    return 0
  fi
  # A neutral directory, so no project settings or home fence colour the answer.
  neutral=$(mktemp -d "${TMPDIR:-/tmp}/po-crew.XXXXXX")
  list=$(cd "$neutral" && claude plugin list --json 2>/dev/null) || list=''
  rmdir "$neutral" 2>/dev/null || true
  printf '%s' "$list" | jq -e 'type == "array"' >/dev/null 2>&1 || { row fail claude "plugin list unreadable"; return 0; }
  for p in $PLUGINS; do
    entry=$(printf '%s' "$list" | jq -c --arg id "$p@$MARKET" '[.[] | select(.id == $id and .scope == "user")][0] // empty')
    if [ -z "$entry" ]; then
      row fail "claude $p@$MARKET" "not installed at user scope; run chezmoi apply"
    elif [ "$(printf '%s' "$entry" | jq -r '.enabled')" != true ]; then
      row fail "claude $p@$MARKET" "installed but disabled at user scope"
    else
      sha=$(jq -r --arg id "$p@$MARKET" '[.plugins[$id][]? | select(.scope == "user") | .gitCommitSha // empty][0] // empty' \
        "$CLAUDE_DIR/plugins/installed_plugins.json" 2>/dev/null || true)
      at_pin claude "$p" "$sha" enabled
    fi
  done
}

check_codex() {
  local list p entry ver sha
  if ! command -v codex >/dev/null 2>&1; then
    row skip codex "not installed"
    return 0
  fi
  list=$(codex plugin list --marketplace "$MARKET" --json 2>/dev/null) || list=''
  printf '%s' "$list" | jq -e '.installed | type == "array"' >/dev/null 2>&1 || { row fail codex "plugin list unreadable"; return 0; }
  for p in $PLUGINS; do
    entry=$(printf '%s' "$list" | jq -c --arg id "$p@$MARKET" '[.installed[] | select(.pluginId == $id and .installed == true)][0] // empty')
    if [ -z "$entry" ]; then
      row fail "codex $p@$MARKET" "not installed; run chezmoi apply"
    elif [ "$(printf '%s' "$entry" | jq -r '.enabled')" != true ]; then
      row fail "codex $p@$MARKET" "installed but disabled"
    else
      ver=$(printf '%s' "$entry" | jq -r '.version // empty')
      sha=$(git -C "$CODEX_DIR/plugins/cache/$MARKET/$p/$ver" rev-parse HEAD 2>/dev/null || true)
      at_pin codex "$p" "$sha" enabled
    fi
  done
}

check_pi() {
  local settings p ref
  if ! command -v pi >/dev/null 2>&1; then
    row skip pi "not installed"
    return 0
  fi
  settings="$PI_DIR/settings.json"
  for p in $PLUGINS; do
    ref=$(jq -r --arg p "$p" '
      [.packages[]? | (if type == "object" then .source else . end) | strings
       | select(test("^git:(https://)?github\\.com/pixeloven/" + $p + "(\\.git)?@"))][0] // empty' "$settings" 2>/dev/null || true)
    if [ -z "$ref" ]; then
      row fail "pi $p@$MARKET" "not installed; run chezmoi apply"
    else
      at_pin pi "$p" "${ref##*@}" installed
    fi
  done
}

check_fence() {
  local home list off
  home=$1
  if is_secondmate_home "$home"; then
    row skip fence "secondmate home"
    return 0
  fi
  if ! command -v claude >/dev/null 2>&1; then
    row skip fence "claude not installed"
    return 0
  fi
  list=$(cd "$home" && claude plugin list --json 2>/dev/null) || list=''
  off=$(printf '%s' "$list" | jq -r --arg m "@$MARKET" --arg want "$PLUGINS" '
    ($want | split(" ")) as $w
    | [ $w[] as $p | first(.[]? | select(.id == ($p + $m))) | select(.enabled == false) ] | length' 2>/dev/null || echo 0)
  if [ "$off" = 5 ]; then
    row ok fence "all five disabled in $home"
  else
    row fail fence "$off of five disabled in $home; run bin/po-crew.sh fence"
  fi
}

check() {
  local home
  home=$(home_dir "${1:-}")
  check_catalogue
  check_claude
  check_codex
  check_pi
  check_fence "$home"
  return $FAILED
}

cmd=${1:-}
[ $# -gt 0 ] && shift
[ $# -le 1 ] || die "usage: po-crew.sh fence|check [home]"
case "$cmd" in
  fence|check) command -v jq >/dev/null 2>&1 || die "jq is required" ;;
esac
case "$cmd" in
  fence) fence "${1:-}" ;;
  check) check "${1:-}" ;;
  -h|--help|help|'') sed -n '2,/^set -eu$/p' "$0" | sed '$d; s/^# \{0,1\}//' ;;
  *) die "unknown command: $cmd" ;;
esac
