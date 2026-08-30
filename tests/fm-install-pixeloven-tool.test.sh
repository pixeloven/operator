#!/usr/bin/env bash
# Regression tests for the exact PixelOven companion-tool source installer.
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

INSTALLER="$ROOT/bin/fm-install-pixeloven-tool.sh"
TMP_ROOT=$(fm_test_tmproot fm-install-pixeloven-tool)
ORIGINAL_PATH=$PATH
FAKEBIN="$TMP_ROOT/fakebin"
CALLS="$TMP_ROOT/calls"
mkdir -p "$FAKEBIN" "$CALLS"

cat > "$FAKEBIN/git" <<'SH'
#!/usr/bin/env bash
set -eu
printf 'git %s\n' "$*" >> "$FM_INSTALL_TEST_CALLS/git.log"
if [ "$1" = init ]; then
  for last_arg in "$@"; do :; done
  mkdir -p "$last_arg"
  exit 0
fi
[ "$1" = -C ] || exit 2
repo_dir=$2
shift 2
case "$1 $2" in
  'remote add')
    printf '%s\n' "$4" > "$repo_dir/.source-url"
    ;;
  'fetch --quiet')
    for last_arg in "$@"; do :; done
    printf '%s\n' "$last_arg" > "$repo_dir/.commit"
    tool=${repo_dir##*/}
    source_url=$(cat "$repo_dir/.source-url")
    tool=${source_url##*/}
    case "$tool" in
      gh-axi) version=0.1.34; bin=./dist/bin/gh-axi.js ;;
      chrome-devtools-axi) version=0.1.33; bin=dist/bin/chrome-devtools-axi.js ;;
      lavish-axi) version=0.1.63; bin=dist/cli.mjs ;;
      tasks-axi) version=0.2.5; bin=dist/bin/tasks-axi.js ;;
      quota-axi) version=0.1.34; bin=./dist/bin/quota-axi.js ;;
      no-mistakes) version=1.60.1 ;;
      *) exit 2 ;;
    esac
    bin=${FM_INSTALL_TEST_BIN_OVERRIDE:-${bin:-}}
    printf '{"name":"%s","version":"%s","bin":{"%s":"%s"}}\n' \
      "$tool" "$version" "$tool" "$bin" > "$repo_dir/package.json"
    ;;
  'rev-parse FETCH_HEAD')
    cat "$repo_dir/.commit"
    ;;
  'checkout --detach')
    ;;
  'show -s')
    printf '2026-08-29T00:00:00+00:00\n'
    ;;
  *) exit 2 ;;
esac
SH

cat > "$FAKEBIN/corepack" <<'SH'
#!/usr/bin/env bash
set -eu
printf 'corepack %s\n' "$*" >> "$FM_INSTALL_TEST_CALLS/corepack.log"
case " $* " in
  *' deploy --legacy '*)
    for target in "$@"; do :; done
    name=$(sed -n 's/.*"name":"\([^"]*\)".*/\1/p' package.json)
    version=$(sed -n 's/.*"version":"\([^"]*\)".*/\1/p' package.json)
    deployed_version=${FM_INSTALL_TEST_DEPLOY_VERSION:-$version}
    bin=$(node -e 'const p=require("./package.json"); process.stdout.write(p.bin[p.name])')
    bin=${bin#./}
    mkdir -p "$target/${bin%/*}" "$target/node_modules/axi-sdk-js"
    {
      printf '%s\n' '#!/usr/bin/env bash'
      printf 'printf '\''%%s\\n'\'' '\''%s'\''\n' "$deployed_version"
    } > "$target/$bin"
    /bin/cp package.json "$target/package.json"
    printf '%s\n' '{"name":"axi-sdk-js","version":"0.1.10"}' \
      > "$target/node_modules/axi-sdk-js/package.json"
    ;;
esac
exit 0
SH

cat > "$FAKEBIN/node" <<'SH'
#!/usr/bin/env bash
set -eu
if [ "${1:-}" = --version ] && [ -n "${FM_INSTALL_TEST_NODE_VERSION:-}" ]; then
  printf '%s\n' "$FM_INSTALL_TEST_NODE_VERSION"
  exit 0
fi
PATH=${PATH#*:}
export PATH
exec node "$@"
SH

cat > "$FAKEBIN/cp" <<'SH'
#!/usr/bin/env bash
set -eu
for last_arg in "$@"; do :; done
if [ "${FM_INSTALL_TEST_CP_FAIL:-0}" = 1 ]; then
  case "$last_arg" in */.gh-axi.new.*) exit 28 ;; esac
fi
exec /bin/cp "$@"
SH

cat > "$FAKEBIN/npm" <<'SH'
#!/usr/bin/env bash
set -eu
printf 'npm %s\n' "$*" >> "$FM_INSTALL_TEST_CALLS/npm.log"
case " $* " in
  *' pack '*)
    destination=
    previous=
    for arg in "$@"; do
      if [ "$previous" = --pack-destination ]; then destination=$arg; fi
      previous=$arg
    done
    name=$(sed -n 's/.*"name":"\([^"]*\)".*/\1/p' package.json)
    version=$(sed -n 's/.*"version":"\([^"]*\)".*/\1/p' package.json)
    printf '%s\t%s\n' "$name" "$version" > "$destination/$name-$version.tgz"
    ;;
  *' install --global '*)
    prefix=
    archive=
    previous=
    for arg in "$@"; do
      if [ "$previous" = --prefix ]; then prefix=$arg; fi
      previous=$arg
      archive=$arg
    done
    IFS="$(printf '\t')" read -r name version < "$archive"
    mkdir -p "$prefix/bin"
    {
      printf '%s\n' '#!/usr/bin/env bash'
      printf 'printf '\''%%s\\n'\'' '\''%s'\''\n' "$version"
    } > "$prefix/bin/$name"
    chmod 0755 "$prefix/bin/$name"
    ;;
  *) exit 2 ;;
esac
SH

cat > "$FAKEBIN/go" <<'SH'
#!/usr/bin/env bash
printf 'go version go1.25.0 test/test\n'
SH

cat > "$FAKEBIN/install" <<'SH'
#!/usr/bin/env bash
set -eu
for last_arg in "$@"; do :; done
if [ "${FM_INSTALL_TEST_INSTALL_FAIL:-0}" = 1 ]; then
  printf '%s\n' partial > "$last_arg"
  exit 28
fi
exec /usr/bin/install "$@"
SH

cat > "$FAKEBIN/make" <<'SH'
#!/usr/bin/env bash
set -eu
printf 'make %s\n' "$*" >> "$FM_INSTALL_TEST_CALLS/make.log"
repo_dir=
version=
previous=
for arg in "$@"; do
  if [ "$previous" = -C ]; then repo_dir=$arg; fi
  case "$arg" in VERSION=v*) version=${arg#VERSION=v} ;; esac
  previous=$arg
done
mkdir -p "$repo_dir/bin"
built_version=${FM_INSTALL_TEST_NO_MISTAKES_VERSION:-$version}
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf 'printf '\''%%s\\n'\'' '\''no-mistakes version v%s (test) 2026-08-29T00:00:00Z'\''\n' "$built_version"
} > "$repo_dir/bin/no-mistakes"
chmod 0755 "$repo_dir/bin/no-mistakes"
SH

chmod 0755 "$FAKEBIN/git" "$FAKEBIN/corepack" "$FAKEBIN/node" "$FAKEBIN/cp" "$FAKEBIN/npm" "$FAKEBIN/go" "$FAKEBIN/install" "$FAKEBIN/make"

test_source_inventory_is_exact_and_downstream() {
  local out
  out=$(/bin/bash "$INSTALLER" --list) || fail '--list failed'
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 6 ] || fail '--list did not report six tools'
  assert_contains "$out" "gh-axi$(printf '\t')https://github.com/pixeloven/gh-axi$(printf '\t')84112b7897fc1d0833f2727a817ecc91a297c3ef$(printf '\t')0.1.34$(printf '\t')npm" 'gh-axi source is not exact'
  assert_contains "$out" "chrome-devtools-axi$(printf '\t')https://github.com/pixeloven/chrome-devtools-axi$(printf '\t')351be6bb8665fda10168242d965a966596d66772$(printf '\t')0.1.33$(printf '\t')npm" 'chrome-devtools-axi source is not exact'
  assert_contains "$out" "lavish-axi$(printf '\t')https://github.com/pixeloven/lavish-axi$(printf '\t')ffd7aacff563b8bca09eb7ebfb17c14faeb968ce$(printf '\t')0.1.63$(printf '\t')npm" 'lavish-axi source is not exact'
  assert_contains "$out" "tasks-axi$(printf '\t')https://github.com/pixeloven/tasks-axi$(printf '\t')d9175b6d083d693c5b6ca21652454d52e4b312d9$(printf '\t')0.2.5$(printf '\t')npm" 'tasks-axi source is not exact'
  assert_contains "$out" "quota-axi$(printf '\t')https://github.com/pixeloven/quota-axi$(printf '\t')bbc3deb4fca6a172db0217fd26d990fad8b4202e$(printf '\t')0.1.34$(printf '\t')npm" 'quota-axi source is not exact'
  assert_contains "$out" "no-mistakes$(printf '\t')https://github.com/pixeloven/no-mistakes$(printf '\t')70185bf682521ed1822e51dc09fa327b85b87e79$(printf '\t')1.60.1$(printf '\t')go" 'no-mistakes source is not exact'
  assert_not_contains "$out" 'kunchenguid/' 'the selected distribution inventory still points at upstream'
  pass 'the public source inventory selects six exact PixelOven fork commits'
}

test_old_node_is_refused_before_source_fetch() {
  local output status=0
  rm -f "$CALLS/git.log"
  output=$(FM_INSTALL_TEST_CALLS="$CALLS" FM_INSTALL_TEST_NODE_VERSION=v20.19.0 \
    PATH="$FAKEBIN:$ORIGINAL_PATH" /bin/bash "$INSTALLER" tasks-axi \
    "$TMP_ROOT/prefix-old-node" 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'Node 20 unexpectedly started an AXI source install'
  assert_contains "$output" 'Node 22.19 or newer is required to install tasks-axi; found v20.19.0' \
    'the Node floor refusal was not actionable'
  [ ! -e "$CALLS/git.log" ] || fail 'the installer fetched source before refusing old Node'
  pass 'AXI source installs refuse Node below the supported floor before fetching'
}

test_every_npm_tool_builds_then_installs_locked_runtime_from_its_fork() {
  local tool prefix output runtime_version installed_bin corepack_calls
  for tool in gh-axi chrome-devtools-axi lavish-axi tasks-axi quota-axi; do
    prefix="$TMP_ROOT/prefix-$tool"
    output=$(FM_INSTALL_TEST_CALLS="$CALLS" PATH="$FAKEBIN:$ORIGINAL_PATH" \
      /bin/bash "$INSTALLER" "$tool" "$prefix" 2>&1) || fail "$tool install failed: $output"
    [ -x "$prefix/bin/$tool" ] || fail "$tool executable was not installed"
    runtime_version=$(node -e 'const p=require(process.argv[1]); process.stdout.write(p.version)' \
      "$prefix/lib/node_modules/$tool/node_modules/axi-sdk-js/package.json") \
      || fail "$tool runtime dependency tree was not materialized"
    [ "$runtime_version" = 0.1.10 ] \
      || fail "$tool installed an unlocked axi-sdk-js version: $runtime_version"
    installed_bin=$(node -e 'const p=require(process.argv[1]); process.stdout.write(p.bin[p.name].replace(/^\.\//, ""))' \
      "$prefix/lib/node_modules/$tool/package.json") \
      || fail "$tool deployed manifest could not be read"
    [ "$(readlink "$prefix/bin/$tool")" = "../lib/node_modules/$tool/$installed_bin" ] \
      || fail "$tool executable did not follow its deployed manifest"
    assert_contains "$output" "installed $tool" "$tool success did not name the tool"
  done
  assert_contains "$(cat "$CALLS/git.log")" 'remote add origin https://github.com/pixeloven/gh-axi' 'gh-axi was not fetched from its PixelOven fork'
  corepack_calls=$(cat "$CALLS/corepack.log")
  assert_contains "$corepack_calls" 'pnpm install --frozen-lockfile --ignore-scripts' 'the source dependency tree was not frozen'
  assert_contains "$corepack_calls" '--prod --offline --frozen-lockfile' 'the installed production tree could re-resolve dependencies'
  assert_contains "$corepack_calls" 'deploy --legacy' 'the locked production tree was not deployed'
  [ ! -e "$CALLS/npm.log" ] || fail 'npm performed a second dependency resolution'
  pass 'every npm companion tool installs its lockfile-selected runtime tree'
}

test_unsafe_manifest_bin_is_refused_before_replacing_install() {
  local prefix output status=0 existing
  prefix="$TMP_ROOT/prefix-unsafe-bin"
  mkdir -p "$prefix/bin"
  existing="$prefix/bin/gh-axi"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" existing' > "$existing"
  chmod 0755 "$existing"
  output=$(FM_INSTALL_TEST_CALLS="$CALLS" FM_INSTALL_TEST_BIN_OVERRIDE=../escape \
    PATH="$FAKEBIN:$ORIGINAL_PATH" /bin/bash "$INSTALLER" gh-axi "$prefix" 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'an escaping manifest bin path was accepted'
  assert_contains "$output" "does not declare a safe 'gh-axi' executable" \
    'unsafe manifest bin refusal was not actionable'
  [ "$("$existing")" = existing ] || fail 'unsafe manifest replaced the existing installation'
  pass 'unsafe manifest executable paths are refused before replacement'
}

test_failed_npm_replacement_preserves_existing_install() {
  local mode prefix install_dir existing output status
  for mode in copy version; do
    prefix="$TMP_ROOT/prefix-failed-$mode"
    install_dir="$prefix/lib/node_modules/gh-axi"
    mkdir -p "$install_dir/dist/bin" "$prefix/bin"
    existing="$install_dir/dist/bin/gh-axi.js"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" existing' > "$existing"
    chmod 0755 "$existing"
    ln -s ../lib/node_modules/gh-axi/dist/bin/gh-axi.js "$prefix/bin/gh-axi"
    status=0
    case "$mode" in
      copy)
        output=$(FM_INSTALL_TEST_CALLS="$CALLS" FM_INSTALL_TEST_CP_FAIL=1 \
          PATH="$FAKEBIN:$ORIGINAL_PATH" /bin/bash "$INSTALLER" gh-axi "$prefix" 2>&1) || status=$?
        ;;
      version)
        output=$(FM_INSTALL_TEST_CALLS="$CALLS" FM_INSTALL_TEST_DEPLOY_VERSION=9.9.9 \
          PATH="$FAKEBIN:$ORIGINAL_PATH" /bin/bash "$INSTALLER" gh-axi "$prefix" 2>&1) || status=$?
        ;;
    esac
    [ "$status" -ne 0 ] || fail "$mode failure unexpectedly installed a replacement"
    [ "$("$prefix/bin/gh-axi")" = existing ] \
      || fail "$mode failure broke the existing installation"
  done
  pass 'copy and version failures preserve the existing npm installation'
}

test_failed_no_mistakes_replacement_preserves_existing_install() {
  local mode prefix existing output status
  for mode in install version; do
    prefix="$TMP_ROOT/prefix-failed-no-mistakes-$mode"
    mkdir -p "$prefix/bin"
    existing="$prefix/bin/no-mistakes"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" existing' > "$existing"
    chmod 0755 "$existing"
    status=0
    case "$mode" in
      install)
        output=$(FM_INSTALL_TEST_CALLS="$CALLS" FM_INSTALL_TEST_INSTALL_FAIL=1 \
          PATH="$FAKEBIN:$ORIGINAL_PATH" /bin/bash "$INSTALLER" no-mistakes "$prefix" 2>&1) || status=$?
        ;;
      version)
        output=$(FM_INSTALL_TEST_CALLS="$CALLS" FM_INSTALL_TEST_NO_MISTAKES_VERSION=9.9.9 \
          PATH="$FAKEBIN:$ORIGINAL_PATH" /bin/bash "$INSTALLER" no-mistakes "$prefix" 2>&1) || status=$?
        ;;
    esac
    [ "$status" -ne 0 ] || fail "$mode failure unexpectedly installed a no-mistakes replacement"
    [ "$("$existing")" = existing ] \
      || fail "$mode failure broke the existing no-mistakes installation"
  done
  pass 'install and version failures preserve the existing no-mistakes installation'
}

test_no_mistakes_build_never_drives_the_daemon() {
  local prefix output calls
  prefix="$TMP_ROOT/prefix-no-mistakes"
  output=$(FM_INSTALL_TEST_CALLS="$CALLS" PATH="$FAKEBIN:$ORIGINAL_PATH" \
    /bin/bash "$INSTALLER" no-mistakes "$prefix" 2>&1) || fail "no-mistakes install failed: $output"
  [ -x "$prefix/bin/no-mistakes" ] || fail 'no-mistakes executable was not installed'
  assert_contains "$output" 'installed no-mistakes 1.60.1 from pixeloven/no-mistakes@70185bf682521ed1822e51dc09fa327b85b87e79' 'no-mistakes success did not preserve fork provenance'
  calls=$(cat "$CALLS/make.log")
  assert_contains "$calls" 'build VERSION=v1.60.1 COMMIT=70185bf' 'no-mistakes build metadata was not pinned'
  assert_not_contains "$calls" 'daemon' 'the no-mistakes source install drove daemon lifecycle behavior'
  pass 'no-mistakes is source-built without starting, stopping, or restarting its daemon'
}

test_unknown_tool_is_refused() {
  local output status=0
  output=$(/bin/bash "$INSTALLER" arbitrary-tool "$TMP_ROOT/arbitrary" 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'an arbitrary repository was accepted as a companion tool'
  assert_contains "$output" "unsupported tool 'arbitrary-tool'" 'unknown-tool refusal was not actionable'
  pass 'the installer is a closed companion-tool inventory, not a package control plane'
}

test_source_inventory_is_exact_and_downstream
test_old_node_is_refused_before_source_fetch
test_every_npm_tool_builds_then_installs_locked_runtime_from_its_fork
test_unsafe_manifest_bin_is_refused_before_replacing_install
test_failed_npm_replacement_preserves_existing_install
test_failed_no_mistakes_replacement_preserves_existing_install
test_no_mistakes_build_never_drives_the_daemon
test_unknown_tool_is_refused
