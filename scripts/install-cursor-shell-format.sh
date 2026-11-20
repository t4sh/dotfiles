#!/usr/bin/env bash
# The Cursor catalog lacks the pinned release. Use the same reviewed VSIX as
# the Windows Cursor installer and verify it before handing it to the editor.
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
pin="$(awk -F '\t' '$1 == "cursor" && $2 == "foxundermoon.shell-format" {
    print $3 "\t" $4 "\t" $5
}' "$repo/config/windows-extensions.tsv")"
IFS=$'\t' read -r extension url checksum <<< "$pin"
if [[ "$pin" == *$'\n'* || ! "$extension" =~ ^foxundermoon\.shell-format@[0-9]+\.[0-9]+\.[0-9]+$ ||
      "$url" != https://github.com/foxundermoon/vs-shell-format/releases/download/* ||
      ! "$checksum" =~ ^[[:xdigit:]]{64}$ ]]; then
    echo 'Invalid Cursor Shell Format release declaration.' >&2
    exit 1
fi

installed="$(cursor --list-extensions --show-versions)"
if grep -Fxiq "$extension" <<< "$installed"; then
    echo "$extension is already installed in Cursor."
    exit 0
fi

scratch="$(mktemp -d "${TMPDIR:-/tmp}/cursor-shell-format.XXXXXXXX")"
vsix="$scratch/shell-format.vsix"
trap 'rm -f -- "$vsix"; rmdir -- "$scratch"' EXIT
curl --fail --silent --show-error --location --retry 2 --output "$vsix" "$url"
printf '%s  %s\n' "$checksum" "$vsix" | shasum -a 256 --check
cursor --install-extension "$vsix" --force
installed="$(cursor --list-extensions --show-versions)"
grep -Fxiq "$extension" <<< "$installed" || {
    echo "Cursor did not report the requested $extension." >&2
    exit 1
}
