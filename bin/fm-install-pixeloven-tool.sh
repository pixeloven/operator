#!/usr/bin/env bash
# fm-install-pixeloven-tool.sh - install Operator's pinned companion tool forks.
#
# This file is the single owner of the exact PixelOven repository, source
# commit, and expected version selected for gh-axi, chrome-devtools-axi,
# lavish-axi, tasks-axi, quota-axi, and no-mistakes.
#
# Usage:
#   fm-install-pixeloven-tool.sh <tool> [prefix]
#   fm-install-pixeloven-tool.sh --source <tool>
#   fm-install-pixeloven-tool.sh --list
#   fm-install-pixeloven-tool.sh --help
#
# The default prefix is ${FM_PIXELOVEN_TOOL_PREFIX:-$HOME/.local}.
# npm tools are fetched at an exact commit, built with their committed pnpm
# lockfile, packed, and installed into the prefix without relying on an npm
# registry publication by the upstream author.
# no-mistakes is built from its exact source commit because GitHub forks do not
# inherit release assets.
# The no-mistakes path only builds and installs the CLI; it never starts, stops,
# restarts, or upgrades a running daemon.
# Hook setup is also deliberately separate from installation.
set -eu

usage() {
  cat <<'EOF'
Usage:
  fm-install-pixeloven-tool.sh <tool> [prefix]
  fm-install-pixeloven-tool.sh --source <tool>
  fm-install-pixeloven-tool.sh --list
  fm-install-pixeloven-tool.sh --help

Supported tools: gh-axi, chrome-devtools-axi, lavish-axi, tasks-axi, quota-axi, no-mistakes.
The default prefix is $FM_PIXELOVEN_TOOL_PREFIX when set, otherwise $HOME/.local.
EOF
}

die() {
  printf 'fm-install-pixeloven-tool.sh: %s\n' "$*" >&2
  exit 1
}

resolve_source() {
  TOOL=$1
  SOURCE_KIND=npm
  case "$TOOL" in
    gh-axi)
      SOURCE_COMMIT=84112b7897fc1d0833f2727a817ecc91a297c3ef
      EXPECTED_VERSION=0.1.34
      ;;
    chrome-devtools-axi)
      SOURCE_COMMIT=351be6bb8665fda10168242d965a966596d66772
      EXPECTED_VERSION=0.1.33
      ;;
    lavish-axi)
      SOURCE_COMMIT=ffd7aacff563b8bca09eb7ebfb17c14faeb968ce
      EXPECTED_VERSION=0.1.63
      ;;
    tasks-axi)
      SOURCE_COMMIT=d9175b6d083d693c5b6ca21652454d52e4b312d9
      EXPECTED_VERSION=0.2.5
      ;;
    quota-axi)
      SOURCE_COMMIT=bbc3deb4fca6a172db0217fd26d990fad8b4202e
      EXPECTED_VERSION=0.1.34
      ;;
    no-mistakes)
      SOURCE_COMMIT=70185bf682521ed1822e51dc09fa327b85b87e79
      EXPECTED_VERSION=1.60.1
      SOURCE_KIND=go
      ;;
    *) die "unsupported tool '$TOOL'" ;;
  esac
  SOURCE_REPO="pixeloven/$TOOL"
  SOURCE_URL="https://github.com/$SOURCE_REPO"
}

print_source() {
  resolve_source "$1"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$TOOL" "$SOURCE_URL" "$SOURCE_COMMIT" "$EXPECTED_VERSION" "$SOURCE_KIND"
}

case "${1:-}" in
  --help|-h)
    [ "$#" -eq 1 ] || { usage >&2; exit 2; }
    usage
    exit 0
    ;;
  --list)
    [ "$#" -eq 1 ] || { usage >&2; exit 2; }
    for listed_tool in gh-axi chrome-devtools-axi lavish-axi tasks-axi quota-axi no-mistakes; do
      print_source "$listed_tool"
    done
    exit 0
    ;;
  --source)
    [ "$#" -eq 2 ] || { usage >&2; exit 2; }
    print_source "$2"
    exit 0
    ;;
  '')
    usage >&2
    exit 2
    ;;
esac

[ "$#" -le 2 ] || { usage >&2; exit 2; }
resolve_source "$1"

if [ "$#" -eq 2 ]; then
  PREFIX=$2
elif [ -n "${FM_PIXELOVEN_TOOL_PREFIX:-}" ]; then
  PREFIX=$FM_PIXELOVEN_TOOL_PREFIX
elif [ -n "${HOME:-}" ]; then
  PREFIX=$HOME/.local
else
  die 'HOME is unset and no install prefix was provided'
fi
[ -n "$PREFIX" ] || die 'install prefix must not be empty'

for required_command in git mktemp install grep sed; do
  command -v "$required_command" >/dev/null 2>&1 \
    || die "$required_command is required to install $TOOL"
done
case "$SOURCE_KIND" in
  npm)
    for required_command in node npm corepack; do
      command -v "$required_command" >/dev/null 2>&1 \
        || die "$required_command is required to install $TOOL"
    done
    ;;
  go)
    for required_command in go make; do
      command -v "$required_command" >/dev/null 2>&1 \
        || die "$required_command is required to build $TOOL from its fork"
    done
    ;;
esac

TEMP_ROOT=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/fm-pixeloven-tool.XXXXXX")
trap 'rm -rf "$TEMP_ROOT"' EXIT
SOURCE_DIR=$TEMP_ROOT/source

git init -q "$SOURCE_DIR"
git -C "$SOURCE_DIR" remote add origin "$SOURCE_URL"
printf 'fm-install-pixeloven-tool.sh: fetching %s at %s\n' "$SOURCE_URL" "$SOURCE_COMMIT" >&2
git -C "$SOURCE_DIR" fetch --quiet --depth=1 origin "$SOURCE_COMMIT" \
  || die "could not fetch $SOURCE_URL at $SOURCE_COMMIT"
ACTUAL_COMMIT=$(git -C "$SOURCE_DIR" rev-parse FETCH_HEAD 2>/dev/null) \
  || die "could not resolve the fetched commit for $TOOL"
[ "$ACTUAL_COMMIT" = "$SOURCE_COMMIT" ] \
  || die "fetched $ACTUAL_COMMIT for $TOOL, expected $SOURCE_COMMIT"
git -C "$SOURCE_DIR" checkout --detach --quiet "$ACTUAL_COMMIT"

if [ "$SOURCE_KIND" = npm ]; then
  MANIFEST_NAME=$(node -e 'const p=require(process.argv[1]); process.stdout.write(p.name)' "$SOURCE_DIR/package.json") \
    || die "could not read $TOOL package name"
  MANIFEST_VERSION=$(node -e 'const p=require(process.argv[1]); process.stdout.write(p.version)' "$SOURCE_DIR/package.json") \
    || die "could not read $TOOL package version"
  [ "$MANIFEST_NAME" = "$TOOL" ] \
    || die "source package is '$MANIFEST_NAME', expected '$TOOL'"
  [ "$MANIFEST_VERSION" = "$EXPECTED_VERSION" ] \
    || die "source version is '$MANIFEST_VERSION', expected '$EXPECTED_VERSION'"

  (
    cd "$SOURCE_DIR"
    COREPACK_HOME="$TEMP_ROOT/corepack" corepack pnpm install \
      --frozen-lockfile --ignore-scripts --store-dir "$TEMP_ROOT/pnpm-store"
    COREPACK_HOME="$TEMP_ROOT/corepack" corepack pnpm run build
    npm_config_cache="$TEMP_ROOT/npm-cache" npm pack \
      --ignore-scripts --pack-destination "$TEMP_ROOT" >/dev/null
  )
  set -- "$TEMP_ROOT"/*.tgz
  [ "$#" -eq 1 ] && [ -f "$1" ] \
    || die "the $TOOL source build did not produce exactly one npm archive"
  npm_config_cache="$TEMP_ROOT/npm-cache" npm install --global --prefix "$PREFIX" "$1"
else
  SOURCE_DATE=$(git -C "$SOURCE_DIR" show -s --format=%cI "$SOURCE_COMMIT") \
    || die "could not read the source date for $TOOL"
  SOURCE_SHORT=${SOURCE_COMMIT:0:7}
  make -C "$SOURCE_DIR" build \
    VERSION="v$EXPECTED_VERSION" COMMIT="$SOURCE_SHORT" DATE="$SOURCE_DATE"
  mkdir -p "$PREFIX/bin"
  install -m 0755 "$SOURCE_DIR/bin/no-mistakes" "$PREFIX/bin/no-mistakes"
fi

INSTALLED_BIN=$PREFIX/bin/$TOOL
[ -x "$INSTALLED_BIN" ] || die "$INSTALLED_BIN was not installed as an executable"
VERSION_OUTPUT=$("$INSTALLED_BIN" --version 2>&1) \
  || die "$INSTALLED_BIN did not report its version after installation"
INSTALLED_VERSION=$(printf '%s\n' "$VERSION_OUTPUT" | grep -oE '[0-9]+(\.[0-9]+)+' | head -n 1 || true)
[ "$INSTALLED_VERSION" = "$EXPECTED_VERSION" ] \
  || die "$INSTALLED_BIN reports '${INSTALLED_VERSION:-<empty>}', expected '$EXPECTED_VERSION'"

printf 'fm-install-pixeloven-tool.sh: installed %s %s from %s@%s at %s\n' \
  "$TOOL" "$INSTALLED_VERSION" "$SOURCE_REPO" "$SOURCE_COMMIT" "$INSTALLED_BIN" >&2
printf '%s\n' "$VERSION_OUTPUT"
case ":$PATH:" in
  *":$PREFIX/bin:"*) ;;
  *) printf 'fm-install-pixeloven-tool.sh: add %s/bin to PATH\n' "$PREFIX" >&2 ;;
esac
