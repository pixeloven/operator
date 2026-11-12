#!/usr/bin/env bash
# tests/po-design.test.sh - behavior tests for the design-system layer
# (bin/po-design-lib.sh through bin/po-theme.sh, ADR-0031).
#
# Coverage:
#   - both bundled design systems validate, and ds-css composes the Google
#     Fonts import first, then the vendored tokens, the adapter, and the
#     component sheet
#   - the Firstmate Default supplies the board template's own semantic values
#     in light mode, keeps upstream's warn and info fills, and every text pair
#     (including the text-safe status inks) reaches 4.5:1 in light and dark
#   - the PixelOven adapter supplies every color, radius, type, and shadow role
#     by --pxo-* reference only
#   - a home's own design system is validated as data: each refusal reason
#     fails with its named reason, a changed vendored copy is refused, and a
#     local firstmate does not shadow the bundled one
#   - default selection writes nothing; another selection writes the resolved
#     stylesheet and one marker line outside the Persona block, independent of
#     the theme; selecting firstmate again removes both
#   - verify and headline report a stale selection, a hand-edited copy, a
#     changed source, and a hand-edited marker; ds-css refuses a hand-edited copy
#   - a secondmate home resolves the inherited marker, ignores a local
#     selection, and falls back to the Firstmate Default with a warning and a
#     drift line when the primary's own design system is not present there
#   - ds-labels follows the theme's words and only the theme's
#
# Fixture code roots are throwaway git repositories: apply writes alias skills
# and .git/info/exclude under the code root of the script it runs.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PT="$ROOT/bin/po-theme.sh"
DESIGNS="$ROOT/.agents/skills/po-theme/designs"
BOARD="$ROOT/.agents/skills/bearings/assets/board-template.html"
TMP_ROOT=$(fm_test_tmproot po-design-tests)
FM_TEST_CLEANUP_DIRS+=("$TMP_ROOT")
trap fm_test_cleanup EXIT
fm_git_identity fmtest fmtest@example.invalid

new_code() {  # <name>: a throwaway code root carrying this tree's theme layer
  local code="$TMP_ROOT/$1/code" s
  mkdir -p "$code/bin" "$code/.agents/skills"
  cp "$PT" "$ROOT/bin/po-design-lib.sh" "$ROOT/bin/po-theme-lib.sh" "$code/bin/"
  cp -R "$ROOT/.agents/skills/po-theme" "$code/.agents/skills/"
  cp "$ROOT/AGENTS.md" "$ROOT/VISION.md" "$code/"
  for s in afk ahoy bearings lavish-url quiet stow updatefirstmate; do
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
  mkdir -p "$home/config" "$home/data" "$home/state"
  printf '%s\n' "$home"
}

run_in() {  # <code> <home> <args...>
  local code=$1 home=$2
  shift 2
  FM_HOME="$home" "$code/bin/po-theme.sh" "$@"
}

# section <css> <name>: the part of a ds-css output under "/* ---- <name> ---- */".
section() {
  awk -v h="/* ---- $2 ---- */" '
    $0 == h { on = 1; next } on && /^\/\* ---- .* ---- \*\/$/ { on = 0 } on
  ' <<<"$1"
}

# block <css> <selector>: "<prop><TAB><value>" for the declarations of the
# top-level rule whose selector line is exactly "<selector> {".
block() {
  awk -v s="$2 {" '
    $0 == s { on = 1; next }
    on && /^}/ { exit }
    on && /^[[:space:]]*--[a-z0-9-]+:/ {
      line = $0; sub(/^[[:space:]]*/, "", line); sub(/;[[:space:]]*$/, "", line)
      c = index(line, ":"); printf "%s\t%s\n", substr(line, 1, c - 1), substr(line, c + 2)
    }
  ' <<<"$1"
}

# board_values: the board template's :root declarations with every var()
# chain resolved, as "<prop><TAB><value>".
board_values() {
  awk '
    /^:root \{/ { on = 1; next } on && /^\}/ { on = 0 }
    on {
      line = $0
      while (match(line, /--[a-z0-9-]+:[^;]*;/)) {
        d = substr(line, RSTART, RLENGTH - 1); line = substr(line, RSTART + RLENGTH)
        c = index(d, ":"); k = substr(d, 1, c - 1); v = substr(d, c + 1); sub(/^[[:space:]]+/, "", v)
        val[k] = v; order[++n] = k
      }
    }
    END {
      for (i = 1; i <= n; i++) {
        k = order[i]; v = val[k]
        while (match(v, /var\(--[a-z0-9-]+\)/)) {
          r = substr(v, RSTART + 4, RLENGTH - 5)
          v = substr(v, 1, RSTART - 1) val[r] substr(v, RSTART + RLENGTH)
        }
        printf "%s\t%s\n", k, v
      }
    }
  ' "$BOARD"
}

val_of() { awk -F '\t' -v k="$2" '$1 == k { print $2; exit }' <<<"$1"; }

# contrast <hex> <hex>: the WCAG 2 contrast ratio, to two decimals.
contrast() {
  awk -v a="$1" -v b="$2" '
    function ch(h, i) { return index("0123456789abcdef", substr(h, i, 1)) - 1 }
    function lin(c) { c = c / 255; return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4 }
    function lum(h) { h = tolower(substr(h, 2)); return 0.2126 * lin(ch(h,1)*16+ch(h,2)) + 0.7152 * lin(ch(h,3)*16+ch(h,4)) + 0.0722 * lin(ch(h,5)*16+ch(h,6)) }
    BEGIN { x = lum(a); y = lum(b); if (x < y) { t = x; x = y; y = t }; printf "%.2f\n", (x + 0.05) / (y + 0.05) }
  '
}

at_least() { awk -v r="$1" -v m="$2" 'BEGIN { exit !(r + 0 >= m + 0) }'; }

# local_design <home> <name> [from]: copy a bundled design system into the
# home's config/po-designs/<name>/ with its name rewritten.
local_design() {
  local dir="$1/config/po-designs/$2"
  mkdir -p "$dir"
  cp "$DESIGNS/${3:-firstmate}/"* "$dir/"
  sed -i.bak "s/^name = .*/name = \"$2\"/" "$dir/design.toml" && rm -f "$dir/design.toml.bak"
  printf '%s\n' "$dir"
}

test_bundled_design_systems() {
  local out css
  for d in firstmate pixeloven; do
    out=$("$PT" ds-validate "$d" 2>&1) || fail "bundled design system $d failed validation: $out"
    assert_equals "ds-validate: $d ok" "$out" "ds-validate did not confirm $d"
  done
  css=$("$PT" ds-css firstmate) || fail "ds-css firstmate failed"
  assert_contains "$(printf '%s\n' "$css" | sed -n 2p)" '@import url("https://fonts.googleapis.com/css2?family=Chango' \
    "the Google Fonts import is not the first rule of the firstmate stylesheet"
  assert_equals 1 "$(printf '%s\n' "$css" | grep -c '@import')" "the firstmate stylesheet does not carry exactly one import"
  assert_contains "$css" ".po-chip[data-status=\"needs-decision\"]" "the firstmate stylesheet lacks the component sheet"
  css=$("$PT" ds-css pixeloven) || fail "ds-css pixeloven failed"
  assert_contains "$(section "$css" 'vendored tokens.css')" "--pxo-surface-bg: #0d101e;" "the pixeloven stylesheet lacks the vendored tokens"
  out=$(printf '%s\n' "$css" | grep -n -e '---- vendored tokens.css ----' -e '---- adapter.css ----' -e '---- components.css ----' | cut -d: -f1 | tr '\n' ' ')
  # shellcheck disable=SC2086  # word-split the three line numbers on purpose
  set -- $out
  [ "$#" -eq 3 ] && [ "$1" -lt "$2" ] && [ "$2" -lt "$3" ] || fail "the pixeloven stylesheet is not tokens, adapter, components in order: $out"
  pass "both bundled design systems validate and compose imports, tokens, adapter, and components in order"
}

test_firstmate_default_values() {
  local css adapter light dark board role want got r mode bg fg
  css=$("$PT" ds-css firstmate)
  adapter=$(section "$css" adapter.css)
  light=$(block "$adapter" ':root')
  dark=$(block "$adapter" ':root[data-theme="dark"]')
  board=$(board_values)
  for role in --bg-page --surface-card --surface-card-warm --text-strong --text-body --text-muted \
      --border-default --border-soft --status-online --status-online-soft --status-warn --status-warn-soft \
      --status-danger --status-danger-soft --status-info --status-info-soft --font-display --font-sans \
      --font-mono --focus-ring; do
    want=$(val_of "$board" "$role"); got=$(val_of "$light" "$role")
    [ -n "$want" ] || fail "the board template no longer defines $role"
    assert_equals "$want" "$got" "the Firstmate Default's light $role is not the board's own value"
  done
  for mode in light dark; do
    if [ "$mode" = light ]; then r=$light; else r=$dark; fi
    for bg in --surface-card --bg-page; do
      for fg in --text-strong --text-body --text-muted --status-online-ink --status-warn-ink --status-danger-ink --status-info-ink; do
        got=$(contrast "$(val_of "$r" "$fg")" "$(val_of "$r" "$bg")")
        at_least "$got" 4.5 || fail "$mode $fg on $bg is $got:1, under 4.5:1"
      done
    done
    for s in online warn danger info; do
      got=$(contrast "$(val_of "$r" "--status-$s-ink")" "$(val_of "$r" "--status-$s-soft")")
      at_least "$got" 4.5 || fail "$mode --status-$s-ink on its soft ground is $got:1, under 4.5:1"
    done
    got=$(contrast "$(val_of "$r" --accent-ink)" "$(val_of "$r" --accent)")
    at_least "$got" 4.5 || fail "$mode --accent-ink on --accent is $got:1, under 4.5:1"
  done
  got=$(contrast "$(val_of "$light" --status-warn)" "$(val_of "$light" --surface-card)")
  at_least "$got" 4.5 && fail "the upstream warn fill unexpectedly reaches 4.5:1 ($got), so the text-safe ink case is vacuous"
  assert_equals "$(val_of "$dark" --text-strong)" \
    "$(block "$adapter" '  :root:not([data-theme="light"])' | awk -F '\t' '$1 == "--text-strong" { print $2 }')" \
    "the OS dark mode and the explicit dark toggle disagree"
  pass "the Firstmate Default keeps the board's values and fills, and its text and status inks reach 4.5:1 in light and dark"
}

test_pixeloven_adapter_references_only() {
  local adapter rows role v
  adapter=$(section "$("$PT" ds-css pixeloven)" adapter.css)
  rows=$(block "$adapter" ':root')
  assert_equals "$(grep -c '^--' "$DESIGNS/roles")" "$(printf '%s\n' "$rows" | grep -c '^--')" \
    "the pixeloven :root block does not supply exactly the role contract"
  while IFS="$(printf '\t')" read -r role v; do
    case "$role" in
      --space-*) printf '%s\n' "$v" | grep -Eq '^[0-9]+px$' || fail "pixeloven $role is not a 4px-grid length: $v"
                 [ $(( ${v%px} % 4 )) -eq 0 ] || fail "pixeloven $role is off the 4px grid: $v" ;;
      *) printf '%s\n' "$v" | grep -q 'var(--pxo-' || fail "pixeloven $role is not a --pxo-* reference: $v"
         printf '%s\n' "$v" | grep -Eiq '#[0-9a-f]{3}|rgba?\(|hsla?\(|"' && fail "pixeloven $role carries a literal color or font: $v" ;;
    esac
  done <<<"$rows"
  pass "the PixelOven adapter supplies every color, radius, type, and shadow role by --pxo-* reference"
}

# refused <home> <name> <reason>: ds-validate of a local design fails naming <reason>.
refused() {
  local out
  out=$(FM_HOME="$1" "$PT" ds-validate "$2" 2>&1) && fail "ds-validate accepted $2 (expected: $3)"
  assert_contains "$out" "$3" "ds-validate of $2 did not name the reason"
}

test_local_design_refusals() {
  local home dir
  home=$(new_home refusals)
  dir=$(local_design "$home" mine)
  assert_equals "ds-validate: mine ok" "$(FM_HOME="$home" "$PT" ds-validate mine 2>&1)" "a copied Firstmate Default did not validate as a local design system"
  edit() { cp "$DESIGNS/firstmate/adapter.css" "$dir/adapter.css"; printf '%s\n' "$1" >> "$dir/adapter.css"; }
  edit ':root { --accent: url(https://example.invalid/x.png); }'; refused "$home" mine "url() is not allowed"
  edit 'body { --accent: #000000; }'; refused "$home" mine "selector is not allowed: body"
  edit '@font-face { font-family: x; }'; refused "$home" mine "at-rule @font-face is not allowed"
  edit ':root { color: #000000; }'; refused "$home" mine "only custom properties and color-scheme are allowed: color"
  edit ':root { --not-a-role: #000000; }'; refused "$home" mine "--not-a-role is not a role name"
  edit ':root { --accent: #000000 !important; }'; refused "$home" mine "!important is not allowed"
  edit ':root { --accent: expression(alert(1)); }'; refused "$home" mine "expression is not allowed"
  edit ':root { --accent: var(--pxo-accent); }'; refused "$home" mine "var(--pxo-accent) is neither a role nor defined by tokens.css"
  edit ':root { --accent: calc(1px + 2px); }'; refused "$home" mine "value has a function"
  edit ':root { --accent: </style><script>; }'; refused "$home" mine "markup characters are not allowed"
  edit '@import url("https://example.invalid/x.css");'; refused "$home" mine "@import must come before every rule"
  edit ':root { --font-display: "a/*"; }
body { background: url(https://example.invalid/x); }
:root { --font-sans: "*/b"; }'; refused "$home" mine "selector is not allowed: body"
  edit ":root { --font-display: 'a/*'; }
input[value^=a] { --accent: #000000; }
:root { --font-sans: '*/b'; }"; refused "$home" mine "selector is not allowed: input"
  { printf '@import url("https://example.invalid/x.css");\n'; cat "$DESIGNS/firstmate/adapter.css"; } > "$dir/adapter.css"
  refused "$home" mine "@import is not a Google Fonts css2 stylesheet"
  grep -v -- '--status-warn-ink:' "$DESIGNS/firstmate/adapter.css" > "$dir/adapter.css"
  refused "$home" mine "role --status-warn-ink is not supplied in the plain :root block"
  cp "$DESIGNS/firstmate/adapter.css" "$dir/adapter.css"
  printf 'schema = "po-design/1"\nname = "other"\ndescription = "x"\n' > "$dir/design.toml"
  refused "$home" mine 'name must be "mine"'

  dir=$(local_design "$home" vend pixeloven)
  assert_equals "ds-validate: vend ok" "$(FM_HOME="$home" "$PT" ds-validate vend 2>&1)" "a copied PixelOven design system did not validate"
  printf ':root { --pxo-accent: #ff0000; }\n' >> "$dir/tokens.css"
  refused "$home" vend "does not match vendored.sha256"
  cp "$DESIGNS/pixeloven/tokens.css" "$dir/tokens.css"
  sed -i.bak '/^vendored.version/d' "$dir/design.toml" && rm -f "$dir/design.toml.bak"
  refused "$home" vend "vendored.version is missing"
  sed -i.bak 's/^vendored.sha256 = .*/vendored.version = "0.6"/' "$dir/design.toml" && rm -f "$dir/design.toml.bak"
  refused "$home" vend "vendored.version is not a semver version"
  rm -f "$dir/tokens.css"
  refused "$home" vend "vendored.* keys are set but there is no tokens.css"

  FM_HOME="$home" "$PT" ds-validate ../etc >/dev/null 2>&1 && fail "a path-shaped design system name validated"
  FM_HOME="$home" "$PT" ds-validate no-such >/dev/null 2>&1 && fail "an unknown design system validated"
  dir=$(local_design "$home" firstmate)
  printf ':root { --accent: url(x); }\n' >> "$dir/adapter.css"
  assert_equals "ds-validate: firstmate ok" "$(FM_HOME="$home" "$PT" ds-validate firstmate 2>&1)" "a local firstmate shadowed the bundled one"
  pass "a home's own design system is validated as data, with a pinned vendored copy, and cannot shadow firstmate"
}

test_selection_and_apply() {
  local code home out css shared
  code=$(new_code apply)
  home=$(new_home apply)
  shared="$home/data/captain-shared.md"
  out=$(run_in "$code" "$home" apply) || fail "default apply failed: $out"
  assert_contains "$out" "design: firstmate - nothing to write" "default apply did not report writing nothing"
  assert_absent "$shared" "default apply wrote data/captain-shared.md"
  assert_absent "$home/state/po-design" "default apply wrote state/po-design"
  assert_equals "firstmate default" "$(run_in "$code" "$home" ds-resolve)" "an unselected home did not resolve the default"
  assert_equals "" "$(run_in "$code" "$home" headline)" "headline printed something in a default home"

  printf 'operator\n' > "$home/config/po-theme"
  printf 'pixeloven\n' > "$home/config/po-design"
  out=$(run_in "$code" "$home" apply) || fail "pixeloven apply failed: $out"
  assert_equals "pixeloven applied" "$(run_in "$code" "$home" ds-resolve)" "apply did not put pixeloven in force"
  css=$(run_in "$code" "$home" ds-css) || fail "ds-css failed after apply"
  assert_equals "$(run_in "$code" "$home" ds-css pixeloven)" "$css" "ds-css did not print the applied pixeloven stylesheet"
  assert_equals "$css" "$(cat "$home/state/po-design/po-ds.css")" "the applied stylesheet differs from state/po-design/po-ds.css"
  assert_equals 1 "$(grep -c '^<!-- po-design: name="pixeloven" source="bundled" sha256="' "$shared")" "the marker line is not in captain-shared.md exactly once"
  assert_equals '<!-- po-theme:persona:end -->' "$(grep -B 1 '^<!-- po-design: ' "$shared" | head -n 1)" \
    "the marker is not right after the Persona block"
  out=$(run_in "$code" "$home" verify) || fail "verify failed right after apply: $out"
  assert_contains "$out" "verify: ok (operator)" "the persona did not verify beside the design marker"
  assert_contains "$out" "design: ok (pixeloven)" "verify did not confirm the applied design system"

  printf 'nautical\n' > "$home/config/po-theme"
  run_in "$code" "$home" apply >/dev/null || fail "nautical apply failed"
  assert_equals "$css" "$(run_in "$code" "$home" ds-css)" "the theme switch changed the stylesheet"
  assert_equals 0 "$(grep -c 'po-theme:persona' "$shared")" "nautical apply left the Persona block"
  assert_equals 1 "$(grep -c '^<!-- po-design: ' "$shared")" "the theme switch removed the design marker"
  assert_equals "" "$(run_in "$code" "$home" headline)" "headline printed something under nautical with a current design"

  dir=$(local_design "$home" broken)
  printf 'body { --accent: #000000; }\n' >> "$dir/adapter.css"
  cp "$shared" "$TMP_ROOT/shared.before"
  printf 'broken\n' > "$home/config/po-design"
  printf 'operator\n' > "$home/config/po-theme"
  run_in "$code" "$home" apply >/dev/null 2>&1 && fail "apply accepted a design system that fails validation"
  assert_equals "$(cat "$TMP_ROOT/shared.before")" "$(cat "$shared")" "a failed design validation still rewrote captain-shared.md"
  printf 'nautical\n' > "$home/config/po-theme"
  rm -rf "$dir"

  printf 'firstmate\n' > "$home/config/po-design"
  out=$(run_in "$code" "$home" headline)
  assert_equals "design drift: config/po-design selects firstmate but pixeloven is applied; run apply" "$out" \
    "headline did not print exactly the design drift line under nautical"
  run_in "$code" "$home" apply >/dev/null || fail "firstmate apply failed"
  assert_absent "$shared" "selecting firstmate again left captain-shared.md written only by apply"
  assert_absent "$home/state/po-design" "selecting firstmate again left state/po-design"
  assert_equals "" "$(run_in "$code" "$home" headline)" "headline printed something after returning to the default"
  pass "default writes nothing; a selection writes the stylesheet and one marker beside the Persona block, independent of the theme"
}

test_drift() {
  local code home out shared dir
  code=$(new_code drift)
  home=$(new_home drift)
  shared="$home/data/captain-shared.md"
  printf 'captain prose\n' > "$shared"
  dir=$(local_design "$home" mine pixeloven)
  printf 'mine\n' > "$home/config/po-design"
  run_in "$code" "$home" apply >/dev/null || fail "apply of a local design system failed"
  assert_equals "mine applied" "$(run_in "$code" "$home" ds-resolve)" "the local design system is not in force"
  assert_equals 'captain prose' "$(head -n 1 "$shared")" "apply did not preserve the captain's prose"
  assert_equals 1 "$(grep -c '^<!-- po-design: name="mine" source="local"' "$shared")" "the marker does not record a local source"

  printf '/* edit */\n' >> "$home/state/po-design/po-ds.css"
  run_in "$code" "$home" ds-css >/dev/null 2>&1 && fail "ds-css printed a hand-edited stylesheet"
  out=$(run_in "$code" "$home" verify) && fail "verify passed a hand-edited stylesheet"
  assert_contains "$out" "design drift: $home/state/po-design/po-ds.css is missing, stale, or hand-edited" "verify did not name the hand-edited stylesheet"
  run_in "$code" "$home" apply >/dev/null || fail "reapply failed"

  sed -i.bak 's/sha256="/sha256="0/' "$shared" && rm -f "$shared.bak"
  out=$(run_in "$code" "$home" verify) && fail "verify passed a hand-edited marker"
  assert_contains "$out" "design drift: the design marker in $shared is missing, stale, or hand-edited" "verify did not name the marker"
  run_in "$code" "$home" apply >/dev/null || fail "reapply failed"

  printf '/* a later comment */\n' >> "$dir/adapter.css"
  out=$(run_in "$code" "$home" verify) && fail "verify passed a changed design system"
  assert_contains "$out" "design drift: design system mine changed since apply; run apply" "verify did not report a changed source"
  printf ':root { --pxo-accent: #ff0000; }\n' >> "$dir/tokens.css"
  out=$(run_in "$code" "$home" verify) && fail "verify passed a changed vendored copy"
  assert_contains "$out" "design drift: design system mine no longer validates" "verify did not report the changed vendored copy"
  out=$(run_in "$code" "$home" apply 2>&1) && fail "apply accepted a changed vendored copy"
  assert_contains "$out" "does not match vendored.sha256" "apply did not name the changed vendored copy"
  pass "verify reports a hand-edited copy, a hand-edited marker, and a changed source; ds-css and apply refuse"
}

test_secondmate_home() {
  local code primary mate out
  code=$(new_code mate)
  primary=$(new_home primary)
  mate=$(new_home mate)
  touch "$mate/.fm-secondmate-home"
  printf 'pixeloven\n' > "$primary/config/po-design"
  run_in "$code" "$primary" apply >/dev/null || fail "primary apply failed"
  cp "$primary/data/captain-shared.md" "$mate/data/captain-shared.md"
  printf 'firstmate\n' > "$mate/config/po-design"
  assert_equals "pixeloven inherited" "$(run_in "$code" "$mate" ds-resolve)" "the secondmate did not resolve the inherited marker"
  assert_equals "$(run_in "$code" "$primary" ds-css)" "$(run_in "$code" "$mate" ds-css)" "the secondmate's stylesheet differs from the primary's"
  out=$(run_in "$code" "$mate" verify) || fail "verify failed on a current inherited marker: $out"
  assert_contains "$out" "design: ok (pixeloven, inherited)" "verify did not confirm the inherited design system"

  local_design "$primary" mine pixeloven >/dev/null
  printf 'mine\n' > "$primary/config/po-design"
  run_in "$code" "$primary" apply >/dev/null || fail "primary apply of a local design system failed"
  cp "$primary/data/captain-shared.md" "$mate/data/captain-shared.md"
  out=$(run_in "$code" "$mate" ds-css 2>&1 >/dev/null)
  assert_contains "$out" "design system mine is not available in this home; printed firstmate instead" "the fallback was silent"
  assert_equals "$("$PT" ds-css firstmate)" "$(run_in "$code" "$mate" ds-css 2>/dev/null)" "the fallback did not print the Firstmate Default"
  out=$(run_in "$code" "$mate" headline)
  assert_equals "design drift: the inherited design system mine is not available in this home; pages get firstmate" "$out" \
    "headline did not print exactly the secondmate's design drift line"
  pass "a secondmate resolves the inherited design system, ignores a local selection, and reports a missing custom one"
}

test_labels_follow_the_theme() {
  local home
  home=$(new_home labels)
  assert_equals "captain's call" "$(FM_HOME="$home" "$PT" ds-labels | awk -F '\t' '$1 == "needs-decision" { print $2 }')" \
    "the nautical needs-decision label is not the captain's call"
  printf 'operator\n' > "$home/config/po-theme"
  assert_equals "operator's call" "$(FM_HOME="$home" "$PT" ds-labels | awk -F '\t' '$1 == "needs-decision" { print $2 }')" \
    "the operator needs-decision label is not the operator's call"
  printf 'pixeloven\n' > "$home/config/po-design"
  assert_equals "operator's call" "$(FM_HOME="$home" "$PT" ds-labels | awk -F '\t' '$1 == "needs-decision" { print $2 }')" \
    "the design selection changed a label"
  assert_equals "working needs-decision blocked paused done failed" \
    "$(FM_HOME="$home" "$PT" ds-labels | awk -F '\t' '{ print $1 }' | tr '\n' ' ' | sed 's/ $//')" "ds-labels did not key every status verb"
  pass "status-chip labels follow the theme's words and only the theme's"
}

test_bundled_design_systems
test_firstmate_default_values
test_pixeloven_adapter_references_only
test_local_design_refusals
test_selection_and_apply
test_drift
test_secondmate_home
test_labels_follow_the_theme

echo "all po-design tests passed"
