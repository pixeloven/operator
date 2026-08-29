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
set -u

usage() {
  cat <<'EOF'
fm-delivery-lane.sh - prepare and verify the autonomous unsigned Git lane

Usage:
  fm-delivery-lane.sh prepare <config-path>
  fm-delivery-lane.sh preflight <config-path>

prepare writes a private task-owned Git config with signing disabled and the
stable Firstmate autonomous identity. preflight verifies that configuration and
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

prepare() {
  local dir tmp
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
  if ! chmod 600 "$tmp" || ! mv -f "$tmp" "$CONFIG"; then
    rm -f "$tmp"
    printf 'prepare=failed reason=write\n' >&2
    return 1
  fi
  printf 'prepare=ok config=%s signing=disabled identity=stable\n' "$CONFIG"
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
