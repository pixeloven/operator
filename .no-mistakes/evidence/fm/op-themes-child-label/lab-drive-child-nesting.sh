#!/usr/bin/env bash
# drive.sh <variant-root> <label>: real-Herdr lab drive of the spawn projection
# parent path for themed homes, before and after the live parent is relabelled.
set -u
VROOT=$1; NAME=$2
WT=/Users/brian/.no-mistakes/worktrees/1d049b31b4fb/01M616DW0TYNZ1P0H5HDZH6G5X
HELPER=$WT/bin/fm-herdr-lab.sh
REAL_HERDR=$(command -v herdr)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/fm-childlabel.XXXXXX")
SES=$("$HELPER" name "child-$NAME")
export HERDR_LAB_SESSION=$SES HELPER REAL_HERDR ORIG_PATH=$PATH
mkdir -p "$WORK/fakebin"
cat > "$WORK/fakebin/herdr" <<'SH'
#!/usr/bin/env bash
args=("$@"); n=${#args[@]}
if [ "$n" -ge 2 ] && [ "${args[$((n-2))]}" = --session ]; then unset "args[$((n-1))]" "args[$((n-2))]"; fi
set -- "${args[@]}"
case "${1:-}" in --version|status) exec env PATH="$ORIG_PATH" "$REAL_HERDR" "$@" --session "$HERDR_LAB_SESSION" ;; esac
exec env PATH="$ORIG_PATH" "$HELPER" run "$HERDR_LAB_SESSION" "$@"
SH
chmod +x "$WORK/fakebin/herdr"
lab() { "$HELPER" run "$SES" "$@"; }
cleanup() { "$HELPER" teardown "$SES" >/dev/null 2>&1; rm -rf "$WORK"; }
trap cleanup EXIT
"$HELPER" provision "$SES" >/dev/null || { echo "provision failed"; exit 1; }
mkdir -p "$WORK/proj"
# Homes: an operator-themed secondmate gfm (inherits block) and an operator primary.
MATE=$WORK/mate-gfm; PRIM=$WORK/primary
mkdir -p "$MATE"/{config,data,state} "$PRIM"/{config,data,state}
printf 'gfm\n' > "$MATE/.fm-secondmate-home"
ln -s "$VROOT/bin" "$MATE/bin"; ln -s "$VROOT/.agents" "$MATE/.agents"
"$VROOT/bin/po-theme.sh" persona operator > "$MATE/data/captain-shared.md"
printf 'operator\n' > "$PRIM/config/po-theme"
FM_HOME=$PRIM "$VROOT/bin/po-theme.sh" refresh >/dev/null 2>&1 || true
FM_HOME=$MATE "$VROOT/bin/po-theme.sh" refresh >/dev/null 2>&1 || true
# Live canonical parents, as they exist before `po-theme.sh relabel` runs.
for l in firstmate 2ndmate-gfm; do lab workspace create --cwd "$WORK/proj" --label "$l" --no-focus >/dev/null; done
spawn_like() {  # <home> <task-id>: the fm-spawn no-launcher-pane projection path
  local home=$1 id=$2
  FM_HOME=$home PATH="$WORK/fakebin:$PATH" HERDR_SESSION=$SES bash -c '
    . "$1/bin/backends/herdr.sh"
    ses=$(fm_backend_herdr_session); want=$(fm_backend_herdr_workspace_label)
    parent=$(fm_backend_herdr_projection_parent_workspace_exact "$ses" "$want" 2>/dev/null || true)
    if [ -z "$parent" ]; then echo "  [$2] home label=$want -> parent absent/ambiguous: FLAT fallback (no projection)"; exit 0; fi
    tok=$(fm_backend_herdr_projection_id); lbl=$(fm_backend_herdr_projection_workspace_label "$2" "$tok")
    fm_backend_herdr_projection_create_task "$3" "$lbl" "$2" >/dev/null || { echo "  [$2] create_task failed"; exit 0; }
    fm_backend_herdr_projection_order_best_effort "$ses" "$FM_BACKEND_HERDR_PROJECTION_WORKSPACE_ID" "$want" "$parent" ""
    echo "  [$2] home label=$want -> parent=$parent, projected workspace $FM_BACKEND_HERDR_PROJECTION_WORKSPACE_ID"
  ' _ "$VROOT" "$id" "$WORK/proj"
}
show() { echo "  herdr workspace list (sidebar order):"; lab workspace list | jq -r '.result.workspaces[] | "    \(.workspace_id)\t\(.label)"' ; }
echo "== $NAME: phase 1 - live parents still canonical (firstmate, 2ndmate-gfm)"
spawn_like "$MATE" gfm-before; spawn_like "$PRIM" prim-before; show
echo "== $NAME: phase 2 - parents relabelled (spotter, navigator-gfm) as po-theme relabel would"
for p in firstmate:spotter 2ndmate-gfm:navigator-gfm; do
  id=$(lab workspace list | jq -r --arg l "${p%%:*}" '.result.workspaces[]|select(.label==$l)|.workspace_id')
  lab workspace rename "$id" "${p#*:}" >/dev/null
done
spawn_like "$MATE" gfm-after; spawn_like "$PRIM" prim-after; show
echo "== $NAME: phase 3 (adversarial) - two live workspaces for gfm (2ndmate-gfm + navigator-gfm)"
lab workspace create --cwd "$WORK/proj" --label 2ndmate-gfm --no-focus >/dev/null
spawn_like "$MATE" gfm-ambig
