#!/usr/bin/env bash
# Create or verify non-secret APFS disk-image fixtures for cross-macOS testing.
set -euo pipefail

MODE="${1:-create}"
OUTPUT="${2:-}"
PROBE_PASS="dotfiles-ventura-format-probe"

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
usage:
  secrets-format-compat.sh create [output-directory]
  secrets-format-compat.sh verify <fixture-directory>

The fixtures contain only a disposable text file. Their shared password is:
  dotfiles-ventura-format-probe
EOF
}

create_fixtures() (
  local output="$OUTPUT" payload udsp udzo
  local output_owned=0 complete=0
  if [[ -z "$output" ]]; then
    output="$(mktemp -d "${TMPDIR:-/private/tmp}/dotfiles-vault-compat.XXXXXX")"
    output_owned=1
  else
    [[ "$output" == /* ]] || die "output directory must be absolute: $output"
    [[ ! -e "$output" ]] || die "output already exists: $output"
    mkdir -p "$output"
    output_owned=1
  fi
  chmod 700 "$output"
  # shellcheck disable=SC2329 # invoked by the EXIT trap
  cleanup_output() {
    if (( output_owned && ! complete )); then
      rm -rf -- "$output"
    fi
  }
  trap cleanup_output EXIT

  payload="$output/payload"
  mkdir -p "$payload"
  printf 'APFS disk-image compatibility probe\n' > "$payload/probe.txt"
  udsp="$output/DotfilesSecrets-APFS-UDSP.sparseimage"
  udzo="$output/DotfilesSecrets-APFS-UDZO.dmg"

  info "creating encrypted APFS/UDSP fixture"
  printf '%s' "$PROBE_PASS" | hdiutil create \
    -srcfolder "$payload" \
    -format UDSP \
    -layout GPTSPUD \
    -fs APFS \
    -volname DotfilesUDSPProbe \
    -encryption AES-256 \
    -stdinpass \
    "$udsp" >/dev/null

  info "creating encrypted APFS/UDZO fixture"
  printf '%s' "$PROBE_PASS" | hdiutil create \
    -srcfolder "$payload" \
    -format UDZO \
    -layout GPTSPUD \
    -fs APFS \
    -volname DotfilesUDZOProbe \
    -encryption AES-256 \
    -stdinpass \
    "$udzo" >/dev/null

  (
    cd "$output"
    shasum -a 256 \
      "$(basename "$udsp")" \
      "$(basename "$udzo")" > SHA256SUMS
  )
  rm -rf -- "$payload"

  complete=1
  ok "fixtures created at $output"
  printf 'shared disposable password: %s\n' "$PROBE_PASS"
  printf 'Ventura check: bash scripts/secrets-format-compat.sh verify %q\n' "$output"
)

verify_one() (
  local image="$1" expected_volume="$2"
  local attach_plist mountpoint="" device="" cleanup_device="" index=0 status=0

  attach_plist="$(mktemp "${TMPDIR:-/private/tmp}/dotfiles-compat-attach.XXXXXX")"
  # shellcheck disable=SC2329 # invoked by the EXIT trap
  cleanup_attachment() {
    if [[ -n "$device" ]]; then
      hdiutil detach "$device" >/dev/null 2>&1 || true
    elif [[ -n "$cleanup_device" ]]; then
      hdiutil detach "$cleanup_device" >/dev/null 2>&1 || true
    fi
    rm -f -- "$attach_plist"
  }
  trap cleanup_attachment EXIT

  info "attaching $(basename "$image")"
  if printf '%s' "$PROBE_PASS" | hdiutil attach \
      -readonly -nobrowse -stdinpass -plist "$image" > "$attach_plist"; then
    :
  else
    status=$?
    printf '\033[31m  ✗\033[0m attach failed: %s\n' "$(basename "$image")" >&2
    return "$status"
  fi

  while :; do
    device="$(/usr/bin/plutil -extract "system-entities.$index.dev-entry" raw -o - "$attach_plist" 2>/dev/null || true)"
    mountpoint="$(/usr/bin/plutil -extract "system-entities.$index.mount-point" raw -o - "$attach_plist" 2>/dev/null || true)"
    [[ -n "$device" || -n "$mountpoint" ]] || break
    if [[ -z "$cleanup_device" && "$device" == /dev/disk* ]]; then
      cleanup_device="$device"
    fi
    if [[ -n "$mountpoint" && "$device" == /dev/disk* ]]; then
      break
    fi
    device=""
    mountpoint=""
    index=$((index + 1))
  done

  [[ -n "$device" && -d "$mountpoint" ]] || die "attach returned no mounted device for $(basename "$image")"
  [[ "$(basename "$mountpoint")" == "$expected_volume" ]] || \
    die "unexpected mounted volume for $(basename "$image"): $mountpoint"
  mount | grep -F " on $mountpoint (apfs," >/dev/null || \
    die "fixture did not mount as APFS: $(basename "$image")"
  [[ "$(<"$mountpoint/probe.txt")" == "APFS disk-image compatibility probe" ]] || \
    die "probe payload unreadable in $(basename "$image")"

  hdiutil detach "$device" >/dev/null
  device=""
  cleanup_device=""
  ok "readable: $(basename "$image")"
)

verify_fixtures() {
  [[ -n "$OUTPUT" && "$OUTPUT" == /* && -d "$OUTPUT" ]] || \
    die "verify requires an absolute fixture directory"
  [[ -f "$OUTPUT/SHA256SUMS" ]] || die "missing SHA256SUMS in $OUTPUT"
  (
    cd "$OUTPUT"
    shasum -a 256 -c SHA256SUMS
  )
  verify_one "$OUTPUT/DotfilesSecrets-APFS-UDSP.sparseimage" DotfilesUDSPProbe
  verify_one "$OUTPUT/DotfilesSecrets-APFS-UDZO.dmg" DotfilesUDZOProbe
  ok "both APFS fixtures are readable on macOS $(sw_vers -productVersion)"
}

case "$MODE" in
  create) create_fixtures ;;
  verify) verify_fixtures ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 2 ;;
esac
