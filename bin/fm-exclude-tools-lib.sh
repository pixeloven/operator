#!/usr/bin/env bash
# fm-exclude-tools-lib.sh - shared parsing and runtime-support checks for
# config/crew-exclude-tools, sourced by bin/fm-spawn.sh and bin/fm-control.sh,
# plus the settings fragment for the tracked bin/fm-worker-connector-deny.list.
#
# docs/configuration.md "Worker tool exclusions" and "Claude worker connector
# deny list" own the file format and operator contract; bin/fm-spawn.sh's
# header owns launch-flag mechanics.
# Name verification belongs inside the worker's loaded-tool registry, never
# in an out-of-band server connection from these launch-time checks.

# fm_exclude_tools_names <config-dir>: print the comma-joined names, empty when
# the file is absent or lists nothing. Non-zero with the reason on stderr when
# the file or an entry is invalid.
fm_exclude_tools_names() {
  local config=$1 file present
  file=$config/crew-exclude-tools
  present=$(perl -MErrno=ENOENT -e '
    if (lstat $ARGV[0]) { print 1 }
    elsif ($! == ENOENT) { print 0 }
    else { die "error: cannot inspect config/crew-exclude-tools: $!\n" }
  ' -- "$file") || return 1
  [ "$present" = 1 ] || return 0
  fm_tool_list_parse "$file" config/crew-exclude-tools
}

# fm_tool_list_parse <file> <label>: print the comma-joined tool names in a
# one-name-per-line list, naming <label> in every refusal. Non-zero with the
# reason on stderr when the file is unreadable or an entry is malformed.
fm_tool_list_parse() {
  local file=$1 label=$2 line names=''
  if [ ! -f "$file" ] || [ ! -r "$file" ]; then
    echo "error: $label must be a readable regular file" >&2
    return 1
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    case "$line" in
    '' | '#'*) continue ;;
    esac
    if [ -n "${line//[A-Za-z0-9_.-]/}" ]; then
      echo "error: $label has a malformed entry '$line'; expected one tool name per line using only letters, digits, _ . and - (blank lines and # comment lines are allowed)" >&2
      return 1
    fi
    names="${names:+$names,}$line"
  done <"$file" || {
    echo "error: cannot read $label" >&2
    return 1
  }
  printf '%s' "$names"
}

# fm_worker_connector_deny_fragment <bin-dir>: print the
# ,"permissions":{"deny":[...]} fragment a Claude ship or scout launch appends
# to its inline --settings JSON, built from the tracked
# bin/fm-worker-connector-deny.list. Every entry passed fm_tool_list_parse's
# name check, so none needs JSON escaping. Non-zero naming the list when it
# is unreadable or malformed, which is a repository defect, not a local choice.
fm_worker_connector_deny_fragment() {
  local names
  names=$(fm_tool_list_parse "$1/fm-worker-connector-deny.list" bin/fm-worker-connector-deny.list) || return 1
  [ -n "$names" ] || return 0
  printf ',"permissions":{"deny":["%s"]}' "${names//,/\",\"}"
}

# fm_exclude_tools_check <harness> <raw-launch 0|1> <config-dir>: succeed when
# this launch can honor the home's list (empty list, or a runtime that hides
# tools); otherwise refuse naming the file. Prints the names on stdout.
fm_exclude_tools_check() {
  local harness=$1 raw=$2 config=$3 names
  names=$(fm_exclude_tools_names "$config") || return 1
  if [ -n "$names" ]; then
    if [ "$raw" = 1 ]; then
      echo "error: config/crew-exclude-tools lists tools to hide, but a raw launch command cannot hide tools; remove the entries or launch a runtime that supports them (pi, pi-signed)" >&2
      return 1
    fi
    case "$harness" in
    pi | pi-signed) ;;
    *)
      echo "error: config/crew-exclude-tools lists tools to hide, but the $harness runtime cannot hide tools, so this launch is refused rather than running with them available; empty the file or launch a runtime that supports exclusion (pi, pi-signed)" >&2
      return 1
      ;;
    esac
  fi
  printf '%s' "$names"
}
