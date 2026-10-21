#!/usr/bin/env bash
# fm-pixeloven-upstream-check.sh - prove the recorded operator upstream pin is
# in the canonical kunchenguid/firstmate default-branch history.
#
# The pin file is validated before any network access.
# The fetch ignores ambient Git configuration, binds one exact default-branch
# ref, and uses a tree filter so only ancestry history is transferred.
#
# Usage:
#   fm-pixeloven-upstream-check.sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
OPERATOR_REPO=kunchenguid/firstmate
OPERATOR_REF=refs/heads/main
OPERATOR_URL=https://github.com/$OPERATOR_REPO.git
OPERATOR_PIN_FILE=$SCRIPT_DIR/../docs/pixeloven/upstream-pin

usage() {
  cat <<'EOF'
Usage:
  fm-pixeloven-upstream-check.sh

Proves the operator upstream pin is an ancestor of the canonical
kunchenguid/firstmate default-branch history.
EOF
}

die() {
  printf 'fm-pixeloven-upstream-check.sh: %s\n' "$*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) [ "$#" -eq 1 ] || { usage >&2; exit 2; }; usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

[ -f "$OPERATOR_PIN_FILE" ] || die "operator pin file is missing: $OPERATOR_PIN_FILE"
operator_pin=
operator_pin_terminated=0
exec 3< "$OPERATOR_PIN_FILE" \
  || die "operator pin file could not be read: $OPERATOR_PIN_FILE"
if IFS= read -r operator_pin <&3; then
  operator_pin_terminated=1
fi
operator_pin_extra=
if IFS= read -r operator_pin_extra <&3 || [ -n "$operator_pin_extra" ]; then
  die 'operator pin must contain exactly one commit line'
fi
exec 3<&-
operator_pin_bytes=$(LC_ALL=C wc -c < "$OPERATOR_PIN_FILE") \
  || die "operator pin file could not be read: $OPERATOR_PIN_FILE"
[ "$operator_pin_bytes" -eq "$((${#operator_pin} + operator_pin_terminated))" ] \
  || die 'operator pin must contain exactly one commit line'
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

# Canonical evidence must not be redirected through user-controlled Git config.
git_clean() (
  unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_CONFIG \
    GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_DIR GIT_GRAFT_FILE \
    GIT_INDEX_FILE GIT_NAMESPACE GIT_OBJECT_DIRECTORY GIT_QUARANTINE_PATH \
    GIT_REPLACE_REF_BASE GIT_WORK_TREE
  GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_NO_REPLACE_OBJECTS=1 \
    GIT_TERMINAL_PROMPT=0 \
    GIT_ASKPASS=/bin/false \
    SSH_ASKPASS=/bin/false \
    command git "$@"
)

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

check_lineage operator "$operator_pin" "$OPERATOR_URL" "$OPERATOR_REF"
printf 'upstream lineage checks passed\n'
