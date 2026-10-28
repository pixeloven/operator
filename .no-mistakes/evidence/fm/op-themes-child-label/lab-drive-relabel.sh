#!/usr/bin/env bash
# relabel.sh <variant-root> <label>: real `po-theme.sh relabel` in a lab session.
set -u
VROOT=$1; NAME=$2
WT=/Users/brian/.no-mistakes/worktrees/1d049b31b4fb/01M616DW0TYNZ1P0H5HDZH6G5X
HELPER=$WT/bin/fm-herdr-lab.sh
REAL_HERDR=$(command -v herdr)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/fm-relabel.XXXXXX")
SES=$("$HELPER" name "rl-$NAME")
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
printf '#!/bin/sh\necho "[]"\n' > "$WORK/fakebin/paseo"   # keep the operator's Paseo daemon untouched
chmod +x "$WORK/fakebin/"*
lab() { "$HELPER" run "$SES" "$@"; }
cleanup() { "$HELPER" teardown "$SES" >/dev/null 2>&1; chmod -R u+w "$WORK"; rm -rf "$WORK"; }
trap cleanup EXIT
"$HELPER" provision "$SES" >/dev/null || { echo "provision failed"; exit 1; }
mkdir -p "$WORK/proj"
PRIM=$WORK/primary; mkdir -p "$PRIM"/{config,data,state}
printf 'operator\n' > "$PRIM/config/po-theme"
mkmate() {  # <id> <with-lib:1|0>
  local m=$WORK/mate-$1; mkdir -p "$m"/{config,data,state}
  printf '%s\n' "$1" > "$m/.fm-secondmate-home"
  if [ "$2" = 1 ]; then ln -s "$VROOT/bin" "$m/bin"; ln -s "$VROOT/.agents" "$m/.agents"; else mkdir "$m/bin"; fi
  "$VROOT/bin/po-theme.sh" persona operator > "$m/data/captain-shared.md"
  printf '%s' "$m"
}
wid() { lab workspace create --cwd "$WORK/proj" --label "$1" --no-focus | jq -r '.result.workspace.workspace_id'; }
W1=$(wid firstmate); W2=$(wid 2ndmate-gfm); W3=$(wid 2ndmate-oldcode)
printf 'herdr_session=%s\nherdr_workspace_id=%s\n' "$SES" "$W1" > "$PRIM/state/primary-self.meta"
printf 'kind=secondmate\nherdr_session=%s\nherdr_workspace_id=%s\nhome=%s\n' "$SES" "$W2" "$(mkmate gfm 1)" > "$PRIM/state/gfm.meta"
printf 'kind=secondmate\nherdr_session=%s\nherdr_workspace_id=%s\nhome=%s\n' "$SES" "$W3" "$(mkmate oldcode 0)" > "$PRIM/state/oldcode.meta"
echo "== $NAME: before relabel"; lab workspace list | jq -r '.result.workspaces[] | "    \(.workspace_id)\t\(.label)"'
echo "== $NAME: po-theme.sh relabel --session <lab>"
PATH="$WORK/fakebin:$PATH" FM_HOME=$PRIM "$VROOT/bin/po-theme.sh" relabel --session "$SES" 2>&1 | sed 's/^/    /'
echo "== $NAME: after relabel"; lab workspace list | jq -r '.result.workspaces[] | "    \(.workspace_id)\t\(.label)"'
