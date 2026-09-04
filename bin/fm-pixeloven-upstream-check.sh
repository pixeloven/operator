#!/usr/bin/env bash
# fm-pixeloven-upstream-check.sh - prove every recorded PixelOven pin is in
# the canonical upstream default-branch history.
#
# The companion upstream mapping is emitted by fm-install-pixeloven-tool.sh;
# this script validates that mapping before fetching each canonical ref.  The
# operator mapping is explicit here because operator is not an installable
# companion tool.  Fetches use a tree-filter so only the commit/ref history
# needed for ancestry is transferred, and no credentials are placed in URLs.
#
# Usage:
#   fm-pixeloven-upstream-check.sh
#   fm-pixeloven-upstream-check.sh --inventory <file> --operator-pin <file>
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
INSTALLER=$SCRIPT_DIR/fm-install-pixeloven-tool.sh
OPERATOR_REPO=kunchenguid/firstmate
OPERATOR_REF=refs/heads/main
OPERATOR_URL=https://github.com/$OPERATOR_REPO.git
INVENTORY=
OPERATOR_PIN_FILE=$SCRIPT_DIR/../docs/pixeloven/upstream-pin

usage() {
  cat <<'EOF'
Usage:
  fm-pixeloven-upstream-check.sh
  fm-pixeloven-upstream-check.sh --inventory <file> --operator-pin <file>

Proves the operator pin and every companion-tool pin are ancestors of the
canonical upstream default-branch history recorded by their registries.
EOF
}

die() {
  printf 'fm-pixeloven-upstream-check.sh: %s\n' "$*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --inventory) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; INVENTORY=$2; shift 2 ;;
    --operator-pin) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; OPERATOR_PIN_FILE=$2; shift 2 ;;
    --help|-h) [ "$#" -eq 1 ] || { usage >&2; exit 2; }; usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

[ -f "$OPERATOR_PIN_FILE" ] || die "operator pin file is missing: $OPERATOR_PIN_FILE"
operator_pin=$(tr -d '[:space:]' < "$OPERATOR_PIN_FILE")
case "$operator_pin" in
  ''|*[!0-9a-fA-F]*) die "operator pin is not a hexadecimal commit: $operator_pin" ;;
esac
[ "${#operator_pin}" -eq 40 ] || die "operator pin must be a full 40-character commit: $operator_pin"

if [ -n "$INVENTORY" ]; then
  [ -f "$INVENTORY" ] || die "upstream inventory is missing: $INVENTORY"
else
  INVENTORY=$(mktemp)
  trap 'rm -f "$INVENTORY"' EXIT
  "$INSTALLER" --upstream-list > "$INVENTORY" \
    || die 'companion upstream inventory could not be read'
fi

check_mapping() {
  local name=$1 pin=$2 url=$3 ref=$4 worktree head
  case "$name" in ''|*[!A-Za-z0-9._-]*) die "malformed upstream inventory name: $name" ;; esac
  case "$pin" in
    ''|*[!0-9a-fA-F]*) die "malformed upstream pin for $name: $pin" ;;
  esac
  [ "${#pin}" -eq 40 ] || die "upstream pin for $name must be a full 40-character commit: $pin"
  case "$url" in
    https://github.com/*/*.git) ;;
    *) die "canonical upstream URL for $name is not a GitHub repository URL" ;;
  esac
  case "$ref" in
    refs/heads/*|refs/tags/*) ;;
    *) die "canonical upstream ref for $name is not a branch or tag ref: $ref" ;;
  esac

  worktree=$(mktemp -d)
  trap 'rm -rf "$worktree"' RETURN
  git -C "$worktree" init -q --bare \
    || die "could not initialize validation repository for $name"
  git -C "$worktree" fetch --quiet --no-tags --filter=tree:0 "$url" "$ref" \
    || die "canonical upstream history unavailable for $name ($url $ref)"
  head=$(git -C "$worktree" rev-parse FETCH_HEAD 2>/dev/null) \
    || die "canonical upstream ref did not resolve to a commit for $name"
  git -C "$worktree" merge-base --is-ancestor "$pin" "$head" \
    || die "upstream pin for $name ($pin) is not an ancestor of canonical upstream $ref"
  printf 'upstream lineage: %s %s is an ancestor of %s\n' "$name" "$pin" "$url $ref"
}

check_mapping operator "$operator_pin" "$OPERATOR_URL" "$OPERATOR_REF"

expected='gh-axi chrome-devtools-axi lavish-axi tasks-axi quota-axi no-mistakes'
seen=
while IFS=$'\t' read -r name url ref pin extra; do
  [ -n "$name" ] || continue
  [ -z "${extra:-}" ] || die "malformed upstream inventory row for $name"
  case " $expected " in *" $name "*) ;; *) die "unexpected upstream inventory name: $name" ;; esac
  case "$seen" in *" $name"*) die "duplicate upstream inventory name: $name" ;; esac
  seen="$seen $name"
  check_mapping "$name" "$pin" "$url" "$ref"
done < "$INVENTORY"
[ "$seen" = " $expected" ] || die "upstream inventory is missing a maintained companion fork"
printf 'upstream lineage checks passed\n'
