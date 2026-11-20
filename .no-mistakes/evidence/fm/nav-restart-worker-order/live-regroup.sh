#!/usr/bin/env bash
# Live driver: real Herdr lab session, real workspaces, real workspace.move mover,
# real fm_backend_herdr_projection_regroup_children_best_effort.
set -u
ROOT=$1; EV=$2
HELPER="$ROOT/bin/fm-herdr-lab.sh"
REAL_HERDR=$(command -v herdr)
T=$(mktemp -d "${TMPDIR:-/tmp}/fm-regroup-live.XXXXXX")
mkdir -p "$T/bin"
LAB=$("$HELPER" name regroup)
ORIG_PATH=$PATH; export LAB HELPER REAL_HERDR ORIG_PATH
# Route every adapter herdr call through the guarded lab helper.
cat > "$T/bin/herdr" <<'SH'
#!/usr/bin/env bash
args=("$@"); n=${#args[@]}
if [ "$n" -ge 2 ] && [ "${args[n-2]}" = --session ] && [ "${args[n-1]}" = "$LAB" ]; then unset "args[n-1]" "args[n-2]"; fi
set -- "${args[@]}"
[ "${1:-}" != --version ] || exec "$REAL_HERDR" "$@" --session "$LAB"
for a in "$@"; do case "$a" in --session*) echo "unexpected session" >&2; exit 1;; esac; done
echo "$*" >> "${CALL_LOG:-/dev/null}"
exec env PATH="$ORIG_PATH" "$HELPER" run "$LAB" "$@"
SH
chmod +x "$T/bin/herdr"
printf '#!/bin/sh\necho "workspace.move ws=$2 insert_index=$3" >> "$MOVE_LOG"\nexec "%s/bin/backends/herdr-workspace-move.py" "$@"\n' "$ROOT" > "$T/bin/mover"; chmod +x "$T/bin/mover"
export MOVE_LOG="$T/moves.log" FM_BACKEND_HERDR_WORKSPACE_MOVER="$T/bin/mover"
cleanup() { "$HELPER" teardown "$LAB" >/dev/null 2>&1; rm -rf "$T"; }
trap cleanup EXIT
"$HELPER" provision "$LAB" >/dev/null || { echo "provision failed"; exit 1; }
echo "lab session: $LAB"
lab() { "$HELPER" run "$LAB" "$@"; }
mkws() { lab workspace create --cwd "$T" --label "$1" --no-focus | jq -r '.result.workspace.workspace_id'; }
order() { lab workspace list | jq -r '[.result.workspaces[] | "\(.workspace_id)=\(.label)"] | join("  |  ")'; }
ids() { lab workspace list | jq -r '[.result.workspaces[].workspace_id] | join(",")'; }
meta() { printf 'kind=%s\nbackend=herdr\nherdr_session=%s\nherdr_workspace_id=%s\n' "$3" "$LAB" "$4" > "$1/$2.meta"; }
regroup() { # <parent> <state-dir>
  PATH="$T/bin:$PATH" CALL_LOG="$T/calls.log" bash -c '. "$0/bin/fm-backend.sh"; . "$0/bin/backends/herdr.sh"
    fm_backend_herdr_projection_regroup_children_best_effort "$1" "$2" "$3"; echo "rc=$?"' "$ROOT" "$LAB" "$1" "$2" 2>&1
  [ ! -s "$MOVE_LOG" ] && echo "real workspace.move calls: none" || { echo "real workspace.move calls:"; sed 's/^/  /' "$MOVE_LOG"; }; : > "$MOVE_LOG"
}
TOK=AbCdEfGhIjKlMnOpQrStU
echo; echo "=== Scenario A: navigator relaunched into a fresh workspace appended at the end ==="
C1=$(mkws "└ op-themes-cache-format-fix · p:${TOK}1")
C2=$(mkws "└ op-other-task · p:${TOK}2")
BRAVO=$(mkws "2ndmate-bravo")
BC=$(mkws "└ bravo-child · p:${TOK}3")
NAV=$(mkws "2ndmate-pixeloven")   # the relaunched navigator, appended last by Herdr
S="$T/homeA/state"; mkdir -p "$S"
meta "$S" op-themes-cache-format-fix ship "$C1"; meta "$S" op-other-task scout "$C2"
meta "$S" nested secondmate "$BC"; meta "$S" flat ship "$NAV"
echo "before: $(order)"
FOCUS_BEFORE=$(lab workspace list | jq -c '[.result.workspaces[]|select(.focused)|.workspace_id]')
: > "$T/calls.log"
regroup "$NAV" "$S"
echo "after:  $(order)"
echo "focused before=$FOCUS_BEFORE after=$(lab workspace list | jq -c '[.result.workspaces[]|select(.focused)|.workspace_id]')"
echo "lifecycle calls (close/rename/stop): $(grep -cE 'close|rename|stop|delete' "$T/calls.log")"
EXP="$C1,$C2,$BRAVO,$BC,$NAV"; EXP="$BRAVO,$BC,$NAV,$C1,$C2"; [ "$(ids)" = "$EXP" ] && echo "A RESULT: PASS" || echo "A RESULT: FAIL expected $EXP got $(ids)"
echo; echo "=== Scenario A2: rerun with children already in place (idempotent, no move) ==="
regroup "$NAV" "$S"; [ "$(ids)" = "$EXP" ] && echo "A2 RESULT: PASS" || echo "A2 RESULT: FAIL $(ids)"

echo; echo "=== Scenario B: non-last parent, child stranded above it, scratch + foreign orphan below (backward-move form) ==="
ACH=$(mkws "└ alpha-task · p:${TOK}5")
P2=$(mkws "2ndmate-alpha")
SCR=$(mkws "scratch")
ORPH=$(mkws "└ x · p:${TOK}7")
S="$T/homeB/state"; mkdir -p "$S"; meta "$S" alpha-task ship "$ACH"
echo "before: $(order)"
PRE=$(ids | sed "s/,$ACH,$P2,$SCR,$ORPH\$//")
: > "$T/calls.log"
regroup "$P2" "$S"
echo "after:  $(order)"
echo "lifecycle calls (close/rename/stop): $(grep -cE 'close|rename|stop|delete' "$T/calls.log")"
EXP="$PRE,$P2,$ACH,$SCR,$ORPH"; [ "$(ids)" = "$EXP" ] && echo "B RESULT: PASS" || echo "B RESULT: FAIL expected $EXP got $(ids)"

echo; echo "=== Scenario C: mixed layout [c0, P, c1, X, c2] keeps relative order c0,c1,c2 ==="
K0=$(mkws "└ c0 · p:${TOK}a"); P3=$(mkws "2ndmate-charlie"); K1=$(mkws "└ c1 · p:${TOK}b"); X=$(mkws "scratch-2"); K2=$(mkws "└ c2 · p:${TOK}c")
S="$T/homeC/state"; mkdir -p "$S"; meta "$S" c0 ship "$K0"; meta "$S" c1 ship "$K1"; meta "$S" c2 ship "$K2"
PRE=$(ids | sed "s/,$K0,$P3,$K1,$X,$K2\$//")
echo "before: $(order)"
regroup "$P3" "$S"
echo "after:  $(order)"
EXP="$PRE,$P3,$K0,$K1,$K2,$X"; [ "$(ids)" = "$EXP" ] && echo "C RESULT: PASS" || echo "C RESULT: FAIL expected $EXP got $(ids)"

echo; echo "=== Scenario D: move failure (mover exits nonzero) warns, rc=0, order unchanged, no cleanup ==="
D1=$(mkws "└ d-task · p:${TOK}d"); P4=$(mkws "2ndmate-delta")
S="$T/homeD/state"; mkdir -p "$S"; meta "$S" d-task ship "$D1"
BEFORE=$(ids)
printf '#!/bin/sh\nexit 4\n' > "$T/badmover"; chmod +x "$T/badmover"
: > "$T/calls.log"
FM_BACKEND_HERDR_WORKSPACE_MOVER="$T/badmover" regroup "$P4" "$S"
echo "lifecycle calls (close/rename/stop): $(grep -cE 'close|rename|stop|delete' "$T/calls.log")"
[ "$(ids)" = "$BEFORE" ] && echo "D RESULT: PASS (order unchanged, all workspaces still present)" || echo "D RESULT: FAIL $(ids)"
echo; echo "final workspace count: $(lab workspace list | jq '.result.workspaces|length')"
