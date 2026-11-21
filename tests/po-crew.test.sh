#!/usr/bin/env bash
# tests/po-crew.test.sh - behavior tests for bin/po-crew.sh (ADR-0019).
#
# Coverage:
#   - fence writes the five disabled entries into a fresh home
#   - fence preserves every other key, backs up once under state/po-crew,
#     overrides an enabled entry, is idempotent, and leaves malformed JSON
#     untouched
#   - fence skips a secondmate home and writes nothing there
#   - check passes a complete install pinned to the newest crew release tag a
#     stub gh publishes, with stub claude, codex, and pi, and reports a missing,
#     disabled, or behind plugin, an absent tool, and a missing fence as the
#     right rows
#   - check warns without failing when a tool is at an older release tag, and
#     fails a ref that is not a published release tag or not a tag at all
#   - check names the switch to pixeloven/crew, never `behind`, for a machine
#     still on the pixeloven/marketplace catalogue or on pi per-pack packages
#   - check falls back to each tool's own marketplace clone with one warn row
#     when gh is absent, fails, or serves malformed JSON, and still catches a
#     plugin that is not at its clone's commit
#   - check warns, without failing, for a pack inside a filtered pi crew package
#     and for an unreadable Codex marketplace install record
#
# Every tool is a stub on PATH and every tool state path is a fixture, so no
# case reads or writes this machine's real install or operator home, and no
# case reaches the network: gh is absent unless a case stubs it.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PC="$ROOT/bin/po-crew.sh"
TMP_ROOT=$(fm_test_tmproot po-crew-tests)
FM_TEST_CLEANUP_DIRS+=("$TMP_ROOT")
trap fm_test_cleanup EXIT
BASE_PATH=$(fm_test_base_path_sans "${FM_TEST_BASE_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}" gh claude codex pi)
fm_git_identity fmtest fmtest@example.invalid

PLUGINS='crew infra-skills planning-skills identity-skills language-skills'

# The only real tools on PATH are jq and git, and BASE_PATH hides any host gh,
# claude, codex, or pi, so an absent stub reads as an absent tool even on a
# machine that has the real one.
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

# new_install <name> [tools...]: fixture tool state for a complete install at
# crew v0.67.0, with stubs only for the named tools (default all three) plus a
# gh that publishes v0.66.0 and v0.67.0. Prints the fixture directory.
new_install() {
  local dir="$TMP_ROOT/$1/machine" tools p sha old claude_list='[]' installed='{}' codex_list='[]'
  shift
  tools=${*:-claude codex pi}
  mkdir -p "$dir/fakebin" "$dir/claude/plugins" "$dir/codex/.tmp/marketplaces" "$dir/pi"
  # One crew repository: v0.66.0 and v0.67.0 are its two commits, and each
  # tool's marketplace clone sits at v0.67.0.
  fm_git_init_commit "$dir/crew" >/dev/null
  old=$(git -C "$dir/crew" rev-parse HEAD)
  git -C "$dir/crew" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m release
  sha=$(git -C "$dir/crew" rev-parse HEAD)
  printf '%s\n' "$sha" > "$dir/tag-commit"
  git clone -q "$dir/crew" "$dir/claude/plugins/marketplaces/pixeloven"
  git clone -q "$dir/crew" "$dir/codex/.tmp/marketplaces/pixeloven"
  jq -n --arg o "$old" --arg n "$sha" '[{name: "v0.67.0", commit: {sha: $n}}, {name: "latest", commit: {sha: $n}}, {name: "v0.66.0", commit: {sha: $o}}]' > "$dir/tags.json"
  for p in $PLUGINS; do
    claude_list=$(jq --arg id "$p@pixeloven" '. + [{id: $id, version: "0.67.0", scope: "user", enabled: true}]' <<<"$claude_list")
    installed=$(jq --arg id "$p@pixeloven" --arg s "$sha" '. + {($id): [{scope: "user", version: "0.67.0", gitCommitSha: $s}]}' <<<"$installed")
    codex_list=$(jq --arg id "$p@pixeloven" '. + [{pluginId: $id, version: "0.67.0", installed: true, enabled: true}]' <<<"$codex_list")
  done
  jq -n --arg l "$dir/claude/plugins/marketplaces/pixeloven" \
    '{pixeloven: {source: {source: "github", repo: "pixeloven/crew", ref: "v0.67.0"}, installLocation: $l}}' \
    > "$dir/claude/plugins/known_marketplaces.json"
  jq -n --argjson p "$installed" '{version: 2, plugins: $p}' > "$dir/claude/plugins/installed_plugins.json"
  jq -n --arg s "$sha" '{source_type: "git", source: "https://github.com/pixeloven/crew.git", ref_name: "v0.67.0", sparse_paths: [], revision: $s}' \
    > "$dir/codex/.tmp/marketplaces/pixeloven/.codex-marketplace-install.json"
  printf '%s\n' "$claude_list" > "$dir/claude-list.json"
  jq -n --argjson i "$codex_list" '{installed: $i, available: []}' > "$dir/codex-list.json"
  jq -n '{packages: ["npm:some-other-package", "git:github.com/pixeloven/crew@v0.67.0"]}' > "$dir/pi/settings.json"
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
  stub_gh "$dir" "$dir/tags.json"
  printf '%s\n' "$dir"
}

# stub_gh <machine> <tags-file|fail|absent>: a gh that publishes pixeloven/crew's
# tags from <tags-file>, one that exits 1, or none at all.
stub_gh() {
  rm -f "$1/fakebin/gh"
  case "$2" in
    absent) return 0 ;;
    fail) printf '#!/usr/bin/env bash\nexit 1\n' > "$1/fakebin/gh" ;;
    *) cat > "$1/fakebin/gh" <<SH
#!/usr/bin/env bash
[ "\$*" = "api --paginate repos/pixeloven/crew/tags?per_page=100" ] || exit 2
cat "$2"
SH
  esac
  chmod +x "$1"/fakebin/*
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

edit_json() {  # <file> <jq filter> [jq args...]: rewrite a fixture file
  local f=$1; shift
  jq "$@" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

test_check_complete_install() {
  local m home out
  m=$(new_install complete)
  home=$(fenced_home complete "$m")
  out=$(run_check "$m" "$home")
  assert_contains "$out" "rc=0" "check failed on a complete install: $out"
  assert_not_contains "$out" "fail " "a complete install reported a failure"
  assert_not_contains "$out" "warn " "a complete install reported a warning"
  assert_equals "$(printf '%s\n' "$out" | grep -c '^ok .*@pixeloven .*at crew v0.67.0$')" 15 "expected one ok row per tool and plugin at the tag: $out"
  printf '%s\n' "$out" | grep -qE '^ok +release +crew v0.67.0 \([0-9a-f]{7}\) is the newest release, from the published pixeloven/crew' \
    || fail "the release row does not name the newest published tag: $out"
  assert_contains "$out" "ok    fence" "the fence row is missing"
  pass "check passes a complete, fenced install at the newest crew tag with one row per tool and plugin"
}

test_check_reports_failures() {
  local m home out
  m=$(new_install failures)
  home=$(fenced_home failures "$m")
  edit_json "$m/claude-list.json" '[.[] | if .id == "language-skills@pixeloven" then .enabled = false else . end]'
  edit_json "$m/claude/plugins/installed_plugins.json" '.plugins["infra-skills@pixeloven"][0].gitCommitSha = "1111111111111111111111111111111111111111"'
  edit_json "$m/codex-list.json" '.installed |= map(select(.pluginId != "planning-skills@pixeloven"))'
  out=$(run_check "$m" "$home")
  assert_contains "$out" "rc=1" "check passed with failures: $out"
  printf '%s\n' "$out" | grep -qE '^fail +claude language-skills@pixeloven +installed but disabled' || fail "disabled Claude plugin not reported: $out"
  printf '%s\n' "$out" | grep -qE '^fail +claude infra-skills@pixeloven +enabled, behind: 1111111 installed, crew v0.67.0 is [0-9a-f]{7}; run the dotfiles plugin update' \
    || fail "behind Claude plugin not reported: $out"
  printf '%s\n' "$out" | grep -qE '^fail +codex planning-skills@pixeloven +not installed' || fail "missing Codex plugin not reported: $out"
  printf '%s\n' "$out" | grep -qE '^ok +claude crew@pixeloven' || fail "an unaffected Claude plugin did not pass: $out"
  pass "check reports a disabled, a missing, and a behind plugin and exits 1"
}

test_check_older_and_unpublished_tags() {
  local m home out
  m=$(new_install oldtag)
  home=$(fenced_home oldtag "$m")
  edit_json "$m/tags.json" '. + [{name: "v0.68.0", commit: {sha: "2222222222222222222222222222222222222222"}}]'
  out=$(run_check "$m" "$home")
  assert_contains "$out" "rc=0" "a tool at an older release tag failed check: $out"
  printf '%s\n' "$out" | grep -qE '^ok +release +crew v0.68.0 ' || fail "the release row did not pick the newest tag: $out"
  assert_equals "$(printf '%s\n' "$out" | grep -cE '^warn +(claude|codex|pi) .*at crew v0.67.0; crew v0.68.0 is released, so move the dotfiles crew tag')" 15 \
    "expected a warn row per tool and plugin at the older tag: $out"
  edit_json "$m/claude/plugins/known_marketplaces.json" '.pixeloven.source.ref = "v0.99.0"'
  edit_json "$m/codex/.tmp/marketplaces/pixeloven/.codex-marketplace-install.json" '.ref_name = null'
  edit_json "$m/pi/settings.json" '.packages |= map(if test("/crew@") then "git:github.com/pixeloven/crew@0000000000000000000000000000000000000000" else . end)'
  out=$(run_check "$m" "$home")
  assert_contains "$out" "rc=1" "unpublished or untagged refs passed check: $out"
  printf '%s\n' "$out" | grep -qE '^fail +claude crew@pixeloven +enabled, pinned to v0.99.0, which is not a published crew release tag' || fail "unpublished Claude tag not reported: $out"
  printf '%s\n' "$out" | grep -qE '^fail +codex crew@pixeloven +enabled, not pinned to a crew release tag \(no ref\)' || fail "unpinned Codex marketplace not reported: $out"
  printf '%s\n' "$out" | grep -qE '^fail +pi crew@pixeloven +installed, pinned by commit 0000000 rather than a crew release tag' || fail "commit-pinned pi package not reported: $out"
  pass "check warns at an older release tag and fails a ref that is not a published release tag"
}

test_check_old_catalogue_switch() {
  local m home out p
  m=$(new_install oldcat)
  home=$(fenced_home oldcat "$m")
  edit_json "$m/claude/plugins/known_marketplaces.json" '.pixeloven.source = {source: "github", repo: "pixeloven/marketplace"}'
  edit_json "$m/claude/plugins/installed_plugins.json" '.plugins |= map_values(map(.gitCommitSha = "3333333333333333333333333333333333333333"))'
  edit_json "$m/codex/.tmp/marketplaces/pixeloven/.codex-marketplace-install.json" '.source = "https://github.com/pixeloven/marketplace.git" | .ref_name = null'
  edit_json "$m/pi/settings.json" '.packages |= map(select(test("/crew@") | not))'
  for p in $PLUGINS; do
    # shellcheck disable=SC2016 # $r is a jq variable.
    edit_json "$m/pi/settings.json" --arg r "git:github.com/pixeloven/$p@3333333333333333333333333333333333333333" '.packages += [$r]'
  done
  out=$(run_check "$m" "$home")
  assert_contains "$out" "rc=1" "a machine on the old catalogue passed check: $out"
  assert_not_contains "$out" "behind" "a machine on the old catalogue read as behind"
  assert_equals "$(printf '%s\n' "$out" | grep -cE '^fail +(claude|codex) .*on the retired pixeloven/marketplace catalogue; switch to pixeloven/crew per crew 0.67.0 Consumer impact')" 10 \
    "expected the switch message on every Claude and Codex row: $out"
  assert_equals "$(printf '%s\n' "$out" | grep -cE '^fail +pi .*its own pre-fold package is still installed; switch to the crew package')" 4 \
    "expected the switch message on every pi pack row: $out"
  printf '%s\n' "$out" | grep -qE '^fail +pi crew@pixeloven +installed, pinned by commit 3333333 rather than a crew release tag; move it to the tag per crew 0.67.0 Consumer impact' \
    || fail "the pre-fold pi crew package did not name the move to a tag: $out"
  pass "check names the switch to pixeloven/crew, not behind, for a machine still on the old catalogue"
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
  pass "check skips absent tools and a secondmate fence, and reports a missing fence"
}

test_check_falls_back_to_clones() {
  local m home out mode
  m=$(new_install fallback)
  home=$(fenced_home fallback "$m")
  for mode in absent fail malformed; do
    if [ "$mode" = malformed ]; then
      printf '[{"name": ' > "$m/bad-tags.json"
      stub_gh "$m" "$m/bad-tags.json"
    else
      stub_gh "$m" "$mode"
    fi
    out=$(run_check "$m" "$home")
    assert_contains "$out" "rc=0" "check failed against the local clones ($mode gh): $out"
    assert_equals "$(printf '%s\n' "$out" | grep -cE '^warn +release +published pixeloven/crew release tags unreadable; comparing each tool against its own marketplace clone')" 1 \
      "expected one fallback warn row ($mode gh): $out"
    assert_equals "$(printf '%s\n' "$out" | grep -c '^ok .*@pixeloven .*at crew v0.67.0$')" 15 "the local clones did not serve every row ($mode gh): $out"
  done
  edit_json "$m/claude/plugins/installed_plugins.json" '.plugins["crew@pixeloven"][0].gitCommitSha = "4444444444444444444444444444444444444444"'
  edit_json "$m/codex/.tmp/marketplaces/pixeloven/.codex-marketplace-install.json" '.revision = "5555555555555555555555555555555555555555"'
  out=$(run_check "$m" "$home")
  assert_contains "$out" "rc=1" "drift from the local clones passed check: $out"
  printf '%s\n' "$out" | grep -qE '^fail +claude crew@pixeloven +enabled, behind: 4444444 installed, crew v0.67.0 is ' || fail "Claude drift from its clone not reported: $out"
  assert_equals "$(printf '%s\n' "$out" | grep -cE '^fail +codex .*behind: [0-9a-f]{7} installed, crew v0.67.0 is 5555555')" 5 "Codex clone drift from its record not reported: $out"
  pass "check falls back to each tool's marketplace clone with one warning and still catches drift there"
}

test_check_pi_filter_and_codex_record() {
  local m home out
  m=$(new_install filtered)
  home=$(fenced_home filtered "$m")
  edit_json "$m/pi/settings.json" '.packages |= map(if test("/crew@") then {source: ., skills: ["skills/**"]} else . end)'
  rm -f "$m/codex/.tmp/marketplaces/pixeloven/.codex-marketplace-install.json"
  out=$(run_check "$m" "$home")
  assert_contains "$out" "rc=0" "a filtered pi package or a missing Codex record failed check: $out"
  printf '%s\n' "$out" | grep -qE '^ok +pi crew@pixeloven +installed, at crew v0.67.0' || fail "the filtered crew package itself did not pass: $out"
  assert_equals "$(printf '%s\n' "$out" | grep -cE '^warn +pi .*has a skills filter; whether it carries this pack is not checked')" 4 "expected a warn row per pack in a filtered pi package: $out"
  assert_equals "$(printf '%s\n' "$out" | grep -cE '^warn +codex .*marketplace install record not readable')" 5 "expected a warn row per Codex plugin without a record: $out"
  pass "check warns, without failing, for packs in a filtered pi package and an unreadable Codex record"
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
test_check_older_and_unpublished_tags
test_check_old_catalogue_switch
test_check_absent_tools_and_fence
test_check_falls_back_to_clones
test_check_pi_filter_and_codex_record
test_check_is_read_only

echo "all po-crew tests passed"
