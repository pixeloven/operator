#!/usr/bin/env bash
# tests/po-herdr-regroup.test.sh - behavior tests for bin/po-herdr-regroup-lib.sh
# (ADR-0040), the Herdr presentation regroup that brings a relaunched
# secondmate's own recorded crew workspaces back directly under it.
#
# Coverage, against a stateful fake Herdr CLI and a fake workspace mover that
# accepts only the two verified workspace.move forms:
#   - only the home's own non-secondmate records in the parent's session are
#     candidates, and only live new-format projected children move
#   - children land directly under a non-last parent, never past unrelated
#     spaces, and keep their existing relative order
#   - a failed move warns once, stops, and still returns success
#   - a home that records no crew workspace never contacts Herdr, and children
#     already in place never move
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v jq >/dev/null 2>&1 || { echo "skip: jq not found (required by the herdr adapter)"; exit 0; }

TMP_ROOT=$(fm_test_tmproot po-herdr-regroup-tests)

# run_regroup_case <dir> <workspaces-json-array>: run the secondmate crew
# regroup against a STATEFUL fake. $dir/workspaces holds the live order; the
# stub CLI serves it and logs every call, and the fake mover applies only the
# two verified workspace.move forms (insert_index equal to the full list
# length moves to last; the last workspace moves backward to a smaller index)
# and fails on any other use or when $dir/mover-fails exists. The parent is
# 2ndmate-alpha (w9) and its home's records live in $dir/home/state.
# Prints the function's combined output; the final order is in $dir/workspaces.
run_regroup_case() {
  local dir=$1 spaces=$2 mover="$1/mover"
  mkdir -p "$dir/home/state"
  printf '%s\n' "$spaces" > "$dir/workspaces"
  : > "$dir/cli.log"; : > "$dir/mover.log"
  cat > "$mover" <<'SH'
#!/usr/bin/env bash
D=$FM_FAKE_REGROUP_DIR
printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$D/mover.log"
[ ! -e "$D/mover-fails" ] || exit 4
next=$(jq -c --arg ws "$2" --argjson i "$3" '
  (map(select(.workspace_id != $ws))) as $rest
  | ([.[] | select(.workspace_id == $ws)][0]) as $moved
  | if $i == length then $rest + [$moved]
    elif (.[-1].workspace_id == $ws) and ($i < length - 1) then $rest[:$i] + [$moved] + $rest[$i:]
    else error("unverified workspace.move form")
    end
' "$D/workspaces") || exit 4
printf '%s\n' "$next" > "$D/workspaces"
jq -c '{id: "fm-workspace-move", result: {type: "workspace_list", workspaces: .}}' "$D/workspaces"
SH
  chmod +x "$mover"
  FM_FAKE_REGROUP_DIR="$dir" FM_BACKEND_HERDR_WORKSPACE_MOVER="$mover" \
    bash -c '. "$0/bin/fm-backend.sh"; . "$0/bin/backends/herdr.sh"; . "$0/bin/po-herdr-regroup-lib.sh"
      D=$FM_FAKE_REGROUP_DIR
      fm_backend_herdr_cli() {
        shift
        printf "%s\n" "$*" >> "$D/cli.log"
        case "$*" in
          "workspace list") jq -c "{result: {workspaces: .}}" "$D/workspaces" ;;
          "status --json") printf "%s\n" "{\"client\":{\"version\":\"0.7.4\",\"protocol\":16}}" ;;
          "api schema --json") printf "%s\n" "{\"schemas\":{\"request\":{\"oneOf\":[{\"properties\":{\"method\":{\"const\":\"workspace.move\"}}}],\"\$defs\":{\"WorkspaceMoveParams\":{\"required\":[\"workspace_id\",\"insert_index\"],\"properties\":{\"insert_index\":{\"type\":\"integer\"}}}}}}}" ;;
          "session list --json") printf "%s\n" "{\"sessions\":[{\"name\":\"fmtest\",\"running\":true,\"socket_path\":\"/tmp/fmtest.sock\"}]}" ;;
          *) return 1 ;;
        esac
      }
      fm_backend_herdr_projection_focus_snapshot() { printf "w1\tw1:t1"; }
      fm_backend_herdr_projection_focus_restore() { return 0; }
      po_herdr_regroup_children_best_effort fmtest w9 "$D/home/state"
      echo "rc=$?"' "$ROOT" 2>&1
}

regroup_recorded() {  # <dir>: the candidate list bin/fm-spawn.sh gates its lock on
  bash -c '. "$0/bin/fm-backend.sh"; . "$0/bin/backends/herdr.sh"; . "$0/bin/po-herdr-regroup-lib.sh"
    po_herdr_regroup_recorded_children fmtest w9 "$1"' "$ROOT" "$1/home/state"
}

regroup_order() {  # <dir>
  jq -r '[.[].workspace_id] | join(",")' "$1/workspaces"
}

regroup_meta() {  # <dir> <task> <kind> <session> <workspace-id>
  printf 'kind=%s\nbackend=herdr\nherdr_session=%s\nherdr_workspace_id=%s\n' "$3" "$4" "$5" \
    > "$1/home/state/$2.meta"
}

test_projection_regroup_brings_recorded_children_under_relaunched_secondmate() {
  local dir out
  dir="$TMP_ROOT/projection-regroup-relaunch"; mkdir -p "$dir/home/state"
  # The navigator's own two workers (w2, w6), plus records that must never
  # select a workspace: a worker in another session, a flat worker inside the
  # navigator's own workspace, and a secondmate-kind record.
  regroup_meta "$dir" own-a ship fmtest w2
  regroup_meta "$dir" own-b scout fmtest w6
  regroup_meta "$dir" elsewhere ship othersession w3
  regroup_meta "$dir" flat ship fmtest w9
  regroup_meta "$dir" nested secondmate fmtest w5
  out=$(run_regroup_case "$dir" '[{"workspace_id":"w1","label":"firstmate"},
    {"workspace_id":"w2","label":"└ own-a · p:AbCdEfGhIjKlMnOpQrStU1"},
    {"workspace_id":"w6","label":"└ own-b · p:AbCdEfGhIjKlMnOpQrStU2"},
    {"workspace_id":"w3","label":"└ primary · p:AbCdEfGhIjKlMnOpQrStU3"},
    {"workspace_id":"w4","label":"2ndmate-bravo"},
    {"workspace_id":"w5","label":"└ bravo-child · p:AbCdEfGhIjKlMnOpQrStU4"},
    {"workspace_id":"w9","label":"2ndmate-alpha"}]')
  [ "$(regroup_recorded "$dir" | tr '\n' ' ')" = "w2 w6 " ] \
    || fail "only the home's own non-secondmate records in the session may be candidates: $(regroup_recorded "$dir")"
  assert_contains "$out" "rc=0" "regroup must succeed"
  assert_not_contains "$out" "warning" "a clean regroup must not warn"
  [ "$(regroup_order "$dir")" = "w1,w3,w4,w5,w9,w2,w6" ] \
    || fail "the relaunched secondmate must be followed by exactly its own recorded children in order: $(regroup_order "$dir")"
  [ "$(cut -f2,3 "$dir/mover.log" | tr '\n' ' ')" = $'w2\t7 w6\t7 ' ] \
    || fail "only the secondmate's own recorded children may move: $(cat "$dir/mover.log")"
  assert_not_contains "$(cat "$dir/cli.log")" "close" "regroup closed a workspace or pane"
  assert_not_contains "$(cat "$dir/cli.log")" "rename" "regroup renamed a workspace"
  pass "herdr presentation regroup: a relaunched secondmate is followed by its own recorded children only"
}

test_projection_regroup_places_children_directly_under_non_last_parent() {
  local dir out
  dir="$TMP_ROOT/projection-regroup-not-last"; mkdir -p "$dir/home/state"
  regroup_meta "$dir" own-a ship fmtest w2
  out=$(run_regroup_case "$dir" '[{"workspace_id":"w1","label":"firstmate"},
    {"workspace_id":"w2","label":"└ own-a · p:AbCdEfGhIjKlMnOpQrStU1"},
    {"workspace_id":"w9","label":"2ndmate-alpha"},
    {"workspace_id":"w4","label":"2ndmate-bravo"},
    {"workspace_id":"w5","label":"└ bravo-child · p:AbCdEfGhIjKlMnOpQrStU4"}]')
  assert_contains "$out" "rc=0" "regroup must succeed"
  assert_not_contains "$out" "warning" "a clean regroup must not warn"
  [ "$(regroup_order "$dir")" = "w1,w9,w2,w4,w5" ] \
    || fail "the child must land directly under its parent ahead of the next parent's block: $(regroup_order "$dir")"
  pass "herdr presentation regroup: children land directly under a non-last parent"
}

test_projection_regroup_never_strands_child_past_unrelated_spaces() {
  local dir out
  dir="$TMP_ROOT/projection-regroup-no-strand"; mkdir -p "$dir/home/state"
  regroup_meta "$dir" own-a ship fmtest w2
  out=$(run_regroup_case "$dir" '[{"workspace_id":"w1","label":"firstmate"},
    {"workspace_id":"w2","label":"└ own-a · p:AbCdEfGhIjKlMnOpQrStU1"},
    {"workspace_id":"w9","label":"2ndmate-alpha"},
    {"workspace_id":"w8","label":"scratch"},
    {"workspace_id":"w7","label":"└ x · p:AbCdEfGhIjKlMnOpQrStU7"}]')
  assert_contains "$out" "rc=0" "regroup must succeed"
  assert_not_contains "$out" "warning" "a clean regroup must not warn"
  [ "$(regroup_order "$dir")" = "w1,w9,w2,w8,w7" ] \
    || fail "the child must land under its parent, never past a scratch space and orphan: $(regroup_order "$dir")"
  [ "$(cut -f2,3 "$dir/mover.log" | tr '\n' ' ')" = $'w2\t5 w2\t2 ' ] \
    || fail "the child must move to last, then back to its slot: $(cat "$dir/mover.log")"
  pass "herdr presentation regroup: a child is never stranded past unrelated spaces"
}

test_projection_regroup_keeps_children_relative_order() {
  local dir out
  dir="$TMP_ROOT/projection-regroup-relative-order"; mkdir -p "$dir/home/state"
  regroup_meta "$dir" c0 ship fmtest w2
  regroup_meta "$dir" c1 ship fmtest w3
  regroup_meta "$dir" c2 ship fmtest w4
  out=$(run_regroup_case "$dir" '[{"workspace_id":"w2","label":"└ c0 · p:AbCdEfGhIjKlMnOpQrStU1"},
    {"workspace_id":"w9","label":"2ndmate-alpha"},
    {"workspace_id":"w3","label":"└ c1 · p:AbCdEfGhIjKlMnOpQrStU2"},
    {"workspace_id":"w8","label":"scratch"},
    {"workspace_id":"w4","label":"└ c2 · p:AbCdEfGhIjKlMnOpQrStU3"}]')
  assert_contains "$out" "rc=0" "regroup must succeed"
  assert_not_contains "$out" "warning" "a clean regroup must not warn"
  [ "$(regroup_order "$dir")" = "w9,w2,w3,w4,w8" ] \
    || fail "children must follow the parent in their existing relative order: $(regroup_order "$dir")"
  pass "herdr presentation regroup: children keep their existing relative order"
}

test_projection_regroup_move_failure_warns_and_succeeds() {
  local dir out before
  dir="$TMP_ROOT/projection-regroup-move-fails"; mkdir -p "$dir/home/state"
  regroup_meta "$dir" own-a ship fmtest w2
  : > "$dir/mover-fails"
  out=$(run_regroup_case "$dir" '[{"workspace_id":"w1","label":"firstmate"},
    {"workspace_id":"w2","label":"└ own-a · p:AbCdEfGhIjKlMnOpQrStU1"},
    {"workspace_id":"w9","label":"2ndmate-alpha"}]')
  before="w1,w2,w9"
  assert_contains "$out" "rc=0" "a failed move must never fail the relaunch"
  assert_contains "$out" "warning: herdr presentation regrouping could not verify a workspace move" "a failed move must warn"
  [ "$(regroup_order "$dir")" = "$before" ] || fail "a failed move changed the order: $(regroup_order "$dir")"
  [ "$(wc -l < "$dir/mover.log" | tr -d ' ')" = 1 ] || fail "a failed move must not be retried: $(cat "$dir/mover.log")"
  assert_not_contains "$(cat "$dir/cli.log")" "close" "a failed move triggered cleanup"
  pass "herdr presentation regroup: a failed move warns, stops, and leaves the relaunch successful"
}

test_projection_regroup_no_children_or_in_place_never_moves() {
  local dir out
  dir="$TMP_ROOT/projection-regroup-no-children"; mkdir -p "$dir/home/state"
  out=$(run_regroup_case "$dir" '[{"workspace_id":"w1","label":"firstmate"},
    {"workspace_id":"w2","label":"└ primary · p:AbCdEfGhIjKlMnOpQrStU1"},
    {"workspace_id":"w9","label":"2ndmate-alpha"}]')
  assert_contains "$out" "rc=0" "regroup with no children must succeed"
  [ ! -s "$dir/mover.log" ] || fail "no recorded children must mean no move: $(cat "$dir/mover.log")"
  [ ! -s "$dir/cli.log" ] || fail "no recorded children must not even contact Herdr: $(cat "$dir/cli.log")"
  [ -z "$(regroup_recorded "$dir")" ] || fail "a home with no crew records must yield no candidate, so the spawn skips the lock"

  dir="$TMP_ROOT/projection-regroup-in-place"; mkdir -p "$dir/home/state"
  regroup_meta "$dir" own-a ship fmtest w2
  regroup_meta "$dir" gone ship fmtest w7
  out=$(run_regroup_case "$dir" '[{"workspace_id":"w1","label":"firstmate"},
    {"workspace_id":"w9","label":"2ndmate-alpha"},
    {"workspace_id":"w2","label":"└ own-a · p:AbCdEfGhIjKlMnOpQrStU1"}]')
  assert_contains "$out" "rc=0" "an in-place regroup must succeed"
  assert_not_contains "$out" "warning" "an in-place regroup must not warn"
  [ ! -s "$dir/mover.log" ] || fail "children already under their parent must not move: $(cat "$dir/mover.log")"
  [ "$(regroup_order "$dir")" = "w1,w9,w2" ] || fail "an in-place regroup changed the order"
  pass "herdr presentation regroup: no recorded children, or children already in place, never move"
}

test_projection_regroup_brings_recorded_children_under_relaunched_secondmate
test_projection_regroup_places_children_directly_under_non_last_parent
test_projection_regroup_never_strands_child_past_unrelated_spaces
test_projection_regroup_keeps_children_relative_order
test_projection_regroup_move_failure_warns_and_succeeds
test_projection_regroup_no_children_or_in_place_never_moves
echo "# all po-herdr-regroup tests passed"
