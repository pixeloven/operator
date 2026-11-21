#!/usr/bin/env bash
# po-carries.sh - PixelOven carry register helper (ADR-0041).
#
# docs/pixeloven/carries.tsv is the carry register: every path the fork may
# change relative to the upstream pin, with the decision or bug fix that claims
# it and when that claim retires. The register's header owns the row format.
# An upstream-owned theme-hook file that `bin/po-theme.sh registry files` lists
# is covered as well, because gate A9 holds it to its registered hook lines.
#
# Every command first validates the register and exits 1 naming each malformed
# row: a row that is not six tab-separated fields, a match other than path or
# regex, an empty path, an owner that is neither fix nor an ADR-NNNN with a
# record under docs/adr/, a retire other than sync or decision, an upstream
# value that is neither - nor an https:// link, an empty note, a fix row that is
# not a path row retiring at sync with a note, a regex grep -E refuses, or a
# repeated row.
#
# A path row covers exactly its path. A regex row covers every path its
# expression matches whole, as if written ^(expression)$.
#
# Usage:
#   po-carries.sh validate            check the register and print its row counts
#   po-carries.sh uncovered           print each path read from stdin that no row
#                                     and no theme-hook file covers
#   po-carries.sh check-paths <ref>   gate A4: every path that differs from <ref>,
#                                     working tree included, is covered. A fix row
#                                     whose path no longer differs from <ref> is a
#                                     finding, because a fix carry retires when its
#                                     file returns to upstream bytes; an ADR's sync
#                                     row whose path no longer differs prints a note
#   po-carries.sh fixes               print each path a fix row names; gate A9
#                                     (bin/po-theme.sh registry check-diff) accepts
#                                     changed lines in such a theme-hook file beyond
#                                     its registered hooks
#
# Exit status: 0 on success; 1 on a malformed register, an uncovered path, a
# fix row whose path no longer differs, an unreadable theme hook registry, an
# unknown ref, or a usage error.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTER="$CODE_ROOT/docs/pixeloven/carries.tsv"
ADR_DIR="$CODE_ROOT/docs/adr"
export LC_ALL=C

die() { printf 'po-carries: %s\n' "$*" >&2; exit 1; }

usage() {
  die "usage: validate | uncovered | check-paths <ref> | fixes"
}

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/po-carries.XXXXXX")
trap 'rm -rf "$TMPD"' EXIT

# load: validate the register and split it into $TMPD/exact (path rows),
# $TMPD/regex (anchored expressions), $TMPD/fix (fix paths), and $TMPD/rows
# (match, path, owner, retire).
load() {
  local re rc
  [ -f "$REGISTER" ] || die "no carry register at $REGISTER"
  : > "$TMPD/adrs"
  if [ -d "$ADR_DIR" ]; then
    ls "$ADR_DIR" > "$TMPD/adrs"
  fi
  : > "$TMPD/exact"
  : > "$TMPD/regex"
  : > "$TMPD/fix"
  : > "$TMPD/rows"
  awk -F '\t' -v adrs="$TMPD/adrs" -v exact="$TMPD/exact" -v regex="$TMPD/regex" \
      -v fix="$TMPD/fix" -v rows="$TMPD/rows" '
    function err(msg) { printf "carries.tsv line %d: %s\n", NR, msg; bad = 1 }
    BEGIN {
      while ((getline l < adrs) > 0)
        if (l ~ /^[0-9][0-9][0-9][0-9]-.*\.md$/) adr["ADR-" substr(l, 1, 4)] = 1
    }
    /^#/ || /^[[:space:]]*$/ { next }
    {
      if (NF != 6) { err("expected 6 tab-separated fields, found " NF); next }
      m = $1; p = $2; o = $3; r = $4; u = $5; n = $6
      ok = 1
      if (m != "path" && m != "regex") { err("match must be path or regex, not " m); ok = 0 }
      if (p == "") { err("empty path"); ok = 0 }
      if (o != "fix" && !(o in adr)) { err("owner " o " is neither fix nor an ADR with a record under docs/adr/"); ok = 0 }
      if (r != "sync" && r != "decision") { err("retire must be sync or decision, not " r); ok = 0 }
      if (u != "-" && u !~ /^https:\/\/[^[:space:]]+$/) { err("upstream must be - or an https:// link, not " u); ok = 0 }
      if (n == "") { err("empty note; write - for none"); ok = 0 }
      if (o == "fix" && m != "path") { err("a fix row names one exact path"); ok = 0 }
      if (o == "fix" && r != "sync") { err("a fix row retires at sync"); ok = 0 }
      if (o == "fix" && n == "-") { err("a fix row needs a note saying what it fixes"); ok = 0 }
      key = m "\t" p "\t" o
      if (key in seen) { err("repeats the row on line " seen[key]); ok = 0 }
      else seen[key] = NR
      if (!ok) next
      if (m == "path") print p > exact
      else print "^(" p ")$" > regex
      if (o == "fix") print p > fix
      print m "\t" p "\t" o "\t" r > rows
    }
    END { exit bad }
  ' "$REGISTER" > "$TMPD/errors" || {
    sed 's/^/po-carries: /' "$TMPD/errors" >&2
    exit 1
  }
  while IFS= read -r re; do
    rc=0
    grep -E -e "$re" < /dev/null > /dev/null 2>&1 || rc=$?
    [ "$rc" -le 1 ] || die "carries.tsv: grep -E refuses the expression $re"
  done < "$TMPD/regex"
}

# drop <grep-flags> <patterns> <in> <out>: the lines of <in> that no pattern in
# <patterns> matches. An empty pattern file drops nothing.
drop() {
  local flags=$1 pats=$2 in=$3 out=$4 rc=0
  if [ ! -s "$pats" ]; then
    cp "$in" "$out"
    return 0
  fi
  grep "$flags" -f "$pats" "$in" > "$out" || rc=$?
  [ "$rc" -le 1 ] || die "could not match paths against $(basename "$pats")"
}

# uncovered_of <paths-file>: print each path no row and no theme-hook file covers.
uncovered_of() {
  "$SCRIPT_DIR/po-theme.sh" registry files > "$TMPD/theme" || die "the theme hook registry is unreadable"
  cat "$TMPD/theme" "$TMPD/exact" > "$TMPD/admitted"
  drop -vxF "$TMPD/admitted" "$1" "$TMPD/after-exact"
  drop -vE "$TMPD/regex" "$TMPD/after-exact" "$TMPD/after-regex"
  sed '/^$/d' "$TMPD/after-regex"
}

check_paths() {
  local ref=$1 bad=0 p o
  git -C "$CODE_ROOT" rev-parse --verify -q "$ref^{commit}" > /dev/null || die "check-paths: unknown ref $ref"
  git -C "$CODE_ROOT" diff --name-only "$ref" > "$TMPD/changed" || die "check-paths: cannot diff against $ref"
  uncovered_of "$TMPD/changed" > "$TMPD/uncovered"
  while IFS= read -r p; do
    printf 'A4: %s: in no PixelOven namespace, carry register row, or theme hook registry\n' "$p"
    bad=1
  done < "$TMPD/uncovered"
  awk -F '\t' '$1 == "path" && $4 == "sync" { print $2 "\t" $3 }' "$TMPD/rows" > "$TMPD/sync"
  while IFS="$(printf '\t')" read -r p o; do
    grep -qxF -- "$p" "$TMPD/changed" && continue
    if [ "$o" = fix ]; then
      printf 'A4: %s: the fix carry no longer differs from %s; drop its row\n' "$p" "$ref"
      bad=1
    else
      printf 'note: %s: no longer differs from %s; drop its %s row\n' "$p" "$ref" "$o"
    fi
  done < "$TMPD/sync"
  [ "$bad" -eq 0 ] || return 1
  echo "carries: every path that differs from $ref is covered"
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case "$cmd" in
  validate)
    [ $# -eq 0 ] || usage
    load
    printf 'carries: %s rows, %s fix carries\n' "$(wc -l < "$TMPD/rows" | tr -d ' ')" "$(wc -l < "$TMPD/fix" | tr -d ' ')" ;;
  uncovered)
    [ $# -eq 0 ] || usage
    load
    cat > "$TMPD/stdin"
    uncovered_of "$TMPD/stdin" ;;
  check-paths)
    [ $# -eq 1 ] || usage
    load
    check_paths "$1" ;;
  fixes)
    [ $# -eq 0 ] || usage
    load
    sort -u "$TMPD/fix" ;;
  *) usage ;;
esac
