#!/usr/bin/env bash
# Signal traps that end the shell, safe on every supported Bash.
# Side-effect free, so any script can source it; bin/fm-wake-lib.sh sources it
# for its consumers.

# fm_trap_exit [--run <action>] <status> <signal>...
# Trap each signal to run <action>, when given, and then exit with <status>,
# including on Bash 5.2. Bash 5.2 runs a trap that falls due while it rescans a
# $(...) word at expansion time (even an unexecuted ${var:-$(...)} alternative)
# inside that scan's half-open $( parser state, so a plain action fails with
# "unexpected EOF while looking for matching `)'" and the signal is lost (Bash
# 5.3 defers such traps). The action's last line closes that phantom $( there;
# everywhere else exit runs before that line is read.
# <action> is shell text evaluated when the trap fires and must be complete
# commands. A trap action that may return instead of exiting cannot use this
# form, because the closing line is then read as a syntax error.
fm_trap_exit() {  # [--run <action>] <status> <signal>...
  local fm_trap_run=
  if [ "$1" = --run ]; then
    fm_trap_run=$2$'\n'
    shift 2
  fi
  # shellcheck disable=SC2064 # The action and status are fixed now.
  trap "${fm_trap_run}exit $1"$'\n'")" "${@:2}"
}
