#!/usr/bin/env bash
# Default-on live guard for the two Claude Code agent-view surfaces Firstmate
# depends on, checked against the INSTALLED claude:
#
#   1. bin/fm-spawn.sh puts "disableAgentView": true in every Claude launch's
#      --settings value so a Firstmate-launched agent cannot be sent to the
#      background (/background, --bg, agent view, the on-demand daemon). The
#      guard proves a --settings value carrying that key reaches Claude's own
#      agent-view gate: `claude agents` refuses under it, naming the setting,
#      and lists sessions without it.
#   2. bin/fm-control.sh refuses exit and relaunch for a Claude agent that
#      `claude agents --json --cwd <dir>` reports as kind "background", reading
#      kind, pid, cwd, and id or sessionId. The guard proves the listing is a
#      JSON array and that every entry it holds carries those fields.
#
# Only the read-only session listing is run: no prompt is submitted and no
# session is created, stopped, or sent to the background, so the shared live
# gate runs it by default wherever claude and jq are installed. Run it after
# every Claude Code upgrade and before trusting the dated "Claude Code agent
# view" entry in docs/verification/runtime-backends.md.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fm_live_gate default-on FM_CLAUDE_AGENT_VIEW_LIVE_E2E claude jq

VERSION=$(claude --version 2>/dev/null | head -1)
[ -n "$VERSION" ] || fail "claude is installed but reported no version"
TMP_ROOT=$(fm_test_tmproot fm-claude-agent-view)
mkdir -p "$TMP_ROOT/cwd"
CWD=$(cd "$TMP_ROOT/cwd" && pwd -P)

# An ambient disable would make the unset case refuse too and prove nothing.
unset CLAUDE_CODE_DISABLE_AGENT_VIEW

disabled_out=$(cd "$CWD" && claude --settings '{"disableAgentView":true}' agents --json --cwd "$CWD" </dev/null 2>&1)
if printf '%s' "$disabled_out" | jq -e 'type == "array"' >/dev/null 2>&1; then
  fail "claude $VERSION: a --settings value with disableAgentView still listed sessions, so Firstmate's launch setting no longer disables agent view: $disabled_out"
fi
assert_contains "$disabled_out" "disableAgentView" \
  "claude $VERSION: the agent-view refusal under --settings no longer names the setting"

listing=$(cd "$CWD" && claude agents --json --cwd "$CWD" </dev/null 2>/dev/null) \
  || fail "claude $VERSION: 'claude agents --json --cwd' failed without the setting; check that agent view is not disabled in user or managed settings"
printf '%s' "$listing" | jq -e 'type == "array"' >/dev/null 2>&1 \
  || fail "claude $VERSION: 'claude agents --json' no longer prints a JSON array: $listing"

all=$(claude agents --json </dev/null 2>/dev/null) || all='[]'
count=$(printf '%s' "$all" | jq 'length' 2>/dev/null) || count=0
if [ "$count" -gt 0 ]; then
  printf '%s' "$all" | jq -e 'all(.[]; (.kind | type) == "string" and (.pid | type) == "number" and (.cwd | type) == "string" and ((.id // .sessionId) | type) == "string")' >/dev/null \
    || fail "claude $VERSION: a listed session lacks kind, pid, cwd, or id/sessionId: $all"
  pass "claude $VERSION: $count listed session(s) carry the kind, pid, cwd, and id fields the background check reads"
else
  printf 'note: claude %s: no live session to check the listing fields against\n' "$VERSION"
fi

pass "claude $VERSION: a disableAgentView --settings value disables agent view, and the session listing is a JSON array"
