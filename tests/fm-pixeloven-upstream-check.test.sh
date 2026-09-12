#!/usr/bin/env bash
# Regression tests for canonical upstream pin-lineage verification.
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CHECK="$ROOT/bin/fm-pixeloven-upstream-check.sh"
TMP_ROOT=$(fm_test_tmproot fm-pixeloven-upstream-check)
REAL_GIT=$(command -v git)
FAKEBIN="$TMP_ROOT/bin"
CANONICAL="$TMP_ROOT/canonical.git"
FORK="$TMP_ROOT/fork"
FETCH_LOG="$TMP_ROOT/fetch.log"
INJECTED="$TMP_ROOT/injected.git"
mkdir -p "$FAKEBIN"

make_commit() {
  local repository=$1 name=$2 content=$3
  printf '%s\n' "$content" > "$repository/$name"
  "$REAL_GIT" -C "$repository" add "$name"
  GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' \
    GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' \
    "$REAL_GIT" -C "$repository" commit -q -m "$content"
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

"$REAL_GIT" clone -q "$CANONICAL" "$FORK"
"$REAL_GIT" -C "$FORK" config user.name 'Lineage Test'
"$REAL_GIT" -C "$FORK" config user.email lineage@example.invalid
make_commit "$FORK" downstream.txt downstream
FORK_SOURCE=$("$REAL_GIT" -C "$FORK" rev-parse HEAD)
FORK_TREE=$("$REAL_GIT" -C "$FORK" rev-parse 'HEAD^{tree}')
UNRELATED_SOURCE=$(printf '%s\n' unrelated | "$REAL_GIT" -C "$FORK" commit-tree "$FORK_TREE")
"$REAL_GIT" -C "$FORK" update-ref refs/heads/unrelated "$UNRELATED_SOURCE"
FOREIGN_PIN=$FORK_SOURCE
"$REAL_GIT" -C "$FORK" cat-file -e "${FOREIGN_PIN}^{commit}" \
  || fail 'foreign fixture commit is not locally present'
if "$REAL_GIT" -C "$CANONICAL" cat-file -e "${FOREIGN_PIN}^{commit}" 2>/dev/null; then
  fail 'foreign fixture commit leaked into canonical history'
fi
CANONICAL_TIP=$("$REAL_GIT" -C "$CANONICAL" rev-parse refs/heads/main)
"$REAL_GIT" clone -q --bare "$CANONICAL" "$INJECTED"
"$REAL_GIT" -C "$INJECTED" fetch -q "$FORK" refs/heads/main:refs/heads/foreign
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
        elif [[ "$arg" = https://github.com/pixeloven/* ]]; then
          rewritten+=("$FM_UPSTREAM_MIRROR_ROOT/fork")
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

write_inventory() {
  local pin=${1:-$VALID_PIN} url=${2:-https://github.com/kunchenguid/upstream-fixture.git} ref=${3:-refs/heads/main}
  local source_commit=${4:-$FORK_SOURCE} source_url
  : > "$TMP_ROOT/inventory"
  for tool in gh-axi chrome-devtools-axi lavish-axi tasks-axi quota-axi no-mistakes; do
    source_url=https://github.com/pixeloven/$tool
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$tool" "$source_url" "$source_commit" "$url" "$ref" "$pin" >> "$TMP_ROOT/inventory"
  done
}

write_pin() {
  printf '%s\n' "${1:-$VALID_PIN}" > "$TMP_ROOT/operator-pin"
}

run_check() {
  FM_REAL_GIT="$REAL_GIT" \
    FM_UPSTREAM_FETCH_LOG="$FETCH_LOG" \
    FM_UPSTREAM_MIRROR_ROOT="$TMP_ROOT" \
    PATH="$FAKEBIN:$PATH" \
    "$CHECK" --inventory "$TMP_ROOT/inventory" --operator-pin "$TMP_ROOT/operator-pin"
}

assert_no_fetch() {
  [ ! -s "$FETCH_LOG" ] || fail "$1"
}

test_valid_ancestor_passes() {
  write_inventory
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
  assert_contains "$calls" "https://github.com/pixeloven/gh-axi $FORK_SOURCE" 'selected fork commit was not fetched exactly'
  assert_contains "$calls" 'config_global=/dev/null config_nosystem=1 config_count=' 'ambient Git configuration was not isolated'
  pass 'a real canonical ancestor and existing legitimate fork history pass'
}

test_unrelated_selected_source_fails() {
  write_inventory "$VALID_PIN" 'https://github.com/kunchenguid/upstream-fixture.git' \
    refs/heads/main "$UNRELATED_SOURCE"
  write_pin
  local output status=0
  output=$(run_check 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'selected fork commit unrelated to its upstream pin was accepted'
  assert_contains "$output" 'does not descend from upstream pin' 'unrelated fork source failure was unclear'
  pass 'an unrelated selected fork source fails real ancestry validation'
}

test_local_foreign_commit_fails() {
  write_inventory "$FOREIGN_PIN"
  write_pin
  local output status=0
  output=$(run_check 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'locally present foreign commit was accepted'
  assert_contains "$output" 'is unavailable from canonical upstream' 'foreign commit failure was unclear'
  pass 'a locally present but non-upstream commit fails real lineage validation'
}

test_ambient_repository_injection_fails() {
  write_inventory "$FOREIGN_PIN"
  write_pin
  local output status=0
  output=$(GIT_DIR="$INJECTED" GIT_REPLACE_REF_BASE=refs/replace run_check 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'ambient repository objects and replacements forged canonical ancestry'
  assert_contains "$output" 'is unavailable from canonical upstream' 'repository injection failure was unclear'
  pass 'ambient repository objects and replacements cannot satisfy canonical ancestry'
}

test_missing_canonical_evidence_fails() {
  write_inventory
  write_pin
  local output status=0
  output=$(FM_UPSTREAM_FETCH_FAIL=1 run_check 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'unreachable canonical upstream was accepted'
  assert_contains "$output" 'canonical upstream history unavailable' 'unreachable upstream failure was unclear'
  pass 'missing canonical upstream evidence fails clearly'
}

test_malformed_registry_and_pin_data_fail_before_fetch() {
  local output status=0
  write_inventory not-a-commit
  write_pin
  : > "$FETCH_LOG"
  output=$(run_check 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'malformed registry pin was accepted'
  assert_contains "$output" 'malformed upstream pin' 'malformed registry pin failure was unclear'
  assert_no_fetch 'malformed pin triggered a canonical fetch'

  status=0
  write_inventory
  {
    printf 'gh-axi\thttps://github.com/pixeloven/gh-axi\t%s\thttps://github.com/kunchenguid/upstream-fixture.git\trefs/heads/main\t%s' \
      "$FORK_SOURCE" "${VALID_PIN:0:20}"
    printf '\0'
    printf '%s\n' "${VALID_PIN:20}"
    for tool in chrome-devtools-axi lavish-axi tasks-axi quota-axi no-mistakes; do
      printf '%s\thttps://github.com/pixeloven/%s\t%s\thttps://github.com/kunchenguid/upstream-fixture.git\trefs/heads/main\t%s\n' \
        "$tool" "$tool" "$FORK_SOURCE" "$VALID_PIN"
    done
  } > "$TMP_ROOT/inventory"
  : > "$FETCH_LOG"
  output=$(run_check 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'NUL-spliced inventory pin was accepted'
  assert_contains "$output" 'non-text bytes are not allowed' 'NUL-spliced inventory failure was unclear'
  assert_no_fetch 'NUL-spliced inventory triggered a canonical fetch'

  status=0
  write_inventory
  printf '%s %s\n' "${VALID_PIN:0:20}" "${VALID_PIN:20}" > "$TMP_ROOT/operator-pin"
  : > "$FETCH_LOG"
  output=$(run_check 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'whitespace-spliced operator pin was accepted'
  assert_contains "$output" 'operator pin is not a lowercase hexadecimal commit' 'whitespace-spliced pin failure was unclear'
  assert_no_fetch 'whitespace-spliced operator pin triggered a canonical fetch'

  status=0
  printf '%s\n%s\n' "$VALID_PIN" "$VALID_PIN" > "$TMP_ROOT/operator-pin"
  : > "$FETCH_LOG"
  output=$(run_check 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'multi-line operator pin was accepted'
  assert_contains "$output" 'operator pin must contain exactly one commit line' 'multi-line pin failure was unclear'
  assert_no_fetch 'multi-line operator pin triggered a canonical fetch'

  status=0
  write_pin
  write_inventory "$VALID_PIN" 'https://secret-token@github.com/kunchenguid/upstream.git'
  : > "$FETCH_LOG"
  output=$(run_check 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'credential-bearing canonical URL was accepted'
  assert_contains "$output" 'credential-free GitHub HTTPS repository URL' 'credential-bearing URL failure was unclear'
  assert_not_contains "$output" 'secret-token' 'credential-bearing URL leaked into failure output'
  assert_no_fetch 'credential-bearing URL triggered a canonical fetch'

  status=0
  write_inventory "$VALID_PIN" 'https://github.com/kunchenguid/upstream.git' 'refs/tags/main'
  : > "$FETCH_LOG"
  output=$(run_check 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'non-branch canonical ref was accepted'
  assert_contains "$output" 'is not a default-branch ref' 'malformed ref failure was unclear'
  assert_no_fetch 'malformed ref triggered a canonical fetch'
  pass 'malformed registry and pin data is rejected before network access'
}

test_valid_ancestor_passes
test_unrelated_selected_source_fails
test_local_foreign_commit_fails
test_ambient_repository_injection_fails
test_missing_canonical_evidence_fails
test_malformed_registry_and_pin_data_fail_before_fetch
