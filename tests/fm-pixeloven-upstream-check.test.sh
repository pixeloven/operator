#!/usr/bin/env bash
# Regression tests for canonical upstream pin-lineage verification.
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CHECK="$ROOT/bin/fm-pixeloven-upstream-check.sh"
TMP_ROOT=$(fm_test_tmproot fm-pixeloven-upstream-check)
REAL_GIT=$(command -v git)
FAKEBIN="$TMP_ROOT/bin"
FIXTURE_ROOT="$TMP_ROOT/check-root"
FIXTURE_CHECK="$FIXTURE_ROOT/bin/fm-pixeloven-upstream-check.sh"
CANONICAL="$TMP_ROOT/canonical.git"
DOWNSTREAM="$TMP_ROOT/downstream"
FETCH_LOG="$TMP_ROOT/fetch.log"
INJECTED="$TMP_ROOT/injected.git"
mkdir -p "$FAKEBIN" "$FIXTURE_ROOT/bin" "$FIXTURE_ROOT/docs/pixeloven"
ln -s "$CHECK" "$FIXTURE_CHECK"

make_commit() {
  local repository=$1 name=$2 content=$3
  printf '%s\n' "$content" > "$repository/$name"
  "$REAL_GIT" -C "$repository" add "$name"
  GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' \
    GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' \
    "$REAL_GIT" -c commit.gpgsign=false -C "$repository" commit -q -m "$content"
}

SOURCE="$TMP_ROOT/source"
"$REAL_GIT" init -q "$SOURCE"
"$REAL_GIT" -C "$SOURCE" symbolic-ref HEAD refs/heads/main
"$REAL_GIT" -C "$SOURCE" config user.name 'Lineage Test'
"$REAL_GIT" -C "$SOURCE" config user.email lineage@example.invalid
make_commit "$SOURCE" base.txt base
VALID_PIN=$("$REAL_GIT" -C "$SOURCE" rev-parse HEAD)
make_commit "$SOURCE" tip.txt tip
"$REAL_GIT" clone -q --bare "$SOURCE" "$CANONICAL"

"$REAL_GIT" clone -q "$CANONICAL" "$DOWNSTREAM"
"$REAL_GIT" -C "$DOWNSTREAM" config user.name 'Lineage Test'
"$REAL_GIT" -C "$DOWNSTREAM" config user.email lineage@example.invalid
make_commit "$DOWNSTREAM" downstream.txt downstream
FOREIGN_PIN=$("$REAL_GIT" -C "$DOWNSTREAM" rev-parse HEAD)
"$REAL_GIT" -C "$DOWNSTREAM" cat-file -e "${FOREIGN_PIN}^{commit}" \
  || fail 'foreign fixture commit is not locally present'
if "$REAL_GIT" -C "$CANONICAL" cat-file -e "${FOREIGN_PIN}^{commit}" 2>/dev/null; then
  fail 'foreign fixture commit leaked into canonical history'
fi
CANONICAL_TIP=$("$REAL_GIT" -C "$CANONICAL" rev-parse refs/heads/main)
"$REAL_GIT" clone -q --bare "$CANONICAL" "$INJECTED"
"$REAL_GIT" -C "$INJECTED" fetch -q "$DOWNSTREAM" refs/heads/main:refs/heads/foreign
"$REAL_GIT" --git-dir="$INJECTED" replace --graft "$CANONICAL_TIP" "$FOREIGN_PIN"
"$REAL_GIT" --git-dir="$INJECTED" merge-base --is-ancestor "$FOREIGN_PIN" "$CANONICAL_TIP" \
  || fail 'injected replacement fixture does not forge canonical ancestry'

cat > "$FAKEBIN/git" <<'SH'
#!/usr/bin/env bash
set -eu
args=("$@")
is_fetch=0
for arg in "${args[@]}"; do
  [ "$arg" = fetch ] && is_fetch=1
done
if [ "$is_fetch" -eq 1 ]; then
  printf 'git' >> "$FM_UPSTREAM_FETCH_LOG"
  printf ' %q' "${args[@]}" >> "$FM_UPSTREAM_FETCH_LOG"
  printf ' config_global=%q config_nosystem=%q config_count=%q\n' \
    "${GIT_CONFIG_GLOBAL:-}" "${GIT_CONFIG_NOSYSTEM:-}" "${GIT_CONFIG_COUNT:-}" \
    >> "$FM_UPSTREAM_FETCH_LOG"
  rewritten=()
  for arg in "${args[@]}"; do
    case "$arg" in
      https://github.com/*)
        if [ "${FM_UPSTREAM_FETCH_FAIL:-0}" = 1 ]; then
          rewritten+=("$FM_UPSTREAM_MIRROR_ROOT/missing.git")
        else
          rewritten+=("$FM_UPSTREAM_MIRROR_ROOT/canonical.git")
        fi
        ;;
      --filter=tree:0)
        # Local file transport cannot negotiate filters; the call log above
        # still proves the production request stays commit-history-only.
        ;;
      *) rewritten+=("$arg") ;;
    esac
  done
  GIT_ALLOW_PROTOCOL=file exec "$FM_REAL_GIT" "${rewritten[@]}"
fi
exec "$FM_REAL_GIT" "${args[@]}"
SH
chmod 0755 "$FAKEBIN/git"

write_pin() {
  printf '%s\n' "${1:-$VALID_PIN}" > "$FIXTURE_ROOT/docs/pixeloven/upstream-pin"
}

run_check() {
  FM_REAL_GIT="$REAL_GIT" \
    FM_UPSTREAM_FETCH_LOG="$FETCH_LOG" \
    FM_UPSTREAM_MIRROR_ROOT="$TMP_ROOT" \
    PATH="$FAKEBIN:$PATH" \
    "$FIXTURE_CHECK"
}

assert_no_fetch() {
  [ ! -s "$FETCH_LOG" ] || fail "$1"
}

test_valid_ancestor_passes() {
  write_pin
  : > "$FETCH_LOG"
  run_check >/dev/null || fail 'valid canonical ancestors were rejected'
  local calls
  calls=$(cat "$FETCH_LOG")
  assert_contains "$calls" 'https://github.com/kunchenguid/firstmate.git' 'operator canonical URL was not fetched'
  assert_contains "$calls" '--no-tags' 'canonical fetch did not exclude tags'
  assert_contains "$calls" '--no-recurse-submodules' 'canonical fetch did not exclude submodules'
  assert_contains "$calls" '--filter=tree:0' 'canonical fetch transferred more than commit history'
  assert_contains "$calls" '+refs/heads/main:refs/remotes/canonical/upstream' 'canonical fetch did not bind one exact branch ref'
  assert_contains "$calls" 'config_global=/dev/null config_nosystem=1 config_count=' 'ambient Git configuration was not isolated'
  pass 'a real canonical ancestor passes'
}

test_local_foreign_commit_fails() {
  write_pin "$FOREIGN_PIN"
  local output status=0
  output=$(run_check 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'locally present foreign commit was accepted'
  assert_contains "$output" 'is unavailable from canonical upstream' 'foreign commit failure was unclear'
  pass 'a locally present but non-upstream commit fails real lineage validation'
}

test_ambient_repository_injection_fails() {
  write_pin "$FOREIGN_PIN"
  local output status=0
  output=$(GIT_DIR="$INJECTED" GIT_REPLACE_REF_BASE=refs/replace run_check 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'ambient repository objects and replacements forged canonical ancestry'
  assert_contains "$output" 'is unavailable from canonical upstream' 'repository injection failure was unclear'
  pass 'ambient repository objects and replacements cannot satisfy canonical ancestry'
}

test_missing_canonical_evidence_fails() {
  write_pin
  local output status=0
  output=$(FM_UPSTREAM_FETCH_FAIL=1 run_check 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'unreachable canonical upstream was accepted'
  assert_contains "$output" 'canonical upstream history unavailable' 'unreachable upstream failure was unclear'
  pass 'missing canonical upstream evidence fails clearly'
}

test_malformed_pin_data_fails_before_fetch() {
  local output status=0
  write_pin not-a-commit
  : > "$FETCH_LOG"
  output=$(run_check 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'non-hexadecimal operator pin was accepted'
  assert_contains "$output" 'operator pin is not a lowercase hexadecimal commit' 'non-hexadecimal pin failure was unclear'
  assert_no_fetch 'non-hexadecimal operator pin triggered a canonical fetch'

  status=0
  write_pin "${VALID_PIN:0:20}"
  : > "$FETCH_LOG"
  output=$(run_check 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'abbreviated operator pin was accepted'
  assert_contains "$output" 'operator pin must be a full 40-character commit' 'abbreviated pin failure was unclear'
  assert_no_fetch 'abbreviated operator pin triggered a canonical fetch'

  status=0
  printf '%s %s\n' "${VALID_PIN:0:20}" "${VALID_PIN:20}" > "$FIXTURE_ROOT/docs/pixeloven/upstream-pin"
  : > "$FETCH_LOG"
  output=$(run_check 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'whitespace-spliced operator pin was accepted'
  assert_contains "$output" 'operator pin is not a lowercase hexadecimal commit' 'whitespace-spliced pin failure was unclear'
  assert_no_fetch 'whitespace-spliced operator pin triggered a canonical fetch'

  status=0
  printf '%s\n%s\n' "$VALID_PIN" "$VALID_PIN" > "$FIXTURE_ROOT/docs/pixeloven/upstream-pin"
  : > "$FETCH_LOG"
  output=$(run_check 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'multi-line operator pin was accepted'
  assert_contains "$output" 'operator pin must contain exactly one commit line' 'multi-line pin failure was unclear'
  assert_no_fetch 'multi-line operator pin triggered a canonical fetch'
  pass 'malformed pin data is rejected before network access'
}

test_fixture_overrides_are_not_public_options() {
  local output status=0
  output=$("$CHECK" --operator-pin "$FIXTURE_ROOT/docs/pixeloven/upstream-pin" 2>&1) || status=$?
  [ "$status" -eq 2 ] || fail 'removed fixture override options were still accepted'
  assert_contains "$output" 'Usage:' 'removed fixture override options did not return usage'
  pass 'fixture inputs are unavailable through the production command interface'
}

test_valid_ancestor_passes
test_local_foreign_commit_fails
test_ambient_repository_injection_fails
test_missing_canonical_evidence_fails
test_malformed_pin_data_fails_before_fetch
test_fixture_overrides_are_not_public_options
