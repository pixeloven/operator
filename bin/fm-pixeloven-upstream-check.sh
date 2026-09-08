#!/usr/bin/env bash
# fm-pixeloven-upstream-check.sh - prove every recorded PixelOven pin is in
# the canonical upstream default-branch history.
#
# The companion upstream mapping is emitted by fm-install-pixeloven-tool.sh;
# this script validates the complete mapping before fetching each canonical ref.
# The operator mapping is explicit here because operator is not an installable
# companion tool.
# Fetches ignore ambient Git configuration, accept only credential-free GitHub
# HTTPS URLs and branch refs, and use a tree filter so only ancestry history is
# transferred.
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
  ''|*[!0-9a-f]*) die "operator pin is not a lowercase hexadecimal commit: $operator_pin" ;;
esac
[ "${#operator_pin}" -eq 40 ] || die "operator pin must be a full 40-character commit: $operator_pin"

TEMP_ROOT=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/fm-pixeloven-upstream.XXXXXX") \
  || die 'could not create the validation directory'
cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

if [ -n "$INVENTORY" ]; then
  [ -f "$INVENTORY" ] || die "upstream inventory is missing: $INVENTORY"
else
  INVENTORY=$TEMP_ROOT/inventory
  "$INSTALLER" --upstream-list > "$INVENTORY" \
    || die 'companion upstream inventory could not be read'
fi

# Canonical evidence must not be redirected through user-controlled Git config.
git_clean() (
  unset GIT_CONFIG GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
  GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_TERMINAL_PROMPT=0 \
    GIT_ASKPASS=/bin/false \
    SSH_ASKPASS=/bin/false \
    command git "$@"
)

validate_mapping() {
  local name=$1 pin=$2 url=$3 ref=$4 slug owner repository
  case "$name" in ''|*[!A-Za-z0-9._-]*) die "malformed upstream inventory name: $name" ;; esac
  case "$pin" in
    ''|*[!0-9a-f]*) die "malformed upstream pin for $name: $pin" ;;
  esac
  [ "${#pin}" -eq 40 ] || die "upstream pin for $name must be a full 40-character commit: $pin"

  case "$url" in
    https://github.com/*.git) ;;
    *) die "canonical upstream URL for $name is not a credential-free GitHub HTTPS repository URL" ;;
  esac
  slug=${url#https://github.com/}
  slug=${slug%.git}
  owner=${slug%%/*}
  repository=${slug#*/}
  [ "$owner" != "$slug" ] && [ -n "$owner" ] && [ -n "$repository" ] \
    || die "canonical upstream URL for $name is missing an owner or repository"
  case "$owner/$repository" in
    *[!A-Za-z0-9._/-]*|*/*/*) die "canonical upstream URL for $name is malformed" ;;
  esac

  case "$ref" in
    refs/heads/?*) ;;
    *) die "canonical upstream ref for $name is not a default-branch ref" ;;
  esac
  git_clean check-ref-format "$ref" >/dev/null 2>&1 \
    || die "canonical upstream ref for $name is malformed: $ref"
}

check_lineage() {
  local name=$1 pin=$2 url=$3 ref=$4 repository head
  repository=$TEMP_ROOT/repository-$name
  mkdir -p "$repository" \
    || die "could not create validation repository for $name"
  git_clean -C "$repository" init -q --bare \
    || die "could not initialize validation repository for $name"
  GIT_ALLOW_PROTOCOL=https git_clean -C "$repository" fetch \
    --quiet --no-tags --no-recurse-submodules --filter=tree:0 \
    "$url" "+$ref:refs/remotes/canonical/upstream" \
    || die "canonical upstream history unavailable for $name ($url $ref)"
  head=$(git_clean -C "$repository" rev-parse --verify \
    'refs/remotes/canonical/upstream^{commit}' 2>/dev/null) \
    || die "canonical upstream ref did not resolve unambiguously to a commit for $name"
  git_clean -C "$repository" cat-file -e "${pin}^{commit}" 2>/dev/null \
    || die "upstream pin for $name ($pin) is unavailable from canonical upstream $ref"
  git_clean -C "$repository" merge-base --is-ancestor "$pin" "$head" \
    || die "upstream pin for $name ($pin) is not an ancestor of canonical upstream $ref"
  printf 'upstream lineage: %s %s is an ancestor of %s\n' "$name" "$pin" "$url $ref"
}

validate_mapping operator "$operator_pin" "$OPERATOR_URL" "$OPERATOR_REF"

awk -F '\t' 'NF != 4 { exit 1 }' "$INVENTORY" \
  || die 'malformed upstream inventory: every row must contain four tab-separated fields'
expected='gh-axi chrome-devtools-axi lavish-axi tasks-axi quota-axi no-mistakes'
seen=
VALIDATED_INVENTORY=$TEMP_ROOT/validated-inventory
: > "$VALIDATED_INVENTORY"
while IFS=$'\t' read -r name url ref pin; do
  case " $expected " in *" $name "*) ;; *) die "unexpected upstream inventory name: $name" ;; esac
  case "$seen" in *" $name"*) die "duplicate upstream inventory name: $name" ;; esac
  validate_mapping "$name" "$pin" "$url" "$ref"
  seen="$seen $name"
  printf '%s\t%s\t%s\t%s\n' "$name" "$url" "$ref" "$pin" >> "$VALIDATED_INVENTORY"
done < "$INVENTORY"
[ "$seen" = " $expected" ] || die "upstream inventory is missing a maintained companion fork"

check_lineage operator "$operator_pin" "$OPERATOR_URL" "$OPERATOR_REF"
while IFS=$'\t' read -r name url ref pin; do
  check_lineage "$name" "$pin" "$url" "$ref"
done < "$VALIDATED_INVENTORY"
printf 'upstream lineage checks passed\n'
