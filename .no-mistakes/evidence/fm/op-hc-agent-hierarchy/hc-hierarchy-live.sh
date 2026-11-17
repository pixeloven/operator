#!/usr/bin/env bash
# Live scenario driver: real herdr-core lab + real bin/fm-spawn.sh / fm-teardown.sh / po-theme.sh.
set -u
ROOT=$1
. "$ROOT/tests/lib.sh"
. "$ROOT/tests/hc-test-safety.sh"
say() { printf '%s\n' "$*"; }
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-hcscen.XXXXXX")
HC_TEST_SES=$("$ROOT/bin/fm-hc-lab.sh" name hcscen)
cleanup() { trap - EXIT; for w in ${WTS:-}; do (cd "$PROJ" && treehouse return --force "$w" >/dev/null 2>&1); done
  hc_test_safe_teardown "$ROOT" "$HC_TEST_SES"; say "teardown rc=$?"; rm -rf "$TMP_ROOT"; }
trap cleanup EXIT
"$ROOT/bin/fm-hc-lab.sh" provision "$HC_TEST_SES" || exit 1
HC_TEST_SOCK=$("$ROOT/bin/fm-hc-lab.sh" socket "$HC_TEST_SES")
HC_LAB_DIR=$(hc_test_lab_dir)/$HC_TEST_SES
export HC_SESSION=$HC_TEST_SES FM_HC_SOCKET=$HC_TEST_SOCK
export XDG_STATE_HOME="$HC_LAB_DIR/env/xdg-state" XDG_CONFIG_HOME="$HC_LAB_DIR/env/xdg-config" XDG_DATA_HOME="$HC_LAB_DIR/env/xdg-data"
unset HC_TERMINAL_ID HC_TERMINAL_SOCKET HC_SCOPE HC_SOCKET HERDR_APP_HOME
export FM_HERDR_APP_BIN="$TMP_ROOT/no-herdr-app"
FM_HOME_DIR=$TMP_ROOT/home; PROJ=$TMP_ROOT/scratch-project
mkdir -p "$FM_HOME_DIR/state" "$PROJ"
export FM_HOME=$FM_HOME_DIR FM_ROOT_OVERRIDE=$ROOT
STATE=$TMP_ROOT/state DATA=$TMP_ROOT/data CONFIG=$TMP_ROOT/config
mkdir -p "$STATE" "$DATA" "$CONFIG"; echo hc > "$CONFIG/backend"
git -C "$PROJ" init -q; echo '# s' > "$PROJ/README.md"; git -C "$PROJ" add README.md
git -C "$PROJ" -c user.name=T -c user.email=t@example.invalid commit -qm initial
git clone --quiet --bare "$PROJ" "$PROJ.origin.git"; git -C "$PROJ" remote add origin "file://$PROJ.origin.git"
SCRUB="env -u TMUX -u FM_BACKEND -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_SESSION -u HERDR_SOCKET_PATH -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u CMUX_WORKSPACE_ID -u __CFBundleIdentifier -u PASEO_AGENT_ID -u TERM_PROGRAM -u REX_BLOCK -u REX_SESSION"
hc() { "$ROOT/bin/fm-hc-lab.sh" run "$HC_TEST_SES" "$@"; }
spawn() { local id=$1; shift; mkdir -p "$DATA/$id"; printf '# Task\n## Captain'"'"'s intent\nlive hc hierarchy check\n\n## Firstmate spec\nx\n' > "$DATA/$id/brief.md"
  "$@" $SCRUB FM_STATE_OVERRIDE="$STATE" FM_DATA_OVERRIDE="$DATA" FM_CONFIG_OVERRIDE="$CONFIG" FM_PROJECTS_OVERRIDE="$TMP_ROOT/up" FM_SPAWN_NO_GUARD=1 \
    "$ROOT/bin/fm-spawn.sh" "$id" "$PROJ" "sh -c 'pwd; sleep 30'" --mode no-mistakes --yolo off; }
field() { sed -n "s/^$2=//p" "$STATE/$1.meta"; }

say "== S1: crewmate spawned from a supervisor terminal is nested under it and leases its worktree"
SUP=$(hc run --bg --no-parent --label herdr.space=fm-sup --label herdr.tab=supervisor | jq -r '.address')
say "supervisor terminal: $SUP"
spawn hcnest1 env HC_TERMINAL_ID=$SUP HC_TERMINAL_SOCKET=$HC_TEST_SOCK; say "spawn rc=$?"
T1=$(field hcnest1 hc_terminal); WT1=$(field hcnest1 worktree); WTS="$WT1"
say "meta:"; sed 's/^/  /' "$STATE/hcnest1.meta" | grep -E 'backend|hc_|worktree|kind'
say "hc get worker parent: $(hc get "$T1" --json | jq -r '.parent // "none"')"
say "treehouse status for the copy:"; (cd "$PROJ" && treehouse status 2>&1) | sed 's/^/  /'
sleep 1; say "worker screen (pwd inside task):"; hc read "$T1" --lines 5 2>&1 | sed 's/^/  /'
say "== S2: teardown returns the durable lease and leaves the supervisor live"
FM_STATE_OVERRIDE="$STATE" FM_DATA_OVERRIDE="$DATA" FM_CONFIG_OVERRIDE="$CONFIG" "$ROOT/bin/fm-teardown.sh" hcnest1 >/dev/null 2>&1; say "teardown rc=$?"
say "treehouse status after teardown:"; (cd "$PROJ" && treehouse status 2>&1) | sed 's/^/  /'
say "supervisor state after teardown: $(hc get "$SUP" --json | jq -r '.state')"
say "== S3 (adversarial): no supervisor terminal -> --no-parent"
spawn hcnest2 env; say "spawn rc=$?"
T2=$(field hcnest2 hc_terminal); WTS="$WTS $(field hcnest2 worktree)"
say "hc get worker parent: $(hc get "$T2" --json | jq -r '.parent // "none"')"
say "== S4 (adversarial): HC_TERMINAL_ID names a terminal that is not live -> --no-parent, spawn still succeeds"
spawn hcnest3 env HC_TERMINAL_ID=9999 HC_TERMINAL_SOCKET=$HC_TEST_SOCK; say "spawn rc=$?"
T3=$(field hcnest3 hc_terminal); WTS="$WTS $(field hcnest3 worktree)"
say "hc get worker parent: $(hc get "$T3" --json | jq -r '.parent // "none"')"
say "== S5 (adversarial): HC_TERMINAL_SOCKET is a foreign socket -> --no-parent"
spawn hcnest4 env HC_TERMINAL_ID=$SUP HC_TERMINAL_SOCKET=$TMP_ROOT/other.sock; say "spawn rc=$?"
T4=$(field hcnest4 hc_terminal); WTS="$WTS $(field hcnest4 worktree)"
say "hc get worker parent: $(hc get "$T4" --json | jq -r '.parent // "none"')"
say "== S6: po-theme hc-spaces / relabel --hc with the app window closed"
P="FM_STATE_OVERRIDE=$STATE FM_DATA_OVERRIDE=$DATA FM_CONFIG_OVERRIDE=$CONFIG"
env FM_STATE_OVERRIDE="$STATE" FM_DATA_OVERRIDE="$DATA" FM_CONFIG_OVERRIDE="$CONFIG" "$ROOT/bin/po-theme.sh" hc-spaces hcnest3; say "hc-spaces rc=$?"
env FM_STATE_OVERRIDE="$STATE" FM_DATA_OVERRIDE="$DATA" FM_CONFIG_OVERRIDE="$CONFIG" HC_TERMINAL_ID=$SUP "$ROOT/bin/po-theme.sh" relabel --hc --dry-run; say "relabel --hc rc=$?"
env FM_STATE_OVERRIDE="$STATE" FM_DATA_OVERRIDE="$DATA" FM_CONFIG_OVERRIDE="$CONFIG" "$ROOT/bin/po-theme.sh" relabel; say "relabel (no flags) rc=$?"
for id in hcnest2 hcnest3 hcnest4; do FM_STATE_OVERRIDE="$STATE" FM_DATA_OVERRIDE="$DATA" FM_CONFIG_OVERRIDE="$CONFIG" "$ROOT/bin/fm-teardown.sh" $id >/dev/null 2>&1; say "teardown $id rc=$?"; done
WTS=""
