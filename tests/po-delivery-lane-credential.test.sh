#!/usr/bin/env bash
# tests/po-delivery-lane-credential.test.sh - behavior tests for the optional
# config/delivery-lane-github-credential-helper setting of
# bin/fm-delivery-lane.sh (ADR-0022).
#
# Coverage:
#   - an absent setting, and a blank or whitespace-only one, leave the lane
#     config byte-identical to the no-setting lane
#   - a shell-function helper with nested quotes, escapes, command substitution,
#     and semicolons round-trips byte-for-byte through `git config --get` as the
#     lane's single credential.https://github.com.helper entry, with signing
#     still disabled, the bot identity unchanged, and preflight passing
#   - `git credential fill` under GIT_CONFIG_NOSYSTEM=1 and the lane as
#     GIT_CONFIG_GLOBAL actually invokes the configured dummy helper for
#     https://github.com and not for another host
#   - a multi-line or unreadable setting refuses before any lane file exists
#   - a real spawn writes the helper into the task's lane config, and the
#     credential the helper emits never reaches the lane file, prepare or
#     preflight output, spawn output, status, task records, or the brief
#   - --carry-github-credential-helper (secondmate launches, ADR-0038) carries
#     the effective https://github.com helper list of a fixture system and
#     global configuration, honoring Git's empty-value reset, scoped to
#     https://github.com, with no other system or human setting carried; it is
#     inert without the flag, when nothing resolves, and when the operator
#     setting is present, and an unreadable host configuration refuses
#   - a real secondmate spawn, under a fixture system gitconfig that wires a
#     dummy helper, gives the navigator lane that helper while the pane still
#     runs with GIT_CONFIG_NOSYSTEM=1; a ship spawn under the same
#     configuration carries no helper
#
# Every helper here is a dummy shell function. The emitted password is assembled
# at run time, so its full sentinel string never appears in any configuration
# the tests write and finding it anywhere on disk would mean a leak.
set -u

# shellcheck source=tests/fixtures.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"

LANE="$ROOT/bin/fm-delivery-lane.sh"
TMP_ROOT=$(fm_test_tmproot po-delivery-lane-credential)
FM_TEST_CLEANUP_DIRS+=("$TMP_ROOT")
trap fm_test_cleanup EXIT

SETTING=delivery-lane-github-credential-helper
KEY=credential.https://github.com.helper
SENTINEL=fm-lane-sentinel-credential-value
# The same quoting hazards as a production helper that reads a secret manager:
# a shell function, double quotes, backslash escapes, nested command
# substitution, a home-relative path, and statement separators.
# shellcheck disable=SC2016
HELPER='!f() { test "$1" = get || exit 0; printf "username=x-dummy-user\npassword=%s\n" "$(DUMMY_ENV=$(cat ~/.config/dummy/file 2>/dev/null) printf %s-%s fm-lane-sentinel credential-value)"; }; f'

prepare_in() {  # <config-dir> <lane-path>
  FM_HOME="$TMP_ROOT/unused-home" FM_CONFIG_OVERRIDE="$1" "$LANE" prepare "$2"
}

test_absent_and_blank_settings_leave_the_lane_unchanged() {
  local dir out status baseline
  dir="$TMP_ROOT/absent"
  mkdir -p "$dir/config"
  out=$(prepare_in "$dir/config" "$dir/baseline")
  expect_code 0 $? "prepare with no setting should succeed"
  assert_not_contains "$out" "credential-helper" "an absent setting must not report a helper"
  baseline=$(cat "$dir/baseline")
  [ -z "$(git config --file "$dir/baseline" --get-all "$KEY")" ] || fail "an absent setting must write no credential helper"

  printf '' > "$dir/config/$SETTING"
  prepare_in "$dir/config" "$dir/empty" >/dev/null
  expect_code 0 $? "prepare with an empty setting should succeed"
  printf ' \t\n\n  \n' > "$dir/config/$SETTING"
  out=$(prepare_in "$dir/config" "$dir/blank")
  status=$?
  expect_code 0 "$status" "prepare with a whitespace-only setting should succeed"
  assert_not_contains "$out" "credential-helper" "a blank setting must not report a helper"
  [ "$(cat "$dir/empty")" = "$baseline" ] || fail "an empty setting must leave the lane config byte-identical to the absent case"
  [ "$(cat "$dir/blank")" = "$baseline" ] || fail "a whitespace-only setting must leave the lane config byte-identical to the absent case"
  cmp -s "$dir/baseline" "$dir/blank" || fail "a whitespace-only setting changed the lane file bytes"
  pass "an absent, empty, or whitespace-only credential-helper setting leaves the lane config unchanged"
}

test_helper_round_trips_and_is_invoked_for_github_only() {
  local dir lane out got count fill other
  dir="$TMP_ROOT/round-trip"
  lane="$dir/gitconfig"
  mkdir -p "$dir/config" "$dir/home"
  # Surrounding whitespace and a trailing newline are trimmed; the command is not.
  printf '  %s\n\n' "$HELPER" > "$dir/config/$SETTING"
  out=$(prepare_in "$dir/config" "$lane" && "$LANE" preflight "$lane")
  expect_code 0 $? "prepare and preflight with a helper setting should succeed"
  assert_contains "$out" "credential-helper=github" "prepare did not report the configured helper"
  assert_contains "$out" "preflight=ok" "preflight must still pass with a credential helper"
  assert_not_contains "$out" "$HELPER" "prepare or preflight echoed the helper command"

  got=$(git config --file "$lane" --get "$KEY")
  [ "$got" = "$HELPER" ] || fail "the helper did not round-trip byte-for-byte: got [$got]"
  count=$(git config --file "$lane" --get-regexp '^credential\.' | wc -l | tr -d ' ')
  [ "$count" = 1 ] || fail "the lane must carry exactly one credential entry, found $count"
  [ "$(git config --file "$lane" --get commit.gpgsign)" = false ] || fail "commit signing must stay disabled"
  [ "$(git config --file "$lane" --get tag.gpgsign)" = false ] || fail "tag signing must stay disabled"
  [ "$(git config --file "$lane" --get user.name)" = "Firstmate Autonomous Worker" ] || fail "the bot name changed"
  [ "$(git config --file "$lane" --get user.email)" = "firstmate-autonomous@localhost" ] || fail "the bot email changed"
  [ "$(stat -c %a "$lane" 2>/dev/null || stat -f %Lp "$lane")" = 600 ] || fail "the lane config must stay owner-only"

  fill=$(printf 'protocol=https\nhost=github.com\npath=example/private.git\n\n' |
    HOME="$dir/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$lane" GIT_TERMINAL_PROMPT=0 \
      git -C "$dir" credential fill 2>&1)
  expect_code 0 $? "git credential fill should be answered by the lane helper: $fill"
  assert_contains "$fill" "username=x-dummy-user" "the lane helper was not invoked for github.com"
  assert_contains "$fill" "password=$SENTINEL" "the lane helper's credential was not returned"

  other=$(printf 'protocol=https\nhost=example.invalid\n\n' |
    HOME="$dir/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$lane" GIT_TERMINAL_PROMPT=0 \
      GIT_ASKPASS=/bin/false SSH_ASKPASS=/bin/false git -C "$dir" credential fill 2>&1)
  assert_not_contains "$other" "$SENTINEL" "the github.com helper answered for another host"

  ! grep -rqF "$SENTINEL" "$dir" || fail "the helper's credential was written to disk"
  pass "the credential helper round-trips through git config and answers only for https://github.com"
}

test_unusable_settings_refuse_before_writing() {
  local dir out
  dir="$TMP_ROOT/refuse"
  mkdir -p "$dir/config"
  printf '!first-line\n!second-line\n' > "$dir/config/$SETTING"
  out=$(prepare_in "$dir/config" "$dir/multi" 2>&1)
  expect_code 1 $? "a multi-line helper setting must refuse"
  assert_contains "$out" "reason=credential-helper-multiline" "a multi-line setting did not name its reason"
  assert_not_contains "$out" "first-line" "the refusal echoed the helper command"
  [ ! -e "$dir/multi" ] || fail "a refused setting must not leave a lane config"

  rm -f "$dir/config/$SETTING"
  mkdir "$dir/config/$SETTING"
  out=$(prepare_in "$dir/config" "$dir/dir" 2>&1)
  expect_code 1 $? "an unreadable helper setting must refuse"
  assert_contains "$out" "reason=credential-helper-unreadable" "an unreadable setting did not name its reason"
  [ ! -e "$dir/dir" ] || fail "an unreadable setting must not leave a lane config"
  [ -z "$(find "$dir" -maxdepth 1 -name '*.tmp.*' -print)" ] || fail "a refusal left a temporary lane file"
  pass "a multi-line or unreadable credential-helper setting refuses before any lane config is written"
}

test_spawn_writes_the_helper_without_leaking_the_credential() {
  local case_dir home proj wt fakebin launchlog panelog id out status lane fill
  id=po-lane-cred-$$
  case_dir="$TMP_ROOT/spawn"
  home="$case_dir/home"
  proj="$case_dir/project"
  wt="$case_dir/wt"
  launchlog="$case_dir/launch.log"
  panelog="$case_dir/pane.log"
  lane="/tmp/fm-$id/gitconfig"
  FM_TEST_CLEANUP_DIRS+=("/tmp/fm-$id")
  fakebin=$(fm_test_make_spawn_fakebin "$case_dir/fake")
  fm_test_spawn_home "$home" codex
  fm_git_worktree "$proj" "$wt" wt-lane-credential
  fm_test_spawn_brief "$home" "$id"
  printf '%s\n' "$HELPER" > "$home/config/$SETTING"
  : > "$launchlog"
  : > "$panelog"
  out=$(FM_FAKE_LAUNCH_LOG="$launchlog" FM_FAKE_PANE_LOG="$panelog" \
    fm_test_run_spawn "$home" "$wt" "$fakebin" "$id" "$proj" --mode no-mistakes --yolo off)
  status=$?
  # The staged launch directory sits beside the task temp root, not inside it.
  local staged
  for staged in "/tmp/fm-$id+"*; do
    [ ! -e "$staged" ] || FM_TEST_CLEANUP_DIRS+=("$staged")
  done
  expect_code 0 "$status" "ship spawn with a credential-helper setting should succeed: $out"
  [ "$(git config --file "$lane" --get "$KEY")" = "$HELPER" ] ||
    fail "the spawned task's lane config does not carry the configured helper"
  assert_contains "$(cat "$panelog")" "GIT_CONFIG_GLOBAL='$lane'" "the worker was not pointed at the lane config"

  fill=$(printf 'protocol=https\nhost=github.com\n\n' |
    HOME="$case_dir" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$lane" GIT_TERMINAL_PROMPT=0 \
      git -C "$wt" credential fill 2>&1)
  assert_contains "$fill" "password=$SENTINEL" "the spawned lane's helper was not invoked"

  assert_not_contains "$out" "$SENTINEL" "spawn output carried the credential"
  assert_not_contains "$out" "$HELPER" "spawn output echoed the helper command"
  ! grep -rqF "$SENTINEL" "/tmp/fm-$id" "$home/state" "$home/data" "$launchlog" "$panelog" ||
    fail "the credential reached the lane file, status, task records, brief, or launch logs"
  ! grep -rqF "$HELPER" "$home/state" "$home/data" "$launchlog" "$panelog" ||
    fail "the helper command was copied into status, task records, the brief, or launch logs"
  pass "a spawn writes the configured helper into the task lane without leaking the credential"
}

# A navigator's helper comes from the launching firstmate's own Git
# configuration, which these fixtures stand in for: a system file that first
# clears any helper the host's own lower-level file wires (the macOS Xcode-level
# osxkeychain, for one), then sets a dummy helper, plus system settings the
# lane must keep out. Nothing here can reach a real keychain or the network.
# shellcheck disable=SC2016
HOST_HELPER='!f() { test "$1" = get || exit 0; printf "username=x-nav-user\npassword=%s\n" "$(printf %s-%s fm-nav-sentinel credential-value)"; }; f'
NAV_SENTINEL=fm-nav-sentinel-credential-value

write_host_config() {  # <dir>
  mkdir -p "$1"
  {
    printf '[credential]\n\thelper =\n\thelper = !stale-cleared-helper\n\thelper =\n'
    printf '[commit]\n\tgpgSign = true\n[user]\n\tsigningKey = fixture-system-key\n\tname = Fixture Human\n'
    printf '[core]\n\tfixtureSystemOnly = system-only-value\n'
    printf '[credential "https://gitlab.example"]\n\thelper = !other-host-helper\n'
  } > "$1/system"
  git config --file "$1/system" --add credential.helper "$HOST_HELPER"
  printf '[gpg]\n\tformat = ssh\n' > "$1/global"
}

# Runs a command under the fixture host configuration, as the launching
# firstmate's ordinary environment would see it.
with_host_config() {  # <dir> <command...>
  local dir=$1
  shift
  GIT_CONFIG_NOSYSTEM=0 GIT_CONFIG_SYSTEM="$dir/system" GIT_CONFIG_GLOBAL="$dir/global" "$@"
}

nav_fill() {  # <lane> <host> <cwd>
  printf 'protocol=https\nhost=%s\n\n' "$2" |
    env -u GIT_CONFIG_SYSTEM HOME="$3" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$1" GIT_TERMINAL_PROMPT=0 \
      GIT_ASKPASS=/bin/false SSH_ASKPASS=/bin/false git -C "$3" credential fill 2>&1
}

test_carry_flag_scopes_the_host_helper_to_github() {
  local dir lane out got fill other plain
  dir="$TMP_ROOT/carry"
  lane="$dir/gitconfig"
  write_host_config "$dir/host"
  mkdir -p "$dir/config" "$dir/home"

  out=$(with_host_config "$dir/host" prepare_in "$dir/config" "$dir/plain")
  expect_code 0 $? "prepare without the flag should succeed under a host helper"
  assert_not_contains "$out" "credential-helper" "a lane without the flag must not report a helper"
  [ -z "$(git config --file "$dir/plain" --get-all "$KEY")" ] || fail "a lane without the flag carried a host helper"
  plain=$(cat "$dir/plain")

  out=$(with_host_config "$dir/host" env FM_HOME="$TMP_ROOT/unused-home" FM_CONFIG_OVERRIDE="$dir/config" \
    "$LANE" prepare "$lane" --carry-github-credential-helper && "$LANE" preflight "$lane")
  expect_code 0 $? "prepare with the carry flag and preflight should succeed: $out"
  assert_contains "$out" "credential-helper=carried" "prepare did not report the carried helper"
  assert_contains "$out" "preflight=ok" "preflight must still pass with a carried helper"
  assert_not_contains "$out" "$HOST_HELPER" "prepare or preflight echoed the carried helper"

  got=$(git config --file "$lane" --get-all "$KEY")
  [ "$got" = "$HOST_HELPER" ] || fail "the lane must carry exactly the effective helper after the reset: got [$got]"
  [ "$(git config --file "$lane" --get-regexp '^credential\.' | wc -l | tr -d ' ')" = 1 ] ||
    fail "the lane carried a cleared, other-host, or extra credential entry"
  [ "$(git config --file "$lane" --get commit.gpgsign)" = false ] || fail "commit signing must stay disabled"
  [ "$(git config --file "$lane" --get user.name)" = "Firstmate Autonomous Worker" ] || fail "the bot name changed"
  for key in user.signingkey core.fixturesystemonly gpg.format; do
    [ -z "$(git config --file "$lane" --get "$key")" ] || fail "the lane carried the host setting $key"
  done
  [ "$(sed '/^\[credential/,$d' "$lane")" = "$plain" ] || fail "carrying the helper changed the rest of the lane"

  fill=$(nav_fill "$lane" github.com "$dir/home")
  expect_code 0 $? "git credential fill should be answered by the carried helper: $fill"
  assert_contains "$fill" "username=x-nav-user" "the carried helper was not invoked for github.com"
  assert_contains "$fill" "password=$NAV_SENTINEL" "the carried helper's credential was not returned"
  other=$(nav_fill "$lane" gitlab.example "$dir/home")
  assert_not_contains "$other" "$NAV_SENTINEL" "the carried helper answered for another host"
  [ -z "$(env -u GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$lane" git -C "$dir/home" config --get core.fixturesystemonly)" ] ||
    fail "the navigator environment can still read the system configuration"
  ! grep -rqF "$NAV_SENTINEL" "$dir" || fail "the carried helper's credential was written to disk"
  pass "the carry flag scopes the effective host helper to https://github.com and carries nothing else"
}

test_carry_flag_is_inert_or_refuses_when_it_should() {
  local dir out
  dir="$TMP_ROOT/carry-edges"
  write_host_config "$dir/host"
  mkdir -p "$dir/config" "$dir/empty-host"
  prepare_in "$dir/config" "$dir/baseline" >/dev/null || fail "the baseline lane should prepare"

  printf '[credential]\n\thelper = !cleared\n\thelper =\n' > "$dir/empty-host/system"
  : > "$dir/empty-host/global"
  out=$(with_host_config "$dir/empty-host" env FM_HOME="$TMP_ROOT/unused-home" FM_CONFIG_OVERRIDE="$dir/config" \
    "$LANE" prepare "$dir/none" --carry-github-credential-helper)
  expect_code 0 $? "the carry flag with no effective host helper should succeed"
  assert_not_contains "$out" "credential-helper" "a lane with nothing to carry must not report a helper"
  cmp -s "$dir/baseline" "$dir/none" || fail "a lane with nothing to carry must be byte-identical to the plain lane"

  printf '%s\n' "$HELPER" > "$dir/config/$SETTING"
  out=$(with_host_config "$dir/host" env FM_HOME="$TMP_ROOT/unused-home" FM_CONFIG_OVERRIDE="$dir/config" \
    "$LANE" prepare "$dir/operator" --carry-github-credential-helper)
  expect_code 0 $? "the carry flag with an operator setting should succeed"
  assert_contains "$out" "credential-helper=github" "the operator setting must still be reported"
  [ "$(git config --file "$dir/operator" --get-all "$KEY")" = "$HELPER" ] ||
    fail "the operator setting must stay the lane's single credential entry"
  rm -f "$dir/config/$SETTING"

  printf '[credential\n' > "$dir/empty-host/system"
  out=$(with_host_config "$dir/empty-host" env FM_HOME="$TMP_ROOT/unused-home" FM_CONFIG_OVERRIDE="$dir/config" \
    "$LANE" prepare "$dir/broken" --carry-github-credential-helper 2>&1)
  expect_code 1 $? "an unreadable host configuration must refuse"
  assert_contains "$out" "reason=credential-helper-resolve" "the refusal did not name its reason"
  [ ! -e "$dir/broken" ] || fail "a refused carry must not leave a lane config"

  out=$("$LANE" preflight "$dir/baseline" --carry-github-credential-helper 2>&1)
  expect_code 2 $? "preflight must reject the carry flag"
  pass "the carry flag is inert with nothing to carry, yields to the operator setting, and refuses an unreadable host configuration"
}

test_secondmate_spawn_carries_the_host_helper_and_ship_does_not() {
  local case_dir home proj wt fakebin launchlog panelog sm out status lane id ship_id fill
  id=po-nav-cred-$$
  ship_id=po-nav-ship-$$
  case_dir="$TMP_ROOT/nav-spawn"
  home="$case_dir/home"
  proj="$case_dir/project"
  wt="$case_dir/wt"
  launchlog="$case_dir/launch.log"
  panelog="$case_dir/pane.log"
  FM_TEST_CLEANUP_DIRS+=("/tmp/fm-$id" "/tmp/fm-$ship_id")
  write_host_config "$case_dir/host"
  fakebin=$(fm_test_make_spawn_fakebin "$case_dir/fake")
  fm_test_spawn_home "$home" codex
  fm_git_worktree "$proj" "$wt" wt-nav-credential
  fm_test_spawn_brief "$home" "$id"
  fm_test_spawn_brief "$home" "$ship_id"
  sm="$case_dir/secondmate-home"
  mkdir -p "$sm/bin" "$sm/data"
  printf '# Firstmate\n' > "$sm/AGENTS.md"
  printf '%s\n' "$id" > "$sm/.fm-secondmate-home"
  printf 'charter for %s\n' "$id" > "$sm/data/charter.md"
  printf '%s\n' 'projects/' 'state/' 'data/' 'config/' '.no-mistakes/' > "$sm/.gitignore"
  git -C "$sm" init -q -b main

  : > "$launchlog"
  : > "$panelog"
  out=$(FM_FAKE_LAUNCH_LOG="$launchlog" FM_FAKE_PANE_LOG="$panelog" \
    with_host_config "$case_dir/host" fm_test_run_spawn "$home" "$wt" "$fakebin" "$id" "$sm" --secondmate)
  status=$?
  local staged
  for staged in "/tmp/fm-$id+"* "/tmp/fm-$ship_id+"*; do
    [ ! -e "$staged" ] || FM_TEST_CLEANUP_DIRS+=("$staged")
  done
  expect_code 0 "$status" "secondmate spawn under a host helper should succeed: $out"
  lane="/tmp/fm-$id/gitconfig"
  [ "$(git config --file "$lane" --get-all "$KEY")" = "$HOST_HELPER" ] ||
    fail "the navigator lane does not carry the host's github.com helper"
  assert_contains "$(cat "$panelog")" "export GIT_CONFIG_NOSYSTEM=1" "the navigator pane lost GIT_CONFIG_NOSYSTEM=1"
  assert_contains "$(cat "$panelog")" "GIT_CONFIG_GLOBAL='$lane'" "the navigator was not pointed at its lane config"
  [ "$(git config --file "$lane" --get commit.gpgsign)" = false ] || fail "the navigator lane must stay unsigned"
  [ -z "$(git config --file "$lane" --get user.signingkey)" ] || fail "the navigator lane carried the host signing key"
  fill=$(nav_fill "$lane" github.com "$case_dir")
  assert_contains "$fill" "password=$NAV_SENTINEL" "the navigator lane's carried helper was not invoked"
  assert_not_contains "$out" "$NAV_SENTINEL" "spawn output carried the credential"
  ! grep -rqF "$NAV_SENTINEL" "/tmp/fm-$id" "$home/state" "$home/data" "$launchlog" "$panelog" ||
    fail "the credential reached the lane file, status, task records, or launch logs"

  : > "$launchlog"
  : > "$panelog"
  out=$(FM_FAKE_LAUNCH_LOG="$launchlog" FM_FAKE_PANE_LOG="$panelog" \
    with_host_config "$case_dir/host" fm_test_run_spawn "$home" "$wt" "$fakebin" "$ship_id" "$proj" --mode no-mistakes --yolo off)
  expect_code 0 $? "ship spawn under a host helper should succeed: $out"
  [ -f "/tmp/fm-$ship_id/gitconfig" ] || fail "the ship spawn wrote no lane config"
  [ -z "$(git config --file "/tmp/fm-$ship_id/gitconfig" --get-regexp '^credential\.')" ] ||
    fail "a ship lane carried the host's credential helper"
  pass "a secondmate spawn carries the host's github.com helper into its isolated lane, and a ship spawn does not"
}

test_absent_and_blank_settings_leave_the_lane_unchanged
test_helper_round_trips_and_is_invoked_for_github_only
test_unusable_settings_refuse_before_writing
test_spawn_writes_the_helper_without_leaking_the_credential
test_carry_flag_scopes_the_host_helper_to_github
test_carry_flag_is_inert_or_refuses_when_it_should
test_secondmate_spawn_carries_the_host_helper_and_ship_does_not
echo "# all po-delivery-lane-credential tests passed"
