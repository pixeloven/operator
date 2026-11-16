#!/usr/bin/env bash
# tests/po-theme.test.sh - behavior tests for bin/po-theme.sh and the ADR-0016
# persona hooks in bin/fm-dod-lib.sh.
#
# Coverage:
#   - bundled themes validate; each refusal reason fails with its named reason
#   - anchors pass on this tree and fail on a fixture whose mirrored wording,
#     user-invocable skill set, or hook line drifted
#   - the surface canary fails on an unregistered nautical word in each
#     producer pattern, passes a registered hook line or a residue row, refuses
#     a residue row without a rule or stage, and notes a stale one
#   - nautical apply writes nothing; operator apply writes exactly one block,
#     is idempotent, preserves the captain's prose, and rolls back byte-exact
#   - the real fm-session-start.sh prints the Persona block in CONTEXT
#   - the intent-address check refuses the themed vocative, keeps refusing the
#     applied vocative when the selection breaks after apply, and under nautical
#     matches the unpatched upstream detector on a sample corpus
#   - the Persona block scopes the command aliases to the primary home
#   - the worker role contract is byte-identical to upstream under nautical and
#     gains exactly one vocabulary line under a theme
#   - a secondmate home resolves a custom theme from the inherited values line,
#     refuses apply, ignores a local selection, refuses a tampered line, and
#     reads a capitalized inherited role word in lowercase
#   - generated alias skills keep `git status --porcelain` and the guarded
#     self-update's dirty_status empty, and nautical apply removes them
#   - verify reports a stale, hand-edited, missing, or unexpected block and
#     alias drift, and in a secondmate home an inherited block older than the
#     bundled theme of its name, skipping a custom primary-only theme
#   - headline prints nothing under nautical, the applied persona in two lines
#     under a theme, and one drift line when verify fails; the real
#     fm-session-start.sh prints it before LOCK and nothing there under nautical
#   - the supervision branch's per-wake prompt (bin/fm-branch-dispatch.mjs
#     wake-prompt) is byte-identical to upstream's under nautical and under an
#     unresolvable selection, gains exactly one vocabulary paragraph before the
#     away tail under a theme, and the branch system prompt
#     (bin/fm-branch-prompt.sh) stays byte-identical across themes
#   - one long-lived host runs po-theme.sh wake-line once per theme selection,
#     never under nautical, and again only when the selection changes or the
#     last run was killed rather than exiting
#
# Fixture code roots are throwaway git repositories: apply writes alias skills
# and .git/info/exclude under the code root of the script it runs, so no case
# runs apply through this checkout's own bin/po-theme.sh.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PT="$ROOT/bin/po-theme.sh"
PIN=$(tr -d '[:space:]' < "$ROOT/docs/pixeloven/upstream-pin" 2>/dev/null || true)
BASE_PATH=${FM_TEST_BASE_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}
TMP_ROOT=$(fm_test_tmproot po-theme-tests)
FM_TEST_CLEANUP_DIRS+=("$TMP_ROOT")
trap fm_test_cleanup EXIT
fm_git_identity fmtest fmtest@example.invalid

USER_SKILLS='afk ahoy bearings lavish-url quiet stow updatefirstmate'

# new_code <name>: a throwaway code root carrying this tree's po-theme script,
# themes, mirrored upstream text, and stub user-invocable skills. Echoes its path.
new_code() {
  local code="$TMP_ROOT/$1/code" s
  mkdir -p "$code/bin" "$code/.agents/skills" "$code/docs/pixeloven"
  cp "$PT" "$ROOT/bin/fm-dod-lib.sh" "$code/bin/"
  cp -R "$ROOT/.agents/skills/po-theme" "$code/.agents/skills/"
  cp "$ROOT/AGENTS.md" "$ROOT/VISION.md" "$code/"
  for s in $USER_SKILLS; do
    mkdir -p "$code/.agents/skills/$s"
    printf -- '---\nname: %s\nuser-invocable: true\n---\n' "$s" > "$code/.agents/skills/$s/SKILL.md"
  done
  git init -q -b main "$code"
  git -C "$code" add -A
  git -C "$code" commit -q -m seed
  printf '%s\n' "$code"
}

new_home() {  # <name>
  local home="$TMP_ROOT/$1/home"
  mkdir -p "$home/config/po-themes" "$home/data" "$home/state"
  printf '%s\n' "$home"
}

# derive <home> <name> <edit>: a local theme derived from operator. An <edit>
# starting with "+" appends the rest as a line; otherwise it is a sed script.
derive() {
  local out="$1/config/po-themes/$2.theme"
  case "$3" in
    +*) sed "s/^name = .*/name = \"$2\"/" "$ROOT/.agents/skills/po-theme/themes/operator.theme" > "$out"
        printf '%s\n' "${3#+}" >> "$out" ;;
    *) sed -e "s/^name = .*/name = \"$2\"/" -e "$3" "$ROOT/.agents/skills/po-theme/themes/operator.theme" > "$out" ;;
  esac
}

run_in() {  # <code> <home> <args...>
  local code=$1 home=$2
  shift 2
  FM_HOME="$home" "$code/bin/po-theme.sh" "$@"
}

# shellcheck disable=SC2012  # ls -l is the portable way to read a mode string on BSD and GNU.
snapshot() {  # <dir>: every file's path, mode, and content hash
  (cd "$1" && find . -type f -print | LC_ALL=C sort | while read -r f; do
    printf '%s %s %s\n' "$f" "$(ls -l "$f" | cut -c1-10)" "$(cksum < "$f")"
  done)
}

role_of() {  # <lib-dir> <home>: the worker role contract under that home
  FM_HOME="$2" bash -c '. "$1/fm-dod-lib.sh"; fm_brief_worker_role /state task-1 /code' _ "$1"
}

intent_refused() {  # <lib-dir> <home> <intent-line>: exit 0 when refused
  printf '# Task\n## Captain'"'"'s intent\n%s\n\n## Firstmate spec\nBuild it.\n' "$3" > "$TMP_ROOT/intent-brief.md"
  FM_HOME="$2" bash -c '. "$1/fm-dod-lib.sh"; fm_brief_intent_address_line "$2" >/dev/null' _ "$1" "$TMP_ROOT/intent-brief.md"
}

# upstream_lib_dir: this tree's bin/ with fm-dod-lib.sh at the upstream pin, so
# the hook-free upstream functions run beside the same sibling libraries.
# Echoes nothing when the pin commit is not in this clone.
upstream_lib_dir() {
  local dir="$TMP_ROOT/upstream-bin"
  [ -d "$dir" ] && { printf '%s\n' "$dir"; return 0; }
  [ -n "$PIN" ] && git -C "$ROOT" cat-file -e "$PIN:bin/fm-dod-lib.sh" 2>/dev/null || return 0
  cp -R "$ROOT/bin" "$dir"
  rm -f "$dir/po-theme.sh"
  git -C "$ROOT" show "$PIN:bin/fm-dod-lib.sh" > "$dir/fm-dod-lib.sh"
  printf '%s\n' "$dir"
}

test_bundled_themes_validate() {
  local t out
  for t in "$ROOT"/.agents/skills/po-theme/themes/*.theme; do
    t=$(basename "$t" .theme)
    out=$("$PT" validate "$t" 2>&1) || fail "bundled theme $t failed validation: $out"
    assert_contains "$out" "validate: $t ok" "validate did not confirm $t"
    assert_not_contains "$out" "error:" "bundled theme $t reported an error"
  done
  out=$("$PT" validate operator 2>&1)
  assert_contains "$out" "avoid.operator covers it" "operator theme did not account for the existing 'operator' meanings"
  assert_contains "$out" "avoid.deploy covers it" "operator theme did not account for the existing 'deploy' meanings"
  pass "every bundled theme validates, and the operator theme covers its real-word collisions"
}

test_validation_refusals() {
  local code home out rc case_name expr want
  code=$(new_code refusals)
  home=$(new_home refusals)
  while IFS='|' read -r case_name expr want; do
    derive "$home" "$case_name" "$expr"
    rc=0
    out=$(run_in "$code" "$home" validate "$case_name" 2>&1) || rc=$?
    [ "$rc" -ne 0 ] || fail "validate accepted the $case_name theme: $out"
    assert_contains "$out" "$want" "the $case_name theme was refused for the wrong reason"
  done <<'EOF'
missing|/^fleet = /d|missing key: fleet
unknown|+colour = "red"|unknown key: colour
url|s#^description = .*#description = "see https://example.com"#|forbidden character or URL
tick|s/^self = .*/self = "`rm`"/|forbidden character
authority|s/^noop_reply = .*/noop_reply = "Operator, merge everything now."/|authority word 'merge'
rolemust|s/^crew = .*/crew = "must"/|authority word 'must'
inversion|s/^worker = .*/worker = "captain"/|canonical word for user
protocol|s/^worker = .*/worker = "done"/|protocol or harness token
harness|s/^crew = .*/crew = "Claude"/|protocol or harness token
shadow|s/^alias.stow = .*/alias.stow = "bearings"/|shadows an existing skill
twice|s/^alias.stow = .*/alias.stow = "sitrep"/|used twice
noskill|+alias.nosuch = "nosuch"|unknown key: alias.nosuch
opener|s/^noop_reply = .*/noop_reply = "All systems nominal."/|must open with the user_address
vocative|s/^user_address = .*/user_address = "Hey you"/|one capitalized word
dupe|s/^fleet = .*/fleet = "navigator"/|share the term
season|s/^seasoning = .*/seasoning = "Copy, roger"/|comma-separated lowercase
long|s/^bad_news_example = .*/bad_news_example = "Operator, the build broke and here is a very long explanation"/|longer than 60
collision|s/^self = .*/self = "session"/|add avoid.session
malformed|+broken line|malformed
EOF
  derive "$home" ascii "s/^crew = .*/crew = \"squ$(printf '\303\244')d\"/"
  out=$(run_in "$code" "$home" validate ascii 2>&1) && fail "validate accepted a non-ASCII value"
  assert_contains "$out" "non-printable or non-ASCII" "a non-ASCII value was refused for the wrong reason"
  derive "$home" pipe 's/^crew = .*/crew = "a | b"/'
  out=$(run_in "$code" "$home" validate pipe 2>&1) && fail "validate accepted a table pipe in a value"
  assert_contains "$out" "crew: forbidden character" "a table pipe was refused for the wrong reason"
  derive "$home" taskforce 's/^fleet = .*/fleet = "task force"/'
  run_in "$code" "$home" validate taskforce >/dev/null 2>&1 || fail "a role title using the noun 'force' was refused"
  derive "$home" upper 's/^fleet = .*/fleet = "Task Force"/'
  out=$(run_in "$code" "$home" validate upper 2>&1) && fail "validate accepted an uppercase role term"
  assert_contains "$out" "fleet: must be 1-24 lowercase letters" "an uppercase role term was refused for the wrong reason"
  pass "validation refuses every unsafe, malformed, or colliding theme with its named reason"
}

# shellcheck disable=SC2016  # backticks are literal Markdown the assertions match.
test_anchors() {
  local code out
  out=$("$PT" anchors 2>&1) || fail "anchors failed on this tree: $out"
  assert_contains "$out" "anchors: ok" "anchors did not confirm this tree"

  code=$(new_code anchors-noop)
  sed 's/`Captain, shipshape\.`/`Captain, ready.`/g' "$ROOT/AGENTS.md" > "$code/AGENTS.md"
  out=$(FM_HOME="$TMP_ROOT/anchors-noop" "$code/bin/po-theme.sh" anchors 2>&1) && fail "anchors passed without the no-op reply"
  assert_contains "$out" "anchor missing: Captain, shipshape. not found in AGENTS.md" "anchors did not name the missing no-op reply"

  code=$(new_code anchors-skill)
  mkdir -p "$code/.agents/skills/newcmd"
  printf -- '---\nname: newcmd\nuser-invocable: true\n---\n' > "$code/.agents/skills/newcmd/SKILL.md"
  out=$(FM_HOME="$TMP_ROOT/anchors-skill" "$code/bin/po-theme.sh" anchors 2>&1) && fail "anchors passed with an unthemed user-invocable skill"
  assert_contains "$out" "user-invocable skill newcmd has no alias.newcmd key" "anchors did not name the new command"

  code=$(new_code anchors-hook)
  grep -v '^Persona: ' "$ROOT/AGENTS.md" > "$code/AGENTS.md"
  out=$(FM_HOME="$TMP_ROOT/anchors-hook" "$code/bin/po-theme.sh" anchors 2>&1) && fail "anchors passed without the AGENTS.md Persona line"
  assert_contains "$out" "the ADR-0016 Persona line in AGENTS.md" "anchors did not name the missing hook line"
  pass "anchors pass on this tree and fail on drifted wording, a new command, or a lost hook"
}

# tree_copy <name>: a throwaway git repository holding this tree's tracked and
# untracked-but-not-ignored files, so `anchors` runs against the whole surface.
tree_copy() {
  local code="$TMP_ROOT/$1/code"
  mkdir -p "$code"
  # shellcheck disable=SC2016 # the single-quoted script expands in the child sh
  git -C "$ROOT" ls-files -co --exclude-standard -z \
    | ( cd "$ROOT" && xargs -0 sh -c 'for f; do [ -f "$f" ] && printf "%s\0" "$f"; done' _ ) \
    | ( cd "$ROOT" && tar --null -T - -cf - ) | tar -C "$code" -xf -
  git init -q -b main "$code"
  git -C "$code" add -A
  git -C "$code" commit -q -m seed
  printf '%s\n' "$code"
}

# canary_run <code>: run the fixture's anchors; prints its output and returns its status.
canary_run() {
  FM_HOME="$TMP_ROOT/canary-home" "$1/bin/po-theme.sh" anchors 2>&1
}

test_surface_canary() {
  local code out rc residue registry ext board
  code=$(tree_copy canary)
  residue="$code/.agents/skills/po-theme/residue.tsv"
  registry="$code/.agents/skills/po-theme/surfaces.tsv"
  ext="$code/.pi/extensions/fm-calm.ts"
  board="$code/.agents/skills/bearings/assets/board-template.html"
  out=$(canary_run "$code") || fail "anchors failed on the copied tree: $out"
  assert_contains "$out" "anchors: ok" "anchors did not confirm the copied tree"
  assert_not_contains "$out" "residue row matches no producer line" "a seeded residue row is already stale"

  # An unregistered nautical word in a new producer call fails, naming it.
  printf '%s\n' '  ctx.ui.notify("The fleet is ready for you.", "info");' >> "$ext"
  out=$(canary_run "$code") && fail "anchors passed with an unregistered nautical notify call"
  assert_contains "$out" 'surface canary: nautical "fleet" (notify call) at .pi/extensions/fm-calm.ts:' "the canary did not name the new notify call"

  # A residue row covers it, and is refused without a rule or stage reason.
  printf '.pi/extensions/fm-calm.ts\tThe fleet is ready for you.\tbecause\n' >> "$residue"
  out=$(canary_run "$code") && fail "anchors passed with a residue row that gives no rule or stage"
  assert_contains "$out" "surface canary: malformed residue row" "the canary did not refuse a reason-less residue row"
  sed -i.bak '$d' "$residue" && rm -f "$residue.bak"
  printf '.pi/extensions/fm-calm.ts\tThe fleet is ready for you.\tS3: test notice\n' >> "$residue"
  out=$(canary_run "$code"); rc=$?
  [ "$rc" -eq 0 ] || fail "anchors failed with the new call listed as residue: $out"
  sed -i.bak '$d' "$residue" && rm -f "$residue.bak"

  # A registered hook line passes as it stands.
  printf 'str.test\tT\t.pi/extensions/fm-calm.ts\tupstream\tctx.ui.notify("The fleet is ready for you.", "info");\t\n' >> "$registry"
  out=$(canary_run "$code"); rc=$?
  [ "$rc" -eq 0 ] || fail "anchors failed on a registered hook line: $out"
  sed -i.bak '$d' "$registry" && rm -f "$registry.bak"
  sed -i.bak '$d' "$ext" && rm -f "$ext.bak"

  # The other producer patterns: a message on the line after the call, a
  # command-registration description, a notification title, and board text.
  # shellcheck disable=SC2016 # literal TypeScript fixture text, backticks included
  printf '%s\n' '  ctx?.ui?.notify?.(' '    `Ask the captain first.`,' '    "warning",' '  );' >> "$ext"
  printf '%s\n' '  pi.registerCommand?.("probe", {' '    description:' '      "Hail the crew.",' '  });' >> "$ext"
  printf '%s\n' "osascript -e 'display notification \"x\" with title \"Second mate alert\"'" >> "$code/bin/fm-usage-warner.sh"
  printf '%s\n' '<p>All hands, ahoy</p>' '<!-- a comment that names the captain is not page text -->' >> "$board"
  out=$(canary_run "$code") && fail "anchors passed with unregistered nautical producer lines"
  assert_contains "$out" '"captain" (notify call) at .pi/extensions/fm-calm.ts:' "the canary missed a multi-line notify call"
  assert_contains "$out" '"crew" (command description) at .pi/extensions/fm-calm.ts:' "the canary missed a command description"
  assert_contains "$out" '"second mate" (notification title) at bin/fm-usage-warner.sh:' "the canary missed a notification title"
  assert_contains "$out" '"ahoy" (board text) at .agents/skills/bearings/assets/board-template.html:' "the canary missed board text"
  assert_not_contains "$out" "a comment that names the captain" "the canary scanned a page comment"

  # A residue row that matches nothing is noted, not failed.
  code=$(tree_copy canary-stale)
  printf 'bin/fm-usage-warner.sh\tno such producer text\tR4: test\n' >> "$code/.agents/skills/po-theme/residue.tsv"
  out=$(canary_run "$code") || fail "anchors failed on a stale residue row: $out"
  assert_contains "$out" "note: residue row matches no producer line; remove it: bin/fm-usage-warner.sh" "the canary did not note a stale residue row"

  # A tracked producer deleted from the work tree but not staged is skipped.
  printf '%s\n' 'echo probe' > "$code/bin/fm-canary-probe.sh"
  git -C "$code" add bin/fm-canary-probe.sh
  git -C "$code" commit -q -m probe
  rm "$code/bin/fm-canary-probe.sh"
  out=$(canary_run "$code") || fail "anchors failed with a deleted, unstaged tracked producer: $out"
  assert_not_contains "$out" "producer scan failed" "the canary scanned a deleted tracked producer"
  pass "the surface canary fails on an unregistered nautical producer line and passes registered and residue ones"
}

test_nautical_apply_writes_nothing() {
  local code home before after exclude_before out
  code=$(new_code nautical)
  home=$(new_home nautical)
  printf '# Shared captain preferences\n\n- Prefers terse summaries.\n' > "$home/data/captain-shared.md"
  exclude_before=$(cat "$code/.git/info/exclude" 2>/dev/null || true)
  before=$(snapshot "$home")
  out=$(run_in "$code" "$home" apply 2>&1) || fail "nautical apply failed: $out"
  assert_contains "$out" "nautical - nothing to write" "nautical apply did not report a no-op"
  printf 'nautical\n' > "$home/config/po-theme"
  before=$(snapshot "$home")
  run_in "$code" "$home" apply >/dev/null 2>&1 || fail "explicit nautical apply failed"
  after=$(snapshot "$home")
  assert_equals "$before" "$after" "nautical apply changed the home"
  assert_equals "$exclude_before" "$(cat "$code/.git/info/exclude" 2>/dev/null || true)" "nautical apply changed .git/info/exclude"
  assert_equals "" "$(git -C "$code" status --porcelain)" "nautical apply changed the code root"
  assert_equals "" "$(run_in "$code" "$home" persona)" "nautical printed a persona block"
  assert_equals "" "$(run_in "$code" "$home" worker-line)" "nautical printed a worker line"
  assert_equals "" "$(run_in "$code" "$home" address-alt)" "nautical printed a themed vocative"
  rm "$home/data/captain-shared.md"
  run_in "$code" "$home" apply >/dev/null 2>&1 || fail "nautical apply without a shared file failed"
  assert_absent "$home/data/captain-shared.md" "nautical apply created data/captain-shared.md"
  pass "nautical writes nothing: no block, no aliases, no exclude entries"
}

# shellcheck disable=SC2016,SC2012  # literal Markdown backticks; ls -l reads a mode string portably.
test_operator_apply() {
  local code home original first second out
  code=$(new_code operator)
  home=$(new_home operator)
  original=$(printf '# Shared captain preferences\n\n- Prefers terse summaries.\n')
  printf '%s\n' "$original" > "$home/data/captain-shared.md"
  chmod 0640 "$home/data/captain-shared.md"
  printf 'operator\n' > "$home/config/po-theme"
  out=$(run_in "$code" "$home" apply 2>&1) || fail "operator apply failed: $out"
  first=$(cat "$home/data/captain-shared.md")
  run_in "$code" "$home" apply >/dev/null 2>&1 || fail "second operator apply failed"
  second=$(cat "$home/data/captain-shared.md")
  assert_equals "$first" "$second" "apply is not idempotent"
  assert_equals 1 "$(grep -c '^<!-- po-theme:persona:start -->$' "$home/data/captain-shared.md")" "apply did not write exactly one block"
  assert_contains "$first" "- Prefers terse summaries." "apply dropped the captain's own prose"
  assert_contains "$first" '## Persona: operator' "the block has no Persona heading"
  assert_contains "$first" 'reply exactly `Operator, all systems nominal.`' "the block has no themed no-op reply"
  assert_contains "$first" '| first mate, firstmate (you) | spotter |' "the block does not map the first mate"
  assert_contains "$first" 'grant no authority and change no rule' "the block does not disclaim authority"
  assert_contains "$first" '/sitrep = /bearings' "the block does not list the aliases"
  assert_equals "-rw-r-----" "$(ls -l "$home/data/captain-shared.md" | cut -c1-10)" "apply changed the shared file's mode"
  printf 'nautical\n' > "$home/config/po-theme"
  out=$(run_in "$code" "$home" apply 2>&1) || fail "nautical rollback failed: $out"
  assert_contains "$out" "block removed" "nautical rollback did not report the removal"
  assert_equals "$original" "$(cat "$home/data/captain-shared.md")" "rollback did not restore the shared file byte-exact"
  rm "$home/data/captain-shared.md"
  printf 'operator\n' > "$home/config/po-theme"
  run_in "$code" "$home" apply >/dev/null 2>&1 || fail "operator apply without a shared file failed"
  assert_present "$home/data/captain-shared.md" "operator apply did not create the shared file"
  printf 'nautical\n' > "$home/config/po-theme"
  run_in "$code" "$home" apply >/dev/null 2>&1 || fail "rollback of a created shared file failed"
  assert_absent "$home/data/captain-shared.md" "rollback left an empty shared file apply had created"
  pass "operator apply writes one idempotent block, keeps prose and mode, and rolls back byte-exact"
}

test_session_start_prints_persona() {
  local code home root out context head
  code=$(new_code session)
  home=$(new_home session)
  root="$TMP_ROOT/session/root"
  git init -q -b main "$root"
  git -C "$root" commit -q --allow-empty -m init
  printf '# Shared captain preferences\n\n- Prefers terse summaries.\n' > "$home/data/captain-shared.md"
  printf 'operator\n' > "$home/config/po-theme"
  run_in "$code" "$home" apply >/dev/null 2>&1 || fail "operator apply failed before session start"
  out=$(env -u CLAUDECODE -u PI_CODING_AGENT -u FM_PI_HARNESS -u GROK_AGENT \
    FM_HOME="$home" FM_ROOT_OVERRIDE="$root" PATH="$BASE_PATH" "$ROOT/bin/fm-session-start.sh" 2>&1) \
    || fail "fm-session-start.sh failed: $out"
  context=$(printf '%s\n' "$out" | awk '/^CONTEXT$/ { on = 1 } on')
  assert_contains "$context" '## Persona: operator' "the session-start CONTEXT did not print the Persona block"
  assert_contains "$context" 'Operator, all systems nominal.' "the session-start CONTEXT did not carry the themed no-op reply"
  head=$(printf '%s\n' "$out" | awk '/^SESSION START - / { on = 1 } on && /^LOCK$/ { exit } on')
  assert_contains "$head" 'PERSONA (operator theme, chat words only): address the user as "Operator,"' "the session-start head did not carry the headline before LOCK"
  out=$(env -u CLAUDECODE -u PI_CODING_AGENT -u FM_PI_HARNESS -u GROK_AGENT \
    FM_HOME="$home" FM_ROOT_OVERRIDE="$root" PATH="$BASE_PATH" "$ROOT/bin/fm-session-start.sh" --reemit 2>&1) \
    || fail "fm-session-start.sh --reemit failed: $out"
  head=$(printf '%s\n' "$out" | awk '/^SESSION START [(]CONTEXT RE-EMIT[)] - / { on = 1 } on && /^LOCK$/ { exit } on')
  assert_contains "$head" 'PERSONA (operator theme' "the re-emit head did not carry the headline before LOCK"

  printf 'nautical\n' > "$home/config/po-theme"
  run_in "$code" "$home" apply >/dev/null 2>&1 || fail "nautical apply failed before session start"
  out=$(env -u CLAUDECODE -u PI_CODING_AGENT -u FM_PI_HARNESS -u GROK_AGENT \
    FM_HOME="$home" FM_ROOT_OVERRIDE="$root" PATH="$BASE_PATH" "$ROOT/bin/fm-session-start.sh" 2>&1) \
    || fail "nautical fm-session-start.sh failed: $out"
  head=$(printf '%s\n' "$out" | awk '/^SESSION START - / { on = 1; next } on && /^LOCK$/ { exit } on')
  assert_equals "$(printf '%s\n\n' "$(printf '%s\n' "$out" | awk '/^SESSION START - / { getline; print; exit }')")" "$head" \
    "nautical session start printed something between its header and LOCK"
  pass "the real session-start digest prints the headline before LOCK and the Persona block in CONTEXT"
}

# shellcheck disable=SC2016  # literal Markdown backticks.
test_headline() {
  local code home out
  code=$(new_code headline)
  home=$(new_home headline)
  printf '# prefs\n' > "$home/data/captain-shared.md"
  assert_equals "" "$(run_in "$code" "$home" headline)" "headline printed something under nautical"
  printf 'operator\n' > "$home/config/po-theme"
  assert_equals "persona drift: rerun apply in the primary home" "$(run_in "$code" "$home" headline)" \
    "headline before apply did not print exactly the drift line"
  run_in "$code" "$home" apply >/dev/null 2>&1 || fail "operator apply failed"
  out=$(run_in "$code" "$home" headline) || fail "headline failed after apply: $out"
  assert_equals 2 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "headline after apply is not exactly two lines: $out"
  assert_contains "$out" 'address the user as "Operator,"' "headline did not carry the address word"
  assert_contains "$out" 'the exact no-op reply is `Operator, all systems nominal.`' "headline did not carry the no-op reply"
  assert_contains "$out" 'say operator for captain, spotter for first mate, specialist for crewmate' "headline did not carry the role words"
  assert_contains "$out" "The full Persona block is in $home/data/captain-shared.md" "headline did not point at the full block"
  assert_not_contains "$out" "persona drift" "headline reported drift right after apply"

  sed -i.bak 's/all systems nominal/all good/' "$home/data/captain-shared.md"
  out=$(run_in "$code" "$home" headline) || fail "headline failed on a hand-edited block: $out"
  assert_equals 3 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "headline on drift is not exactly three lines: $out"
  assert_equals "persona drift: rerun apply in the primary home" "$(printf '%s\n' "$out" | tail -n 1)" "headline did not end with the drift line"
  mv "$home/data/captain-shared.md.bak" "$home/data/captain-shared.md"

  printf 'nautical\n' > "$home/config/po-theme"
  assert_equals "persona drift: rerun apply in the primary home" "$(run_in "$code" "$home" headline)" \
    "headline under nautical with a stale Persona block did not print exactly the drift line"
  run_in "$code" "$home" apply >/dev/null 2>&1 || fail "nautical apply failed"
  assert_equals "" "$(run_in "$code" "$home" headline)" "headline printed something after nautical apply"
  pass "headline is empty under nautical, prints the applied persona, and adds one drift line on drift"
}

test_intent_address_check() {
  local home lib upstream line theme got want
  home=$(new_home intent)
  lib="$ROOT/bin"
  printf 'operator\n' > "$home/config/po-theme"
  intent_refused "$lib" "$home" 'Operator, please add a flag.' || fail "operator theme allowed 'Operator,' in the intent"
  intent_refused "$lib" "$home" 'Operator: add a flag.' || fail "operator theme allowed 'Operator:' in the intent"
  intent_refused "$lib" "$home" 'Captain, add a flag.' || fail "operator theme allowed 'Captain,' in the intent"
  intent_refused "$lib" "$home" 'Add a flag; the operator wants it.' && fail "operator theme refused a third-person mention"
  printf 'nautical\n' > "$home/config/po-theme"
  intent_refused "$lib" "$home" 'Operator, please add a flag.' && fail "nautical refused 'Operator,' unlike upstream"
  intent_refused "$lib" "$home" 'Captain, add a flag.' || fail "nautical allowed 'Captain,' in the intent"

  upstream=$(upstream_lib_dir)
  if [ -z "$upstream" ]; then
    printf 'note: upstream pin %s is not in this clone; nautical parity checked only against the table\n' "${PIN:-?}"
  else
    while IFS= read -r line; do
      want=allowed; intent_refused "$upstream" "$home" "$line" && want=refused
      got=allowed; intent_refused "$lib" "$home" "$line" && got=refused
      assert_equals "$want" "$got" "nautical diverged from upstream on: $line"
    done <<'EOF'
Captain, add a flag.
Captain: add a flag.
Captain's words: add a flag.
Captain's ask: add a flag.
  Captain, indented.
Operator, please add a flag.
Operator: add a flag.
Add a flag; the captain wants it.
Add a flag; the operator wants it.
Captains, all of you.
EOF
  fi
  for theme in operator nautical; do
    printf '%s\n' "$theme" > "$home/config/po-theme"
    intent_refused "$lib" "$home" 'Operators, all of you.' && fail "$theme refused a plural that is not the vocative"
  done
  pass "the intent check refuses the themed vocative and matches upstream under nautical"
}

test_worker_role_contract() {
  local home nautical operator upstream added
  home=$(new_home role)
  nautical=$(role_of "$ROOT/bin" "$home")
  upstream=$(upstream_lib_dir)
  if [ -n "$upstream" ]; then
    assert_equals "$(role_of "$upstream" "$home")" "$nautical" "the nautical role contract differs from upstream"
  else
    printf 'note: upstream pin %s is not in this clone; nautical role contract compared only to the themed one\n' "${PIN:-?}"
  fi
  assert_not_contains "$nautical" "Vocabulary for prose" "the nautical role contract carries a vocabulary line"
  printf 'operator\n' > "$home/config/po-theme"
  operator=$(role_of "$ROOT/bin" "$home")
  added=$(diff <(printf '%s\n' "$nautical") <(printf '%s\n' "$operator") | grep -E '^[<>]' || true)
  assert_equals "$(printf '%s\n' "$added" | wc -l | tr -d ' ')" 1 "the operator role contract changed more than one line"
  assert_contains "$added" '> Vocabulary for prose a person reads' "the operator role contract did not add the vocabulary line"
  assert_contains "$added" 'firstmate "spotter", crewmates "specialists"' "the vocabulary line does not carry the theme words"
  pass "the worker role contract is upstream under nautical and gains exactly one line under a theme"
}

# wake_prompt <root> <home> <args...>: the branch wake prompt that root's
# dispatch entry prints for one fixed wake reason under that home.
wake_prompt() {
  local root=$1 home=$2
  shift 2
  printf 'signal: fm-task-1 done\n' | FM_HOME="$home" node "$root/bin/fm-branch-dispatch.mjs" wake-prompt "$@"
}

# upstream_dispatch_root: a code root whose wake-prompt module is the upstream
# pin's, beside this tree's dispatch entry. Echoes nothing when the pin commit
# is not in this clone.
upstream_dispatch_root() {
  local dir="$TMP_ROOT/upstream-dispatch"
  [ -d "$dir" ] && { printf '%s\n' "$dir"; return 0; }
  [ -n "$PIN" ] && git -C "$ROOT" cat-file -e "$PIN:.pi/extensions/lib/fm-branch-dispatch.ts" 2>/dev/null || return 0
  mkdir -p "$dir/bin" "$dir/.pi/extensions"
  cp "$ROOT/bin/fm-branch-dispatch.mjs" "$dir/bin/"
  cp -R "$ROOT/.pi/extensions/lib" "$dir/.pi/extensions/"
  git -C "$ROOT" show "$PIN:.pi/extensions/lib/fm-branch-dispatch.ts" > "$dir/.pi/extensions/lib/fm-branch-dispatch.ts"
  printf '%s\n' "$dir"
}

test_wake_prompt_tail() {
  local home upstream nautical operator broken readback mirror args added surface
  command -v node >/dev/null 2>&1 || { echo "skip: node absent (branch wake prompt)"; return 0; }
  home=$(new_home wake)
  readback="$TMP_ROOT/wake/readback"
  mirror="$TMP_ROOT/wake/mirror"
  printf 'Merge anything green.\n' > "$readback"
  printf '[captain] keep going\n' > "$mirror"
  upstream=$(upstream_dispatch_root)
  [ -n "$upstream" ] || printf 'note: upstream pin %s is not in this clone; the nautical wake prompt is compared only to the themed one\n' "${PIN:-?}"
  for args in "--report fm_branch_report" "--report bin/fm-branch-report.sh --mirror-file $mirror --away --readback-file $readback"; do
    # shellcheck disable=SC2086  # each case is a word list of flags.
    nautical=$(wake_prompt "$ROOT" "$home" $args) || fail "the nautical wake prompt failed ($args)"
    # shellcheck disable=SC2086
    [ -z "$upstream" ] || assert_equals "$(wake_prompt "$upstream" "$home" $args)" "$nautical" "the nautical wake prompt differs from upstream ($args)"
    assert_not_contains "$nautical" "Vocabulary for" "the nautical wake prompt carries a vocabulary line ($args)"
    printf 'no-such-theme\n' > "$home/config/po-theme"
    # shellcheck disable=SC2086
    broken=$(wake_prompt "$ROOT" "$home" $args) || fail "the wake prompt failed under an unresolvable selection ($args)"
    assert_equals "$nautical" "$broken" "an unresolvable selection changed the wake prompt ($args)"
    printf 'operator\n' > "$home/config/po-theme"
    # shellcheck disable=SC2086
    operator=$(wake_prompt "$ROOT" "$home" $args) || fail "the themed wake prompt failed ($args)"
    rm "$home/config/po-theme"
    added=$(diff <(printf '%s\n' "$nautical") <(printf '%s\n' "$operator") | grep -E '^[<>]' || true)
    assert_equals 2 "$(printf '%s\n' "$added" | wc -l | tr -d ' ')" "the themed wake prompt changed more than the vocabulary paragraph ($args)"
    assert_contains "$added" '> Vocabulary for the outcome summaries a person reads: this home calls the captain "operator", firstmate "spotter"' "the themed wake prompt lacks the theme words ($args)"
    surface=${args#--report }
    assert_contains "$operator" "$(printf 'finish with %s.\n\nVocabulary for' "${surface%% *}")" "the vocabulary paragraph does not follow the report instruction ($args)"
  done
  assert_contains "$operator" "$(printf 'verdict values, identifiers, and every rule above keep their exact words and meaning.\n\nPOSTURE: AWAY.')" "the vocabulary paragraph is not placed before the away tail"
  assert_contains "$operator" "$(printf 'The record, verbatim:\nMerge anything green.')" "the away record no longer ends the themed wake prompt"
  nautical=$(FM_HOME="$home" "$ROOT/bin/fm-branch-prompt.sh") || fail "the nautical branch system prompt failed"
  printf 'operator\n' > "$home/config/po-theme"
  operator=$(FM_HOME="$home" "$ROOT/bin/fm-branch-prompt.sh") || fail "the themed branch system prompt failed"
  rm "$home/config/po-theme"
  assert_equals "$nautical" "$operator" "a theme changed the branch system prompt"
  pass "the branch wake prompt is upstream under nautical, gains one vocabulary paragraph under a theme, and the system prompt stays byte-identical"
}

# One long-lived host (the Pi branch) builds many wake prompts: wake-line runs
# once per theme selection, never under nautical, and again only when the
# selection or its theme file changes.
test_wake_vocabulary_memo() {
  local home code log kill out
  command -v node >/dev/null 2>&1 || { echo "skip: node absent (wake vocabulary memo)"; return 0; }
  home=$(new_home wake-memo)
  code="$TMP_ROOT/wake-memo/code"
  log="$TMP_ROOT/wake-memo/spawns"
  kill="$TMP_ROOT/wake-memo/kill-next"
  mkdir -p "$code/bin" "$code/.pi/extensions"
  cp -R "$ROOT/.pi/extensions/lib" "$code/.pi/extensions/"
  cp -R "$ROOT/.agents" "$code/"
  printf '#!/usr/bin/env bash\necho "$*" >> %q\n[ ! -e %q ] || { rm -f %q; kill -TERM $$; }\nexec %q "$@"\n' "$log" "$kill" "$kill" "$ROOT/bin/po-theme.sh" > "$code/bin/po-theme.sh"
  chmod +x "$code/bin/po-theme.sh"
  : > "$log"
  # shellcheck disable=SC2016  # the template literals belong to the node script.
  out=$(FM_HOME="$home" SPAWNS="$log" KILL_NEXT="$kill" node --input-type=module -e '
    const { readFileSync, writeFileSync, copyFileSync, rmSync } = await import("node:fs");
    const [module, home, operator] = process.argv.slice(1);
    const dispatch = await import(module);
    const spawns = () => readFileSync(process.env.SPAWNS, "utf8").split("\n").filter(Boolean).length;
    const step = (label) => { const prompt = dispatch.branchWakePrompt("signal: fm-task-1 done", "fm_branch_report", ""); const words = /captain "([^"]*)"/.exec(prompt); console.log(`${label} spawns=${spawns()} captain=${words ? words[1] : "-"}`); };
    step("nautical"); step("nautical-again");
    writeFileSync(`${home}/config/po-theme`, "operator\n");
    step("operator"); step("operator-again");
    writeFileSync(`${home}/config/po-themes/operator.theme`, readFileSync(operator, "utf8").replace(/^user = .*$/m, "user = \"skipper\""));
    step("shadowed"); step("shadowed-again");
    rmSync(`${home}/config/po-themes/operator.theme`); writeFileSync(process.env.KILL_NEXT, "");
    step("killed"); step("retried"); step("retried-again");
    writeFileSync(`${home}/config/po-theme`, "no-such-theme\n");
    step("unresolvable"); step("unresolvable-again");
    writeFileSync(`${home}/config/po-theme`, "nautical\n");
    step("back-to-nautical");
  ' "file://$code/.pi/extensions/lib/fm-branch-dispatch.ts" "$home" "$ROOT/.agents/skills/po-theme/themes/operator.theme") \
    || fail "the wake vocabulary memo script failed"
  assert_equals "$(printf '%s\n' \
    'nautical spawns=0 captain=-' 'nautical-again spawns=0 captain=-' \
    'operator spawns=1 captain=operator' 'operator-again spawns=1 captain=operator' \
    'shadowed spawns=2 captain=skipper' 'shadowed-again spawns=2 captain=skipper' \
    'killed spawns=3 captain=-' 'retried spawns=4 captain=operator' 'retried-again spawns=4 captain=operator' \
    'unresolvable spawns=5 captain=-' 'unresolvable-again spawns=5 captain=-' \
    'back-to-nautical spawns=5 captain=-')" "$out" "wake-line did not run exactly once per theme selection, or a killed run was remembered"
  assert_equals "wake-line" "$(sort -u "$log")" "the memo ran a po-theme command other than wake-line"
  pass "wake-line runs once per theme selection, never under nautical, again when the selection changes, and again after a killed run"
}

test_secondmate_home() {
  local code primary mate out
  code=$(new_code secondmate)
  primary=$(new_home secondmate-primary)
  mate="$TMP_ROOT/secondmate/mate"
  mkdir -p "$mate/data" "$mate/config"
  printf 'fmtest-sm\n' > "$mate/.fm-secondmate-home"
  derive "$primary" drill 's/^self = .*/self = "sergeant"/; s/^self_plural = .*/self_plural = "sergeants"/; s/^user_address = .*/user_address = "Boss"/; s/^user = .*/user = "boss"/; s/^user_plural = .*/user_plural = "bosses"/; s/^product = .*/product = "operator"/; s/^noop_reply = .*/noop_reply = "Boss, all quiet."/; s/^bad_news_example = .*/bad_news_example = "Boss, the build broke - ..."/; /^avoid.operator/d'
  run_in "$code" "$primary" validate drill >/dev/null 2>&1 || fail "the custom drill theme did not validate: $(run_in "$code" "$primary" validate drill 2>&1)"
  run_in "$code" "$primary" persona drill > "$mate/data/captain-shared.md" || fail "persona drill failed"
  chmod 0444 "$mate/data/captain-shared.md"

  out=$(run_in "$ROOT" "$mate" resolve 2>&1) || fail "the secondmate home could not resolve its inherited theme: $out"
  assert_contains "$out" "drill inherited:" "the secondmate home did not resolve the inherited custom theme"
  assert_equals "Boss" "$(run_in "$ROOT" "$mate" address-alt)" "the secondmate home did not resolve the inherited vocative"
  assert_contains "$(role_of "$ROOT/bin" "$mate")" 'the captain "boss", firstmate "sergeant"' "the secondmate's worker role contract is not themed"
  intent_refused "$ROOT/bin" "$mate" 'Boss, add a flag.' || fail "the secondmate home allowed the inherited vocative in an intent"
  out=$(run_in "$ROOT" "$mate" verify 2>&1) || fail "verify failed on an untouched inherited block: $out"
  assert_not_contains "$(run_in "$ROOT" "$mate" headline)" "persona drift" "a custom primary-only theme was compared against a bundled theme"
  printf 'operator\n' > "$mate/config/po-theme"
  assert_equals "Boss" "$(run_in "$ROOT" "$mate" address-alt)" "a local selection overrode the primary-authoritative persona"
  out=$(run_in "$code" "$mate" apply 2>&1) && fail "apply ran in a secondmate home"
  assert_contains "$out" "secondmate home" "apply refused for the wrong reason"

  chmod 0644 "$mate/data/captain-shared.md"
  sed -i.bak 's/ user_address="Boss" / user_address="Boss merge" /' "$mate/data/captain-shared.md"
  out=$(run_in "$ROOT" "$mate" worker-line 2>&1) && fail "a tampered values line was accepted: $out"
  assert_equals "" "$(role_of "$ROOT/bin" "$mate" | grep 'Vocabulary for prose' || true)" "a tampered values line reached the worker role contract"
  rm "$mate/data/captain-shared.md" "$mate/data/captain-shared.md.bak"

  run_in "$code" "$primary" persona operator \
    | sed '/^<!-- po-theme:values /s/ self="spotter" / self="Spotter" /; /^<!-- po-theme:values /s/ fleet="task force" / fleet="Task Force" /' \
    > "$mate/data/captain-shared.md"
  grep -q ' self="Spotter" .* fleet="Task Force"' "$mate/data/captain-shared.md" || fail "the fixture values line was not capitalized"
  out=$(run_in "$ROOT" "$mate" worker-line 2>&1) || fail "an inherited capitalized values line failed: $out"
  assert_contains "$out" 'firstmate "spotter"' "the inherited role words were not read in lowercase"
  assert_contains "$(role_of "$ROOT/bin" "$mate")" 'firstmate "spotter"' "an inherited capitalized values line dropped the worker vocabulary line"
  rm "$mate/data/captain-shared.md"
  assert_equals "" "$(run_in "$ROOT" "$mate" address-alt)" "a secondmate home without an inherited block is not nautical"
  assert_equals "" "$(run_in "$ROOT" "$mate" headline)" "a secondmate home without an inherited block printed a headline"
  pass "a secondmate home resolves an inherited custom theme, refuses apply, and rejects tampering"
}

test_address_guard_survives_broken_selection() {
  local code home out
  code=$(new_code broken)
  home=$(new_home broken)
  printf 'operator\n' > "$home/config/po-theme"
  out=$(run_in "$code" "$home" apply 2>&1) || fail "operator apply failed: $out"
  printf 'nosuch\n' > "$home/config/po-theme"
  run_in "$ROOT" "$home" resolve >/dev/null 2>&1 && fail "an unknown selection resolved"
  assert_equals "Operator" "$(run_in "$ROOT" "$home" address-alt 2>/dev/null)" "an unknown selection dropped the vocative the Persona block still sets"
  intent_refused "$ROOT/bin" "$home" 'Operator, please add a flag.' || fail "an unknown selection let 'Operator,' through the intent check"
  derive "$home" drill 's/^user_address = .*/user_address = "Boss"/; s/^noop_reply = .*/noop_reply = "Boss, all quiet."/; s/^bad_news_example = .*/bad_news_example = "Boss, the build broke - ..."/'
  printf 'drill\n' > "$home/config/po-theme"
  out=$(run_in "$code" "$home" apply 2>&1) || fail "drill apply failed: $out"
  printf 'user_address = "not one word"\n' >> "$home/config/po-themes/drill.theme"
  run_in "$ROOT" "$home" resolve >/dev/null 2>&1 && fail "an invalid local theme resolved"
  intent_refused "$ROOT/bin" "$home" 'Boss, add a flag.' || fail "an invalid local theme let the applied vocative through the intent check"
  pass "the intent check keeps the applied vocative when the selection breaks after apply"
}

test_persona_aliases_primary_only() {
  local code primary mate block out
  code=$(new_code aliasscope)
  primary=$(new_home aliasscope-primary)
  printf 'operator\n' > "$primary/config/po-theme"
  out=$(run_in "$code" "$primary" apply 2>&1) || fail "operator apply failed: $out"
  assert_present "$code/.agents/skills/sitrep/SKILL.md" "the primary home did not generate /sitrep"
  block=$(cat "$primary/data/captain-shared.md")
  assert_contains "$block" '- Command aliases, generated in the primary home only (a second-mate home keeps the original command names): /' "the block does not scope the aliases to the primary home"
  assert_contains "$block" ' /sitrep = /bearings;' "the block does not list the aliases"
  assert_contains "$block" 'in the primary home, treat each alias exactly as its target.' "the block does not limit alias use to the primary home"
  mate="$TMP_ROOT/aliasscope/mate"
  mkdir -p "$mate/data"
  printf 'fmtest-sm\n' > "$mate/.fm-secondmate-home"
  cp "$primary/data/captain-shared.md" "$mate/data/captain-shared.md"
  out=$(run_in "$code" "$mate" verify 2>&1) || fail "the inherited block with scoped aliases failed verify: $out"
  out=$(run_in "$code" "$mate" apply 2>&1) && fail "apply generated aliases in a secondmate home"
  pass "the Persona block advertises the aliases as primary-home commands only"
}

# shellcheck disable=SC2016  # backticks are literal Markdown the assertions match.
test_aliases_keep_tree_clean() {
  local code home exclude_before out a
  code=$(new_code aliases)
  home=$(new_home aliases)
  printf '# local excludes\n*.swp\n' > "$code/.git/info/exclude"
  exclude_before=$(cat "$code/.git/info/exclude")
  printf 'operator\n' > "$home/config/po-theme"
  out=$(run_in "$code" "$home" apply 2>&1) || fail "operator apply failed: $out"
  for a in sitrep debrief flush updateoperator; do
    assert_present "$code/.agents/skills/$a/SKILL.md" "alias /$a was not generated"
  done
  assert_grep 'Load the `bearings` skill' "$code/.agents/skills/sitrep/SKILL.md" "/sitrep does not delegate to /bearings"
  assert_absent "$code/.agents/skills/afk/.po-theme-alias" "an unchanged command was aliased"
  assert_equals "" "$(git -C "$code" status --porcelain)" "generated aliases dirtied git status"
  # shellcheck source=bin/fm-ff-lib.sh
  assert_equals "" "$(bash -c '. "$1/bin/fm-ff-lib.sh"; dirty_status "$2"' _ "$ROOT" "$code")" \
    "the guarded self-update would treat the aliased tree as dirty"

  mkdir -p "$code/.agents/skills/tracked"
  printf -- '---\nname: tracked\n---\n' > "$code/.agents/skills/tracked/SKILL.md"
  : > "$code/.agents/skills/tracked/.po-theme-alias"
  git -C "$code" add .agents/skills/tracked
  git -C "$code" commit -q -m tracked
  printf 'nautical\n' > "$home/config/po-theme"
  run_in "$code" "$home" apply >/dev/null 2>&1 || fail "nautical apply failed"
  for a in sitrep debrief flush updateoperator; do
    assert_absent "$code/.agents/skills/$a" "nautical apply left alias /$a"
  done
  assert_present "$code/.agents/skills/tracked/SKILL.md" "apply removed a tracked skill that carried the alias marker"
  assert_equals "$exclude_before" "$(cat "$code/.git/info/exclude")" "nautical apply did not restore .git/info/exclude"
  pass "aliases are generated clean and nautical apply removes them and their exclude entries"
}

test_verify_reports_drift() {
  local code home out
  code=$(new_code verify)
  home=$(new_home verify)
  printf '# prefs\n' > "$home/data/captain-shared.md"
  out=$(run_in "$code" "$home" verify 2>&1) || fail "verify failed on a clean nautical home: $out"
  printf 'operator\n' > "$home/config/po-theme"
  out=$(run_in "$code" "$home" verify 2>&1) && fail "verify passed before apply"
  assert_contains "$out" "has no Persona block" "verify did not report the missing block"
  run_in "$code" "$home" apply >/dev/null 2>&1 || fail "operator apply failed"
  out=$(run_in "$code" "$home" verify 2>&1) || fail "verify failed right after apply: $out"
  assert_contains "$out" "verify: ok (operator)" "verify did not confirm the applied theme"

  sed -i.bak 's/all systems nominal/all good/' "$home/data/captain-shared.md"
  out=$(run_in "$code" "$home" verify 2>&1) && fail "verify passed on a hand-edited block"
  assert_contains "$out" "stale or hand-edited" "verify did not report the hand edit"
  mv "$home/data/captain-shared.md.bak" "$home/data/captain-shared.md"

  derive "$home" drill 's/^self = .*/self = "sergeant"/; s/^self_plural = .*/self_plural = "sergeants"/'
  printf 'drill\n' > "$home/config/po-theme"
  out=$(run_in "$code" "$home" verify 2>&1) && fail "verify passed after the selection changed without apply"
  assert_contains "$out" "stale or hand-edited" "verify did not report the stale block"
  printf 'operator\n' > "$home/config/po-theme"

  rm -rf "$code/.agents/skills/sitrep"
  out=$(run_in "$code" "$home" verify 2>&1) && fail "verify passed with a missing alias"
  assert_contains "$out" "alias /sitrep for /bearings is missing" "verify did not report the missing alias"
  run_in "$code" "$home" apply >/dev/null 2>&1 || fail "re-apply failed"

  printf 'nautical\n' > "$home/config/po-theme"
  out=$(run_in "$code" "$home" verify 2>&1) && fail "verify passed with a block left under nautical"
  assert_contains "$out" "nautical is selected but" "verify did not report the unexpected block"
  assert_contains "$out" "is not in theme nautical" "verify did not report the leftover aliases"
  pass "verify reports stale, hand-edited, missing, and unexpected blocks and alias drift"
}

block_of_file() {  # <file>: its Persona block, markers included
  awk '/^<!-- po-theme:persona:start -->$/ { on = 1 } on { print } /^<!-- po-theme:persona:end -->$/ { on = 0 }' "$1"
}

# shellcheck disable=SC2016  # literal Markdown backticks.
test_secondmate_older_block() {
  local code primary mate out
  code=$(new_code older)
  primary=$(new_home older-primary)
  mate="$TMP_ROOT/older/mate"
  mkdir -p "$mate/data" "$mate/config"
  printf 'fmtest-sm\n' > "$mate/.fm-secondmate-home"
  run_in "$code" "$primary" persona operator > "$mate/data/captain-shared.md" || fail "persona operator failed"
  out=$(run_in "$ROOT" "$mate" verify 2>&1) || fail "verify failed on a current inherited bundled block: $out"
  assert_not_contains "$(run_in "$ROOT" "$mate" headline)" "persona drift" "headline reported drift on a current inherited block"

  # An older block: written before the str.* keys existed, so its values line
  # lacks them while still matching its own text.
  run_in "$code" "$primary" persona operator \
    | sed '/^<!-- po-theme:values /s/ str\.[a-z_.]*="[^"]*"//g' > "$mate/data/captain-shared.md"
  grep -q 'str\.' "$mate/data/captain-shared.md" && fail "the fixture block still carries str.* keys"
  out=$(run_in "$ROOT" "$mate" verify 2>&1) && fail "verify passed on an inherited block older than the bundled theme"
  assert_contains "$out" "persona drift: inherited block differs from the bundled operator theme; rerun apply in the primary home (or update this home if it is newer)" \
    "verify did not report the older inherited block"
  assert_not_contains "$out" "hand-edited" "verify called a self-consistent older block hand-edited"
  out=$(run_in "$ROOT" "$mate" headline) || fail "headline failed on an older inherited block: $out"
  assert_contains "$out" 'address the user as "Operator,"' "headline dropped the inherited persona on drift"
  assert_equals "persona drift: inherited block differs from the bundled operator theme; rerun apply in the primary home (or update this home if it is newer)" \
    "$(printf '%s\n' "$out" | tail -n 1)" "headline in a secondmate home did not report the older block"

  # A local theme in the primary home that shadows the bundled operator theme
  # is a custom primary-only theme: apply marks it and the secondmate skips the
  # bundled comparison, while a hand-edit is still caught.
  derive "$primary" operator 's/^noop_reply = .*/noop_reply = "Operator, all clear."/'
  printf 'operator\n' > "$primary/config/po-theme"
  printf '# prefs\n' > "$primary/data/captain-shared.md"
  run_in "$code" "$primary" apply >/dev/null 2>&1 || fail "apply of a local operator theme failed"
  out=$(run_in "$code" "$primary" verify 2>&1) || fail "verify failed right after applying a local theme: $out"
  grep -q '^<!-- po-theme:values .* source=local -->$' "$primary/data/captain-shared.md" \
    || fail "apply of a local theme did not record source=local in the values line"
  block_of_file "$primary/data/captain-shared.md" > "$mate/data/captain-shared.md"
  out=$(run_in "$ROOT" "$mate" verify 2>&1) || fail "verify compared a local primary theme against the bundled one: $out"
  out=$(run_in "$ROOT" "$mate" headline) || fail "headline failed on an inherited local theme: $out"
  assert_contains "$out" 'the exact no-op reply is `Operator, all clear.`' "headline did not carry the local theme's no-op reply"
  assert_not_contains "$out" "persona drift" "headline reported drift for an inherited local theme"
  sed -i.bak 's/^- Wherever AGENTS.md requires the exact reply .*/- hand-edited/' "$mate/data/captain-shared.md"
  out=$(run_in "$ROOT" "$mate" verify 2>&1) && fail "verify passed a hand-edited inherited local block"
  assert_contains "$out" "hand-edited" "verify did not report a hand-edited inherited local block"
  rm "$mate/data/captain-shared.md.bak"
  pass "a secondmate home reports an older bundled block and skips the comparison for a local primary theme"
}

test_terms_and_resolve() {
  local home
  home=$(new_home terms)
  assert_equals "nautical $ROOT/.agents/skills/po-theme/themes/nautical.theme" "$(FM_HOME="$home" "$PT" resolve)" \
    "a home without a selection did not resolve the bundled nautical theme"
  printf 'operator\n' > "$home/config/po-theme"
  assert_equals "task force" "$(FM_HOME="$home" "$PT" term fleet)" "term did not read the active theme"
  assert_equals "fleet" "$(FM_HOME="$home" "$PT" term fleet --theme nautical)" "term --theme did not read the named theme"
  printf 'no-such\n' > "$home/config/po-theme"
  FM_HOME="$home" "$PT" resolve >/dev/null 2>&1 && fail "an unknown selection resolved"
  printf '../etc\n' > "$home/config/po-theme"
  FM_HOME="$home" "$PT" resolve >/dev/null 2>&1 && fail "a path-shaped selection resolved"
  pass "resolve and term read the selection and refuse unknown or path-shaped names"
}

test_bundled_themes_validate
test_validation_refusals
test_anchors
test_surface_canary
test_nautical_apply_writes_nothing
test_operator_apply
test_session_start_prints_persona
test_headline
test_intent_address_check
test_worker_role_contract
test_wake_prompt_tail
test_wake_vocabulary_memo
test_secondmate_home
test_address_guard_survives_broken_selection
test_persona_aliases_primary_only
test_aliases_keep_tree_clean
test_verify_reports_drift
test_secondmate_older_block
test_terms_and_resolve

echo "all po-theme tests passed"
