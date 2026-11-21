#!/usr/bin/env bash
# po-crew.sh - PixelOven crew delivery helper (ADR-0019).
#
# Crew and its skill packs reach every specialist through the machine-level,
# user-scope install that dotfiles maintains for Claude Code, Codex, and pi.
# Since crew 0.67.0, pixeloven/crew serves crew and its four packs as the
# pixeloven marketplace, and one crew release tag pins crew and every pack.
# Operator installs nothing itself. This helper checks that install and applies
# the one per-home choice operator owns: the supervising home's own session is
# fenced off from crew, while its workers keep it.
#
# The fence is five `"<plugin>@pixeloven": false` entries under enabledPlugins
# in the home's untracked .claude/settings.local.json. `fence` merges exactly
# those entries and keeps every other key in the file, such as permission rules;
# it backs the file up once, to the home's gitignored
# state/po-crew/settings.local.json.bak, before its first change, and is a
# no-op when the entries are already present.
# A secondmate home (.fm-secondmate-home marker) is skipped: its Claude settings
# come from the parent home's spawn, not from this file.
#
# `check` is read-only. It prints one row per item and exits 1 when any row is
# `fail`; a tool that is not installed prints `skip` rows instead.
# It reads pixeloven/crew's published release tags (vX.Y.Z) with `gh api`, and
# checks each tool against the crew tag that tool is pinned to:
#   - release: the newest published crew release tag; when the tags are
#     unreadable, one `warn` row, and each tool is compared against the commit
#     its own marketplace clone holds instead
#   - Claude Code: every plugin installed at user scope and enabled, its
#     marketplace (known_marketplaces.json) on pixeloven/crew at a release tag,
#     and each plugin's gitCommitSha equal to that tag's commit
#   - Codex: every plugin installed and enabled, and its marketplace clone
#     (.tmp/marketplaces/pixeloven) cloned from pixeloven/crew at a release tag
#     whose commit is the clone's HEAD
#   - pi: one git:github.com/pixeloven/crew@<tag> package carrying crew and the
#     packs; a pack is not checked inside a package entry with a skills filter
#   - the home fence (Claude Code lists all five disabled from the home); a
#     secondmate home skips it
# A tool at its tag while a newer crew release exists gets a `warn` row: moving
# the tag is a dotfiles change. A tool still on the retired pixeloven/marketplace
# catalogue, or a pi per-pack package, fails with the switch to pixeloven/crew
# that crew 0.67.0's Consumer impact describes, rather than a `behind` row.
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
SOURCE_REPO=pixeloven/crew
OLD_REPO=pixeloven/marketplace
SWITCH="on the retired $OLD_REPO catalogue; switch to $SOURCE_REPO per crew 0.67.0 Consumer impact with the dotfiles plugin update"
UPDATE='run the dotfiles plugin update'
TAGS=''     # "<tag> <commit>" lines for the published crew release tags
NEWEST=''   # the newest of them
REL_SETTINGS='.claude/settings.local.json'
REL_BACKUP='state/po-crew/settings.local.json.bak'

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
      echo "fence: already present in $file"
      return 0
    fi
    if [ ! -e "$home/$REL_BACKUP" ]; then
      mkdir -p "$(dirname "$home/$REL_BACKUP")"
      cp -p "$file" "$home/$REL_BACKUP"
    fi
  else
    mkdir -p "$home/.claude"
    cur='{}'
  fi
  tmp=$(mktemp "$home/.claude/.settings.local.json.XXXXXX")
  printf '%s' "$cur" | jq --argjson w "$want" '.enabledPlugins = ((.enabledPlugins // {}) + $w)' > "$tmp" \
    || { rm -f "$tmp"; die "could not write $file"; }
  # Rewrite in place so an existing file keeps its mode and inode.
  if [ -f "$file" ]; then cat "$tmp" > "$file" && rm -f "$tmp"; else mv "$tmp" "$file"; fi
  echo "fence: applied to $file"
}

FAILED=0
row() {  # <ok|warn|fail|skip> <item> <detail>
  printf '%-4s  %-34s %s\n' "$1" "$2" "$3"
  [ "$1" != fail ] || FAILED=1
}

short() { printf '%s' "$1" | cut -c1-7; }

is_tag() { printf '%s' "$1" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; }

tag_commit() {  # <tag>: its published commit, empty when unknown
  printf '%s\n' "$TAGS" | awk -v t="$1" '$1 == t { print $2; exit }'
}

# at_tag <tool> <plugin> <state> <tag> <installed-commit> <local-commit>
# Compares an install against the commit of the crew tag it is pinned to: the
# published commit, or, when the tags are unreadable, <local-commit>, the commit
# the tool's own marketplace clone resolved that tag to.
at_tag() {
  local item="$1 $2@$MARKET" state=$3 tag=$4 have=$5 want
  if ! is_tag "$tag"; then
    row fail "$item" "$state, not pinned to a crew release tag (${tag:-no ref}); $UPDATE"
    return 0
  fi
  if [ -n "$TAGS" ]; then
    want=$(tag_commit "$tag")
    [ -n "$want" ] || { row fail "$item" "$state, pinned to $tag, which is not a published crew release tag; $UPDATE"; return 0; }
  else
    want=$6
    [ -n "$want" ] || { row fail "$item" "$state, pinned to crew $tag, but its commit is unreadable; $UPDATE"; return 0; }
  fi
  if [ -z "$have" ]; then
    row fail "$item" "$state, installed commit unreadable"
  elif [ "$have" != "$want" ]; then
    row fail "$item" "$state, behind: $(short "$have") installed, crew $tag is $(short "$want"); $UPDATE"
  elif [ -n "$NEWEST" ] && [ "$tag" != "$NEWEST" ]; then
    row warn "$item" "$state, at crew $tag; crew $NEWEST is released, so move the dotfiles crew tag to adopt it"
  else
    row ok "$item" "$state, at crew $tag"
  fi
}

# source_row <tool> <plugin> <state> <source>: a failure row for an install
# whose marketplace is not pixeloven/crew; returns 1 when the source is crew.
source_row() {
  case "$4" in
    *"$SOURCE_REPO"|*"$SOURCE_REPO.git") return 1 ;;
    *"$OLD_REPO"|*"$OLD_REPO.git") row fail "$1 $2@$MARKET" "$3, $SWITCH" ;;
    *) row fail "$1 $2@$MARKET" "$3, marketplace source ${4:-unreadable} is not $SOURCE_REPO; $UPDATE" ;;
  esac
}

# Loads TAGS and NEWEST from pixeloven/crew's published release tags.
check_release() {
  local published=''
  if command -v gh >/dev/null 2>&1; then
    published=$(GH_PROMPT_DISABLED=1 gh api --paginate "repos/$SOURCE_REPO/tags?per_page=100" 2>/dev/null) || published=''
  fi
  TAGS=$(printf '%s' "$published" | jq -r '.[]? | select(type == "object") | "\(.name) \(.commit.sha // "")"' 2>/dev/null \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+ [0-9a-f]{40}$' || true)
  if [ -z "$TAGS" ]; then
    row warn release "published $SOURCE_REPO release tags unreadable; comparing each tool against its own marketplace clone, without the newest release"
    return 0
  fi
  NEWEST=$(printf '%s\n' "$TAGS" | awk '{ print $1 }' | sort -V | tail -n 1)
  row ok release "crew $NEWEST ($(short "$(tag_commit "$NEWEST")")) is the newest release, from the published $SOURCE_REPO"
}

check_claude() {
  local list p entry sha neutral market src ref loc head
  if ! command -v claude >/dev/null 2>&1; then
    row skip claude "not installed"
    return 0
  fi
  # A neutral directory, so no project settings or home fence colour the answer.
  neutral=$(mktemp -d "${TMPDIR:-/tmp}/po-crew.XXXXXX")
  list=$(cd "$neutral" && claude plugin list --json 2>/dev/null) || list=''
  rmdir "$neutral" 2>/dev/null || true
  printf '%s' "$list" | jq -e 'type == "array"' >/dev/null 2>&1 || { row fail claude "plugin list unreadable"; return 0; }
  market=$(jq -c --arg m "$MARKET" '.[$m] // empty' "$CLAUDE_DIR/plugins/known_marketplaces.json" 2>/dev/null || true)
  src=$(printf '%s' "$market" | jq -r '.source.repo // .source.url // empty' 2>/dev/null || true)
  ref=$(printf '%s' "$market" | jq -r '.source.ref // empty' 2>/dev/null || true)
  loc=$(printf '%s' "$market" | jq -r '.installLocation // empty' 2>/dev/null || true)
  head=''
  [ -z "$loc" ] || head=$(git -C "$loc" rev-parse HEAD 2>/dev/null || true)
  for p in $PLUGINS; do
    entry=$(printf '%s' "$list" | jq -c --arg id "$p@$MARKET" '[.[] | select(.id == $id and .scope == "user")][0] // empty')
    if [ -z "$entry" ]; then
      row fail "claude $p@$MARKET" "not installed at user scope; run chezmoi apply"
    elif [ "$(printf '%s' "$entry" | jq -r '.enabled')" != true ]; then
      row fail "claude $p@$MARKET" "installed but disabled at user scope"
    elif ! source_row claude "$p" enabled "$src"; then
      sha=$(jq -r --arg id "$p@$MARKET" '[.plugins[$id][]? | select(.scope == "user") | .gitCommitSha // empty][0] // empty' \
        "$CLAUDE_DIR/plugins/installed_plugins.json" 2>/dev/null || true)
      at_tag claude "$p" enabled "$ref" "$sha" "$head"
    fi
  done
}

check_codex() {
  local list p entry clone record src ref rev head
  if ! command -v codex >/dev/null 2>&1; then
    row skip codex "not installed"
    return 0
  fi
  list=$(codex plugin list --marketplace "$MARKET" --json 2>/dev/null) || list=''
  printf '%s' "$list" | jq -e '.installed | type == "array"' >/dev/null 2>&1 || { row fail codex "plugin list unreadable"; return 0; }
  # Codex installs every plugin from its one marketplace clone; the install
  # record names the source and ref that clone came from.
  clone="$CODEX_DIR/.tmp/marketplaces/$MARKET"
  record=$(jq -c . "$clone/.codex-marketplace-install.json" 2>/dev/null || true)
  src=$(printf '%s' "$record" | jq -r '.source // empty' 2>/dev/null || true)
  ref=$(printf '%s' "$record" | jq -r '.ref_name // empty' 2>/dev/null || true)
  rev=$(printf '%s' "$record" | jq -r '.revision // empty' 2>/dev/null || true)
  head=$(git -C "$clone" rev-parse HEAD 2>/dev/null || true)
  [ "$(git -C "$clone" rev-parse --show-toplevel 2>/dev/null || true)" = "$(cd "$clone" 2>/dev/null && pwd -P)" ] || head=''
  for p in $PLUGINS; do
    entry=$(printf '%s' "$list" | jq -c --arg id "$p@$MARKET" '[.installed[] | select(.pluginId == $id and .installed == true)][0] // empty')
    if [ -z "$entry" ]; then
      row fail "codex $p@$MARKET" "not installed; run chezmoi apply"
    elif [ "$(printf '%s' "$entry" | jq -r '.enabled')" != true ]; then
      row fail "codex $p@$MARKET" "installed but disabled"
    elif [ -z "$record" ]; then
      row warn "codex $p@$MARKET" "enabled, marketplace install record not readable"
    elif ! source_row codex "$p" enabled "$src"; then
      at_tag codex "$p" enabled "$ref" "${head:-$rev}" "$rev"
    fi
  done
}

# pi_pkg <settings> <name>: "<source string> <filtered>" for name's git package
# entry, if any; <filtered> is true for an object entry with a skills filter.
pi_pkg() {
  jq -r --arg p "$2" '
    [.packages[]? | {s: (if type == "object" then .source else . end), f: (type == "object" and has("skills"))}
     | select(.s | strings | test("^git:(https://)?github\\.com/pixeloven/" + $p + "(\\.git)?@")) | "\(.s) \(.f)"][0] // empty' \
    "$1" 2>/dev/null || true
}

check_pi() {
  local settings p entry ref filtered=false state
  if ! command -v pi >/dev/null 2>&1; then
    row skip pi "not installed"
    return 0
  fi
  settings="$PI_DIR/settings.json"
  # One crew package carries crew and every pack; a pre-fold machine has one
  # git:github.com/pixeloven/<name>@<commit> package per plugin instead.
  entry=$(pi_pkg "$settings" crew)
  ref=''
  if [ -n "$entry" ]; then
    filtered=${entry##* }
    entry=${entry% *}
    ref=${entry##*@}
  fi
  for p in $PLUGINS; do
    state=installed
    [ "$p" = crew ] || state="in the crew package"
    if [ "$p" != crew ] && [ -n "$(pi_pkg "$settings" "$p")" ]; then
      row fail "pi $p@$MARKET" "its own pre-fold package is still installed; switch to the crew package, which carries every pack, per crew 0.67.0 Consumer impact with the dotfiles plugin update"
    elif [ -z "$entry" ]; then
      row fail "pi $p@$MARKET" "not installed; run chezmoi apply"
    elif [ "$p" != crew ] && [ "$filtered" = true ]; then
      row warn "pi $p@$MARKET" "the crew package at $ref has a skills filter; whether it carries this pack is not checked"
    elif ! is_tag "$ref"; then
      row fail "pi $p@$MARKET" "$state, pinned by commit $(short "$ref") rather than a crew release tag; move it to the tag per crew 0.67.0 Consumer impact with the dotfiles plugin update"
    elif [ -n "$TAGS" ]; then
      # pi records no commit: the package entry's tag is the install.
      at_tag pi "$p" "$state" "$ref" "$(tag_commit "$ref")" ''
    else
      row ok "pi $p@$MARKET" "$state, at crew $ref"
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
  check_release
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
