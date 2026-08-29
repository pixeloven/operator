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
      gh-axi) version=0.1.34 ;;
      chrome-devtools-axi) version=0.1.33 ;;
      lavish-axi) version=0.1.63 ;;
      tasks-axi) version=0.2.5 ;;
      quota-axi) version=0.1.34 ;;
      no-mistakes) version=1.60.1 ;;
      *) exit 2 ;;
    esac
    printf '{"name":"%s","version":"%s"}\n' "$tool" "$version" > "$repo_dir/package.json"
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
exit 0
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
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf 'printf '\''%%s\\n'\'' '\''no-mistakes version v%s (test) 2026-08-29T00:00:00Z'\''\n' "$version"
} > "$repo_dir/bin/no-mistakes"
chmod 0755 "$repo_dir/bin/no-mistakes"
SH

chmod 0755 "$FAKEBIN/git" "$FAKEBIN/corepack" "$FAKEBIN/npm" "$FAKEBIN/go" "$FAKEBIN/make"

test_source_inventory_is_exact_and_downstream() {
  local out
  out=$(/bin/bash "$INSTALLER" --list) || fail '--list failed'
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 6 ] || fail '--list did not report six tools'
  assert_contains "$out" "gh-axi$(printf '\t')https://github.com/pixeloven/gh-axi$(printf '\t')84112b7897fc1d0833f2727a817ecc91a297c3ef$(printf '\t')0.1.34$(printf '\t')npm" 'gh-axi source is not exact'
  assert_contains "$out" "chrome-devtools-axi$(printf '\t')https://github.com/pixeloven/chrome-devtools-axi$(printf '\t')351be6bb8665fda10168242d965a966596d66772$(printf '\t')0.1.33$(printf '\t')npm" 'chrome-devtools-axi source is not exact'
  assert_contains "$out" "lavish-axi$(printf '\t')https://github.com/pixeloven/lavish-axi$(printf '\t')ffd7aacff563b8bca09eb7ebfb17c14faeb968ce$(printf '\t')0.1.63$(printf '\t')npm" 'lavish-axi source is not exact'
  assert_contains "$out" "tasks-axi$(printf '\t')https://github.com/pixeloven/tasks-axi$(printf '\t')d9175b6d083d693c5b6ca21652454d52e4b312d9$(printf '\t')0.2.5$(printf '\t')npm" 'tasks-axi source is not exact'
  assert_contains "$out" "quota-axi$(printf '\t')https://github.com/pixeloven/quota-axi$(printf '\t')bbc3deb4fca6a172db0217fd26d990fad8b4202e$(printf '\t')0.1.34$(printf '\t')npm" 'quota-axi source is not exact'
  assert_contains "$out" "no-mistakes$(printf '\t')https://github.com/pixeloven/no-mistakes$(printf '\t')554474f66423ad3f6021fc934077cc3a54e20158$(printf '\t')1.60.1$(printf '\t')go" 'no-mistakes source is not exact'
  assert_not_contains "$out" 'kunchenguid/' 'the selected distribution inventory still points at upstream'
  pass 'the public source inventory selects six exact PixelOven fork commits'
}

test_every_npm_tool_builds_then_installs_from_its_fork() {
  local tool prefix output
  for tool in gh-axi chrome-devtools-axi lavish-axi tasks-axi quota-axi; do
    prefix="$TMP_ROOT/prefix-$tool"
    output=$(FM_INSTALL_TEST_CALLS="$CALLS" PATH="$FAKEBIN:$ORIGINAL_PATH" \
      /bin/bash "$INSTALLER" "$tool" "$prefix" 2>&1) || fail "$tool install failed: $output"
    [ -x "$prefix/bin/$tool" ] || fail "$tool executable was not installed"
    assert_contains "$output" "installed $tool" "$tool success did not name the tool"
  done
  assert_contains "$(cat "$CALLS/git.log")" 'remote add origin https://github.com/pixeloven/gh-axi' 'gh-axi was not fetched from its PixelOven fork'
  assert_contains "$(cat "$CALLS/npm.log")" 'install --global --prefix' 'the built npm archive was not installed into the requested prefix'
  pass 'every npm companion tool is built and installed from its exact fork source'
}

test_no_mistakes_build_never_drives_the_daemon() {
  local prefix output calls
  prefix="$TMP_ROOT/prefix-no-mistakes"
  output=$(FM_INSTALL_TEST_CALLS="$CALLS" PATH="$FAKEBIN:$ORIGINAL_PATH" \
    /bin/bash "$INSTALLER" no-mistakes "$prefix" 2>&1) || fail "no-mistakes install failed: $output"
  [ -x "$prefix/bin/no-mistakes" ] || fail 'no-mistakes executable was not installed'
  assert_contains "$output" 'installed no-mistakes 1.60.1 from pixeloven/no-mistakes@554474f66423ad3f6021fc934077cc3a54e20158' 'no-mistakes success did not preserve fork provenance'
  calls=$(cat "$CALLS/make.log")
  assert_contains "$calls" 'build VERSION=v1.60.1 COMMIT=554474f' 'no-mistakes build metadata was not pinned'
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
test_every_npm_tool_builds_then_installs_from_its_fork
test_no_mistakes_build_never_drives_the_daemon
test_unknown_tool_is_refused
