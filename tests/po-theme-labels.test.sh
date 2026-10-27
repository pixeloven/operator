#!/usr/bin/env bash
# tests/po-theme-labels.test.sh - behavior tests for the ADR-0020 workspace
# label and display-string hooks (bin/po-theme-lib.sh), `bin/po-theme.sh
# refresh`, `label`, `relabel`, and `registry`, and the A11
# architectural-invariance gate.
#
# Coverage:
#   - nautical: every label, accept-set, and herdr and Paseo matcher answers
#     exactly what upstream's own adapters answer at the pin, and nothing is
#     written to the home
#   - operator: the primary labels `spotter` and `spotter-afk-daemon`, and a
#     secondmate home inheriting the block labels itself `navigator-<id>`
#   - accept-set: an operator home adopts a live `2ndmate-gfm` workspace without
#     creating one, and keeps a legacy `firstmate/` child grouped under a
#     relabeled `spotter` parent
#   - switching themes and back never mints a duplicate home workspace
#   - relabel renames only this home's recorded workspaces in a named
#     non-default Herdr lab session and retires unused history (real Herdr;
#     capability-skipped when herdr or jq is absent), never renames an
#     unrecorded `firstmate` workspace, renames a primary home's second mate
#     record to that second mate's own label (skipping a label foreign to that
#     second mate, or one its own home does not resolve yet, or whose home is
#     remote or unreadable; a record without home= falls back to the registry;
#     planning only under --dry-run), and keeps a history label a Paseo
#     workspace or another recorded herdr session still uses, or any it
#     cannot list (fake clients)
#   - the validator refuses bad labels
#   - display strings: nautical gives upstream's herdr group state
#     `needs-captain` and wedge-alarm title, operator gives `needs-operator` and
#     `operator: away-mode escalations WEDGED` (plan output, and the real
#     osascript and herdr argv against recording fakes, the macOS title as argv
#     item 2), an S1-era values cache is rebuilt, absent keys derive from the
#     role words, and the validator refuses bad strings
#   - the registry check refuses an unregistered changed line, and anchors fail
#     when a registered hook line is lost
#   - A11: routing names, hometags, session names, and the worker role contract
#     without its vocabulary line are byte-identical under every bundled theme
#
# `bash tests/po-theme-labels.test.sh a11` runs only the A11 case (gate A11).
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PT="$ROOT/bin/po-theme.sh"
PIN=$(tr -d '[:space:]' < "$ROOT/docs/pixeloven/upstream-pin" 2>/dev/null || true)
TMP_ROOT=$(fm_test_tmproot po-theme-labels-tests)
FM_TEST_CLEANUP_DIRS+=("$TMP_ROOT")
HERDR_LAB_HELPER="$ROOT/bin/fm-herdr-lab.sh"
HERDR_LAB_SESSION=''
labels_cleanup() {
  if [ -n "$HERDR_LAB_SESSION" ]; then
    "$HERDR_LAB_HELPER" teardown "$HERDR_LAB_SESSION" >/dev/null 2>&1 \
      || printf 'not ok - herdr lab teardown failed for %s\n' "$HERDR_LAB_SESSION" >&2
    HERDR_LAB_SESSION=''
  fi
  fm_test_cleanup
}
trap labels_cleanup EXIT
fm_git_identity fmtest fmtest@example.invalid
unset HERDR_ENV HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SOCKET_PATH HERDR_SESSION

new_home() {  # <name> [<theme>]: a primary home, optionally selecting <theme>
  local home="$TMP_ROOT/$1"
  mkdir -p "$home/config" "$home/data" "$home/state"
  [ -z "${2:-}" ] || printf '%s\n' "$2" > "$home/config/po-theme"
  printf '%s\n' "$home"
}

# new_mate <name> <id> [<theme>]: a secondmate home inheriting <theme>'s block.
new_mate() {
  local home="$TMP_ROOT/$1"
  mkdir -p "$home/config" "$home/data" "$home/state"
  printf '%s\n' "$2" > "$home/.fm-secondmate-home"
  [ -z "${3:-}" ] || "$PT" persona "$3" > "$home/data/captain-shared.md"
  printf '%s\n' "$home"
}

lib() {  # <home> <shell>: run <shell> with the label library sourced
  FM_HOME="$1" bash -c '. "$0/bin/po-theme-lib.sh"; eval "$1"' "$ROOT" "$2"
}

# adapter <bin-dir> <home> <list-json> <shell>: run <shell> with that bin's herdr
# and Paseo adapters sourced and both CLIs answering <list-json> to every read;
# calls are logged one per line to $TMP_ROOT/calls.
adapter() {
  : > "$TMP_ROOT/calls"
  CALLS="$TMP_ROOT/calls" LIST="$3" PLIST="${PLIST:-[]}" FM_HOME="$2" FM_ROOT_OVERRIDE="$2" bash -c '
    . "$0/backends/herdr.sh"; . "$0/backends/paseo.sh"
    fm_backend_herdr_cli() { shift; printf "%s\n" "$*" >> "$CALLS"; case "$1 ${2:-}" in "workspace create") printf "{\"result\":{\"workspace\":{\"workspace_id\":\"wNEW\"},\"tab\":{\"tab_id\":\"tNEW\"}}}" ;; *) printf "%s" "$LIST" ;; esac; }
    fm_backend_paseo_cli() { printf "%s\n" "$*" >> "$CALLS"; printf "%s" "$PLIST"; }
    fm_backend_paseo_cli_json() { printf "%s\n" "$*" >> "$CALLS"; printf "{\"workspaceId\":\"wNEW\"}"; }
    fm_backend_herdr_projection_focus_snapshot() { printf "w0\tw0:t0"; }
    fm_backend_herdr_projection_focus_restore() { return 0; }
    eval "$1"' "$1" "$4" 2>&1
}

# ws <label>...: a herdr workspace list with ids w1, w2, ... in order.
ws() {
  local i=0 l out=''
  for l in "$@"; do
    i=$((i + 1))
    out="$out${out:+,}$(jq -cn --arg id "w$i" --arg l "$l" '{workspace_id: $id, label: $l}')"
  done
  printf '{"result":{"workspaces":[%s]}}' "$out"
}

# upstream_bin: this tree's bin/ with the hooked adapters at the upstream pin.
# Echoes nothing when the pin is not in this clone.
upstream_bin() {
  local dir="$TMP_ROOT/upstream/bin" f
  [ -d "$dir" ] && { printf '%s\n' "$dir"; return 0; }
  [ -n "$PIN" ] && git -C "$ROOT" cat-file -e "$PIN^{commit}" 2>/dev/null || return 0
  mkdir -p "$TMP_ROOT/upstream"
  cp -R "$ROOT/bin" "$dir"
  for f in $("$PT" registry files); do
    git -C "$ROOT" show "$PIN:$f" > "$dir/${f#bin/}"
  done
  printf '%s\n' "$dir"
}

TOKEN=AbCdEfGhIjKlMnOpQrStUv

test_nautical_matches_upstream() {
  local up home mate probe list a b
  home=$(new_home nautical-primary)
  mate=$(new_mate nautical-mate gfm)
  # shellcheck disable=SC2016  # the label calls run in lib's shell.
  assert_equals "firstmate 2ndmate firstmate-afk-daemon" \
    "$(lib "$home" 'echo $(po_label primary) $(po_label submate) $(po_label afk)')" "nautical labels are not upstream's literals"
  assert_equals "firstmate-afk-daemon" "$(FM_HOME="$home" "$PT" label afk)" "the away-daemon label is not upstream's literal"
  # shellcheck disable=SC2016  # the probe is evaluated by adapter's shell.
  probe='fm_backend_herdr_workspace_label; echo; fm_backend_paseo_workspace_label; echo
    fm_backend_herdr_projection_workspace_label firstmate/t1 '"$TOKEN"'; echo
    fm_backend_herdr_projection_workspace_label 2ndmate-gfm/t2 '"$TOKEN"'; echo
    fm_backend_herdr_workspace_find_all fmtest; echo "ensure=$(fm_backend_herdr_workspace_ensure fmtest /tmp none; echo " rc=$?")"
    fm_backend_herdr_projection_order_best_effort fmtest w4 "$(fm_backend_herdr_workspace_label)" "" ""; echo "order=$?"'
  list=$(ws firstmate "firstmate/old · p:$TOKEN" 2ndmate-gfm "└ new · p:$TOKEN" spotter navigator-gfm)
  up=$(upstream_bin)
  for h in "$home" "$mate"; do
    a=$(adapter "$ROOT/bin" "$h" "$list" "$probe")
    if [ -n "$up" ]; then
      b=$(adapter "$up" "$h" "$list" "$probe")
      assert_equals "$b" "$a" "nautical herdr and Paseo answers differ from upstream's adapters in $(basename "$h")"
    fi
  done
  assert_contains "$(adapter "$ROOT/bin" "$home" "$list" "$probe")" "ensure=w1 rc=0" "a nautical primary did not adopt its firstmate workspace"
  assert_contains "$(adapter "$ROOT/bin" "$mate" "$list" "$probe")" "ensure=w3 rc=0" "a nautical secondmate did not adopt its 2ndmate workspace"
  [ -n "$up" ] || printf 'note: upstream pin %s is not in this clone; nautical answers checked only against literals\n' "${PIN:-?}"
  assert_absent "$home/state/po-theme" "a nautical home wrote theme state"
  assert_absent "$mate/state/po-theme" "a nautical secondmate home wrote theme state"
  pass "nautical labels and every herdr and Paseo matcher answer exactly as upstream's adapters do"
}

test_operator_labels() {
  local home mate out
  home=$(new_home op-primary operator)
  mate=$(new_mate op-mate gfm operator)
  # shellcheck disable=SC2016  # the label calls run in lib's shell.
  assert_equals "spotter spotter-afk-daemon" "$(lib "$home" 'echo $(po_label primary) $(po_label afk)')" "the operator primary labels are wrong"
  assert_equals "spotter-afk-daemon" "$(FM_HOME="$home" "$PT" label afk)" "the away-daemon label is not themed"
  out=$(adapter "$ROOT/bin" "$home" "$(ws)" 'fm_backend_herdr_workspace_label; echo; fm_backend_paseo_workspace_label')
  assert_equals $'spotter\nspotter' "$out" "the operator primary herdr or Paseo label is wrong"
  out=$(adapter "$ROOT/bin" "$mate" "$(ws)" 'fm_backend_herdr_workspace_label; echo; fm_backend_paseo_workspace_label')
  assert_equals $'navigator-gfm\nnavigator-gfm' "$out" "the inheriting secondmate's herdr or Paseo label is wrong"
  out=$(adapter "$ROOT/bin" "$home" "$(ws)" 'fm_backend_herdr_workspace_ensure fmtest /tmp none')
  assert_equals "wNEW" "$out" "an operator home with no workspace did not create one"
  assert_contains "$(cat "$TMP_ROOT/calls")" "workspace create --cwd /tmp --label spotter --no-focus" "the operator home workspace was not created as spotter"
  out=$(PLIST='[]' adapter "$ROOT/bin" "$mate" "$(ws)" 'fm_backend_paseo_workspace_ensure /tmp')
  assert_contains "$(cat "$TMP_ROOT/calls")" "--title navigator-gfm" "the Paseo workspace was not titled navigator-gfm"
  assert_equals "primary	spotter" "$(grep '^primary' "$home/state/po-theme/history")" "the primary label was not recorded in history"
  pass "operator gives spotter and spotter-afk-daemon, and an inheriting secondmate names itself navigator-gfm"
}

test_accept_set_adopts_and_groups() {
  local mate home out
  mate=$(new_mate accept-mate gfm operator)
  out=$(adapter "$ROOT/bin" "$mate" "$(ws firstmate 2ndmate-gfm)" 'fm_backend_herdr_workspace_ensure fmtest /tmp none; echo " rc=$?"')
  assert_equals "w2 rc=0" "$out" "an operator secondmate did not adopt its live 2ndmate-gfm workspace"
  assert_not_contains "$(cat "$TMP_ROOT/calls")" "workspace create" "adopting 2ndmate-gfm still created a workspace"
  out=$(PLIST='[{"workspaceId":"p1","name":"2ndmate-gfm","cwd":"/tmp"}]' adapter "$ROOT/bin" "$mate" "$(ws)" 'fm_backend_paseo_workspace_ensure /tmp')
  assert_equals "p1" "$out" "an operator secondmate did not adopt its live 2ndmate-gfm Paseo workspace"
  home=$(new_home accept-primary operator)
  out=$(adapter "$ROOT/bin" "$home" "$(ws spotter "firstmate/old · p:$TOKEN" "└ new · p:$TOKEN")" \
    'fm_backend_herdr_projection_order_best_effort fmtest w3 spotter w1 ""; echo "rc=$?"')
  assert_equals "rc=0" "$out" "a legacy firstmate/ child under a relabeled spotter parent was not grouped"
  out=$(adapter "$ROOT/bin" "$(new_home accept-nautical)" "$(ws spotter "firstmate/old · p:$TOKEN" "└ new · p:$TOKEN")" \
    'fm_backend_herdr_projection_order_best_effort fmtest w3 spotter w1 ""; echo "rc=$?"')
  assert_contains "$out" "ambiguous workspace layout" "the grouping case is vacuous: a home that never applied a theme also grouped it"
  pass "the accept-set adopts a live 2ndmate-gfm and keeps legacy children grouped under a renamed parent"
}

test_switch_and_back_never_duplicates() {
  local home out
  home=$(new_home switch)
  out=$(adapter "$ROOT/bin" "$home" "$(ws firstmate)" 'fm_backend_herdr_workspace_ensure fmtest /tmp none')
  assert_equals "w1" "$out" "nautical did not adopt its firstmate workspace"
  printf 'operator\n' > "$home/config/po-theme"
  FM_HOME="$home" "$PT" refresh >/dev/null || fail "refresh failed under operator"
  out=$(adapter "$ROOT/bin" "$home" "$(ws firstmate)" 'fm_backend_herdr_workspace_ensure fmtest /tmp none')
  assert_equals "w1" "$out" "switching to operator did not adopt the live firstmate workspace"
  out=$(adapter "$ROOT/bin" "$home" "$(ws spotter)" 'fm_backend_herdr_workspace_ensure fmtest /tmp none')
  assert_equals "w1" "$out" "operator did not adopt its relabeled spotter workspace"
  printf 'nautical\n' > "$home/config/po-theme"
  FM_HOME="$home" "$PT" refresh >/dev/null || fail "refresh failed under nautical"
  out=$(adapter "$ROOT/bin" "$home" "$(ws spotter)" 'fm_backend_herdr_workspace_ensure fmtest /tmp none')
  assert_equals "w1" "$out" "switching back to nautical orphaned the live spotter workspace"
  out=$(adapter "$ROOT/bin" "$home" "$(ws spotter firstmate)" 'fm_backend_herdr_workspace_ensure fmtest /tmp none; echo " rc=$?"')
  assert_contains "$out" "2 herdr workspaces in session 'fmtest' are labeled 'firstmate' (w1 w2)" "two live workspaces for one home were not refused by the duplicate check"
  assert_not_contains "$(cat "$TMP_ROOT/calls")" "workspace create" "the duplicate check still created a workspace"
  out=$(adapter "$ROOT/bin" "$home" "$(ws spotter)" 'po_label_same spotter firstmate && echo same')
  assert_equals "same" "$out" "reclaim does not treat the historical parent label as the same home"
  pass "switching themes and back adopts the live workspace and never mints a duplicate"
}

test_relabel_in_lab() {
  local home out list wa wb wc wd
  if ! command -v herdr >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "skip: relabel lab case needs herdr and jq"
    return 0
  fi
  HERDR_LAB_SESSION=$("$HERDR_LAB_HELPER" name po-relabel) || fail "could not name a herdr lab session"
  case "$HERDR_LAB_SESSION" in default|'') fail "refusing herdr lab session '$HERDR_LAB_SESSION'" ;; esac
  "$HERDR_LAB_HELPER" provision "$HERDR_LAB_SESSION" >/dev/null || fail "herdr lab provision failed"
  mklabel() { "$HERDR_LAB_HELPER" run "$HERDR_LAB_SESSION" workspace create --cwd "$TMP_ROOT" --label "$1" --no-focus | jq -r '.result.workspace.workspace_id'; }
  wa=$(mklabel firstmate); wb=$(mklabel firstmate); wc=$(mklabel 2ndmate-gfm); wd=$(mklabel 2ndmate-gfm)
  [ -n "$wa" ] && [ -n "$wb" ] && [ -n "$wc" ] && [ -n "$wd" ] || fail "could not create lab workspaces"
  home=$(new_home relabel operator)
  printf 'herdr_session=%s\nherdr_workspace_id=%s\n' "$HERDR_LAB_SESSION" "$wa" > "$home/state/t1.meta"
  printf 'herdr_session=%s\nherdr_workspace_id=%s\n' "$HERDR_LAB_SESSION" "$wc" > "$home/state/t2.meta"
  printf 'herdr_session=other\nherdr_workspace_id=%s\n' "$wb" > "$home/state/t3.meta"
  printf 'kind=secondmate\nherdr_session=%s\nherdr_workspace_id=%s\nhome=%s\n' "$HERDR_LAB_SESSION" "$wd" "$(new_mate relabel-mate gfm operator)" > "$home/state/gfm.meta"
  FM_HOME="$home" "$PT" refresh >/dev/null || fail "refresh failed"
  label_of() { "$HERDR_LAB_HELPER" run "$HERDR_LAB_SESSION" workspace list | jq -r --arg id "$1" '.result.workspaces[] | select(.workspace_id == $id) | .label'; }

  out=$(FM_HOME="$home" "$PT" relabel --session "$HERDR_LAB_SESSION" --dry-run 2>&1) || fail "relabel --dry-run failed: $out"
  assert_contains "$out" "$wa 'firstmate' -> 'spotter'" "the dry run did not plan the recorded workspace rename"
  assert_contains "$out" "$wd '2ndmate-gfm' -> 'navigator-gfm'" "the dry run did not plan the secondmate workspace rename"
  assert_equals "firstmate" "$(label_of "$wa")" "the dry run renamed a workspace"
  assert_equals "2ndmate-gfm" "$(label_of "$wd")" "the dry run renamed the secondmate workspace"

  out=$(FM_HOME="$home" "$PT" relabel --session "$HERDR_LAB_SESSION" 2>&1) || fail "relabel failed: $out"
  assert_equals "spotter" "$(label_of "$wa")" "relabel did not rename the recorded workspace"
  assert_equals "firstmate" "$(label_of "$wb")" "relabel renamed a workspace this home did not record in that session"
  assert_equals "2ndmate-gfm" "$(label_of "$wc")" "relabel renamed a workspace outside this home's accept-set"
  assert_contains "$out" "is labeled '2ndmate-gfm', not one of this home's labels" "relabel did not report the foreign label"
  assert_equals "navigator-gfm" "$(label_of "$wd")" "relabel did not rename the secondmate's own workspace to its label"

  printf 'nautical\n' > "$home/config/po-theme"
  FM_HOME="$home" "$PT" refresh >/dev/null || fail "refresh failed under nautical"
  rm "$home/state/t3.meta"
  out=$(FM_HOME="$home" "$PT" relabel --session "$HERDR_LAB_SESSION" 2>&1) || fail "relabel back failed: $out"
  assert_equals "firstmate" "$(label_of "$wa")" "relabel did not rename the workspace back"
  assert_equals "2ndmate-gfm" "$(label_of "$wd")" "relabel did not rename the secondmate workspace back"
  assert_contains "$out" "history retired primary 'spotter'" "relabel did not retire the unused primary label"
  assert_contains "$out" "history retired submate 'navigator'" "relabel did not retire the unused secondmate label"
  assert_equals "" "$(cat "$home/state/po-theme/history")" "retired history entries were kept"
  out=$(FM_HOME="$home" "$PT" relabel 2>&1) && fail "relabel ran without a named session"
  assert_contains "$out" "needs --session" "relabel refused for the wrong reason"
  "$HERDR_LAB_HELPER" teardown "$HERDR_LAB_SESSION" >/dev/null || fail "herdr lab teardown failed"
  HERDR_LAB_SESSION=''
  pass "relabel renames only recorded workspaces in a named lab session and retires unused history"
}

# fake_clis <dir>: fake herdr and paseo clients in <dir>. herdr answers
# `workspace list --session S` from <dir>/herdr-S.json (failing when absent) and
# logs every rename to <dir>/calls; paseo answers `workspace ls --json` from
# <dir>/paseo.json (failing when absent).
fake_clis() {
  mkdir -p "$1"
  cat > "$1/herdr" <<'SH'
#!/usr/bin/env bash
d=$(dirname "$0")
case "$1 $2" in
  "workspace list") cat "$d/herdr-${*: -1}.json" 2>/dev/null ;;
  "workspace rename") printf '%s\n' "$*" >> "$d/calls" ;;
  *) exit 1 ;;
esac
SH
  cat > "$1/paseo" <<'SH'
#!/usr/bin/env bash
[ "$*" = "workspace ls --json" ] && cat "$(dirname "$0")/paseo.json" 2>/dev/null
SH
  chmod +x "$1/herdr" "$1/paseo"
}

test_relabel_keeps_history_other_containers_use() {
  local home fake out
  command -v jq >/dev/null 2>&1 || { echo "skip: relabel history case needs jq"; return 0; }
  fake="$TMP_ROOT/fakecli"
  fake_clis "$fake"
  home=$(new_home relabel-history operator)
  printf 'herdr_session=lab\nherdr_workspace_id=w1\n' > "$home/state/t1.meta"
  printf 'herdr_session=side\nherdr_workspace_id=s1\n' > "$home/state/t2.meta"
  FM_HOME="$home" "$PT" refresh >/dev/null || fail "refresh failed"
  ws firstmate firstmate > "$fake/herdr-lab.json"
  ws navigator-gfm > "$fake/herdr-side.json"
  printf '[]' > "$fake/paseo.json"
  out=$(PATH="$fake:$PATH" FM_HOME="$home" "$PT" relabel --session lab 2>&1) || fail "relabel failed: $out"
  assert_equals "workspace rename w1 spotter --session lab" "$(cat "$fake/calls")" "relabel did not rename only the recorded workspace"
  assert_contains "$out" "relabel: w1 'firstmate' -> 'spotter'" "relabel did not report the recorded rename"

  printf 'nautical\n' > "$home/config/po-theme"
  FM_HOME="$home" "$PT" refresh >/dev/null || fail "refresh failed under nautical"
  jq -cn --arg o "$TMP_ROOT/secondmate-home" '[{workspaceId: "p1", name: "spotter", cwd: $o}]' > "$fake/paseo.json"
  out=$(PATH="$fake:$PATH" FM_HOME="$home" "$PT" relabel --session lab 2>&1) || fail "relabel failed: $out"
  assert_not_contains "$out" "history retired" "relabel retired a label a Paseo workspace outside projects/ or another session still uses"
  assert_equals "primary	spotter
submate	navigator" "$(cat "$home/state/po-theme/history")" "the history lost a label a live container uses"

  printf '[]' > "$fake/paseo.json"
  rm "$fake/herdr-side.json"
  out=$(PATH="$fake:$PATH" FM_HOME="$home" "$PT" relabel --session lab 2>&1) || fail "relabel failed: $out"
  assert_contains "$out" "history kept" "relabel did not keep the history when a recorded session could not be listed"
  assert_equals "primary	spotter
submate	navigator" "$(cat "$home/state/po-theme/history")" "an unlistable session did not keep the history"

  ws navigator-gfm > "$fake/herdr-side.json"
  out=$(PATH="$fake:$PATH" FM_HOME="$home" "$PT" relabel --session lab 2>&1) || fail "relabel failed: $out"
  assert_contains "$out" "history retired primary 'spotter'" "relabel did not retire a label no container uses"
  assert_equals "submate	navigator" "$(cat "$home/state/po-theme/history")" "relabel retired the label another session still uses"
  assert_equals "workspace rename w1 spotter --session lab" "$(cat "$fake/calls")" "relabel renamed an unrecorded workspace"
  out=$(PATH="$fake:$PATH" FM_HOME="$home" "$PT" relabel --session lab --workspace w2 2>&1) && fail "relabel accepted a caller-supplied workspace id"
  assert_contains "$out" "unknown argument: --workspace" "relabel refused --workspace for the wrong reason"
  pass "relabel renames only recorded workspaces and keeps history labels any listed container uses"
}

test_relabel_secondmate_records() {
  local home fake out
  command -v jq >/dev/null 2>&1 || { echo "skip: relabel secondmate case needs jq"; return 0; }
  fake="$TMP_ROOT/fakecli-mate"
  fake_clis "$fake"
  home=$(new_home relabel-mates operator)
  printf 'herdr_session=lab\nherdr_workspace_id=w1\n' > "$home/state/t1.meta"
  printf 'kind=secondmate\nherdr_session=lab\nherdr_workspace_id=w2\nhome=%s\n' "$(new_mate mate-gfm gfm operator)" > "$home/state/gfm.meta"
  printf 'kind=secondmate\nherdr_session=lab\nherdr_workspace_id=w3\nhome=%s\n' "$(new_mate mate-pixeloven pixeloven operator)" > "$home/state/pixeloven.meta"
  printf 'kind=secondmate\nherdr_session=lab\nherdr_workspace_id=w4\nhome=%s\n' "$(new_mate mate-odd odd operator)" > "$home/state/odd.meta"
  printf 'kind=secondmate\nherdr_session=lab\nherdr_workspace_id=w6\nhome=%s\n' "$(new_mate mate-stale stale)" > "$home/state/stale.meta"
  printf 'kind=secondmate\nherdr_session=lab\nherdr_workspace_id=w7\nhome=%s\n' "$TMP_ROOT/mate-missing" > "$home/state/missing.meta"
  printf 'kind=secondmate\nherdr_session=lab\nherdr_workspace_id=w8\n' > "$home/state/legacy.meta"
  printf -- '- legacy - Legacy mate (home: %s; scope: legacy work; projects: none; added 2026-10-01)\n' "$(new_mate mate-legacy legacy operator)" > "$home/data/secondmates.md"
  printf 'kind=secondmate\nherdr_session=lab\nherdr_workspace_id=w9\nhome=%s\nremote_host=box\n' "$(new_mate mate-remote remote operator)" > "$home/state/remote.meta"
  printf 'kind=secondmate\nherdr_session=lab\nherdr_workspace_id=w10\nhome=box:%s\n' "$(new_mate mate-hostpath hostpath operator)" > "$home/state/hostpath.meta"
  FM_HOME="$home" "$PT" refresh >/dev/null || fail "refresh failed"
  ws firstmate 2ndmate-gfm 2ndmate-pixeloven 2ndmate-gfm operator 2ndmate-stale 2ndmate-missing 2ndmate-legacy 2ndmate-remote 2ndmate-hostpath > "$fake/herdr-lab.json"
  printf '[]' > "$fake/paseo.json"

  out=$(PATH="$fake:$PATH" FM_HOME="$home" "$PT" relabel --session lab --dry-run 2>&1) || fail "relabel --dry-run failed: $out"
  assert_contains "$out" "relabel: w2 '2ndmate-gfm' -> 'navigator-gfm'" "the dry run did not plan the secondmate rename"
  assert_contains "$out" "relabel: w3 '2ndmate-pixeloven' -> 'navigator-pixeloven'" "the dry run did not plan the second secondmate rename"
  assert_equals "" "$(cat "$fake/calls" 2>/dev/null)" "the dry run renamed a workspace"

  out=$(PATH="$fake:$PATH" FM_HOME="$home" "$PT" relabel --session lab 2>&1) || fail "relabel failed: $out"
  assert_equals "workspace rename w1 spotter --session lab
workspace rename w2 navigator-gfm --session lab
workspace rename w3 navigator-pixeloven --session lab
workspace rename w8 navigator-legacy --session lab" "$(sort "$fake/calls")" "relabel did not rename exactly the recorded worker and secondmate workspaces"
  assert_contains "$out" "relabel: w4 is labeled '2ndmate-gfm', not one of second mate odd's labels; skipped" "relabel renamed a secondmate record whose label belongs to another secondmate"
  assert_contains "$out" "relabel: w6 skipped: second mate stale has not received the current theme yet; rerun after it propagates" "relabel renamed a secondmate workspace before that secondmate resolves the new label"
  assert_contains "$out" "relabel: w7 skipped: second mate missing's home cannot be read locally" "relabel renamed a secondmate workspace whose home it could not read"
  assert_contains "$out" "relabel: w9 skipped: second mate remote's home cannot be read locally" "relabel read a remote secondmate's home as a local one"
  assert_contains "$out" "relabel: w10 skipped: second mate hostpath's home cannot be read locally" "relabel read a HOST:path secondmate home as a local one"
  assert_not_contains "$out" "w5" "relabel touched the operator's unrecorded workspace"

  : > "$fake/calls"
  printf 'nautical\n' > "$home/config/po-theme"
  FM_HOME="$home" "$PT" refresh >/dev/null || fail "refresh failed under nautical"
  ws spotter navigator-gfm navigator-pixeloven 2ndmate-gfm operator 2ndmate-stale 2ndmate-missing navigator-legacy 2ndmate-remote 2ndmate-hostpath > "$fake/herdr-lab.json"
  out=$(PATH="$fake:$PATH" FM_HOME="$home" "$PT" relabel --session lab 2>&1) || fail "relabel back failed: $out"
  assert_equals "workspace rename w1 firstmate --session lab
workspace rename w2 2ndmate-gfm --session lab
workspace rename w3 2ndmate-pixeloven --session lab
workspace rename w8 2ndmate-legacy --session lab" "$(sort "$fake/calls")" "relabel did not rename the secondmate workspaces back"
  assert_contains "$(cat "$home/state/po-theme/history")" "submate	navigator" "relabel retired the secondmate label a live secondmate workspace still uses"
  pass "relabel renames a primary home's secondmate workspaces to their own labels and skips a foreign or unpropagated one"
}

test_label_validation() {
  local home rc out name edit want
  home=$(new_home validation)
  mkdir -p "$home/config/po-themes"
  while IFS='|' read -r name edit want; do
    { sed "s/^name = .*/name = \"$name\"/" "$ROOT/.agents/skills/po-theme/themes/operator.theme"; printf '%s\n' "$edit"; } \
      > "$home/config/po-themes/$name.theme"
    rc=0
    out=$(FM_HOME="$home" "$PT" validate "$name" 2>&1) || rc=$?
    [ "$rc" -ne 0 ] || fail "validate accepted the $name labels: $out"
    assert_contains "$out" "$want" "the $name labels were refused for the wrong reason"
  done <<'EOF'
slash|label.primary = "spot/ter"|label.primary: 'spot/ter' must be 2-24
fmprefix|label.primary = "fm-spotter"|must not start with fm-
upper|label.submate = "Navigator"|label.submate: 'Navigator' must be 2-24
long|label.primary = "abcdefghijklmnopqrstuvwxy"|must be 2-24
overlap|label.submate = "spotter-x"|overlap as prefixes
same|label.submate = "spotter"|label.primary equals label.submate
canonprimary|label.submate = "firstmate"|label.submate equals the canonical primary label
canonsub|label.primary = "2ndmate"|label.primary equals the canonical secondmate label
canonprefix|label.primary = "2ndmate-x"|overlap as prefixes
afkhome|label.afk = "spotter"|label.afk: 'spotter' equals a home label
afksub|label.afk = "navigator-afk"|would read as a secondmate label
EOF
  sed -e 's/^name = .*/name = "oldschema"/' -e 's#^schema = .*#schema = "po-theme/1"#' -e '/^str\./d' "$ROOT/.agents/skills/po-theme/themes/operator.theme" > "$home/config/po-themes/oldschema.theme"
  FM_HOME="$home" "$PT" validate oldschema >/dev/null 2>&1 || fail "a po-theme/1 theme without label keys was refused"
  printf 'label.primary = "spotter"\n' >> "$home/config/po-themes/oldschema.theme"
  out=$(FM_HOME="$home" "$PT" validate oldschema 2>&1) && fail "a po-theme/1 theme accepted a label key"
  assert_contains "$out" "needs schema po-theme/2" "a label key under po-theme/1 was refused for the wrong reason"
  sed -e 's/^name = .*/name = "derived"/' -e 's/^self = .*/self = "fm boss"/' "$ROOT/.agents/skills/po-theme/themes/operator.theme" > "$home/config/po-themes/derived.theme"
  out=$(FM_HOME="$home" "$PT" validate derived 2>&1) && fail "a derived fm- label was accepted"
  assert_contains "$out" "label.primary: 'fm-boss' must not start with fm-" "a derived label was refused for the wrong reason"
  pass "the validator refuses bad, overlapping, colliding, and misplaced labels"
}

# groups_plan <home>: `fm-herdr-groups.sh plan` for one herdr task with an
# open decision in <home>; no Herdr call is made.
groups_plan() {
  printf 'on\n' > "$1/config/herdr-project-groups"
  printf 'window=s1:w2:p2\nproject=/p/storefront\nkind=ship\nbackend=herdr\nherdr_session=s1\nherdr_workspace_id=w2\nherdr_tab_id=w2:t2\nherdr_pane_id=w2:p2\n' > "$1/state/web-ask.meta"
  printf 'needs-decision [key=pick]: which one\n' > "$1/state/web-ask.status"
  env FM_ROOT_OVERRIDE='' FM_HOME="$1" FM_STATE_OVERRIDE="$1/state" FM_CONFIG_OVERRIDE="$1/config" \
    "$ROOT/bin/fm-herdr-groups.sh" plan 2>&1 | cut -f 1-3
}

# wedge_argv <home>: the argv the daemon's osascript and herdr wedge notifiers
# hand to recording fakes, one notifier per line, items joined by "|". The
# fakes must be the commands resolved, so no real notification is ever posted.
wedge_argv() {
  local fake="$TMP_ROOT/wedge-fakes" c
  mkdir -p "$fake"
  for c in osascript herdr; do
    # shellcheck disable=SC2016  # expanded by the fake at run time.
    printf '#!/usr/bin/env bash\n{ printf %%s %s; printf "|%%s" "$@"; printf "\\n"; } >> "$WEDGE_ARGV_LOG"\n' "$c" > "$fake/$c"
    chmod +x "$fake/$c"
  done
  : > "$TMP_ROOT/wedge-argv"
  # shellcheck disable=SC2016  # expanded by the child shell.
  WEDGE_ARGV_LOG="$TMP_ROOT/wedge-argv" FM_HOME="$1" PATH="$fake:$PATH" bash -c '
    . "$0/bin/fm-supervise-daemon.sh"
    [ "$(command -v osascript)" = "$1/osascript" ] && [ "$(command -v herdr)" = "$1/herdr" ] || exit 99
    FM_WEDGE_ALARM_EXEC=
    wedge_alarm_via_osascript "escalations stuck 900s"
    wedge_alarm_via_herdr "escalations stuck 900s"
  ' "$ROOT" "$fake" >/dev/null 2>&1 || fail "the wedge notifiers did not reach the recording fakes"
  cat "$TMP_ROOT/wedge-argv"
}

test_display_strings() {
  local home op mate out
  home=$(new_home strings-nautical)
  op=$(new_home strings-operator operator)
  mate=$(new_mate strings-mate gfm operator)
  # shellcheck disable=SC2016  # the string calls run in lib's shell.
  assert_equals "needs-captain|firstmate: away-mode escalations WEDGED" \
    "$(lib "$home" 'echo "$(po_str sidebar.needs)|$(po_str alert.wedge_title)"')" "nautical strings are not upstream's literals"
  assert_equals $'web-ask\tstorefront\tneeds-captain' "$(groups_plan "$home")" "the nautical group state is not upstream's"
  out=$(wedge_argv "$home")
  assert_equals "osascript|-e|on run argv|-e|display notification (item 1 of argv) with title (item 2 of argv) sound name \"Basso\"|-e|end run|escalations stuck 900s|firstmate: away-mode escalations WEDGED
herdr|notification|show|firstmate: away-mode escalations WEDGED|--body|escalations stuck 900s|--sound|request" "$out" "the nautical wedge notifiers' argv"
  assert_absent "$home/state/po-theme" "a nautical home wrote theme state"
  # shellcheck disable=SC2016  # the string calls run in lib's shell.
  assert_equals "needs-operator|operator: away-mode escalations WEDGED" \
    "$(lib "$op" 'echo "$(po_str sidebar.needs)|$(po_str alert.wedge_title)"')" "the operator strings are wrong"
  assert_equals $'web-ask\tstorefront\tneeds-operator' "$(groups_plan "$op")" "the operator group state is wrong"
  out=$(wedge_argv "$op")
  assert_contains "$out" "|end run|escalations stuck 900s|operator: away-mode escalations WEDGED" "the macOS title did not travel as argv item 2"
  assert_contains "$out" "herdr|notification|show|operator: away-mode escalations WEDGED|--body" "the herdr notification title is not themed"
  assert_equals "needs-operator" "$(lib "$mate" 'po_str sidebar.needs')" "an inheriting secondmate's group state is wrong"
  # An S1-era cache has labels but no strings and no cache format line.
  grep -v '^cache\|^str\.' "$op/state/po-theme/values" > "$op/state/po-theme/values.old"
  mv "$op/state/po-theme/values.old" "$op/state/po-theme/values"
  assert_equals "needs-operator" "$(lib "$op" 'po_str sidebar.needs')" "an S1-era values cache was not rebuilt"
  lib "$op" 'po_str sidebar.unknown' >/dev/null 2>&1 && fail "po_str accepted an unregistered key"
  pass "nautical keeps needs-captain and the firstmate wedge title; operator gives needs-operator and the operator title as macOS argv item 2"
}

test_string_validation() {
  local home rc out name edit want
  home=$(new_home str-validation)
  mkdir -p "$home/config/po-themes"
  while IFS='|' read -r name edit want; do
    { sed -e "s/^name = .*/name = \"$name\"/" -e '/^str\./d' "$ROOT/.agents/skills/po-theme/themes/operator.theme"; printf '%s\n' "$edit"; } \
      > "$home/config/po-themes/$name.theme"
    rc=0
    out=$(FM_HOME="$home" "$PT" validate "$name" 2>&1) || rc=$?
    [ "$rc" -ne 0 ] || fail "validate accepted the $name strings: $out"
    assert_contains "$out" "$want" "the $name strings were refused for the wrong reason"
  done <<'EOF'
state|str.sidebar.needs = "Needs Op"|str.sidebar.needs: 'Needs Op' must be 2-24
running|str.sidebar.needs = "running"|equals another herdr group state
verb|str.sidebar.needs = "needs-decision"|contains the status verb needs-decision
fmtoken|str.alert.wedge_title = "fm-alert WEDGED"|contains an architectural token
long|str.alert.wedge_title = "operator: away-mode escalations WEDGED and still undelivered after many retries in a row"|longer than 80 characters
unknown|str.alert.other = "x"|unknown key: str.alert.other
EOF
  sed -e 's/^name = .*/name = "derived"/' -e '/^str\./d' -e 's/^user = .*/user = "field boss"/' -e 's/^product = .*/product = "ops"/' \
    "$ROOT/.agents/skills/po-theme/themes/operator.theme" > "$home/config/po-themes/derived.theme"
  printf 'derived\n' > "$home/config/po-theme"
  assert_equals "needs-field-boss" "$(lib "$home" 'po_str sidebar.needs')" "an absent sidebar state did not derive from the user word"
  assert_equals "ops: away-mode escalations WEDGED" "$(lib "$home" 'po_str alert.wedge_title')" "an absent wedge title did not derive from the product word"
  sed -e 's/^name = .*/name = "oldstr"/' -e 's#^schema = .*#schema = "po-theme/1"#' "$ROOT/.agents/skills/po-theme/themes/operator.theme" > "$home/config/po-themes/oldstr.theme"
  out=$(FM_HOME="$home" "$PT" validate oldstr 2>&1) && fail "a po-theme/1 theme accepted a str key"
  assert_contains "$out" "str.sidebar.needs: needs schema po-theme/2" "a str key under po-theme/1 was refused for the wrong reason"
  pass "absent strings derive from the role words, and the validator refuses bad or misplaced strings"
}

# fixture_repo <name>: a throwaway repository whose first commit carries the
# registered upstream files at the pin and whose working tree carries this
# tree's hooks, so `registry check-diff HEAD` sees exactly the theme hunks.
fixture_repo() {
  local repo="$TMP_ROOT/$1" f
  mkdir -p "$repo/bin/backends" "$repo/.agents/skills" "$repo/docs/pixeloven"
  cp -R "$ROOT/.agents/skills/po-theme" "$repo/.agents/skills/"
  cp "$PT" "$ROOT/bin/po-theme-lib.sh" "$repo/bin/"
  printf '%s\n' "$PIN" > "$repo/docs/pixeloven/upstream-pin"
  git init -q -b main "$repo"
  for f in $("$PT" registry files); do git -C "$ROOT" show "$PIN:$f" > "$repo/$f"; done
  git -C "$repo" add -A
  git -C "$repo" commit -q -m upstream
  for f in $("$PT" registry files); do cp "$ROOT/$f" "$repo/$f"; done
  printf '%s\n' "$repo"
}

test_registry_gates() {
  local repo out
  if [ -z "$PIN" ] || ! git -C "$ROOT" cat-file -e "$PIN^{commit}" 2>/dev/null; then
    printf 'note: upstream pin %s is not in this clone; registry gates not exercised\n' "${PIN:-?}"
    return 0
  fi
  out=$("$PT" registry check-diff "$PIN" 2>&1) || fail "the registry check failed on this tree: $out"
  repo=$(fixture_repo registry)
  out=$("$repo/bin/po-theme.sh" registry check-diff HEAD 2>&1) || fail "the registry check failed on the fixture: $out"
  printf '# extra\n' >> "$repo/bin/backends/paseo.sh"
  out=$("$repo/bin/po-theme.sh" registry check-diff HEAD 2>&1) && fail "the registry check accepted an unregistered line"
  assert_contains "$out" "A9: bin/backends/paseo.sh: unregistered changed line: # extra" "the registry check did not name the unregistered line"
  cp "$ROOT/bin/backends/paseo.sh" "$repo/bin/backends/paseo.sh"
  grep -v '^FM_AFK_LAUNCH_LOCK=' "$ROOT/bin/fm-afk-launch.sh" > "$repo/bin/fm-afk-launch.sh"
  out=$("$repo/bin/po-theme.sh" registry check-diff HEAD 2>&1) && fail "the registry check accepted a deleted upstream line"
  assert_contains "$out" "A9: bin/fm-afk-launch.sh: unregistered removed line: FM_AFK_LAUNCH_LOCK=" "the registry check did not name the deleted line"
  pass "the registry check refuses an unregistered added or removed line"
}

test_anchors_name_a_lost_hook() {
  local code out s
  code="$TMP_ROOT/anchors/code"
  mkdir -p "$code/bin/backends" "$code/.agents/skills" "$code/docs/pixeloven"
  cp "$PT" "$ROOT/bin/po-theme-lib.sh" "$ROOT/bin/fm-dod-lib.sh" "$ROOT/bin/fm-afk-launch.sh" \
    "$ROOT/bin/fm-herdr-groups.sh" "$ROOT/bin/fm-supervise-daemon.sh" "$code/bin/"
  cp "$ROOT/bin/backends/herdr.sh" "$ROOT/bin/backends/paseo.sh" "$code/bin/backends/"
  cp -R "$ROOT/.agents/skills/po-theme" "$code/.agents/skills/"
  cp "$ROOT/AGENTS.md" "$ROOT/VISION.md" "$code/"
  for s in afk ahoy bearings quiet stow updatefirstmate; do
    mkdir -p "$code/.agents/skills/$s"
    printf -- '---\nname: %s\nuser-invocable: true\n---\n' "$s" > "$code/.agents/skills/$s/SKILL.md"
  done
  out=$(FM_HOME="$TMP_ROOT/anchors" "$code/bin/po-theme.sh" anchors 2>&1) || fail "anchors failed on an intact fixture: $out"
  sed -i.bak 's/^  po_home_label firstmate$/  printf '"'"'firstmate'"'"'/' "$code/bin/backends/herdr.sh"
  out=$(FM_HOME="$TMP_ROOT/anchors" "$code/bin/po-theme.sh" anchors 2>&1) && fail "anchors passed without a registered hook line"
  assert_contains "$out" "anchor missing: hook label.primary not found in bin/backends/herdr.sh: po_home_label firstmate" "anchors did not name the lost hook"
  pass "anchors fail when a registered hook line is lost in a merge"
}

# routing_names <home>: the architectural outputs A11 holds constant.
routing_names() {
  FM_HOME="$1" FM_ROOT_OVERRIDE="$1" bash -c '
    . "$0/bin/backends/cmux.sh" 2>/dev/null; . "$0/bin/backends/zellij.sh" 2>/dev/null
    . "$0/bin/backends/paseo.sh"; . "$0/bin/backends/herdr.sh"; . "$0/bin/fm-dod-lib.sh"
    echo "hometag=$(fm_backend_hometag)"
    echo "cmux=$(fm_backend_cmux_scoped_title fm-t1)"
    echo "zellij=$(fm_backend_zellij_scoped_title fm-t1) session=$(fm_backend_zellij_session)"
    echo "paseo=$(fm_backend_paseo_scoped_name fm-t1)"
    echo "herdr-session=$(fm_backend_herdr_session)"
    fm_brief_worker_role /state task-1 /code | grep -v "^Vocabulary for prose"
    fm_dod_block no-mistakes task-1 fm/task-1
  ' "$ROOT" 2>&1 | sed "s#$1#<home>#g"
}

test_a11_architectural_invariance() {
  local t base out kind home
  for kind in primary mate; do
    base=''
    home="$TMP_ROOT/a11-$kind"
    mkdir -p "$home/config" "$home/data" "$home/state"
    [ "$kind" = primary ] || printf 'gfm\n' > "$home/.fm-secondmate-home"
    for t in "$ROOT"/.agents/skills/po-theme/themes/*.theme; do
      t=$(basename "$t" .theme)
      if [ "$kind" = primary ]; then
        printf '%s\n' "$t" > "$home/config/po-theme"
      else
        "$PT" persona "$t" > "$home/data/captain-shared.md"
      fi
      out=$(routing_names "$home")
      assert_contains "$out" "cmux=fm-" "A11 produced no routing names under $t"
      assert_contains "$out" "Delivery contract: mode=no-mistakes" "A11 produced no brief sections under $t"
      if [ -z "$base" ]; then base=$out; else
        assert_equals "$base" "$out" "A11: architectural output differs under theme $t ($kind home)"
      fi
    done
  done
  pass "A11: routing names, session names, and the worker role contract are identical under every bundled theme"
}

if [ "${1:-}" = a11 ]; then
  test_a11_architectural_invariance
  exit 0
fi
test_nautical_matches_upstream
test_operator_labels
test_accept_set_adopts_and_groups
test_switch_and_back_never_duplicates
test_label_validation
test_display_strings
test_string_validation
test_registry_gates
test_anchors_name_a_lost_hook
test_a11_architectural_invariance
test_relabel_keeps_history_other_containers_use
test_relabel_secondmate_records
test_relabel_in_lab

echo "all po-theme-labels tests passed"
