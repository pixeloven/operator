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

test_absent_and_blank_settings_leave_the_lane_unchanged
test_helper_round_trips_and_is_invoked_for_github_only
test_unusable_settings_refuse_before_writing
test_spawn_writes_the_helper_without_leaking_the_credential
echo "# all po-delivery-lane-credential tests passed"
