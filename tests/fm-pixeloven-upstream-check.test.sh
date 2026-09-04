#!/usr/bin/env bash
# Regression tests for canonical upstream pin-lineage verification.
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CHECK="$ROOT/bin/fm-pixeloven-upstream-check.sh"
TMP_ROOT=$(fm_test_tmproot fm-pixeloven-upstream-check)
FAKEBIN="$TMP_ROOT/bin"
mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/git" <<'SH'
#!/usr/bin/env bash
set -eu
if [ "${1:-}" = -C ]; then
  shift 2
fi
case "${1:-}" in
  init) exit 0 ;;
  fetch)
    [ "${FM_UPSTREAM_FETCH_FAIL:-0}" = 1 ] && exit 1
    exit 0
    ;;
  rev-parse)
    printf '%s\n' 0123456789012345678901234567890123456789
    ;;
  merge-base)
    [ -z "${FM_UPSTREAM_BAD_PIN:-}" ]
    ;;
  *) exit 2 ;;
esac
SH
chmod 0755 "$FAKEBIN/git"

write_inventory() {
  local pin=${1:-0123456789012345678901234567890123456789}
  : > "$TMP_ROOT/inventory"
  for tool in gh-axi chrome-devtools-axi lavish-axi tasks-axi quota-axi no-mistakes; do
    printf '%s\thttps://github.com/kunchenguid/%s.git\trefs/heads/main\t%s\n' "$tool" "$tool" "$pin" >> "$TMP_ROOT/inventory"
  done
}

write_pin() {
  printf '%s\n' 0123456789012345678901234567890123456789 > "$TMP_ROOT/operator-pin"
}

run_check() {
  PATH="$FAKEBIN:$PATH" "$CHECK" --inventory "$TMP_ROOT/inventory" --operator-pin "$TMP_ROOT/operator-pin"
}

test_valid_ancestor_passes() {
  write_inventory; write_pin
  FM_UPSTREAM_BAD_PIN='' PATH="$FAKEBIN:$PATH" run_check >/dev/null \
    || fail 'valid canonical ancestors were rejected'
  pass 'valid upstream ancestors pass'
}

test_local_foreign_commit_fails() {
  write_inventory deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
  write_pin
  local output status=0
  output=$(FM_UPSTREAM_BAD_PIN=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef PATH="$FAKEBIN:$PATH" run_check 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'foreign local commit was accepted'
  assert_contains "$output" 'is not an ancestor of canonical upstream' 'foreign commit failure was unclear'
  pass 'a locally present foreign commit fails lineage validation'
}

test_missing_canonical_evidence_fails() {
  write_inventory; write_pin
  local output status=0
  output=$(FM_UPSTREAM_FETCH_FAIL=1 PATH="$FAKEBIN:$PATH" run_check 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'unreachable canonical upstream was accepted'
  assert_contains "$output" 'canonical upstream history unavailable' 'unreachable upstream failure was unclear'
  pass 'missing canonical upstream evidence fails clearly'
}

test_malformed_registry_pin_fails() {
  write_inventory not-a-commit; write_pin
  local output status=0
  output=$(PATH="$FAKEBIN:$PATH" run_check 2>&1) || status=$?
  [ "$status" -ne 0 ] || fail 'malformed registry pin was accepted'
  assert_contains "$output" 'malformed upstream pin' 'malformed registry failure was unclear'
  pass 'malformed registry and pin data remains rejected'
}

test_valid_ancestor_passes
test_local_foreign_commit_fails
test_missing_canonical_evidence_fails
test_malformed_registry_pin_fails
