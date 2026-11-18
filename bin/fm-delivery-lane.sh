#!/usr/bin/env bash
# fm-delivery-lane.sh - autonomous worker Git delivery contract.
#
# Usage:
#   fm-delivery-lane.sh prepare <config-path> [--carry-github-credential-helper]
#   fm-delivery-lane.sh preflight <config-path>
#
# The autonomous lane uses a task-owned Git config as GIT_CONFIG_GLOBAL with
# GIT_CONFIG_NOSYSTEM=1. It is deliberately unsigned and carries a stable bot
# identity, so a worker never invokes a captain's interactive signer. The file
# is disposable with the task temp root and is inspectable while the task runs.
#
# The optional local config/delivery-lane-github-credential-helper (resolved
# like every other config file: FM_CONFIG_OVERRIDE, else $FM_HOME/config) names
# one Git credential helper for https://github.com, because GIT_CONFIG_NOSYSTEM=1
# and the replaced global config otherwise leave a worker with none. prepare
# trims surrounding whitespace, ignores a blank file exactly like an absent one,
# refuses an unreadable or multi-line value, and writes the value through
# `git config` as the lane's single credential.https://github.com.helper entry,
# so Git owns the quoting. The value is a command, never a credential, and is
# never echoed into output (ADR-0022).
#
# --carry-github-credential-helper is for secondmate (navigator) launches only:
# a navigator supervises from its own home and must reach GitHub the way its
# launching firstmate does, for example for fm-teardown.sh's landed-work fetch,
# but GIT_CONFIG_NOSYSTEM=1 also hides the system-level file that wires a host
# helper such as macOS osxkeychain. When the setting above is absent or blank,
# prepare resolves the effective credential.helper list that this process's own
# Git configuration applies to https://github.com - the generic key and the
# exact credential.https://github.com.helper key, in configuration order, with an
# empty value clearing the list the way Git does - and writes each surviving
# helper as a credential.https://github.com.helper entry. Nothing else from the
# system or human configuration is carried, the helpers answer only for
# https://github.com, and an operator-configured setting still wins as the lane's
# single entry. A lane with nothing to carry is byte-identical to the plain lane.
# Ship and scout launches never pass the flag (ADR-0038).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$(dirname "$SCRIPT_DIR")}}"
CREDENTIAL_HELPER_FILE="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}/delivery-lane-github-credential-helper"
CREDENTIAL_HELPER_KEY=credential.https://github.com.helper

usage() {
  cat <<'EOF'
fm-delivery-lane.sh - prepare and verify the autonomous unsigned Git lane

Usage:
  fm-delivery-lane.sh prepare <config-path> [--carry-github-credential-helper]
  fm-delivery-lane.sh preflight <config-path>

prepare writes a private task-owned Git config with signing disabled and the
stable Firstmate autonomous identity, plus the https://github.com credential
helper named by config/delivery-lane-github-credential-helper when that file
is present and not blank. With --carry-github-credential-helper (secondmate
launches) and no such setting, it instead carries the credential helpers this
process's own Git configuration applies to https://github.com, scoped to that
host. preflight verifies that configuration and
prints one diagnostic line per relevant host signing setting; it never changes
human Git configuration or invokes a signer.
EOF
}

die() { printf 'fm-delivery-lane: %s\n' "$1" >&2; exit 2; }

case "${1-}" in -h|--help) usage; exit 0 ;; esac
[ "$#" -eq 2 ] || [ "$#" -eq 3 ] || { usage >&2; exit 2; }
ACTION=$1
CONFIG=$2
CARRY_HOST_HELPER=0
case "$ACTION" in prepare|preflight) ;; *) die "unknown action: $ACTION" ;; esac
case "$CONFIG" in ''|-*) die "config path must be non-empty and not an option" ;; esac
if [ "$#" -eq 3 ]; then
  [ "$ACTION" = prepare ] && [ "$3" = --carry-github-credential-helper ] || die "unknown option for $ACTION: $3"
  CARRY_HOST_HELPER=1
fi

# Prints the trimmed helper command, or nothing when the setting is absent or
# blank; returns non-zero, naming only the reason, when it cannot be used.
credential_helper() {
  local value
  [ -e "$CREDENTIAL_HELPER_FILE" ] || [ -L "$CREDENTIAL_HELPER_FILE" ] || return 0
  if [ ! -f "$CREDENTIAL_HELPER_FILE" ] || ! value=$(cat "$CREDENTIAL_HELPER_FILE" 2>/dev/null); then
    printf 'prepare=failed reason=credential-helper-unreadable path=%s\n' "$CREDENTIAL_HELPER_FILE" >&2
    return 1
  fi
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  case "$value" in
    *$'\n'*|*$'\r'*)
      printf 'prepare=failed reason=credential-helper-multiline path=%s\n' "$CREDENTIAL_HELPER_FILE" >&2
      return 1 ;;
  esac
  printf '%s' "$value"
}

# Fills HOST_HELPERS with the effective credential.helper list this process's
# own Git configuration applies to https://github.com, outside any repository.
# An empty value clears the list, as in Git; a valueless key is skipped because
# Git itself rejects it. Returns non-zero when the configuration is unreadable.
HOST_HELPERS=()
resolve_host_helpers() {
  local raw status entry key value
  raw=$(cd / && env -u GIT_DIR -u GIT_WORK_TREE git config -z --get-regexp \
    '^credential\.(https://github\.com\.)?helper$' 2>/dev/null | tr '\0' '\036'; exit "${PIPESTATUS[0]}")
  status=$?
  case "$status" in
    0) ;;
    1) return 0 ;;
    *)
      printf 'prepare=failed reason=credential-helper-resolve\n' >&2
      return 1 ;;
  esac
  while IFS= read -r -d $'\036' entry; do
    key=${entry%%$'\n'*}
    [ "$key" != "$entry" ] || continue
    value=${entry#*$'\n'}
    if [ -z "$value" ]; then
      HOST_HELPERS=()
    else
      HOST_HELPERS+=("$value")
    fi
  done <<< "$raw"
  return 0
}

prepare() {
  local dir tmp helper carried=0 host_helper
  helper=$(credential_helper) || return 1
  if [ -z "$helper" ] && [ "$CARRY_HOST_HELPER" = 1 ]; then
    resolve_host_helpers || return 1
    carried=${#HOST_HELPERS[@]}
  fi
  dir=$(dirname "$CONFIG")
  mkdir -p "$dir" || { printf 'prepare=failed reason=directory\n' >&2; return 1; }
  tmp="$CONFIG.tmp.$$"
  umask 077
  cat > "$tmp" <<'EOF'
# Firstmate autonomous delivery lane. Unsigned by design; do not copy to a human repo.
[commit]
    gpgSign = false
[tag]
    gpgSign = false
[user]
    name = Firstmate Autonomous Worker
    email = firstmate-autonomous@localhost
EOF
  if [ -n "$helper" ] && ! git config --file "$tmp" "$CREDENTIAL_HELPER_KEY" "$helper" 2>/dev/null; then
    rm -f "$tmp" "$tmp.lock"
    printf 'prepare=failed reason=credential-helper-write\n' >&2
    return 1
  fi
  if [ "$carried" -gt 0 ]; then
    for host_helper in "${HOST_HELPERS[@]}"; do
      if ! git config --file "$tmp" --add "$CREDENTIAL_HELPER_KEY" "$host_helper" 2>/dev/null; then
        rm -f "$tmp" "$tmp.lock"
        printf 'prepare=failed reason=credential-helper-write\n' >&2
        return 1
      fi
    done
  fi
  if ! chmod 600 "$tmp" || ! mv -f "$tmp" "$CONFIG"; then
    rm -f "$tmp"
    printf 'prepare=failed reason=write\n' >&2
    return 1
  fi
  if [ -n "$helper" ]; then
    printf 'prepare=ok config=%s signing=disabled identity=stable credential-helper=github\n' "$CONFIG"
  elif [ "$carried" -gt 0 ]; then
    printf 'prepare=ok config=%s signing=disabled identity=stable credential-helper=carried\n' "$CONFIG"
  else
    printf 'prepare=ok config=%s signing=disabled identity=stable\n' "$CONFIG"
  fi
}

preflight() {
  local commit tag format signer key
  [ -f "$CONFIG" ] || { printf 'preflight=failed reason=missing-config path=%s\n' "$CONFIG" >&2; return 1; }
  commit=$(git config --file "$CONFIG" --get commit.gpgsign 2>/dev/null || true)
  tag=$(git config --file "$CONFIG" --get tag.gpgsign 2>/dev/null || true)
  [ "$commit" = false ] || { printf 'preflight=failed reason=commit-signing-not-disabled value=%s\n' "${commit:-unset}" >&2; return 1; }
  [ "$tag" = false ] || { printf 'preflight=failed reason=tag-signing-not-disabled value=%s\n' "${tag:-unset}" >&2; return 1; }
  format=$(git config --get gpg.format 2>/dev/null || true)
  signer=$(git config --get gpg.ssh.program 2>/dev/null || true)
  key=$(git config --get user.signingkey 2>/dev/null || true)
  if [ -n "$signer" ] && printf '%s' "$signer" | grep -qi '1password\|op-ssh-sign'; then
    printf 'diagnostic=human-1password-signer-overridden\n'
  elif [ "$format" = ssh ] && [ -z "$key" ] && [ -z "$(git config --get gpg.ssh.defaultKeyCommand 2>/dev/null || true)" ]; then
    printf 'diagnostic=human-ssh-signing-config-incomplete\n'
  else
    printf 'diagnostic=human-signing-config-not-used\n'
  fi
  printf 'preflight=ok config=%s signing=disabled\n' "$CONFIG"
}

case "$ACTION" in
  prepare) prepare ;;
  preflight) preflight ;;
esac
