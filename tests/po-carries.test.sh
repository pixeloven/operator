#!/usr/bin/env bash
# tests/po-carries.test.sh - behavior tests for the carry register (ADR-0041):
# bin/po-carries.sh, which gate A4 runs, and the fix-carry exception in gate A9
# (bin/po-theme.sh registry check-diff).
#
# Coverage:
#   - check-paths passes when every changed path is a theme-hook file, a path
#     row, or a whole-path match of a regex row, and names each other path;
#     uncovered reports the same verdict for paths on stdin, so a regex row
#     never matches a longer path, a nested path, or another case
#   - every malformed row is refused with a message naming its line, and a
#     missing or malformed register fails check-paths
#   - a fix row whose path is back to upstream bytes fails check-paths, while an
#     ADR's sync row in that state only prints a note
#   - A9 refuses an unregistered changed line in a theme-hook file, still does
#     so when only an ADR row names the file, and accepts it once a fix row
#     names the file; the file's hooks are still counted and still have to
#     replace their upstream lines
#   - on this tree the register validates, check-paths passes against the
#     upstream pin, and the PixelOven namespaces admit exactly their own paths
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PC="$ROOT/bin/po-carries.sh"
PT="$ROOT/bin/po-theme.sh"
PIN=$(tr -d '[:space:]' < "$ROOT/docs/pixeloven/upstream-pin" 2>/dev/null || true)
TMP_ROOT=$(fm_test_tmproot po-carries)
fm_git_identity fmtest fmtest@example.invalid

# fixture <name>: a throwaway repository whose one commit stands for upstream:
# bin/x.sh, which the fixture's hook registry lists with one theme hook, plus
# bin/up.sh, docs/up.md, and one ADR record. The working tree then carries the
# PixelOven helpers and applies the hook, so bin/x.sh differs only by its hook.
fixture() {
  local repo="$TMP_ROOT/$1"
  mkdir -p "$repo/bin" "$repo/docs/adr" "$repo/docs/pixeloven" "$repo/.agents/skills/po-theme"
  printf 'say firstmate\nkeep\n' > "$repo/bin/x.sh"
  printf 'up\n' > "$repo/bin/up.sh"
  printf 'up\n' > "$repo/docs/up.md"
  printf '# ADR-0001: fixture\n' > "$repo/docs/adr/0001-fixture.md"
  git init -q -b main "$repo"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m upstream
  cp "$PT" "$PC" "$ROOT/bin/po-theme-lib.sh" "$ROOT/bin/po-design-lib.sh" "$repo/bin/"
  cp -R "$ROOT/.agents/skills/po-theme/themes" "$ROOT/.agents/skills/po-theme/designs" "$repo/.agents/skills/po-theme/"
  # shellcheck disable=SC2016 # the hook line is literal shell text
  printf 'str.x\tT\tbin/x.sh\tupstream\tsay "$who"\tsay firstmate\n' > "$repo/.agents/skills/po-theme/surfaces.tsv"
  # shellcheck disable=SC2016 # the hook line is literal shell text
  printf 'say "$who"\nkeep\n' > "$repo/bin/x.sh"
  printf '%s\n' "$repo"
}

# register <repo> <row>...: write the fixture's carry register; each row's
# fields are separated by | in the argument.
register() {
  local repo=$1 row
  shift
  printf '# fixture carry register\n' > "$repo/docs/pixeloven/carries.tsv"
  for row in "$@"; do
    printf '%s\n' "$row" | tr '|' '\t' >> "$repo/docs/pixeloven/carries.tsv"
  done
}

test_paths_follow_the_register() {
  local repo out status
  repo=$(fixture paths)
  register "$repo" \
    'regex|bin/po-[a-z0-9-]+\.sh|ADR-0001|decision|-|fork scripts' \
    'path|bin/up.sh|ADR-0001|decision|-|a carried edit'
  printf 'changed\n' > "$repo/bin/up.sh"
  printf 'new\n' > "$repo/bin/po-new.sh"
  git -C "$repo" add -N bin/po-new.sh
  out=$("$repo/bin/po-carries.sh" check-paths HEAD 2>&1)
  status=$?
  expect_code 0 "$status" "check-paths on a covered tree"
  assert_contains "$out" "carries: every path that differs from HEAD is covered" "check-paths did not report the covered tree"
  printf 'changed\n' > "$repo/docs/up.md"
  out=$("$repo/bin/po-carries.sh" check-paths HEAD 2>&1)
  status=$?
  expect_code 1 "$status" "check-paths with an uncovered path"
  assert_contains "$out" "A4: docs/up.md: in no PixelOven namespace, carry register row, or theme hook registry" "check-paths did not name the uncovered path"
  assert_not_contains "$out" "A4: bin/" "check-paths named a covered path"
  out=$(printf '%s\n' bin/po-a.sh bin/po-a/b.sh bin/po-A.sh xbin/po-a.sh bin/po-a.sh.bak bin/up.sh bin/up.sh.bak bin/x.sh \
    | "$repo/bin/po-carries.sh" uncovered)
  assert_equals "$(printf '%s\n' bin/po-a/b.sh bin/po-A.sh xbin/po-a.sh bin/po-a.sh.bak bin/up.sh.bak)" "$out" \
    "uncovered did not hold regex rows to whole paths and path rows to exact paths"
  pass "A4 admits theme-hook files, exact path rows, and whole-path regex matches, and names every other changed path"
}

test_malformed_register_is_refused() {
  local repo out status
  repo=$(fixture malformed)
  expect_malformed() {  # <message> <row>...
    local want=$1
    shift
    register "$repo" "$@"
    out=$("$repo/bin/po-carries.sh" validate 2>&1)
    status=$?
    expect_code 1 "$status" "validate on a register with: $want"
    assert_contains "$out" "$want" "validate did not name the malformed row"
  }
  expect_malformed "line 2: expected 6 tab-separated fields, found 5" 'path|bin/up.sh|ADR-0001|sync|-'
  expect_malformed "line 2: match must be path or regex, not glob" 'glob|bin/*|ADR-0001|decision|-|x'
  expect_malformed "line 2: empty path" 'path||ADR-0001|decision|-|x'
  expect_malformed "line 2: owner ADR-0099 is neither fix nor an ADR with a record under docs/adr/" 'path|bin/up.sh|ADR-0099|sync|-|x'
  expect_malformed "line 2: retire must be sync or decision, not never" 'path|bin/up.sh|ADR-0001|never|-|x'
  expect_malformed "line 2: upstream must be - or an https:// link, not http://example.invalid/1" 'path|bin/up.sh|fix|sync|http://example.invalid/1|x'
  expect_malformed "line 2: empty note" 'path|bin/up.sh|ADR-0001|sync|-|'
  expect_malformed "line 2: a fix row names one exact path" 'regex|bin/.*|fix|sync|-|x'
  expect_malformed "line 2: a fix row retires at sync" 'path|bin/up.sh|fix|decision|-|x'
  expect_malformed "line 2: a fix row needs a note saying what it fixes" 'path|bin/up.sh|fix|sync|-|-'
  expect_malformed "line 3: repeats the row on line 2" 'path|bin/up.sh|ADR-0001|sync|-|x' 'path|bin/up.sh|ADR-0001|sync|-|y'
  expect_malformed "grep -E refuses the expression ^(bin/(x)\$" 'regex|bin/(x|ADR-0001|decision|-|x'
  register "$repo" 'path|bin/up.sh|ADR-0099|sync|-|x'
  out=$("$repo/bin/po-carries.sh" check-paths HEAD 2>&1)
  status=$?
  expect_code 1 "$status" "check-paths on a malformed register"
  assert_not_contains "$out" "is covered" "check-paths reported a covered tree from a malformed register"
  rm "$repo/docs/pixeloven/carries.tsv"
  out=$("$repo/bin/po-carries.sh" check-paths HEAD 2>&1)
  status=$?
  expect_code 1 "$status" "check-paths without a register"
  assert_contains "$out" "no carry register at" "check-paths did not report the missing register"
  register "$repo" 'path|bin/up.sh|fix|sync|https://example.invalid/pull/1|repairs up' 'path|docs/up.md|ADR-0001|decision|-|-'
  out=$("$repo/bin/po-carries.sh" validate 2>&1) || fail "validate refused a well-formed register: $out"
  assert_contains "$out" "carries: 2 rows, 1 fix carries" "validate did not count the rows"
  pass "every malformed register row is refused by line, and a missing or malformed register fails A4"
}

test_fix_carry_retires_with_upstream_bytes() {
  local repo out status
  repo=$(fixture retire)
  register "$repo" 'path|bin/up.sh|fix|sync|-|repairs up' 'path|docs/up.md|ADR-0001|sync|-|an ADR carry'
  printf 'fixed\n' > "$repo/bin/up.sh"
  printf 'carried\n' > "$repo/docs/up.md"
  out=$("$repo/bin/po-carries.sh" check-paths HEAD 2>&1) || fail "check-paths refused live carries: $out"
  assert_not_contains "$out" "note:" "check-paths noted a carry that still differs"
  printf 'up\n' > "$repo/docs/up.md"
  out=$("$repo/bin/po-carries.sh" check-paths HEAD 2>&1) || fail "check-paths failed on an ADR carry back at upstream bytes: $out"
  assert_contains "$out" "note: docs/up.md: no longer differs from HEAD; drop its ADR-0001 row" "check-paths did not note the retired ADR carry"
  printf 'up\n' > "$repo/bin/up.sh"
  out=$("$repo/bin/po-carries.sh" check-paths HEAD 2>&1)
  status=$?
  expect_code 1 "$status" "check-paths with a fix carry back at upstream bytes"
  assert_contains "$out" "A4: bin/up.sh: the fix carry no longer differs from HEAD; drop its row" "check-paths did not name the retired fix carry"
  pass "a fix row fails A4 once its file is back at upstream bytes, while an ADR carry there only gets a note"
}

test_a9_accepts_a_fix_carry_in_a_theme_hook_file() {
  local repo out status
  repo=$(fixture a9)
  register "$repo" 'path|docs/up.md|ADR-0001|decision|-|-'
  out=$("$repo/bin/po-theme.sh" registry check-diff HEAD 2>&1) || fail "A9 refused a file that differs only by its hook: $out"
  # shellcheck disable=SC2016 # the hook line is literal shell text
  printf 'say "$who"\n# fixed\nkeep\n' > "$repo/bin/x.sh"
  out=$("$repo/bin/po-theme.sh" registry check-diff HEAD 2>&1)
  status=$?
  expect_code 1 "$status" "A9 with an unregistered line and no carry"
  assert_contains "$out" "A9: bin/x.sh: unregistered changed line: # fixed" "A9 did not name the unregistered line"
  register "$repo" 'path|bin/x.sh|ADR-0001|sync|-|an ADR carry'
  out=$("$repo/bin/po-theme.sh" registry check-diff HEAD 2>&1)
  status=$?
  expect_code 1 "$status" "A9 with an unregistered line and only an ADR row"
  assert_contains "$out" "A9: bin/x.sh: unregistered changed line: # fixed" "an ADR row relaxed A9"
  register "$repo" 'path|bin/x.sh|fix|sync|https://example.invalid/pull/2|repairs x'
  out=$("$repo/bin/po-theme.sh" registry check-diff HEAD 2>&1) || fail "A9 refused a fix carry's line: $out"
  assert_contains "$out" "registry: bin/x.sh also carries a bug fix, so its other changed lines are that carry's" "A9 did not report the carried file"
  # shellcheck disable=SC2016 # the hook line is literal shell text
  printf 'say "$who"\n# fixed\n' > "$repo/bin/x.sh"
  out=$("$repo/bin/po-theme.sh" registry check-diff HEAD 2>&1) || fail "A9 refused a fix carry's removed line: $out"
  # shellcheck disable=SC2016 # the hook line is literal shell text
  printf 'say "$who"\nsay "$who"\n# fixed\n' > "$repo/bin/x.sh"
  out=$("$repo/bin/po-theme.sh" registry check-diff HEAD 2>&1)
  status=$?
  expect_code 1 "$status" "A9 with a repeated hook line in a carried file"
  # shellcheck disable=SC2016 # the hook line is literal shell text
  assert_contains "$out" 'A9: bin/x.sh: hook line appears more times than it is registered: say "$who"' "A9 stopped counting hooks in a carried file"
  # shellcheck disable=SC2016 # the hook line is literal shell text
  printf 'say "$who"\nsay firstmate\n# fixed\n' > "$repo/bin/x.sh"
  out=$("$repo/bin/po-theme.sh" registry check-diff HEAD 2>&1)
  status=$?
  expect_code 1 "$status" "A9 with a hook that keeps its upstream line in a carried file"
  # shellcheck disable=SC2016 # the hook line is literal shell text
  assert_contains "$out" 'A9: bin/x.sh: hook does not replace its registered upstream line: say "$who"' "A9 stopped holding hooks to their upstream lines in a carried file"
  out=$("$repo/bin/po-carries.sh" check-paths HEAD 2>&1) || fail "A4 refused a theme-hook file with a fix carry: $out"
  pass "A9 accepts a fix carry's lines in a theme-hook file, not an ADR row's, and still holds that file's hooks to their rows"
}

test_this_tree() {
  local out
  out=$("$PC" validate 2>&1) || fail "this tree's carry register is malformed: $out"
  out=$(printf '%s\n' bin/po-new-helper.sh tests/po-new.test.sh docs/pixeloven/a/b.md docs/adr/0999-new.md \
      .github/workflows/pixeloven-new.yml bin/backends/new.sh .agents/skills/po-new/SKILL.md \
      .claude/mods/firstmate-calm/lib/po-new.ts .claude/mods/firstmate-calm/tests/po-new.test.ts .pi/extensions/lib/po-new.ts \
      bin/po-new/x.sh bin/po-New.sh tests/po-new.sh .claude/mods/firstmate-calm/hooks/po-new.ts .pi/extensions/po-new.ts \
      bin/fm-not-carried.sh docs/configuration.md.bak \
    | "$PC" uncovered)
  assert_equals "$(printf '%s\n' bin/po-new/x.sh bin/po-New.sh tests/po-new.sh .claude/mods/firstmate-calm/hooks/po-new.ts \
      .pi/extensions/po-new.ts bin/fm-not-carried.sh docs/configuration.md.bak)" "$out" \
    "this tree's namespaces admitted a path outside them or refused one inside them"
  if [ -z "$PIN" ] || ! git -C "$ROOT" cat-file -e "$PIN^{commit}" 2>/dev/null; then
    printf 'note: upstream pin %s is not in this clone; check-paths not exercised on this tree\n' "${PIN:-?}"
  else
    out=$("$PC" check-paths "$PIN" 2>&1) || fail "check-paths failed on this tree: $out"
  fi
  pass "this tree's register validates, admits exactly its namespaces' paths, and covers the diff against the upstream pin"
}

test_paths_follow_the_register
test_malformed_register_is_refused
test_fix_carry_retires_with_upstream_bytes
test_a9_accepts_a_fix_carry_in_a_theme_hook_file
test_this_tree
