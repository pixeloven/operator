#!/usr/bin/env bash
# fm-delivery-lane.sh - autonomous worker Git delivery contract.
#
# Usage:
#   fm-delivery-lane.sh prepare <config-path>
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
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$(dirname "$SCRIPT_DIR")}}"
CREDENTIAL_HELPER_FILE="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}/delivery-lane-github-credential-helper"
CREDENTIAL_HELPER_KEY=credential.https://github.com.helper

usage() {
  cat <<'EOF'
fm-delivery-lane.sh - prepare and verify the autonomous unsigned Git lane

Usage:
  fm-delivery-lane.sh prepare <config-path>
  fm-delivery-lane.sh preflight <config-path>

prepare writes a private task-owned Git config with signing disabled and the
stable Firstmate autonomous identity, plus the https://github.com credential
helper named by config/delivery-lane-github-credential-helper when that file
is present and not blank. preflight verifies that configuration and
prints one diagnostic line per relevant host signing setting; it never changes
human Git configuration or invokes a signer.
EOF
}

die() { printf 'fm-delivery-lane: %s\n' "$1" >&2; exit 2; }

[ "$#" -eq 2 ] || { usage >&2; exit 2; }
ACTION=$1
CONFIG=$2
case "$ACTION" in prepare|preflight) ;; -h|--help) usage; exit 0 ;; *) die "unknown action: $ACTION" ;; esac
case "$CONFIG" in ''|-*) die "config path must be non-empty and not an option" ;; esac

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

prepare() {
  local dir tmp helper
  helper=$(credential_helper) || return 1
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
  if ! chmod 600 "$tmp" || ! mv -f "$tmp" "$CONFIG"; then
    rm -f "$tmp"
    printf 'prepare=failed reason=write\n' >&2
    return 1
  fi
  if [ -n "$helper" ]; then
    printf 'prepare=ok config=%s signing=disabled identity=stable credential-helper=github\n' "$CONFIG"
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
