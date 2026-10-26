#!/usr/bin/env bash
# tests/po-crew.test.sh - behavior tests for bin/po-crew.sh (ADR-0019).
#
# Coverage:
#   - fence writes the five disabled entries into a fresh home
#   - fence preserves every other key, backs up once under state/po-crew,
#     overrides an enabled entry, is idempotent, and leaves malformed JSON
#     untouched
#   - fence skips a secondmate home and writes nothing there
#   - check passes on a complete install with stub claude, codex, and pi, and
#     reports a missing, disabled, or behind plugin, a missing catalogue, an
#     absent tool, and a missing fence as the right rows, and warns without
#     failing when a Codex cache directory is not a git checkout
#   - check compares against the published catalogue a stub gh serves, so a
#     re-pin the local copy lacks reads as behind, and falls back to the local
#     copy with one warn row when gh is absent, fails, or serves malformed JSON
#
# Every tool is a stub on PATH and every tool state path is a fixture, so no
# case reads or writes this machine's real install or operator home, and no
# case reaches the network: gh is absent unless a case stubs it.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PC="$ROOT/bin/po-crew.sh"
BASE_PATH=${FM_TEST_BASE_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}
TMP_ROOT=$(fm_test_tmproot po-crew-tests)
FM_TEST_CLEANUP_DIRS+=("$TMP_ROOT")
trap fm_test_cleanup EXIT
fm_git_identity fmtest fmtest@example.invalid

PLUGINS='crew infra-skills planning-skills identity-skills language-skills'

# The only real tools on PATH are jq and git, so an absent stub reads as an
# absent tool even on a machine that has the real one.
TOOLBIN="$TMP_ROOT/toolbin"
mkdir -p "$TOOLBIN"
ln -s "$(command -v jq)" "$TOOLBIN/jq"
ln -s "$(command -v git)" "$TOOLBIN/git"

new_home() {  # <name>: a primary home that is a git work tree
  local home="$TMP_ROOT/$1/home"
  fm_git_init_commit "$home" >/dev/null
  printf '%s\n' "$home"
}

settings() { printf '%s\n' "$1/.claude/settings.local.json"; }
backup() { printf '%s\n' "$1/state/po-crew/settings.local.json.bak"; }

fenced() {  # <file>: exit 0 when all five entries are false
  jq -e '(.enabledPlugins // {}) as $e | all("crew","infra-skills","planning-skills","identity-skills","language-skills"; $e[. + "@pixeloven"] == false)' "$1" >/dev/null
}

test_fence_fresh_home() {
  local home out
  home=$(new_home fresh)
  out=$(PATH="$TOOLBIN:$BASE_PATH" "$PC" fence "$home" 2>&1) || fail "fence failed on a fresh home: $out"
  assert_contains "$out" "fence: applied" "fence did not report applying"
  fenced "$(settings "$home")" || fail "fresh fence is missing an entry: $(cat "$(settings "$home")")"
  assert_absent "$(backup "$home")" "fence backed up a file that did not exist"
  pass "fence writes the five entries into a fresh home"
}

test_fence_preserves_and_is_idempotent() {
  local home file before after out
  home=$(new_home preserve)
  file=$(settings "$home")
  mkdir -p "$home/.claude"
  cat > "$file" <<'JSON'
{
  "permissions": {"allow": ["Bash(ls:*)"], "deny": ["Bash(rm:*)"]},
  "enabledPlugins": {"other@elsewhere": true, "crew@pixeloven": true},
  "env": {"KEEP": "1"}
}
JSON
  before=$(cat "$file")
  out=$(PATH="$TOOLBIN:$BASE_PATH" "$PC" fence "$home" 2>&1) || fail "fence failed: $out"
  fenced "$file" || fail "fence did not override the enabled crew entry: $(cat "$file")"
  assert_equals "$(jq -c '.permissions' "$file")" '{"allow":["Bash(ls:*)"],"deny":["Bash(rm:*)"]}' "fence lost the permission rules"
  assert_equals "$(jq -r '.env.KEEP' "$file")" 1 "fence lost an unrelated key"
  assert_equals "$(jq -r '.enabledPlugins["other@elsewhere"]' "$file")" true "fence lost another plugin's entry"
  assert_equals "$(cat "$(backup "$home")")" "$before" "the backup is not the original file"
  after=$(cksum < "$file")
  out=$(PATH="$TOOLBIN:$BASE_PATH" "$PC" fence "$home" 2>&1) || fail "second fence failed: $out"
  assert_contains "$out" "already present" "second fence did not report a no-op"
  assert_equals "$(cksum < "$file")" "$after" "second fence changed the file"
  jq '.enabledPlugins["crew@pixeloven"] = true' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  PATH="$TOOLBIN:$BASE_PATH" "$PC" fence "$home" >/dev/null 2>&1 || fail "re-fence failed"
  assert_equals "$(cat "$(backup "$home")")" "$before" "a later change overwrote the first backup"
  pass "fence keeps every other key, backs up once, overrides an enabled entry, and is idempotent"
}

test_fence_refuses_malformed() {
  local home file rc=0 out
  home=$(new_home malformed)
  file=$(settings "$home")
  mkdir -p "$home/.claude"
  printf '{"permissions": ' > "$file"
  out=$(PATH="$TOOLBIN:$BASE_PATH" "$PC" fence "$home" 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "fence accepted malformed JSON: $out"
  assert_contains "$out" "malformed JSON" "fence refused for the wrong reason"
  assert_equals "$(cat "$file")" '{"permissions": ' "fence changed a malformed file"
  pass "fence refuses malformed settings and leaves them unchanged"
}

test_fence_skips_secondmate() {
  local home out
  home=$(new_home secondmate)
  touch "$home/.fm-secondmate-home"
  out=$(PATH="$TOOLBIN:$BASE_PATH" FM_HOME="$home" "$PC" fence 2>&1) || fail "fence failed in a secondmate home: $out"
  assert_contains "$out" "secondmate home" "fence did not report the secondmate skip"
  assert_absent "$(settings "$home")" "fence wrote settings into a secondmate home"
  pass "fence skips a secondmate home, resolving it from FM_HOME"
}

# new_install <name> [tools...]: fixture tool state for a complete install,
# with stubs only for the named tools (default all three). Prints the fixture
# directory; it carries env.sh to source before running check.
new_install() {
  local dir="$TMP_ROOT/$1/machine" tools p sha cat_json='[]' claude_list='[]' installed='{}' codex_list='[]' pi_pkgs='[]'
  shift
  tools=${*:-claude codex pi}
  mkdir -p "$dir/fakebin" "$dir/claude/plugins/marketplaces/pixeloven/.claude-plugin" "$dir/pi"
  for p in $PLUGINS; do
    fm_git_init_commit "$dir/codex/plugins/cache/pixeloven/$p/0.1.0" >/dev/null
    sha=$(git -C "$dir/codex/plugins/cache/pixeloven/$p/0.1.0" rev-parse HEAD)
    cat_json=$(jq --arg p "$p" --arg s "$sha" '. + [{name: $p, source: {source: "url", url: "https://example.invalid/\($p).git", sha: $s}}]' <<<"$cat_json")
    claude_list=$(jq --arg id "$p@pixeloven" '. + [{id: $id, version: "0.1.0", scope: "user", enabled: true}]' <<<"$claude_list")
    installed=$(jq --arg id "$p@pixeloven" --arg s "$sha" '. + {($id): [{scope: "user", version: "0.1.0", gitCommitSha: $s}]}' <<<"$installed")
    codex_list=$(jq --arg id "$p@pixeloven" '. + [{pluginId: $id, version: "0.1.0", installed: true, enabled: true}]' <<<"$codex_list")
    pi_pkgs=$(jq --arg r "git:github.com/pixeloven/$p@$sha" '. + [$r]' <<<"$pi_pkgs")
  done
  jq -n --argjson p "$cat_json" '{name: "pixeloven", plugins: $p}' > "$dir/claude/plugins/marketplaces/pixeloven/.claude-plugin/marketplace.json"
  jq -n --argjson p "$installed" '{version: 2, plugins: $p}' > "$dir/claude/plugins/installed_plugins.json"
  printf '%s\n' "$claude_list" > "$dir/claude-list.json"
  jq -n --argjson i "$codex_list" '{installed: $i, available: []}' > "$dir/codex-list.json"
  jq -n --argjson p "$pi_pkgs" '{packages: (["npm:some-other-package"] + $p)}' > "$dir/pi/settings.json"
  case " $tools " in *" claude "*)
    # A directory holding .stub-claude-list.json answers with it, as a project
    # with its own settings would; anywhere else gets the user-scope list.
    cat > "$dir/fakebin/claude" <<SH
#!/usr/bin/env bash
[ "\$*" = "plugin list --json" ] || exit 2
if [ -f "\$PWD/.stub-claude-list.json" ]; then cat "\$PWD/.stub-claude-list.json"; else cat "$dir/claude-list.json"; fi
SH
  esac
  case " $tools " in *" codex "*)
    cat > "$dir/fakebin/codex" <<SH
#!/usr/bin/env bash
[ "\$*" = "plugin list --marketplace pixeloven --json" ] || exit 2
cat "$dir/codex-list.json"
SH
  esac
  case " $tools " in *" pi "*)
    printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/fakebin/pi"
  esac
  chmod +x "$dir"/fakebin/* 2>/dev/null || true
  printf '%s\n' "$dir"
}

run_check() {  # <machine> <home>: check output, then "rc=<n>"
  local rc=0 out
  out=$(PATH="$1/fakebin:$TOOLBIN:$BASE_PATH" CLAUDE_CONFIG_DIR="$1/claude" CODEX_HOME="$1/codex" \
    PI_CODING_AGENT_DIR="$1/pi" "$PC" check "$2" 2>&1) || rc=$?
  printf '%s\nrc=%s\n' "$out" "$rc"
}

fenced_home() {  # <name> <machine>: a home whose Claude listing shows the fence
  local home
  home=$(new_home "$1")
  jq '[.[] | .enabled = false]' "$2/claude-list.json" > "$home/.stub-claude-list.json"
  printf '%s\n' "$home"
}

test_check_complete_install() {
  local m home out
  m=$(new_install complete)
  home=$(fenced_home complete "$m")
  out=$(run_check "$m" "$home")
  assert_contains "$out" "rc=0" "check failed on a complete install: $out"
  assert_not_contains "$out" "fail " "a complete install reported a failure"
  assert_equals "$(printf '%s\n' "$out" | grep -c '^ok .*@pixeloven')" 15 "expected one ok row per tool and plugin: $out"
  assert_contains "$out" "ok    catalogue" "the catalogue row is missing"
  assert_contains "$out" "ok    fence" "the fence row is missing"
  pass "check passes a complete, fenced install with one row per tool and plugin"
}

test_check_reports_failures() {
  local m home out
  m=$(new_install failures)
  home=$(fenced_home failures "$m")
  jq '[.[] | if .id == "language-skills@pixeloven" then .enabled = false else . end]' "$m/claude-list.json" > "$m/x" && mv "$m/x" "$m/claude-list.json"
  jq '.installed |= map(select(.pluginId != "planning-skills@pixeloven"))' "$m/codex-list.json" > "$m/x" && mv "$m/x" "$m/codex-list.json"
  jq '.packages |= map(if test("/crew@") then "git:github.com/pixeloven/crew@0000000000000000000000000000000000000000" else . end)' "$m/pi/settings.json" > "$m/x" && mv "$m/x" "$m/pi/settings.json"
  out=$(run_check "$m" "$home")
  assert_contains "$out" "rc=1" "check passed with failures: $out"
  printf '%s\n' "$out" | grep -qE '^fail +claude language-skills@pixeloven +installed but disabled' || fail "disabled Claude plugin not reported: $out"
  printf '%s\n' "$out" | grep -qE '^fail +codex planning-skills@pixeloven +not installed' || fail "missing Codex plugin not reported: $out"
  printf '%s\n' "$out" | grep -qE '^fail +pi crew@pixeloven +installed, behind: 0000000 installed' || fail "behind pi plugin not reported: $out"
  printf '%s\n' "$out" | grep -qE '^ok +pi infra-skills@pixeloven' || fail "an unaffected pi plugin did not pass: $out"
  pass "check reports a disabled, a missing, and a behind plugin and exits 1"
}

test_check_absent_tools_and_fence() {
  local m home out
  m=$(new_install absent claude)
  home=$(new_home absent)
  out=$(run_check "$m" "$home")
  printf '%s\n' "$out" | grep -qE '^skip +codex +not installed' || fail "absent codex not skipped: $out"
  printf '%s\n' "$out" | grep -qE '^skip +pi +not installed' || fail "absent pi not skipped: $out"
  printf '%s\n' "$out" | grep -qE '^fail +fence +0 of five disabled' || fail "missing fence not reported: $out"
  assert_contains "$out" "rc=1" "a missing fence did not fail check"
  touch "$home/.fm-secondmate-home"
  out=$(run_check "$m" "$home")
  printf '%s\n' "$out" | grep -qE '^skip +fence +secondmate home' || fail "secondmate fence not skipped: $out"
  assert_contains "$out" "rc=0" "check failed in a secondmate home with absent tools: $out"
  rm -f "$m/claude/plugins/marketplaces/pixeloven/.claude-plugin/marketplace.json"
  out=$(run_check "$m" "$home")
  printf '%s\n' "$out" | grep -qE '^fail +catalogue +local copy not found' || fail "missing catalogue not reported: $out"
  printf '%s\n' "$out" | grep -qE '^fail +claude crew@pixeloven +enabled, but the catalogue has no pin' || fail "pin compare without a catalogue not reported: $out"
  pass "check skips absent tools and a secondmate fence, and reports a missing fence or catalogue"
}

test_check_codex_cache_without_git() {
  local m home out p
  m=$(new_install nogit)
  home=$(fenced_home nogit "$m")
  for p in $PLUGINS; do rm -rf "$m/codex/plugins/cache/pixeloven/$p/0.1.0/.git"; done
  fm_git_init_commit "$m/codex" >/dev/null
  out=$(run_check "$m" "$home")
  assert_contains "$out" "rc=0" "a Codex cache without .git failed check: $out"
  assert_equals "$(printf '%s\n' "$out" | grep -cE '^warn +codex .*installed commit not readable from cache')" 5 "expected one warn row per Codex plugin: $out"
  assert_not_contains "$out" "fail " "a Codex cache without .git reported a failure"
  pass "check warns without failing when the Codex cache is not a git checkout, ignoring a parent repository"
}

# stub_gh <machine> <published-file|fail>: a gh that serves the published
# catalogue from <published-file>, or exits 1 for "fail".
stub_gh() {
  if [ "$2" = fail ]; then
    printf '#!/usr/bin/env bash\nexit 1\n' > "$1/fakebin/gh"
  else
    cat > "$1/fakebin/gh" <<SH
#!/usr/bin/env bash
[ "\$*" = "api -H Accept: application/vnd.github.raw repos/pixeloven/marketplace/contents/.claude-plugin/marketplace.json" ] || exit 2
cat "$2"
SH
  fi
  chmod +x "$1/fakebin/gh"
}

test_check_reads_published_catalogue() {
  local m home out local_cat
  m=$(new_install published)
  home=$(fenced_home published "$m")
  local_cat="$m/claude/plugins/marketplaces/pixeloven/.claude-plugin/marketplace.json"
  jq '.plugins |= map(if .name == "crew" then .source.sha = "1111111111111111111111111111111111111111" else . end)' "$local_cat" > "$m/published.json"
  stub_gh "$m" "$m/published.json"
  out=$(run_check "$m" "$home")
  assert_contains "$out" "rc=1" "a re-pin in the published catalogue did not fail check: $out"
  printf '%s\n' "$out" | grep -qE '^ok +catalogue +pins for all five plugins, from the published pixeloven/marketplace' || fail "catalogue row does not name the published source: $out"
  assert_equals "$(printf '%s\n' "$out" | grep -cE '^fail +(claude|codex|pi) crew@pixeloven +.*behind: .* catalogue pins 1111111')" 3 "expected crew behind the published pin on all three tools: $out"
  printf '%s\n' "$out" | grep -qE '^ok +pi infra-skills@pixeloven' || fail "an unchanged pin did not pass: $out"
  assert_not_contains "$out" "local copy" "a published read still warned about the local copy"
  pass "check compares against the published catalogue, so a re-pin the local copy lacks reads as behind"
}

test_check_falls_back_to_local_copy() {
  local m home out
  m=$(new_install fallback)
  home=$(fenced_home fallback "$m")
  out=$(run_check "$m" "$home")
  assert_contains "$out" "rc=0" "check failed on the local copy with gh absent: $out"
  assert_equals "$(printf '%s\n' "$out" | grep -cE '^warn +catalogue +published pixeloven/marketplace catalogue unreadable; comparing against the local copy')" 1 "expected one fallback warn row with gh absent: $out"
  printf '%s\n' "$out" | grep -qE '^ok +catalogue +pins for all five plugins, from the local copy' || fail "catalogue row does not name the local copy: $out"
  stub_gh "$m" fail
  out=$(run_check "$m" "$home")
  assert_contains "$out" "rc=0" "check failed on the local copy when gh failed: $out"
  assert_equals "$(printf '%s\n' "$out" | grep -c 'comparing against the local copy')" 1 "expected one fallback warn row when gh failed: $out"
  printf '{"plugins": ' > "$m/published.json"
  stub_gh "$m" "$m/published.json"
  out=$(run_check "$m" "$home")
  assert_contains "$out" "rc=0" "check failed on the local copy when gh served malformed JSON: $out"
  assert_equals "$(printf '%s\n' "$out" | grep -c 'comparing against the local copy')" 1 "expected one fallback warn row on malformed JSON: $out"
  assert_equals "$(printf '%s\n' "$out" | grep -c '^ok .*@pixeloven')" 15 "the local copy did not serve every pin: $out"
  pass "check falls back to the local copy with one warning when gh is absent, fails, or serves malformed JSON"
}

test_check_is_read_only() {
  local m home before after
  m=$(new_install readonly)
  home=$(new_home readonly)
  before=$( (cd "$TMP_ROOT/readonly" && find . -type f -print | LC_ALL=C sort | xargs cksum) )
  run_check "$m" "$home" >/dev/null
  after=$( (cd "$TMP_ROOT/readonly" && find . -type f -print | LC_ALL=C sort | xargs cksum) )
  assert_equals "$after" "$before" "check changed a file"
  pass "check writes nothing to the home or tool state"
}

test_fence_fresh_home
test_fence_preserves_and_is_idempotent
test_fence_refuses_malformed
test_fence_skips_secondmate
test_check_complete_install
test_check_reports_failures
test_check_absent_tools_and_fence
test_check_codex_cache_without_git
test_check_reads_published_catalogue
test_check_falls_back_to_local_copy
test_check_is_read_only

echo "all po-crew tests passed"
