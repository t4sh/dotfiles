#!/usr/bin/env bash
# Idempotently enable Touch ID authentication for sudo through sudo_local.
set -euo pipefail

MODE=apply
case "${1:-}" in
  --apply|'') ;;
  --check) MODE=check ;;
  --hardware-check) MODE=hardware-check ;;
  --dry-run) MODE=dry-run ;;
  -h|--help)
    echo "usage: touch-id-sudo.sh [--apply|--check|--hardware-check|--dry-run]"
    exit 0
    ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac

TARGET="${DOTFILES_SUDO_LOCAL:-/etc/pam.d/sudo_local}"
TEMPLATE="${DOTFILES_SUDO_LOCAL_TEMPLATE:-/etc/pam.d/sudo_local.template}"
PATTERN='^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so([[:space:]]|$)'

enabled() {
  [[ -f "$TARGET" ]] && grep -Eq "$PATTERN" "$TARGET"
}

touch_id_available() {
  local override="${DOTFILES_TOUCH_ID_HARDWARE:-auto}" inventory
  case "$override" in
    available) return 0 ;;
    unavailable) return 1 ;;
    auto) ;;
    *) echo "DOTFILES_TOUCH_ID_HARDWARE must be auto, available, or unavailable" >&2; return 2 ;;
  esac
  command -v ioreg >/dev/null 2>&1 || return 1
  inventory="$(ioreg -l -w 0 -r -c AppleBiometricSensor 2>/dev/null || true)"
  [[ -n "$inventory" ]]
}

hardware_status=0
touch_id_available || hardware_status=$?
if (( hardware_status == 2 )); then
  exit 2
fi

if [[ "$MODE" == hardware-check ]]; then
  exit "$hardware_status"
fi

if (( hardware_status != 0 )); then
  echo "  - Touch ID hardware not detected; password-only sudo policy accepted"
  exit 0
fi

if [[ "$MODE" == check ]]; then
  if enabled; then
    echo "  ✓ Touch ID sudo enabled ($TARGET)"
    exit 0
  fi
  echo "Touch ID sudo is not enabled; run: make touch-id-sudo" >&2
  exit 1
fi

if enabled; then
  echo "  ✓ Touch ID sudo already enabled ($TARGET)"
  exit 0
fi

if [[ "$MODE" == dry-run ]]; then
  echo "  would enable pam_tid.so in $TARGET"
  exit 0
fi

base=""
if [[ -f "$TARGET" ]]; then
  base="$TARGET"
elif [[ -f "$TEMPLATE" ]]; then
  base="$TEMPLATE"
fi

stage="$(mktemp -t dotfiles-sudo-local.XXXXXX)"
trap 'rm -f "$stage"' EXIT
{
  printf '%s\n' 'auth       sufficient     pam_tid.so'
  if [[ -n "$base" ]]; then
    awk '!/pam_tid\.so/' "$base"
  fi
} > "$stage"

if [[ "$TARGET" == /etc/* ]]; then
  sudo install -o root -g wheel -m 0444 "$stage" "$TARGET"
else
  mkdir -p "$(dirname "$TARGET")"
  install -m 0444 "$stage" "$TARGET"
fi

enabled || { echo "failed to enable Touch ID sudo in $TARGET" >&2; exit 1; }
echo "  ✓ Touch ID sudo enabled ($TARGET)"
