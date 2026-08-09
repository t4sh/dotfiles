#!/usr/bin/env bash
# Validate the declarative TSV manifests before any consumer mutates state.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
DESTINATIONS_TMP=""
DOMAINS_TMP=""
PLISTS_TMP=""

cleanup() {
  if [[ -n "$DESTINATIONS_TMP" ]]; then rm -f -- "$DESTINATIONS_TMP"; fi
  if [[ -n "$DOMAINS_TMP" ]]; then rm -f -- "$DOMAINS_TMP"; fi
  if [[ -n "$PLISTS_TMP" ]]; then rm -f -- "$PLISTS_TMP"; fi
  return 0
}
trap cleanup EXIT

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

tab_count() {
  local tabs="${1//[^$'\t']/}"
  printf '%s' "${#tabs}"
}

expand_supported_absolute() {
  local value="$1" label="$2" expanded
  expanded="$value"
  expanded="${expanded//\$DOTFILES/$DOTFILES}"
  expanded="${expanded//\$HOME/$HOME}"
  [[ "$expanded" == /* ]] || die "$label must resolve to an absolute path: $value"
  [[ "$expanded" != *'$'* && "$expanded" != *'`'* ]] || die "$label uses an unsupported placeholder: $value"
  [[ "$expanded" != *'/../'* && "$expanded" != */.. && "$expanded" != *'/./'* && "$expanded" != */. ]] || \
    die "$label must not contain dot segments: $value"
  printf '%s' "$expanded"
}

validate_symlinks() {
  local manifest="${SYMLINKS_MANIFEST:-$DOTFILES/symlinks.tsv}" line number=0 src dst expanded_src expanded_dst
  [[ -f "$manifest" ]] || die "manifest not found: $manifest"
  DESTINATIONS_TMP="$(mktemp -t dotfiles-link-destinations.XXXXXX)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    number=$((number + 1))
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$(tab_count "$line")" == "1" ]] || die "$manifest:$number must contain exactly 2 tab-separated fields"
    IFS=$'\t' read -r src dst <<< "$line"
    [[ -n "$src" && -n "$dst" ]] || die "$manifest:$number has an empty source or destination"
    expanded_src="$(expand_supported_absolute "$src" "$manifest:$number source")"
    expanded_dst="$(expand_supported_absolute "$dst" "$manifest:$number destination")"
    [[ "$expanded_src" == "$DOTFILES/"* || "$expanded_src" == "$HOME/.secrets/"* || \
       "$expanded_src" == "$HOME/.agents/"* ]] || \
      die "$manifest:$number source must be beneath an owned root (\$DOTFILES, \$HOME/.secrets, or \$HOME/.agents): $src"
    [[ "$expanded_dst" == "$HOME/"* ]] || \
      die "$manifest:$number destination must be beneath the owned root \$HOME: $dst"
    if grep -Fqx -- "$expanded_dst" "$DESTINATIONS_TMP"; then
      die "$manifest:$number duplicates destination: $dst"
    fi
    printf '%s\n' "$expanded_dst" >> "$DESTINATIONS_TMP"
  done < "$manifest"
}

validate_apps() {
  local manifest="${APPS_MANIFEST:-$DOTFILES/apps.tsv}" line number=0 domain label plist fields
  [[ -f "$manifest" ]] || die "manifest not found: $manifest"
  DOMAINS_TMP="$(mktemp -t dotfiles-app-domains.XXXXXX)"
  PLISTS_TMP="$(mktemp -t dotfiles-app-plists.XXXXXX)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    number=$((number + 1))
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    fields=$(( $(tab_count "$line") + 1 ))
    (( fields == 3 || fields == 4 )) || die "$manifest:$number must contain 3 or 4 tab-separated fields"
    IFS=$'\t' read -r domain label plist _ <<< "$line"
    [[ -n "$domain" && -n "$label" && -n "$plist" ]] || die "$manifest:$number has an empty required field"
    [[ "$domain" != *[[:space:]]* ]] || die "$manifest:$number domain must not contain whitespace: $domain"
    [[ "$plist" != /* && "$plist" != *'$'* && "$plist" != *'`'* ]] || \
      die "$manifest:$number plist must be repo-relative without placeholders: $plist"
    [[ "$plist" != ../* && "$plist" != *'/../'* && "$plist" != */.. && "$plist" != ./* && "$plist" != *'/./'* ]] || \
      die "$manifest:$number plist must not contain dot segments: $plist"
    if grep -Fqx -- "$domain" "$DOMAINS_TMP"; then
      die "$manifest:$number duplicates domain: $domain"
    fi
    if grep -Fqx -- "$plist" "$PLISTS_TMP"; then
      die "$manifest:$number duplicates plist path: $plist"
    fi
    printf '%s\n' "$domain" >> "$DOMAINS_TMP"
    printf '%s\n' "$plist" >> "$PLISTS_TMP"
  done < "$manifest"
}

case "${1:-all}" in
  symlinks) validate_symlinks ;;
  apps) validate_apps ;;
  all) validate_symlinks; validate_apps ;;
  *) die "usage: validate-manifests.sh [symlinks|apps|all]" ;;
esac
