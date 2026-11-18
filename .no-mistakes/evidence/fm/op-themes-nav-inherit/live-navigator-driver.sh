#!/usr/bin/env bash
# live: new navigator homes in a real Herdr lab session, fixed (HEAD) vs base checkout
set -u
ROOT=$1 S=$2 BASE=$S/base
LABH="$ROOT/bin/fm-herdr-lab.sh"
unset HERDR_ENV HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SOCKET_PATH HERDR_SESSION
SESS=$("$LABH" name navtheme) || exit 1
case "$SESS" in fm-lab-*) ;; *) echo "bad session $SESS"; exit 1;; esac
trap '"$LABH" teardown "$SESS" >/dev/null 2>&1 && echo "teardown ok: $SESS"' EXIT
"$LABH" provision "$SESS" >/dev/null || { echo provision failed; exit 1; }
echo "lab session: $SESS"
primary() { # <name> [theme] [strip]
  local h=$S/$1; mkdir -p "$h/config" "$h/data" "$h/state"
  printf '# Shared captain preferences\n\nThis file is main-authoritative in the main firstmate home.\nIt is read-only in secondmate homes and must not be edited there.\nRoute new captain-preference discoveries to the main firstmate through marked status or a document pointer.\n' > "$h/data/captain-shared.md"
  if [ -n "${2:-}" ]; then echo "$2" > "$h/config/po-theme"; FM_HOME=$h "$ROOT/bin/po-theme.sh" apply >/dev/null 2>&1 || echo "apply failed in $1" >&2; fi
  if [ -n "${3:-}" ]; then sed -i '' 's/ alias\.lavish-url="[^"]*"//' "$h/data/captain-shared.md"; fi
  echo "$h"
}
mate() { # <name> <id> <primary> <checkout-root>
  local h=$S/$1; mkdir -p "$h/config" "$h/data" "$h/state"
  ln -s "$4/bin" "$h/bin"; ln -s "$4/.agents" "$h/.agents"; echo "$2" > "$h/.fm-secondmate-home"
  FM_CONFIG_INHERIT_REPORT=$S/$1.report bash -c '. "$0/bin/fm-config-inherit-lib.sh"; propagate_secondmate_inheritance "$1" "$2"' "$4" "$3" "$h" >/dev/null 2>&1 || echo "propagate failed $1" >&2
  echo "$h"
}
ensure() { # <checkout-root> <home>
  FM_HOME=$2 FM_ROOT_OVERRIDE=$2 bash -c '. "$0/bin/backends/herdr.sh"; fm_backend_herdr_workspace_ensure "$1" /tmp other-home' "$1" "$SESS" "$2" 2>&1
}
label_of() { "$LABH" run "$SESS" workspace list | jq -r --arg id "$1" '.result.workspaces[] | select(.workspace_id == $id) | .label'; }
run_case() { # <title> <primary> <id> <checkout>
  local m wid
  m=$(mate "$3" "$3" "$2" "$4")
  echo "== $1"
  echo "inherited values line: $(grep -o 'name="[a-z]*"' "$m/data/captain-shared.md" | head -1) lavish-url key present: $(grep -q 'alias.lavish-url=' "$m/data/captain-shared.md" && echo yes || echo no)"
  wid=$(ensure "$4" "$m"); echo "workspace_ensure -> $wid"
  echo "real herdr workspace label: $(label_of "$wid")"
  echo "$m" > "$S/last"
}
P_OP=$(primary op-primary operator)
P_STALE=$(primary stale-primary operator strip)
P_NAUT=$(primary naut-primary)
run_case "FIXED: fresh operator primary -> new navigator 'strategy'" "$P_OP" strategy "$ROOT"
run_case "FIXED: older-apply operator block (no alias.lavish-url) -> new navigator 'strat2'" "$P_STALE" strat2 "$ROOT"
M=$(cat "$S/last")
echo "-- verify in that navigator home:"; FM_HOME=$M "$ROOT/bin/po-theme.sh" verify 2>&1; echo "verify exit=$?"
echo "-- headline in that navigator home:"; FM_HOME=$M "$ROOT/bin/po-theme.sh" headline 2>&1
run_case "BASE (pre-fix): older-apply operator block -> new navigator 'strat3'" "$P_STALE" strat3 "$BASE"
run_case "FIXED: unthemed (nautical) primary -> new navigator 'plain'" "$P_NAUT" plain "$ROOT"
echo "-- nautical navigator wrote theme state? $( [ -e "$(cat "$S/last")/state/po-theme" ] && echo yes || echo no)"
echo "-- final lab workspace list:"; "$LABH" run "$SESS" workspace list | jq -r '.result.workspaces[] | "\(.workspace_id)\t\(.label)"'
