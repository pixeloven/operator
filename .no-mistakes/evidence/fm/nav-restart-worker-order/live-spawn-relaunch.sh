#!/usr/bin/env bash
# Live driver: real fm-spawn.sh --secondmate and --relaunch against a guarded
# Herdr lab session; checks the navigator ends up followed by its own children.
set -u
ROOT=$1
HELPER="$ROOT/bin/fm-herdr-lab.sh"
REAL_HERDR=$(command -v herdr)
unset HERDR_ENV HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SOCKET_PATH HERDR_SESSION
T=$(mktemp -d "$(cd "${TMPDIR:-/tmp}" && pwd -P)/fm-regroup-spawn.XXXXXX")
mkdir -p "$T/bin"
LAB=$("$HELPER" name regroupspawn)
NAVID=rgnav$$
ORIG_PATH=$PATH; export LAB HELPER REAL_HERDR ORIG_PATH CALL_LOG="$T/calls.log"
cat > "$T/bin/herdr" <<'SH'
#!/usr/bin/env bash
args=("$@"); n=${#args[@]}
if [ "$n" -ge 2 ] && [ "${args[n-2]}" = --session ] && [ "${args[n-1]}" = "$LAB" ]; then unset "args[n-1]" "args[n-2]"; fi
set -- "${args[@]}"
printf '%s\n' "$*" >> "$CALL_LOG"
[ "${1:-}" != --version ] || exec env PATH="$ORIG_PATH" "$REAL_HERDR" "$@" --session "$LAB"
for a in "$@"; do case "$a" in --session*) echo "unexpected session" >&2; exit 1;; esac; done
exec env PATH="$ORIG_PATH" "$HELPER" run "$LAB" "$@"
SH
chmod +x "$T/bin/herdr"
: > "$CALL_LOG"
cleanup() { TMUX_GUARD=$(tmux ls 2>/dev/null | grep -c rgnav); [ "$TMUX_GUARD" = 0 ] || echo "WARNING: tmux session appeared"; env PATH="$ORIG_PATH" "$HELPER" teardown "$LAB" >/dev/null 2>&1; chmod -R u+w "$T" 2>/dev/null; rm -rf "$T" /tmp/fm-$NAVID /tmp/fm-$NAVID+*; }
trap cleanup EXIT
"$HELPER" provision "$LAB" >/dev/null || { echo "provision failed"; exit 1; }
echo "lab session: $LAB"
export HERDR_SESSION=$LAB
lab() { env PATH="$ORIG_PATH" "$HELPER" run "$LAB" "$@"; }
mkws() { lab workspace create --cwd "$T" --label "$1" --no-focus | jq -r '.result.workspace.workspace_id'; }
order() { lab workspace list | jq -r '[.result.workspaces[] | "\(.workspace_id)=\(.label)"] | join("  |  ")'; }
labels() { lab workspace list | jq -r '[.result.workspaces[].label] | join(" , ")'; }

HOME_DIR="$T/home"; SH2="$T/home-2ndmate-$NAVID"
mkdir -p "$HOME_DIR/state" "$HOME_DIR/config" "$HOME_DIR/data" "$SH2/state" "$SH2/config" "$SH2/data" "$SH2/bin"
printf '%s\n' "$NAVID" > "$SH2/.fm-secondmate-home"; touch "$SH2/state/.last-watcher-beat"
git -C "$SH2" init -q
printf 'config/herdr-presentation-spaces\nconfig/crew-harness\nconfig/crew-dispatch.json\nconfig/backlog-backend\nconfig/backend\nconfig/startup-memory-budget\n' > "$SH2/.gitignore"
git -C "$SH2" add .gitignore; git -C "$SH2" -c user.name=t -c user.email=t@example.invalid commit -qm init
printf '# fixture\n' > "$SH2/AGENTS.md"; printf 'charter\n' > "$SH2/data/charter.md"

TOP=$(mkws "firstmate")
C1=$(mkws "└ op-themes-cache-format-fix · p:AbCdEfGhIjKlMnOpQrStU1")
C2=$(mkws "└ op-second-task · p:AbCdEfGhIjKlMnOpQrStU2")
OTHER=$(mkws "└ another-homes-task · p:AbCdEfGhIjKlMnOpQrStU9")
for pair in "op-themes-cache-format-fix:$C1" "op-second-task:$C2"; do
  printf 'kind=ship\nbackend=herdr\nherdr_session=%s\nherdr_workspace_id=%s\n' "$LAB" "${pair#*:}" > "$SH2/state/${pair%%:*}.meta"
done

spawn() {
  PATH="$T/bin:$ORIG_PATH" FM_GATE_REFUSE_BYPASS=1 FM_SPAWN_NO_GUARD=1 FM_HOME="$HOME_DIR" FM_ROOT_OVERRIDE="$ROOT" \
    "$ROOT/bin/fm-spawn.sh" "$@"
}
echo; echo "=== Scenario E: fresh secondmate launch via fm-spawn.sh --secondmate --backend herdr ==="
echo "before: $(labels)"
spawn "$NAVID" "$SH2" "sh -c 'while :; do sleep 60; done'" --secondmate --backend herdr > "$T/e.out" 2> "$T/e.err"; echo "fm-spawn exit=$?"
tail -n 3 "$T/e.out"; grep -i "warning\|error" "$T/e.err" | head -5
NAV=$(grep '^herdr_workspace_id=' "$HOME_DIR/state/$NAVID.meta" | cut -d= -f2-)
echo "after:  $(labels)"
IDS=$(lab workspace list | jq -r '[.result.workspaces[].workspace_id]|join(",")')
[ "$IDS" = "$TOP,$OTHER,$NAV,$C1,$C2" ] && echo "E RESULT: PASS" || echo "E RESULT: FAIL got $IDS want $TOP,$OTHER,$NAV,$C1,$C2"

echo; echo "=== Scenario F: navigator workspace gone; secondmate respawn (fm-spawn.sh <id> --secondmate --backend herdr, as the liveness sweep does) into a fresh workspace ==="
lab workspace close "$NAV" >/dev/null && echo "closed old navigator workspace $NAV"
# put a scratch space at the end so the stale children sit above unrelated work
SCR=$(mkws "scratch")
echo "before relaunch: $(labels)"
: > "$CALL_LOG"
spawn "$NAVID" "$SH2" "sh -c 'while :; do sleep 60; done'" --secondmate --backend herdr > "$T/f.out" 2> "$T/f.err"; echo "fm-spawn <id> <home> <cmd> --secondmate --backend herdr (respawn) exit=$?"
tail -n 3 "$T/f.out"; grep -i "warning\|error" "$T/f.err" | head -5
NAV2=$(grep '^herdr_workspace_id=' "$HOME_DIR/state/$NAVID.meta" | cut -d= -f2-)
echo "new navigator workspace: $NAV2"
echo "after relaunch:  $(order)"
IDS=$(lab workspace list | jq -r '[.result.workspaces[].workspace_id]|join(",")')
[ "$NAV2" != "$NAV" ] && [ "$IDS" = "$TOP,$OTHER,$SCR,$NAV2,$C1,$C2" ] && echo "F RESULT: PASS" || echo "F RESULT: FAIL got $IDS want $TOP,$OTHER,$SCR,$NAV2,$C1,$C2"
echo "close/rename calls during respawn (all herdr calls in order, lifecycle ones marked):"
grep -nE '^(workspace|pane|tab) (close|rename|create|move)' "$CALL_LOG" | sed 's/^/  /'
echo "  regroup-phase calls (after last pane/agent start):"; awk '/^workspace list/{n=NR} END{}' "$CALL_LOG"; tail -n 12 "$CALL_LOG" | sed 's/^/    /'
echo "children workspaces still present: $(lab workspace list | jq --arg a "$C1" --arg b "$C2" '[.result.workspaces[]|select(.workspace_id==$a or .workspace_id==$b)]|length') (labels unchanged: $(lab workspace list | jq -r --arg a "$C1" '.result.workspaces[]|select(.workspace_id==$a)|.label'))"
true || echo " $(lab workspace list | jq --arg a "$C1" --arg b "$C2" '[.result.workspaces[]|select(.workspace_id==$a or .workspace_id==$b)]|length')"
