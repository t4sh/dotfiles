#!/usr/bin/env bash
# Idempotency drift detector.
#
# Usage:
#   scripts/verify-idempotency.sh snapshot    # phase 1: capture current state
#   make all                                  # run the bootstrap
#   scripts/verify-idempotency.sh diff        # phase 2: compare against snapshot
#
# Snapshots live in /tmp/dotfiles-idempotency-<user>/. Re-run `snapshot` to
# refresh; re-run `diff` any number of times.
#
# =============================================================================
# TWO DISTINCT USE CASES
# =============================================================================
#
# 1. DRIFT TEST ON A RUNNING MAC (this is what the script was built for)
#    Snapshot → `make all` → diff. Verifies that a second `make all` on an
#    already-bootstrapped Mac doesn't change observable state. This is the
#    "converges to declared state" claim in the README.
#
# 2. FRESH-MAC VERIFICATION (the one path that can't be tested any other way)
#    On a brand-new Mac after cloning the repo:
#      a. BEFORE running `install.sh`:
#            scripts/verify-idempotency.sh snapshot
#         The baseline will be mostly MISSING links and empty `defaults`
#         domains — that's fine, it's the point.
#      b. Run `bash install.sh`. Note any target that errors — those are first-run
#         idempotency bugs (the branches that only execute when a file/path
#         is absent: Homebrew install, keygen, plist import, shell change).
#      c. Run `scripts/verify-idempotency.sh diff`. On a fresh Mac the diff
#         will be LARGE — that's expected. What matters:
#            - every repo-backed MISSING link should now be a LINK
#            - secret-backed links remain MISSING safely until vault restore + make link
#            - brew check should flip from "missing X, Y, Z" to clean
#            - `defaults` domains should fill in with declared values
#      d. After vault recovery, capture a new baseline, run `make all`, and
#         re-diff. This existing-Mac run is the
#         real idempotency test — it should produce only the known-noise
#         categories (below). Any other drift is a bug.
#
# =============================================================================
# KNOWN-NOISE CATEGORIES (ignore these in any diff)
# =============================================================================
#
#   com.apple.dock:
#     - GUID           (regenerated every `dock.sh` run — by design)
#     - mod-count      (bumped by every `defaults write`)
#     - file-mod-date / parent-mod-date (filesystem mod-times on Dock items)
#     - last-analytics-stamp / trash-full (runtime state, not Dock policy)
#
#   com.apple.finder:
#     - file-bookmark / name pairs under FXRecentFolders (Finder remembers
#       folders you opened during the session)
#     - GoToField / GoToFieldHistory (Cmd-Shift-G history)
#
#   NSGlobalDomain:
#     - AppleAntiAliasingThreshold and AppleLanguages reorderings
#
#   Anywhere:
#     - `book = { length = N, bytes = 0x... }` entries — binary bookmark
#       blobs that change whenever a referenced file moves
#
# =============================================================================
# REAL DRIFT WORTH INVESTIGATING
# =============================================================================
#
#   - Any line in the `symlink / file drift` section. LINK → FILE, readlink
#     target change, or MISSING after `make all` ran = bug in link.sh or
#     the manifest.
#   - Any modified file in the `repo drift` section. `make all` must not
#     write into the repo. (`make backup` does — but it's not in `all`.)
#   - `brew drift` showing newly-missing packages — means something got
#     uninstalled or the Brewfile drifted from reality.
#   - In `defaults`, any key OUTSIDE the known-noise categories flipping
#     value across two `make all` runs. That means a `defaults write` in
#     macos/defaults.sh or dock.sh is toggling instead of setting.
#
# =============================================================================
# FRESH-MAC CHECKLIST (things the drift test can't see; verify manually)
# =============================================================================
#
#   [ ] `xcode-select -p` returns a path (was step 1 of install.sh)
#   [ ] `command -v brew` resolves (Homebrew installed)
#   [ ] `echo $SHELL` returns /bin/zsh (default shell change took)
#   [ ] `ssh -T git@github.com` greets by username (restored key validated and registered)
#   [ ] `gh ssh-key list` shows this host's restored key for authentication, and
#       signing is registered when git signing uses the same key (`make ssh-setup`
#       converges auth + signing separately — two list entries can be correct).
#       Generation requires explicit `scripts/ssh-setup.sh --generate`.
#       Prune older manual duplicates that are not this host's key.
#   [ ] `ls ~/.secrets/` is populated (vault restored from sparseimage)
#   [ ] `gh auth status` reports logged in
#   [ ] Touch ID for sudo works in a NEW terminal tab (/etc/pam.d/sudo_local)
#   [ ] Dock shows the apps declared in macos/dock.sh in the right order
#   [ ] Raycast config imported from ~/.secrets/apps/raycast/ + extensions if needed (manual)
#   [ ] Default browser / mail client set (manual)
#   [ ] SymbolicLinker installed (manual .dmg)
#
# For agents doing this verification: report findings as a structured list
# of (surface, status, evidence). Do NOT silently treat known-noise drift as
# a failure. Do NOT declare success if the manual checklist has unchecked
# items — the drift test is necessary but not sufficient for fresh-Mac
# correctness.
set -euo pipefail

SNAPDIR="${DOTFILES_IDEMPOTENCY_SNAPSHOT_DIR:-/tmp/dotfiles-idempotency-$USER}"
mkdir -p "$SNAPDIR"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
MANIFEST="$DOTFILES/symlinks.tsv"

expand() { local s="$1"; s="${s//\$DOTFILES/$DOTFILES}"; s="${s//\$HOME/$HOME}"; printf '%s' "$s"; }

# Paths to snapshot: every symlink in the manifest + a few well-known ones.
collect_link_paths() {
    awk -F'\t' '!/^[[:space:]]*#/ && NF==2 {print $2}' "$MANIFEST" \
        | while IFS= read -r p; do expand "$p"; echo; done
}

snapshot_links() {
    # Record: path, is-symlink, readlink target, real file inode
    collect_link_paths | while IFS= read -r p; do
        if [ -L "$p" ]; then
            printf 'LINK\t%s\t%s\n' "$p" "$(readlink "$p")"
        elif [ -e "$p" ]; then
            printf 'FILE\t%s\t%s\n' "$p" "$(stat -f '%i' "$p")"
        else
            printf 'MISSING\t%s\t-\n' "$p"
        fi
    done
}

normalize_defaults_plist() {
    local domain="$1" plist="$2"
    python3 - "$domain" "$plist" <<'PY'
import plistlib
import sys

DOMAIN = sys.argv[1]
DROP = {"book", "file-bookmark"}
if DOMAIN == "com.apple.dock":
    DROP.update({
        "GUID",
        "file-mod-date",
        "last-analytics-stamp",
        "mod-count",
        "parent-file-mod-date",
        "parent-mod-date",
        "trash-full",
    })
elif DOMAIN == "com.apple.finder":
    DROP.update({"FXRecentFolders", "GoToField", "GoToFieldHistory"})
elif DOMAIN == "NSGlobalDomain":
    DROP.update({"AppleAntiAliasingThreshold", "AppleLanguages"})


def clean(value):
    if isinstance(value, dict):
        return {key: clean(child) for key, child in value.items() if key not in DROP}
    if isinstance(value, list):
        return [clean(child) for child in value]
    return value


with open(sys.argv[2], "rb") as handle:
    data = plistlib.load(handle)
sys.stdout.buffer.write(plistlib.dumps(clean(data), fmt=plistlib.FMT_XML, sort_keys=True))
PY
}

snapshot_defaults() {
    # Export deterministic plists and remove only the documented runtime-noise
    # keys. Any remaining difference is actionable idempotency drift.
    local domains=(
        com.apple.dock
        com.apple.finder
        com.apple.screencapture
        com.apple.screensaver
        com.apple.menuextra.clock
        com.apple.HIToolbox
        com.apple.symbolichotkeys
        NSGlobalDomain
    )
    local d raw
    for d in "${domains[@]}"; do
        printf '=== %s ===\n' "$d"
        raw="$(mktemp)"
        if defaults export "$d" - > "$raw" 2>/dev/null; then
            normalize_defaults_plist "$d" "$raw"
        else
            echo "(domain absent)"
        fi
        rm -f "$raw"
    done
}

snapshot_repo() {
    git -C "$DOTFILES" status --porcelain
    echo "---"
    git -C "$DOTFILES" rev-parse HEAD
}

snapshot_brew() {
    # The phased helper checks npm rows under the pinned Node runtime.
    env DOTFILES="$DOTFILES" bash "$DOTFILES/scripts/brewfile.sh" check 2>&1 || true
}

phase_snapshot() {
    echo "Snapshotting to $SNAPDIR ..."
    snapshot_links    > "$SNAPDIR/links.txt"
    snapshot_defaults > "$SNAPDIR/defaults.txt"
    snapshot_repo     > "$SNAPDIR/repo.txt"
    snapshot_brew     > "$SNAPDIR/brew.txt"
    wc -l "$SNAPDIR"/*.txt
    echo ""
    echo "Next: run 'make all' (or any subset), then re-run this with 'diff'."
}

phase_diff() {
    [ -f "$SNAPDIR/links.txt" ] || { echo "no snapshot found — run 'snapshot' first" >&2; exit 1; }

    local tmp
    tmp="$(mktemp -d)"
    snapshot_links    > "$tmp/links.txt"
    snapshot_defaults > "$tmp/defaults.txt"
    snapshot_repo     > "$tmp/repo.txt"
    snapshot_brew     > "$tmp/brew.txt"

    local actionable=0
    echo "=== symlink / file drift ==="
    if ! diff -u "$SNAPDIR/links.txt" "$tmp/links.txt"; then actionable=1; fi

    echo ""
    echo "=== repo drift (should be empty — make all must not modify tracked files) ==="
    if ! diff -u "$SNAPDIR/repo.txt" "$tmp/repo.txt"; then actionable=1; fi

    echo ""
    echo "=== brew drift ==="
    if ! diff -u "$SNAPDIR/brew.txt" "$tmp/brew.txt"; then actionable=1; fi

    echo ""
    echo "=== brewfile audit (declared vs current system — catches rg-style gaps) ==="
    if ! bash "$DOTFILES/scripts/audit-brewfile.sh" --check; then actionable=1; fi

    echo ""
    echo "=== defaults drift (documented runtime-noise keys normalized) ==="
    if ! diff -u "$SNAPDIR/defaults.txt" "$tmp/defaults.txt"; then actionable=1; fi

    echo ""
    echo "=== captured app preference safety ==="
    if ! bash "$DOTFILES/scripts/audit-app-prefs.sh" --check; then actionable=1; fi

    echo ""
    echo "=== skill license gate (no restrictive-licensed skill un-gitignored) ==="
    if ! bash "$DOTFILES/scripts/audit-skill-licenses.sh" --check; then actionable=1; fi

    echo ""
    echo "=== rulebook sync (AGENTS.md @-includes match agents/rules/*.md) ==="
    if ! bash "$DOTFILES/scripts/audit-rules.sh"; then actionable=1; fi

    echo ""
    echo "=== Skillsfile sync (generated manifest matches .skill-lock.json) ==="
    if ! python3 "$DOTFILES/scripts/gen-skillsfile.py" --check; then actionable=1; fi

    echo ""
    if [ "$actionable" -eq 0 ]; then
        echo "✓ no actionable drift detected across links, repo, brew, preferences, or policy gates."
    else
        echo "✗ actionable drift detected — review diffs above."
    fi

    rm -rf "$tmp"
    return "$actionable"
}

case "${1:-}" in
    snapshot) phase_snapshot ;;
    diff)     phase_diff ;;
    *)        echo "usage: $0 {snapshot|diff}" >&2; exit 1 ;;
esac
