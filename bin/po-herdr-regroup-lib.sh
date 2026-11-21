#!/usr/bin/env bash
# po-herdr-regroup-lib.sh - sourceable Herdr presentation regroup that brings a
# relaunched secondmate's own crew workspaces back directly under it (ADR-0040).
# Bash 3.2; defines functions only.
#
# bin/fm-spawn.sh sources it after every Herdr secondmate launch, because a
# navigator respawned into a fresh workspace lands at the end of Herdr's list
# while its crew's projected workspaces keep their old positions under another
# parent. It builds on the Herdr adapter's own helpers (fm_backend_herdr_cli,
# fm_backend_herdr_workspace_move_capable, the presentation socket and focus
# helpers, and bin/backends/herdr-workspace-move.py), so a caller sources it
# only after bin/fm-backend.sh has loaded bin/backends/herdr.sh.
#
# Functions:
#   po_herdr_regroup_recorded_children <session> <parent-workspace-id> <home-state-dir>
#       print the candidate child workspace ids, one per line; nothing when
#       the home records none, so a caller can skip the presentation lock
#   po_herdr_regroup_children_best_effort <session> <parent-workspace-id> <home-state-dir>
#       move the live candidates directly after the parent; always returns 0
#
# <home-state-dir> is the parent home's own state directory. The only
# candidates are the exact herdr_workspace_id values its non-secondmate task
# records name for <session>, and only a candidate whose live label is a
# new-format "└ ... · p:<token>" projection is ever moved: nothing is
# discovered by label, and no other home's workspace is touched.
# When the live recorded children already form the run directly after the
# parent nothing is probed or moved. Otherwise every live recorded child not
# yet in its slot, in list order, takes only the two verified workspace.move
# forms: to the list end (insert_index equal to the full list length), then,
# unless its slot is the end, backward from last to its slot directly after
# the parent and the children already placed. Each move is verified against
# the exact expected order.
#
# Presentation-only: every unavailable, ambiguous, failed, or unverifiable step
# prints a warning and stops, leaving every agent running in Herdr's current
# order. It never closes, renames, restarts, or re-parents any agent or
# workspace.

po_herdr_regroup_recorded_children() {  # <session> <parent-workspace-id> <home-state-dir>
  local session=$1 parent_ws=$2 state_dir=$3 meta ws
  [ -n "$parent_ws" ] && [ -d "$state_dir" ] || return 0
  for meta in "$state_dir"/*.meta; do
    [ -f "$meta" ] && [ ! -L "$meta" ] || continue
    [ "$(fm_meta_get "$meta" kind)" != secondmate ] || continue
    [ "$(fm_meta_get "$meta" backend)" = herdr ] || continue
    [ "$(fm_meta_get "$meta" herdr_session)" = "$session" ] || continue
    ws=$(fm_meta_get "$meta" herdr_workspace_id)
    [ -n "$ws" ] && [ "$ws" != "$parent_ws" ] || continue
    printf '%s\n' "$ws"
  done
  return 0
}

po_herdr_regroup_children_best_effort() {  # <session> <parent-workspace-id> <home-state-dir>
  local session=$1 parent_ws=$2 state_dir=$3 children list pending child
  local move_capable socket mover focus_before response move_status plan at expected placed
  children=$(po_herdr_regroup_recorded_children "$session" "$parent_ws" "$state_dir")
  [ -n "$children" ] || return 0
  list=$(fm_backend_herdr_cli "$session" workspace list 2>/dev/null) || {
    echo "warning: herdr presentation regrouping could not list workspaces; leaving workers in Herdr's current order" >&2
    return 0
  }
  pending=$(printf '%s' "$list" | jq -r --arg parent "$parent_ws" \
    --argjson children "$(printf '%s' "$children" | jq -Rsc 'split("\n") | map(select(length > 0))')" '
    def is_new_child:
      (.label | type) == "string"
      and (.label | test("^└ .+ · p:[A-Za-z0-9_-]{22}$"));
    (.result.workspaces // null) as $s
    | select(($s | type) == "array")
    | ([range(0; $s | length) | select($s[.].workspace_id == $parent)]) as $p
    | select(($p | length) == 1)
    | $p[0] as $pidx
    | [range(0; $s | length)
        | select(. != $pidx)
        | select($s[.].workspace_id as $id | any($children[]; . == $id))
        | select($s[.] | is_new_child)] as $live
    | "ok", (if $live == [range($pidx + 1; $pidx + 1 + ($live | length))] then empty else ($live[] | $s[.].workspace_id) end)
  ' 2>/dev/null) || pending=
  case "$pending" in
    ok) return 0 ;;
    ok$'\n'*) pending=${pending#ok$'\n'} ;;
    *)
      echo "warning: herdr presentation regrouping found the parent workspace absent or ambiguous; leaving workers in Herdr's current order" >&2
      return 0
      ;;
  esac

  if fm_backend_herdr_workspace_move_capable "$session"; then
    move_capable=0
  else
    move_capable=$?
  fi
  [ "$move_capable" -eq 0 ] || {
    echo "warning: herdr presentation regrouping could not verify workspace.move support; leaving workers in Herdr's current order" >&2
    return 0
  }
  socket=$(fm_backend_herdr_presentation_session_socket_path "$session") || {
    echo "warning: herdr presentation regrouping found an ambiguous named session socket; leaving workers in Herdr's current order" >&2
    return 0
  }
  mover=${FM_BACKEND_HERDR_WORKSPACE_MOVER:-$FM_BACKEND_HERDR_ROOT/bin/backends/herdr-workspace-move.py}
  placed=0
  while IFS= read -r child; do
    [ -n "$child" ] || continue
    list=$(fm_backend_herdr_cli "$session" workspace list 2>/dev/null) || list=
    plan=$(printf '%s' "$list" | jq -c --arg ws "$child" --arg parent "$parent_ws" --argjson k "$placed" '
      [.result.workspaces[].workspace_id] as $ids
      | select(($ids | map(select(. == $ws)) | length) == 1)
      | ($ids | map(select(. != $ws))) as $rest
      | ([range(0; $rest | length) | select($rest[.] == $parent)]) as $p
      | select(($p | length) == 1)
      | ($p[0] + 1 + $k) as $at
      | ($rest[:$at] + [$ws] + $rest[$at:]) as $expected
      | {at: $at, expected: $expected, unchanged: ($expected == $ids),
         steps: ([{index: ($ids | length), expected: ($rest + [$ws])}]
           + (if $at < ($rest | length) then [{index: $at, expected: $expected}] else [] end))}
    ' 2>/dev/null) || plan=
    at=$(printf '%s' "$plan" | jq -r '.at // empty' 2>/dev/null) || at=
    case "$at" in
      ''|*[!0-9]*)
        echo "warning: herdr presentation regrouping could not re-read the workspace order; leaving workers in Herdr's current order" >&2
        return 0
        ;;
    esac
    placed=$((placed + 1))
    [ "$(printf '%s' "$plan" | jq -r '.unchanged')" != true ] || continue
    while IFS=$'\t' read -r at expected; do
      focus_before=$(fm_backend_herdr_projection_focus_snapshot "$session") || {
        echo "warning: herdr presentation regrouping could not capture exact active workspace and tab; leaving workers in Herdr's current order" >&2
        return 0
      }
      if response=$("$mover" "$socket" "$child" "$at" </dev/null 2>/dev/null); then
        move_status=0
      else
        move_status=$?
      fi
      fm_backend_herdr_projection_focus_restore "$session" "$focus_before" "workspace move" || true
      if [ "$move_status" -ne 0 ] \
        || ! printf '%s' "$response" | jq -e --argjson expected "$expected" '
          .result.type == "workspace_list"
          and ([.result.workspaces[].workspace_id] == $expected)
        ' >/dev/null 2>&1; then
        echo "warning: herdr presentation regrouping could not verify a workspace move; leaving workers running in Herdr's current order" >&2
        return 0
      fi
    done <<FMSTEPS
$(printf '%s' "$plan" | jq -r '.steps[] | "\(.index)\t\(.expected | tojson)"')
FMSTEPS
  done <<FMEOF
$pending
FMEOF
  return 0
}

