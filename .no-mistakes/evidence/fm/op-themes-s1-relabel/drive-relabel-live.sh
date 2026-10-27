#!/usr/bin/env bash
# Live drive: po-theme relabel against a real isolated Herdr lab session.
set -u
ROOT=$1; PT="$ROOT/bin/po-theme.sh"; LABH="$ROOT/bin/fm-herdr-lab.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/fm-relabel-ev.XXXXXX")
S=$("$LABH" name po-relabel-ev); echo "# lab session: $S"
trap '"$LABH" teardown "$S" >/dev/null 2>&1; rm -rf "$T"; echo "# teardown done"' EXIT
"$LABH" provision "$S" >/dev/null || { echo provision failed; exit 1; }
mk() { "$LABH" run "$S" workspace create --cwd "$T" --label "$1" --no-focus | jq -r '.result.workspace.workspace_id'; }
list() { "$LABH" run "$S" workspace list | jq -r '.result.workspaces[] | "  \(.workspace_id)\t\(.label)"'; }
home="$T/primary"; mkdir -p "$home"/{config,data,state}; echo operator > "$home/config/po-theme"
mate() { local h="$T/$1"; mkdir -p "$h"/{config,data,state}; echo "$2" > "$h/.fm-secondmate-home"; [ -z "${3:-}" ] || "$PT" persona "$3" > "$h/data/captain-shared.md"; echo "$h"; }
wP=$(mk firstmate); wG=$(mk 2ndmate-gfm); wX=$(mk 2ndmate-pixeloven); wO=$(mk operator); wS=$(mk 2ndmate-stale); wL=$(mk 2ndmate-legacy); wR=$(mk 2ndmate-remote)
gfm=$(mate mate-gfm gfm operator); px=$(mate mate-px pixeloven operator)
printf 'herdr_session=%s\nherdr_workspace_id=%s\n' "$S" "$wP" > "$home/state/t1.meta"
printf 'kind=secondmate\nherdr_session=%s\nherdr_workspace_id=%s\nhome=%s\n' "$S" "$wG" "$gfm" > "$home/state/gfm.meta"
printf 'kind=secondmate\nherdr_session=%s\nherdr_workspace_id=%s\nhome=%s\n' "$S" "$wX" "$px" > "$home/state/pixeloven.meta"
printf 'kind=secondmate\nherdr_session=%s\nherdr_workspace_id=%s\nhome=%s\n' "$S" "$wS" "$(mate mate-stale stale)" > "$home/state/stale.meta"
printf 'kind=secondmate\nherdr_session=%s\nherdr_workspace_id=%s\n' "$S" "$wL" > "$home/state/legacy.meta"
printf -- '- legacy - Legacy mate (home: %s; scope: legacy work; projects: none; added 2026-10-01)\n' "$(mate mate-legacy legacy operator)" > "$home/data/secondmates.md"
printf 'kind=secondmate\nherdr_session=%s\nherdr_workspace_id=%s\nhome=%s\nremote_host=box\n' "$S" "$wR" "$(mate mate-remote remote operator)" > "$home/state/remote.meta"
FM_HOME="$home" "$PT" refresh >/dev/null
echo "# operator workspace (captain's, unrecorded): $wO"
echo "## herdr workspace list BEFORE"; list
echo "## \$ po-theme.sh relabel --session $S --dry-run"; FM_HOME="$home" "$PT" relabel --session "$S" --dry-run 2>&1; echo "  (exit $?)"
echo "## herdr workspace list after dry run"; list
echo "## \$ po-theme.sh relabel --session $S"; FM_HOME="$home" "$PT" relabel --session "$S" 2>&1; echo "  (exit $?)"
echo "## herdr workspace list AFTER"; list
echo "## gfm second mate home resolves its own home workspace via the real herdr adapter"
FM_HOME="$gfm" HERDR_SESSION="$S" bash -c '. "$1/bin/po-theme-lib.sh"; . "$1/bin/backends/herdr.sh"; echo "  label=$(fm_backend_herdr_workspace_label) found=$(fm_backend_herdr_workspace_find_all "$2" | tr "\n" " ")"' _ "$ROOT" "$S" 2>&1
echo "## \$ po-theme.sh relabel (second run, idempotent)"; FM_HOME="$home" "$PT" relabel --session "$S" 2>&1 | grep -v history; echo "  (exit $?)"
echo "## switch primary back to nautical, refresh, relabel"
echo nautical > "$home/config/po-theme"; FM_HOME="$home" "$PT" refresh >/dev/null
FM_HOME="$home" "$PT" relabel --session "$S" 2>&1; echo "  (exit $?)"
echo "## herdr workspace list after switching back"; list
