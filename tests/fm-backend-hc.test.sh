#!/usr/bin/env bash
# tests/fm-backend-hc.test.sh - fake-hc-CLI unit tests for the herdr-core
# session-provider adapter (bin/backends/hc.sh) and its dispatcher arms in
# bin/fm-backend.sh. tests/fm-backend-hc-smoke.test.sh drives a real isolated
# hc core; this suite pins selection, identity, keys, liveness, and close
# behavior with a stub so it runs everywhere.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-backend-hc-tests)

# The stub answers `get` from <dir>/<address>.json (exit from <address>.exit,
# 3 = not_found when no file exists), `ls` from <dir>/ls.json, `run` with
# <dir>/run.json, and removes <address>.json on `rm` unless <dir>/rm-sticks
# exists. Every call is logged with its HC_SESSION and HC_SOCKET.
make_hc_fakebin() {  # <dir> -> echoes fakebin dir
  local fb="$1/fakebin"
  mkdir -p "$fb"
  cat > "$fb/hc" <<'SH'
#!/usr/bin/env bash
set -u
D="${FAKE_HC_DIR:?}"
{
  printf 'HC_SESSION=%s HC_SOCKET=%s' "${HC_SESSION:-}" "${HC_SOCKET:-}"
  for a in "$@"; do printf '\x1f%s' "$a"; done
  printf '\n'
} >> "$D/log"
cmd=${1:-}
last=""
for a in "$@"; do last=$a; done
case "$cmd" in
  --version) printf 'hc %s\n' "${FAKE_HC_VERSION:-0.1.20}" ;;
  server) printf '{"live":0}\n' ;;
  connect)
    IFS= read -r _req || true
    printf '{"jsonrpc":"2.0","id":1,"result":{"generation":%s}}\n' "${FAKE_HC_GENERATION:-1}"
    ;;
  ls) cat "$D/ls.json" 2>/dev/null || printf '{"terminals":[]}\n' ;;
  run) cat "$D/run.json" ;;
  get)
    [ -f "$D/$last.exit" ] && exit "$(cat "$D/$last.exit")"
    [ -f "$D/$last.json" ] || { printf '{"error":{"kind":"not_found"}}\n' >&2; exit 3; }
    cat "$D/$last.json"
    ;;
  rm) [ -e "$D/rm-sticks" ] || rm -f "$D/$last.json"; printf '{}\n' ;;
  read) printf 'screen of %s\n' "$last" ;;
  send)
    if [ -f "$D/send.exit" ]; then
      printf '{"error":{"kind":"%s"}}\n' "$(cat "$D/send.kind" 2>/dev/null || echo blocked)" >&2
      exit "$(cat "$D/send.exit")"
    fi
    cat "$D/send.json" 2>/dev/null || printf '{"started":true,"wait":{"status":"working"}}\n'
    ;;
  *) printf '{}\n' ;;
esac
SH
  chmod +x "$fb/hc"
  printf '%s\n' "$fb"
}

# Each case runs in its own shell with a fresh stub directory and home.
setup_case() {  # <name> -> sets D, FB, HOMEDIR
  D="$TMP_ROOT/$1"
  mkdir -p "$D"
  FB=$(make_hc_fakebin "$D")
  HOMEDIR="$D/home"
  mkdir -p "$HOMEDIR"
}

# hc_shell <script>: run <script> in bash with the adapter sourced against the
# stub. FM_HC_BIN pins the stub so an inherited FM_HC_BIN or an installed
# herdr-core never wins; CASE_HC_BIN overrides it for binary-resolution cases.
# HOMETAG is exported so the script can build matching labels.
hc_shell() {  # <script>
  FAKE_HC_DIR=$D PATH="$FB:$PATH" FM_HC_BIN=${CASE_HC_BIN:-$FB/hc} \
    FM_HOME=$HOMEDIR FM_ROOT_OVERRIDE=$HOMEDIR \
    HC_SESSION=fmtest bash -c '
      . "'"$FM_TEST_ROOT"'/bin/fm-backend.sh"
      fm_backend_source hc || { echo "source failed" >&2; exit 90; }
      HOMETAG=$(fm_backend_hometag)
      '"$1"
}

# terminal_json <address> <state> <task-label> <home> <fg-name> <fg-argv0>
write_terminal() {
  jq -n --arg a "$2" --arg s "$3" --arg t "$4" --arg h "$5" --arg n "$6" --arg v "$7" '
    {address: $a, state: $s, labels: {"firstmate.task": $t, "firstmate.home": $h},
     cwd: "/start", foreground: (if $n == "" then null else {name: $n, argv: [$v], cwd: "/live", pid: 1} end)}' \
    > "$1/$2.json"
}

hometag_of() {
  FM_HOME=$HOMEDIR FM_ROOT_OVERRIDE=$HOMEDIR bash -c '. "'"$FM_TEST_ROOT"'/bin/fm-backend.sh"; fm_backend_source hc; fm_backend_hometag'
}

# expect_refused <cmd...>: the command must exit nonzero.
expect_refused() {
  local rc=0
  "$@" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "expected a refusal from: ${*: -1}"
}

FM_TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

test_hc_is_spawn_capable_and_needs_app_signals() {
  local out
  # HC_TERMINAL_ID alone is never a selection: it reaches every process an hc
  # terminal starts. This env lacks the app-terminal claim defined in
  # docs/hc-backend.md "Runtime auto-detection"; an open window is irrelevant.
  out=$(bash -c '. "'"$FM_TEST_ROOT"'/bin/fm-backend.sh"
    fm_backend_validate_spawn hc && echo spawn-ok
    unset TMUX HERDR_ENV CMUX_WORKSPACE_ID TERM_PROGRAM REX_BLOCK __CFBundleIdentifier HC_TERMINAL_SOCKET
    HC_TERMINAL_ID=t7 HC_SESSION=x HERDR_APP_HOME="'"$TMP_ROOT"'/no-app-home" fm_backend_detect >/dev/null && echo detected || echo not-detected
    fm_backend_required_tools hc' 2>&1)
  assert_contains "$out" spawn-ok "hc must be spawn-capable"
  assert_contains "$out" not-detected "bare HC_TERMINAL_* markers without an app signal must not select hc"
  assert_contains "$out" "hc jq treehouse" "hc needs hc, jq and treehouse"
  pass "hc: spawn-capable, detects only on the Herdr app signals, with its tool set"
}

test_create_task_is_independent_labeled_and_refuses_duplicates() {
  local out tag
  setup_case create
  printf '{"address":"t9"}\n' > "$D/run.json"
  out=$(hc_shell 'fm_backend_hc_create_task fmtest fm-a1 /proj')
  assert_equals "$out" t9 "create_task prints the new address"
  tag=$(hometag_of)
  out=$(grep $'\x1frun\x1f' "$D/log")
  for want in HC_SESSION=fmtest --no-parent --outlive-parent --no-notify $'--cwd\x1f/proj' \
    "firstmate.task=fm-a1" "firstmate.home=$tag" "herdr.space=fm-$tag" "herdr.tab=$tag-fm-a1"; do
    assert_contains "$out" "$want" "hc run must carry $want"
  done
  printf '{"terminals":[{"address":"t9"}]}\n' > "$D/ls.json"
  : > "$D/log"
  expect_refused hc_shell 'fm_backend_hc_create_task fmtest fm-a1 /proj'
  assert_not_contains "$(cat "$D/log")" $'\x1frun\x1f' "a live duplicate must not start a second terminal"
  pass "hc: create_task starts an independent labeled terminal and refuses a duplicate"
}

test_control_interrupt_delivers_the_harness_keys() {
  local tag out rc=0 id=hcint1
  setup_case interrupt
  tag=$(hometag_of)
  write_terminal "$D" t2 live "fm-$id" "$tag" 2.1.312 claude
  mkdir -p "$HOMEDIR/state" "$HOMEDIR/data"
  printf 'window=fmtest:t2\nendpoint_task_id=%s\nworktree=%s\nproject=%s\nharness=claude\nkind=scout\nbackend=hc\nhc_session=fmtest\nhc_terminal=t2\n' \
    "$id" "$D" "$D" > "$HOMEDIR/state/$id.meta"
  out=$(FAKE_HC_DIR=$D PATH="$FB:$PATH" FM_HC_BIN="$FB/hc" FM_HOME=$HOMEDIR FM_ROOT_OVERRIDE=$HOMEDIR \
    FM_STATE_OVERRIDE="$HOMEDIR/state" FM_DATA_OVERRIDE="$HOMEDIR/data" FM_CONTROL_POLL=0.05 \
    "$FM_TEST_ROOT/bin/fm-control.sh" "$id" interrupt 2>&1) || rc=$?
  expect_code 0 "$rc" "interrupt on an hc task should succeed"$'\n'"$out"
  assert_contains "$(grep $'\x1fkeys\x1f' "$D/log")" $'keys\x1f--json\x1ft2\x1f--\x1fesc' "interrupt must press Escape on the recorded terminal"
  pass "hc: fm-control interrupt delivers the harness's interrupt key"
}

test_foreign_or_unlabeled_terminal_gets_no_input_and_no_close() {
  local tag
  setup_case foreign
  tag=$(hometag_of)
  write_terminal "$D" t3 live fm-other "$tag" zsh /bin/zsh
  write_terminal "$D" t4 live fm-a1 other-home zsh /bin/zsh
  write_terminal "$D" t5 live "" "" zsh /bin/zsh
  expect_refused hc_shell 'fm_backend_send_key hc fmtest:t3 Enter fm-a1'
  expect_refused hc_shell 'fm_backend_send_key hc fmtest:t4 Enter fm-a1'
  expect_refused hc_shell 'fm_backend_kill hc fmtest:t5'
  expect_refused hc_shell 'fm_backend_kill hc fmtest:t4'
  assert_not_contains "$(cat "$D/log")" $'\x1fkeys\x1f' "no key may reach a foreign terminal"
  assert_not_contains "$(cat "$D/log")" $'\x1fkill\x1f' "no foreign terminal may be closed"
  pass "hc: another task's, another home's, or an unlabeled terminal gets no input and no close"
}

test_invalid_session_never_reaches_hc() {
  setup_case session
  expect_refused hc_shell 'fm_backend_hc_cli "" ls'
  expect_refused hc_shell 'fm_backend_send_key hc :t2 Enter'
  assert_equals "$(cat "$D/log" 2>/dev/null)" "" "an empty or malformed session must not call hc"
  pass "hc: an empty session never falls through to the ambient core"
}

# hc 0.1.14 lets an exported HC_SOCKET win over HC_SESSION, so an inherited one
# would send every call to another core.
test_inherited_socket_never_overrides_the_session() {
  setup_case socket
  HC_SOCKET=/elsewhere/other.sock hc_shell 'fm_backend_hc_cli fmtest ls' >/dev/null
  assert_contains "$(cat "$D/log")" "HC_SESSION=fmtest HC_SOCKET="$'\x1f'"ls" "hc must run with HC_SOCKET unset"
  pass "hc: an inherited HC_SOCKET never overrides the session pin"
}

test_agent_state_classifies_foreground_and_absence() {
  local tag out
  setup_case state
  tag=$(hometag_of)
  write_terminal "$D" t1 live fm-a1 "$tag" 2.1.312 claude
  write_terminal "$D" t2 live fm-a1 "$tag" zsh /bin/zsh
  write_terminal "$D" t3 finished fm-a1 "$tag" "" ""
  write_terminal "$D" t4 live fm-a1 "$tag" node node
  write_terminal "$D" t5 live fm-a1 "$tag" "" ""
  printf '1\n' > "$D/t6.exit"
  # shellcheck disable=SC2016 # the inner shell expands it
  out=$(hc_shell 'for a in t1 t2 t3 t4 t5 t6 t7; do printf "%s=%s " $a "$(fm_backend_agent_state hc fmtest:$a)"; done')
  assert_equals "$out" "t1=alive t2=dead t3=missing t4=ambiguous t5=unreadable t6=unreadable t7=missing " \
    "agent_state over claude, shell, finished, other, no foreground, core error, not found"
  pass "hc: agent_state maps foreground, finished, not_found and core errors onto the shared vocabulary"
}

test_agent_state_reads_a_shell_wrappers_group() {
  local tag out wrapper
  setup_case wrapper
  tag=$(hometag_of)
  # A shell wrapper in its own process group, waiting on a harness child.
  set -m
  bash -c '(exec -a claude sleep 30); :' &
  wrapper=$!
  set +m
  write_terminal "$D" t9 live fm-a1 "$tag" bash bash
  jq --argjson p "$wrapper" '.foreground.pid = $p' "$D/t9.json" > "$D/t9.tmp" && mv "$D/t9.tmp" "$D/t9.json"
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -g "$wrapper" -f '^claude' >/dev/null && break; sleep 0.1; done
  out=$(hc_shell 'fm_backend_agent_state hc fmtest:t9')
  kill -- "-$wrapper" 2>/dev/null || true
  wait "$wrapper" 2>/dev/null || true
  assert_equals "$out" alive "a shell wrapper running a harness child is alive"
  pass "hc: agent_state reads a shell wrapper's process group before calling it dead"
}

test_kill_proves_the_terminal_is_gone() {
  local tag
  setup_case kill
  tag=$(hometag_of)
  write_terminal "$D" t1 live fm-a1 "$tag" zsh /bin/zsh
  hc_shell 'fm_backend_kill hc fmtest:t1' || fail "closing a live own terminal must succeed"
  assert_contains "$(cat "$D/log")" $'\x1fkill\x1f--json\x1ft1' "kill must end the program"
  assert_contains "$(cat "$D/log")" $'\x1frm\x1f--json\x1ft1' "kill must remove the terminal"
  hc_shell 'fm_backend_kill hc fmtest:t1' || fail "an already-gone terminal is a silent success"
  write_terminal "$D" t2 live fm-a1 "$tag" zsh /bin/zsh
  touch "$D/rm-sticks"
  expect_refused hc_shell 'fm_backend_kill hc fmtest:t2'
  pass "hc: kill ends and removes the terminal and refuses when it survives"
}

test_kill_refuses_another_tasks_terminal() {
  local tag
  setup_case kill-label
  tag=$(hometag_of)
  write_terminal "$D" t1 live fm-other "$tag" zsh /bin/zsh
  write_terminal "$D" t2 live fm-a1 "$tag" zsh /bin/zsh
  expect_refused hc_shell 'fm_backend_kill hc fmtest:t1 "" fm-a1'
  [ -f "$D/t1.json" ] || fail "another task's terminal must stay alive"
  assert_not_contains "$(cat "$D/log")" $'\x1fkill\x1f' "another task's terminal must not be closed"
  hc_shell 'fm_backend_kill hc fmtest:t2 "" fm-a1' || fail "closing the task's own labeled terminal must succeed"
  [ ! -f "$D/t2.json" ] || fail "the task's own terminal must be removed"
  pass "hc: teardown's expected label refuses another task's terminal and closes the matching one"
}

test_capture_and_current_path_read_the_recorded_terminal() {
  local tag out
  setup_case read
  tag=$(hometag_of)
  write_terminal "$D" t1 live fm-a1 "$tag" zsh /bin/zsh
  out=$(hc_shell 'fm_backend_capture hc fmtest:t1 40 fm-a1; fm_backend_visible_capture hc fmtest:t1 fm-a1; fm_backend_hc_current_path fmtest:t1 fm-a1')
  assert_contains "$out" "screen of t1" "capture reads the recorded terminal"
  assert_contains "$out" "/live" "current_path prefers the foreground cwd"
  assert_contains "$(cat "$D/log")" $'read\x1f--lines\x1f40\x1ft1' "capture asks for the requested history"
  assert_contains "$(cat "$D/log")" $'read\x1f--lines\x1f0\x1ft1' "visible capture reads the screen only"
  pass "hc: capture, visible capture, and current path read the recorded terminal"
}

test_endpoint_validation_binds_hc_meta() {
  local meta out
  setup_case meta
  meta="$D/a1.meta"
  printf 'window=fmtest:t4\nendpoint_task_id=a1\nworktree=/wt\nproject=/p\nbackend=hc\nhc_session=fmtest\nhc_terminal=t4\n' > "$meta"
  out=$(bash -c '. "'"$FM_TEST_ROOT"'/bin/fm-backend.sh"; fm_backend_validate_task_endpoint "'"$meta"'" a1 && echo "$FM_BACKEND_VALIDATED_BACKEND $FM_BACKEND_VALIDATED_TARGET"')
  assert_equals "$out" "hc fmtest:t4" "a consistent hc record validates to its target"
  printf 'window=fmtest:t5\nendpoint_task_id=a1\nworktree=/wt\nproject=/p\nbackend=hc\nhc_session=fmtest\nhc_terminal=t4\n' > "$meta"
  expect_refused bash -c '. "'"$FM_TEST_ROOT"'/bin/fm-backend.sh"; fm_backend_validate_task_endpoint "'"$meta"'" a1 2>/dev/null'
  pass "hc: endpoint validation requires window to equal hc_session:hc_terminal"
}

test_container_ensure_gates_binary_version_and_generation() {
  local out
  setup_case gate
  out=$(hc_shell 'fm_backend_hc_container_ensure')
  assert_equals "$out" fmtest "container_ensure prints the session after every gate passes"
  : > "$D/log"
  FAKE_HC_VERSION=0.1.19 expect_refused hc_shell 'fm_backend_hc_container_ensure'
  FAKE_HC_VERSION=bogus expect_refused hc_shell 'fm_backend_hc_container_ensure'
  FAKE_HC_GENERATION=2 expect_refused hc_shell 'fm_backend_hc_container_ensure'
  FAKE_HC_GENERATION=1 hc_shell 'fm_backend_hc_container_ensure' >/dev/null \
    || fail "generation 1 must be accepted"
  assert_contains "$(cat "$D/log")" $'\x1fconnect\x1f' "container_ensure must run the hello handshake"
  pass "hc: container_ensure refuses a misnamed, old, or wrong-generation binary"
}

test_send_text_submit_confirms_through_send_wait() {
  local tag out log
  setup_case submit
  tag=$(hometag_of)
  write_terminal "$D" t1 live fm-a1 "$tag" zsh /bin/zsh
  out=$(hc_shell 'fm_backend_hc_send_text_submit fmtest:t1 "deploy now" 3 0.4 0 fm-a1')
  assert_equals "$out" empty "a started turn confirms the submit"
  log=$(grep $'\x1fsend\x1f' "$D/log")
  assert_contains "$log" $'--wait\x1f--timeout\x1f' "submit must confirm through send --wait"
  assert_contains "$log" $'\x1f--\x1fdeploy now' "the text must arrive after the -- delimiter"
  printf '9\n' > "$D/send.exit"
  printf 'blocked\n' > "$D/send.kind"
  out=$(hc_shell 'fm_backend_hc_send_text_submit fmtest:t1 "deploy now" 3 0.4 0 fm-a1' 2>&1)
  assert_contains "$out" unknown "a blocked terminal is unknown, never forced"
  assert_contains "$out" blocked "the refusal must name the blocked cause"
  printf '11\n' > "$D/send.exit"
  out=$(hc_shell 'fm_backend_hc_send_text_submit fmtest:t1 "deploy now" 3 0.4 0 fm-a1')
  assert_equals "$out" send-failed "a finished terminal is send-failed"
  printf '3\n' > "$D/send.exit"
  out=$(hc_shell 'fm_backend_hc_send_text_submit fmtest:t1 "deploy now" 3 0.4 0 fm-a1')
  assert_equals "$out" send-failed "a missing terminal is send-failed"
  rm -f "$D/send.exit" "$D/send.kind"
  printf '{"started":null,"wait":{"status":"idle","timed_out":true}}\n' > "$D/send.json"
  out=$(hc_shell 'fm_backend_hc_send_text_submit fmtest:t1 "deploy now" 3 0.4 0 fm-a1')
  assert_equals "$out" unknown "a silent program falls back to the composer screen, which cannot prove empty on a plain pane"
  pass "hc: send_text_submit proves the turn through send --wait and never forces a blocked terminal"
}

test_send_delimiters_and_binary_socket_pins() {
  local tag out
  setup_case pins
  tag=$(hometag_of)
  write_terminal "$D" t1 live fm-a1 "$tag" zsh /bin/zsh
  hc_shell 'fm_backend_hc_send_text_line fmtest:t1 "-rf / --force" fm-a1' \
    || fail "send_text_line must accept flag-looking text"
  assert_contains "$(cat "$D/log")" $'send\x1f--json\x1ft1\x1f--\x1f-rf / --force' \
    "flag-looking text must arrive after the -- delimiter"
  out=$(FM_HC_SOCKET=/tmp/pinned.sock hc_shell 'fm_backend_hc_cli fmtest ls'; cat "$D/log")
  assert_contains "$out" "HC_SOCKET=/tmp/pinned.sock" "FM_HC_SOCKET must pin the socket for the call"
  CASE_HC_BIN=/nonexistent/hc expect_refused hc_shell 'fm_backend_hc_cli fmtest ls'
  mkdir -p "$D/pinned"
  cp "$FB/hc" "$D/pinned/hc"
  out=$(CASE_HC_BIN="$D/pinned/hc" hc_shell 'fm_backend_hc_bin')
  assert_equals "$out" "$D/pinned/hc" "FM_HC_BIN must win over an hc on PATH"
  pass "hc: send text is -- delimited, and FM_HC_BIN/FM_HC_SOCKET pin the call"
}

test_required_tool_check_uses_the_adapter_resolver() {
  local out
  setup_case tools
  mkdir -p "$D/core-only" "$D/none"
  cp "$FB/hc" "$D/core-only/herdr-core"
  out=$(env -u FM_HC_BIN PATH="$D/core-only:/usr/bin:/bin" "$BASH" -c '
    . "'"$FM_TEST_ROOT"'/bin/fm-backend.sh"
    fm_backend_required_tool_available hc hc && echo core-only-ok' 2>&1)
  assert_contains "$out" core-only-ok "a herdr-core-only install must satisfy the hc tool check"
  out=$(FM_HC_BIN="$FB/hc" PATH="$D/none:/usr/bin:/bin" "$BASH" -c '
    . "'"$FM_TEST_ROOT"'/bin/fm-backend.sh"
    fm_backend_required_tool_available hc hc && echo pinned-ok' 2>&1)
  assert_contains "$out" pinned-ok "an FM_HC_BIN-only install must satisfy the hc tool check"
  out=$(FM_HC_BIN=/nonexistent/hc PATH="$FB:/usr/bin:/bin" "$BASH" -c '
    . "'"$FM_TEST_ROOT"'/bin/fm-backend.sh"
    fm_backend_required_tool_available hc hc && echo found || echo missing' 2>&1)
  assert_contains "$out" missing "an unusable FM_HC_BIN must report hc missing even with hc on PATH"
  pass "hc: the bootstrap tool check resolves hc exactly as the adapter does"
}

# --- lifecycle-modelling fake for spawn, control, restart, and recovery -------
#
# make_hc_life_fakebin models just enough of a core for the real fm-spawn,
# fm-control, fm-secondmate-restart, and liveness paths: terminals are
# <dir>/term/<address>.json records that `run` creates, `kill` finishes, and
# `rm` deletes; `ls` filters them by label (finished ones only with --all);
# `server status` reports <dir>/core-id as the core's identity. `send` stages
# the agent lifecycle the same way the tmux fakes do: a launch brief makes the
# terminal's foreground the harness in <dir>/becomes, the harness exit command
# turns it back into a shell, and `cd -- <path>` moves the foreground cwd. A
# doorbell is answered on the parent channel when <dir>/answer-inbox is armed.
make_hc_life_fakebin() {  # <dir> -> echoes fakebin dir
  local fb="$1/fakebin"
  mkdir -p "$fb" "$1/term"
  printf 'core-a' > "$1/core-id"
  printf 'claude' > "$1/becomes"
  printf '1' > "$1/next"
  cat > "$fb/hc" <<'SH'
#!/usr/bin/env bash
set -u
D="${FAKE_HC_DIR:?}"
{
  printf 'HC_SESSION=%s' "${HC_SESSION:-}"
  for a in "$@"; do printf '\x1f%s' "$a"; done
  printf '\n'
} >> "$D/log"
cmd=${1:-}
[ "$#" -eq 0 ] || shift
term() { printf '%s/term/%s.json' "$D" "$1"; }
set_fg() {  # <address> <name> <argv0> [cwd]
  local f tmp
  f=$(term "$1")
  tmp="$f.tmp"
  jq --arg n "$2" --arg v "$3" --arg c "${4:-}" '
    .foreground = {name: $n, argv: [$v], cwd: (if $c == "" then .foreground.cwd else $c end), pid: (if $n == "zsh" then 999999 else 1 end)}' \
    "$f" > "$tmp" && mv "$tmp" "$f"
}
case "$cmd" in
  --version) printf 'hc %s\n' "${FAKE_HC_VERSION:-0.1.20}" ;;
  server)
    printf '{"core":{"id":"%s","name":"fake"},"live":0,"pid":1,"version":"%s"}\n' \
      "$(cat "$D/core-id")" "${FAKE_HC_VERSION:-0.1.20}"
    ;;
  connect)
    IFS= read -r _req || true
    printf '{"jsonrpc":"2.0","id":1,"result":{"generation":1}}\n'
    ;;
  ls)
    all=0
    filter='true'
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --all) all=1 ;;
        --label) filter="$filter and (.labels[\"${2%%=*}\"] == \"${2#*=}\")"; shift ;;
      esac
      shift
    done
    {
      for f in "$D"/term/*.json; do [ -e "$f" ] && cat "$f"; done
    } | jq -s --argjson all "$all" "{terminals: [.[] | select($filter) | select(\$all == 1 or .state == \"live\") | {address, state}]}"
    ;;
  run)
    cwd=/
    labels='{}'
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --cwd) cwd=$2; shift ;;
        --label) labels=$(printf '%s' "$labels" | jq --arg k "${2%%=*}" --arg v "${2#*=}" '. + {($k): $v}'); shift ;;
      esac
      shift
    done
    n=$(cat "$D/next")
    printf '%s' "$((n + 1))" > "$D/next"
    jq -n --arg a "t$n" --arg c "$cwd" --argjson l "$labels" \
      '{address: $a, state: "live", labels: $l, cwd: $c, foreground: {name: "zsh", argv: ["/bin/zsh"], cwd: $c, pid: 999999}}' \
      > "$(term "t$n")"
    printf '%s t%s\n' "$cwd" "$n" >> "$D/created"
    printf '{"address":"t%s"}\n' "$n"
    ;;
  get)
    for a in "$@"; do last=$a; done
    [ -f "$(term "$last")" ] || { printf '{"error":{"kind":"not_found"}}\n' >&2; exit 3; }
    cat "$(term "$last")"
    ;;
  rm)
    for a in "$@"; do last=$a; done
    [ -f "$(term "$last")" ] || exit 3
    rm -f "$(term "$last")"
    printf '{"removed":"%s"}\n' "$last"
    ;;
  kill)
    for a in "$@"; do last=$a; done
    f=$(term "$last")
    jq '.state = "finished" | .foreground = null' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    printf '{}\n'
    ;;
  read) printf '╭────╮\n│    │\n╰────╯\n' ;;
  keys) printf '{}\n' ;;
  send)
    addr=
    wait=0
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --json) ;;
        --wait) wait=1 ;;
        --timeout) shift ;;
        --) shift; break ;;
        *) addr=$1 ;;
      esac
      shift
    done
    payload=${1:-}
    [ -f "$(term "$addr")" ] || exit 3
    [ "$(jq -r .state "$(term "$addr")")" = live ] || exit 11
    case "$payload" in
      ". '"*"'") staged=${payload#". '"}; staged=${staged%"'"}; [ ! -f "$staged" ] || payload=$(cat "$staged") ;;
    esac
    printf '%s\n' "$payload" >> "$D/sent.$addr"
    case "$payload" in
      'cd -- '*)
        eval "set -- $payload"
        set_fg "$addr" zsh /bin/zsh "$3"
        ;;
      /exit|/quit) set_fg "$addr" zsh /bin/zsh ;;
      *'encode launch-brief'* | *'Firstmate operational input waiting: read'*)
        set_fg "$addr" 2.1.312 "$(cat "$D/becomes")"
        ;;
      ': Firstmate instruction waiting: list '*)
        if [ -f "$D/answer-inbox" ]; then
          corr=$(cat "$(cat "$D/answer-inbox")"/*.msg 2>/dev/null | grep -oE 'corr=[0-9a-f]{16}' | head -1)
          [ -z "$corr" ] || printf 'done [%s]: open records written down\n' "$corr" >> "$(cat "$D/answer-status")"
        fi
        ;;
    esac
    if [ "$wait" = 1 ]; then printf '{"started":true,"wait":{"status":"working"}}\n'; else printf '{}\n'; fi
    ;;
  *) printf '{}\n' ;;
esac
SH
  chmod +x "$fb/hc"
  # Claude's session listing reports no background session, so exit and
  # relaunch never consult a real Claude daemon.
  cat > "$fb/claude" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" != agents ] || printf '[]\n'
exit 0
SH
  chmod +x "$fb/claude"
  cat > "$fb/sleep" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in ''|*[!0-9.]*) ;; *) /bin/sleep 0.01 ;; esac
exit 0
SH
  chmod +x "$fb/sleep"
  printf '%s\n' "$fb"
}

# life_case <name>: fresh lifecycle world with a primary home. Sets D, FB, HOMEDIR.
life_case() {
  D="$TMP_ROOT/$1"
  mkdir -p "$D/home/state" "$D/home/data" "$D/home/config" "$D/user-home"
  FB=$(make_hc_life_fakebin "$D")
  HOMEDIR="$D/home"
  printf 'claude\n' > "$HOMEDIR/config/secondmate-harness"
  touch "$HOMEDIR/state/.last-watcher-beat"
}

# life_env <cmd...>: run a real Firstmate command against the lifecycle fake,
# with no ambient multiplexer, hc terminal, or real Claude store in reach.
life_env() {
  env -u TMUX -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_SESSION -u HC_TERMINAL_ID \
    -u HC_TERMINAL_SOCKET -u HC_SCOPE -u HC_SOCKET -u FM_HC_SOCKET -u FM_HC_SPACE \
    FAKE_HC_DIR="$D" PATH="$FB:$PATH" FM_HC_BIN="$FB/hc" HC_SESSION=fmtest \
    FM_HOME="$HOMEDIR" FM_ROOT_OVERRIDE='' HOME="$D/user-home" CLAUDE_CONFIG_DIR='' \
    FM_STATE_OVERRIDE="$HOMEDIR/state" FM_DATA_OVERRIDE="$HOMEDIR/data" \
    FM_CONFIG_OVERRIDE="$HOMEDIR/config" FM_PROJECTS_OVERRIDE="$HOMEDIR/projects" \
    FM_SPAWN_NO_GUARD=1 FM_CONTROL_POLL=0.01 FM_CONTROL_EXIT_WAIT=0.5 FM_CONTROL_LAUNCH_WAIT=0.5 \
    FM_SECONDMATE_PERSIST_POLL=1 FM_SECONDMATE_PERSIST_WAIT="${FM_TEST_PERSIST_WAIT:-30}" \
    "$@" 2>&1
}

# tag_of <home>: the home tag a process with FM_HOME=<home> derives, with FM_ROOT
# resolved as life_env resolves it (the code root) or as a secondmate's own
# processes do (the home itself) when <root> is given.
tag_of() {  # <home> [root]
  FM_HOME=$1 FM_ROOT_OVERRIDE=${2:-} bash -c '. "'"$FM_TEST_ROOT"'/bin/fm-backend.sh"; fm_backend_source hc; fm_backend_hometag'
}

# seed_life_secondmate <id>: a Firstmate-seeded secondmate home beside HOMEDIR.
seed_life_secondmate() {  # <id> -> echoes home
  local id=$1 sm="$D/$1-home"
  mkdir -p "$sm/bin" "$sm/data" "$sm/state" "$sm/config" "$sm/projects"
  cp "$FM_TEST_ROOT/bin/fm-turnend-guard.sh" "$sm/bin/fm-turnend-guard.sh"
  printf '# Firstmate\n' > "$sm/AGENTS.md"
  printf '%s\n' "$id" > "$sm/.fm-secondmate-home"
  printf 'charter\n' > "$sm/data/charter.md"
  fm_git_init_commit "$sm" >/dev/null
  printf '%s\n' "$sm"
}

# put_terminal <address> <state> <task-label> <home-tag> <fg-name> <fg-argv0> <cwd>
put_terminal() {
  jq -n --arg a "$1" --arg s "$2" --arg t "$3" --arg h "$4" --arg n "$5" --arg v "$6" --arg c "$7" '
    {address: $a, state: $s, labels: {"firstmate.task": $t, "firstmate.home": $h}, cwd: $c,
     foreground: (if $n == "" then null else {name: $n, argv: [$v], cwd: $c, pid: (if $n == "zsh" then 999999 else 1 end)} end)}' \
    > "$D/term/$1.json"
}

# hc_life_meta <id> <kind> <address> <worktree> [extra key=val...]
hc_life_meta() {
  local id=$1 kind=$2 addr=$3 wt=$4
  shift 4
  {
    echo "window=fmtest:$addr"
    echo "endpoint_task_id=$id"
    echo "worktree=$wt"
    echo "project=$wt"
    echo "harness=claude"
    echo "kind=$kind"
    echo "model=default"
    echo "effort=default"
    echo "backend=hc"
    echo "hc_session=fmtest"
    echo "hc_terminal=$addr"
    echo "hc_core=core-a"
    for kv in "$@"; do echo "$kv"; done
  } > "$HOMEDIR/state/$id.meta"
}

# hc_life_ship <id> <address> <fg-name> <fg-argv0>: a ship task on the fake core.
hc_life_ship() {  # -> sets WT
  local id=$1
  WT="$D/wt-$id"
  fm_git_worktree "$D/proj-$id" "$WT" "task-$id" >/dev/null
  mkdir -p "$HOMEDIR/data/$id"
  printf '# Task\n## Captain'"'"'s intent\nExercise hc control for %s.\n\n## Firstmate spec\nKeep the task whole.\n' "$id" \
    > "$HOMEDIR/data/$id/brief.md"
  hc_life_meta "$id" ship "$2" "$WT" mode=no-mistakes yolo=off "tasktmp=$D/tmp-$id"
  sed -i.bak "s#^project=.*#project=$D/proj-$id#" "$HOMEDIR/state/$id.meta" && rm -f "$HOMEDIR/state/$id.meta.bak"
  put_terminal "$2" live "fm-$id" "$(tag_of "$HOMEDIR")" "$3" "$4" "$WT"
}

meta_of() {  # <id> <key>
  grep "^$2=" "$HOMEDIR/state/$1.meta" | tail -1 | cut -d= -f2-
}

# --- (a) a --secondmate spawn launches on hc ---------------------------------
test_secondmate_spawn_launches_on_hc_in_its_own_app_space() {
  local sm out rc=0 run_line ptag smtag
  life_case sm-spawn
  sm=$(seed_life_secondmate nav1)
  out=$(life_env "$FM_TEST_ROOT/bin/fm-spawn.sh" nav1 "$sm" claude --secondmate --backend hc) || rc=$?
  expect_code 0 "$rc" "a --secondmate spawn on hc should launch"$'\n'"$out"
  assert_contains "$out" "kind=secondmate" "the spawn must report a secondmate"
  assert_equals hc "$(meta_of nav1 backend)" "the mate's record must name the hc backend"
  assert_equals fmtest "$(meta_of nav1 hc_session)" "the mate's record must name its core session"
  assert_equals core-a "$(meta_of nav1 hc_core)" "the mate's record must name the core it was created on"
  assert_equals "fmtest:$(meta_of nav1 hc_terminal)" "$(meta_of nav1 window)" "window must equal hc_session:hc_terminal"
  assert_equals "$sm" "$(meta_of nav1 home)" "the record must name the mate's home"
  ptag=$(tag_of "$HOMEDIR")
  smtag=$(tag_of "$sm" "$sm")
  run_line=$(grep $'\x1frun\x1f' "$D/log")
  assert_contains "$run_line" $'--cwd\x1f'"$sm" "the mate's terminal must start in its own home"
  assert_contains "$run_line" "firstmate.task=fm-nav1" "the terminal must carry the mate's task label"
  assert_contains "$run_line" "firstmate.home=$ptag" "the terminal must carry the owning (launching) home's label"
  assert_contains "$run_line" "herdr.space=fm-$smtag" "the mate must get its own Herdr app space, shared with its crew"
  assert_contains "$run_line" "herdr.tab=$ptag-fm-nav1" "the mate must get one Herdr app tab"
  assert_contains "$(cat "$D/sent.$(meta_of nav1 hc_terminal)")" "Firstmate operational input waiting: read" \
    "the mate's launch must be delivered into its terminal"
  pass "hc: a --secondmate spawn launches into its own Herdr app space with the owner's identity labels"
}

# --- (b) recovery-grade exit and relaunch on an hc task ----------------------
test_control_exit_stops_an_hc_agent_and_keeps_its_terminal() {
  local out rc=0
  life_case exit-live
  hc_life_ship hx1 t5 2.1.312 claude
  out=$(life_env "$FM_TEST_ROOT/bin/fm-control.sh" hx1 exit) || rc=$?
  expect_code 0 "$rc" "exit on a live hc agent should stop it"$'\n'"$out"
  assert_contains "$out" "stopped hx1" "exit must report the agent stopped"
  assert_contains "$(cat "$D/sent.t5")" "/exit" "exit must submit the harness exit command into the recorded terminal"
  assert_equals live "$(jq -r .state "$D/term/t5.json")" "exit must preserve the terminal"
  assert_equals "fmtest:t5" "$(meta_of hx1 window)" "exit must leave the record's endpoint alone"
  pass "hc: fm-control exit stops the agent and preserves its terminal"
}

test_control_exit_proves_a_finished_terminal_gone_on_the_recorded_core() {
  local out rc=0
  life_case exit-gone
  hc_life_ship hx2 t6 "" ""
  jq '.state = "finished"' "$D/term/t6.json" > "$D/t6.tmp" && mv "$D/t6.tmp" "$D/term/t6.json"
  out=$(life_env "$FM_TEST_ROOT/bin/fm-control.sh" hx2 exit) || rc=$?
  expect_code 0 "$rc" "a finished terminal on the recorded core is a proven-gone endpoint"$'\n'"$out"
  assert_contains "$out" "endpoint-gone hx2" "exit must report the endpoint gone, not already-stopped"
  pass "hc: fm-control exit proves a finished terminal gone on the core the record names"
}

test_control_refuses_absence_read_from_another_core() {
  local out rc=0 verb
  for verb in exit relaunch; do
    life_case "foreign-core-$verb"
    hc_life_ship hx3 t6 "" ""
    rm -f "$D/term/t6.json"
    # The session name now reaches a different core (another state root, say),
    # whose not_found says nothing about the core the task was created on.
    printf 'core-b' > "$D/core-id"
    rc=0
    if [ "$verb" = exit ]; then
      out=$(life_env "$FM_TEST_ROOT/bin/fm-control.sh" hx3 exit) || rc=$?
    else
      out=$(life_env "$FM_TEST_ROOT/bin/fm-control.sh" hx3 relaunch --note "moved") || rc=$?
    fi
    [ "$rc" -ne 0 ] || fail "$verb must refuse a not-found read from a core other than the recorded one"$'\n'"$out"
    assert_contains "$out" "core" "the $verb refusal must name the core identity mismatch"
    assert_absent "$D/created" "$verb must not create a terminal on an unproven absence"
    assert_equals "fmtest:t6" "$(meta_of hx3 window)" "$verb must leave the record untouched"
  done
  pass "hc: exit and relaunch refuse an absence read from a core other than the recorded one"
}

test_control_relaunch_replaces_the_agent_in_the_same_terminal() {
  local out rc=0 sent
  life_case relaunch-adopt
  hc_life_ship hx4 t7 2.1.312 claude
  out=$(life_env "$FM_TEST_ROOT/bin/fm-control.sh" hx4 relaunch --note "context ran out") || rc=$?
  expect_code 0 "$rc" "relaunch on an hc task should replace its agent"$'\n'"$out"
  assert_contains "$out" "relaunched hx4" "relaunch must report the replacement"
  assert_contains "$out" "endpoint=fmtest:t7" "the replacement must run in the same terminal"
  assert_absent "$D/created" "an adopted relaunch must not create a second terminal"
  sent=$(cat "$D/sent.t7")
  assert_contains "$sent" "/exit" "the old agent must be stopped first"
  assert_contains "$sent" "Firstmate operational input waiting: read" "the replacement must be launched into the same terminal"
  assert_equals "fmtest:t7" "$(meta_of hx4 window)" "the record must keep its endpoint"
  assert_equals t7 "$(meta_of hx4 hc_terminal)" "the record must keep its terminal"
  assert_equals core-a "$(meta_of hx4 hc_core)" "the record must keep its core identity"
  pass "hc: fm-control relaunch replaces the agent inside the same terminal"
}

test_relaunch_rebinds_a_finished_terminal_on_the_recorded_core() {
  local out rc=0 new
  life_case relaunch-rebind
  hc_life_ship hx5 t8 "" ""
  jq '.state = "finished"' "$D/term/t8.json" > "$D/t8.tmp" && mv "$D/t8.tmp" "$D/term/t8.json"
  out=$(life_env "$FM_TEST_ROOT/bin/fm-control.sh" hx5 relaunch --note "terminal ended") || rc=$?
  expect_code 0 "$rc" "relaunch should re-create a proven-gone hc terminal"$'\n'"$out"
  new=$(meta_of hx5 hc_terminal)
  assert_not_equals t8 "$new" "the record must rebind to a fresh terminal"
  assert_equals "fmtest:$new" "$(meta_of hx5 window)" "window must follow the rebind"
  assert_equals fmtest "$(meta_of hx5 hc_session)" "the rebind must stay in the recorded session"
  assert_equals core-a "$(meta_of hx5 hc_core)" "the rebind must stay on the recorded core"
  assert_contains "$(cat "$D/created")" "$WT $new" "the fresh terminal must open in the recorded worktree"
  assert_absent "$D/term/t8.json" "the finished predecessor carrying this task's labels must be removed"
  assert_contains "$(cat "$D/sent.$new")" "Firstmate operational input waiting: read" "the replacement must launch in the fresh terminal"
  pass "hc: relaunch re-creates a proven-gone terminal in the recorded session on the recorded core"
}

# --- (c) navigator restart and recovery on hc --------------------------------
hc_life_mate() {  # <id> <address> <fg-name> <fg-argv0> -> sets SM
  local id=$1
  SM=$(seed_life_secondmate "$id")
  mkdir -p "$HOMEDIR/data/$id"
  printf '# charter\n' > "$HOMEDIR/data/$id/brief.md"
  hc_life_meta "$id" secondmate "$2" "$SM" mode=secondmate yolo=off "home=$SM" projects=
  put_terminal "$2" live "fm-$id" "$(tag_of "$HOMEDIR")" "$3" "$4" "$SM"
}

test_secondmate_restart_persists_then_relaunches_on_hc() {
  local out rc=0 sent
  life_case sm-restart
  hc_life_mate nav2 t4 2.1.312 claude
  printf '%s' "$HOMEDIR/state/nav2.inbox" > "$D/answer-inbox"
  printf '%s' "$HOMEDIR/state/nav2.status" > "$D/answer-status"
  out=$(life_env "$FM_TEST_ROOT/bin/fm-secondmate-restart.sh" nav2) || rc=$?
  expect_code 0 "$rc" "a navigator on hc should restart"$'\n'"$out"
  assert_contains "$out" "restarted: nav2" "the restart must report the navigator restarted"
  sent=$(cat "$D/sent.t4")
  assert_contains "$sent" "/exit" "the old navigator agent must be stopped"
  assert_contains "$sent" "Firstmate operational input waiting: read" "the replacement navigator must launch in the same terminal"
  assert_equals "fmtest:t4" "$(meta_of nav2 window)" "the navigator keeps its terminal across a restart"
  pass "hc: fm-secondmate-restart persists then relaunches a navigator in its terminal"
}

test_secondmate_liveness_recovers_a_finished_hc_navigator() {
  local out
  life_case sm-recover
  hc_life_mate nav3 t3 "" ""
  jq '.state = "finished"' "$D/term/t3.json" > "$D/t3.tmp" && mv "$D/t3.tmp" "$D/term/t3.json"
  # shellcheck disable=SC2016 # positional params expand in the child shell.
  out=$(life_env env FM_ROOT="$FM_TEST_ROOT" STATE="$HOMEDIR/state" bash -c '
    . "$1/bin/fm-secondmate-liveness-lib.sh"
    fm_secondmate_liveness_probe "$2" nav3 poll
    echo "probe=$FM_SM_LIVE_STATUS/$FM_SM_LIVE_STATE"
    rc=0
    fm_secondmate_liveness_relaunch "$2" nav3 || rc=$?
    echo "relaunch=rc$rc"
    [ "$rc" -eq 0 ] || printf "%s\n" "$FM_SM_LIVE_OUT"
  ' _ "$FM_TEST_ROOT" "$HOMEDIR/state/nav3.meta")
  assert_contains "$out" "probe=relaunchable/missing" "a finished navigator terminal must read relaunchable"
  assert_contains "$out" "relaunch=rc0" "the liveness relaunch must respawn the navigator on hc"
  assert_equals hc "$(meta_of nav3 backend)" "the respawned navigator must stay on hc"
  assert_not_equals t3 "$(meta_of nav3 hc_terminal)" "the navigator must get a fresh terminal"
  assert_absent "$D/term/t3.json" "the finished predecessor must not linger beside the respawned navigator"
  pass "hc: the secondmate liveness path respawns a finished navigator on hc"
}

test_secondmate_liveness_refuses_an_absence_read_from_another_core() {
  local out
  life_case sm-foreign-core
  hc_life_mate nav5 t3 "" ""
  rm -f "$D/term/t3.json"
  # The recorded session name now reaches a different core, whose not_found
  # says nothing about the live navigator on the core the record names.
  printf 'core-b' > "$D/core-id"
  # shellcheck disable=SC2016 # positional params expand in the child shell.
  out=$(life_env env FM_ROOT="$FM_TEST_ROOT" STATE="$HOMEDIR/state" bash -c '
    . "$1/bin/fm-secondmate-liveness-lib.sh"
    fm_secondmate_liveness_probe "$2" nav5 poll
    echo "probe=$FM_SM_LIVE_STATUS/$FM_SM_LIVE_STATE"
    echo "reason=$FM_SM_LIVE_REASON"
    if [ "$FM_SM_LIVE_STATUS" = relaunchable ]; then
      fm_secondmate_liveness_relaunch "$2" nav5 || true
    fi
  ' _ "$FM_TEST_ROOT" "$HOMEDIR/state/nav5.meta")
  assert_contains "$out" "probe=skipped/unproven" "a not_found from another core must not read relaunchable"$'\n'"$out"
  assert_contains "$out" "a core other than the one the task was created on" "the refusal must name the core identity mismatch"
  assert_absent "$D/created" "no replacement navigator may be created on an unproven absence"
  assert_equals "fmtest:t3" "$(meta_of nav5 window)" "the navigator record must be left untouched"
  assert_equals core-a "$(meta_of nav5 hc_core)" "the navigator record must keep its core identity"
  pass "hc: the secondmate liveness path refuses an absence read from a core other than the recorded one"
}

# Retiring a navigator closes its crew too. Those workers were spawned from
# inside the navigator's own home, so their terminals carry that home's tag.
test_forced_secondmate_teardown_closes_hc_children_with_the_child_home_tag() {
  local out rc=0
  life_case sm-teardown
  hc_life_mate nav4 t2 "" ""
  hc_life_meta_in "$SM" kid1 t6
  put_terminal t6 live fm-kid1 "$(tag_of "$SM" "$SM")" zsh /bin/zsh "$D"
  out=$(life_env "$FM_TEST_ROOT/bin/fm-teardown.sh" nav4 --force) || rc=$?
  expect_code 0 "$rc" "force-retiring an hc navigator with an hc worker should succeed"$'\n'"$out"
  assert_absent "$D/term/t6.json" "the navigator's worker terminal must be closed as its own home"
  assert_absent "$D/term/t2.json" "the navigator's own terminal must be closed"
  pass "hc: force-retiring a navigator closes its hc workers using the worker home's tag"
}

# hc_life_meta_in <home> <id> <address>: a scout record inside another home.
hc_life_meta_in() {
  {
    echo "window=fmtest:$3"
    echo "endpoint_task_id=$2"
    echo "worktree=$D/missing-$2-worktree"
    echo "project=$D"
    echo "harness=claude"
    echo "kind=scout"
    echo "backend=hc"
    echo "hc_session=fmtest"
    echo "hc_terminal=$3"
    echo "hc_core=core-a"
  } > "$1/state/$2.meta"
}

fm_test_run \
  test_secondmate_spawn_launches_on_hc_in_its_own_app_space \
  test_control_exit_stops_an_hc_agent_and_keeps_its_terminal \
  test_control_exit_proves_a_finished_terminal_gone_on_the_recorded_core \
  test_control_refuses_absence_read_from_another_core \
  test_control_relaunch_replaces_the_agent_in_the_same_terminal \
  test_relaunch_rebinds_a_finished_terminal_on_the_recorded_core \
  test_secondmate_restart_persists_then_relaunches_on_hc \
  test_secondmate_liveness_recovers_a_finished_hc_navigator \
  test_secondmate_liveness_refuses_an_absence_read_from_another_core \
  test_forced_secondmate_teardown_closes_hc_children_with_the_child_home_tag \
  test_hc_is_spawn_capable_and_needs_app_signals \
  test_required_tool_check_uses_the_adapter_resolver \
  test_create_task_is_independent_labeled_and_refuses_duplicates \
  test_control_interrupt_delivers_the_harness_keys \
  test_foreign_or_unlabeled_terminal_gets_no_input_and_no_close \
  test_invalid_session_never_reaches_hc \
  test_inherited_socket_never_overrides_the_session \
  test_agent_state_classifies_foreground_and_absence \
  test_agent_state_reads_a_shell_wrappers_group \
  test_kill_proves_the_terminal_is_gone \
  test_kill_refuses_another_tasks_terminal \
  test_capture_and_current_path_read_the_recorded_terminal \
  test_endpoint_validation_binds_hc_meta \
  test_container_ensure_gates_binary_version_and_generation \
  test_send_text_submit_confirms_through_send_wait \
  test_send_delimiters_and_binary_socket_pins
