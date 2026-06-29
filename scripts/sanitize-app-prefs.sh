#!/usr/bin/env bash
# Normalize portable app pref snapshots after `make backup` copies live files.
# - Sublime: /Users/<user>/.nvm/... → ~/.nvm/versions/node/<dotfiles-default>/bin
# - VS Code: drop yaml.schemas entries with machine-specific file:// paths
# - Binary plists: remove keys that store local home paths, file bookmarks, or
#   account-revealing cloud folder names.
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
APPS="$DOTFILES/apps"
# Literal tilde is written into portable Sublime settings; do not expand it here.
NODE_DEFAULT="$(tr -d '[:space:]' < "$DOTFILES/.node-version" 2>/dev/null || printf 'v22.22.0')"
# shellcheck disable=SC2088
NVM_NODE_BIN="~/.nvm/versions/node/$NODE_DEFAULT/bin"
PLISTBUDDY=/usr/libexec/PlistBuddy
NODE_STABLE="$HOME/.local/bin/node-stable"

plist_delete() {
  local plist="$1" key="$2"
  [[ -f "$plist" ]] || return 0
  "$PLISTBUDDY" -c "Delete :$key" "$plist" >/dev/null 2>&1 || true
}

for f in \
  "$APPS/sublime-text/Formatter.sublime-settings" \
  "$APPS/sublime-text/SublimeLinter.sublime-settings"; do
  [[ -f "$f" ]] || continue
  perl -i -pe '
    s#/Users/[^/]+/\.nvm/versions/node/[^"/]+/bin#'"$NVM_NODE_BIN"'#g;
    s#~/\.nvm/versions/node/[^"/]+/bin#'"$NVM_NODE_BIN"'#g;
  ' "$f"
done

VSCODE="$APPS/vscode/settings.json"
if [[ -f "$VSCODE" ]] && grep -q '/Users/' "$VSCODE" 2>/dev/null; then
  if [[ ! -x "$NODE_STABLE" ]]; then
    echo "sanitize-app-prefs: $NODE_STABLE not found; skipping VS Code JSON sanitizer" >&2
  else
    VSCODE_SETTINGS="$VSCODE" "$NODE_STABLE" <<'NODE'
const fs = require("fs");
const path = process.env.VSCODE_SETTINGS;
if (!path) process.exit(1);
let s = fs.readFileSync(path, "utf8");
const re = /\n(\s*)"yaml\.schemas"\s*:\s*\{/;
const m = re.exec(s);
if (!m || !s.includes("/Users/")) process.exit(0);
const start = m.index;
let i = m.index + m[0].length;
let depth = 1;
while (i < s.length && depth > 0) {
  const ch = s[i++];
  if (ch === "{") depth++;
  else if (ch === "}") depth--;
}
while (s[i] === " " || s[i] === "\t") i++;
if (s[i] === ",") i++;
if (s[i] === "\r") i++;
if (s[i] === "\n") i++;
fs.writeFileSync(path, s.slice(0, start) + s.slice(i));
NODE
  fi
fi

# Clop stores output folders, recent directories, and security-scoped bookmarks.
for key in \
  workdir imageDirs videoDirs NSOSPLastRootDirectory; do
  plist_delete "$APPS/clop/clop.plist" "$key"
done

# Gifski stores the last save/open directories, including cloud-account paths.
for key in \
  previousSaveDirectory NSOSPLastRootDirectory; do
  plist_delete "$APPS/gifski/gifski.plist" "$key"
done

# IINA stores screenshot and last-played paths.
for key in \
  screenShotFolder NSOSPLastRootDirectory iinaLastPlayedFilePath; do
  plist_delete "$APPS/iina/iina.plist" "$key"
done

# Pearcleaner stores user-specific app folder choices.
plist_delete "$APPS/pearcleaner/pearcleaner.plist" "settings.folders.apps"
plist_delete "$APPS/pearcleaner/pearcleaner.plist" "settings.lipo.excludedApps"

# Dock binary bookmarks encode local machine/account data and can trip secret
# scanners. Keep app tile URLs and bundle identifiers, but drop bookmark blobs
# and right-side folder tiles from the committed backup.
if [[ -f "$DOTFILES/macos/dock-backup.plist" ]]; then
  while IFS= read -r idx; do
    plist_delete "$DOTFILES/macos/dock-backup.plist" "persistent-apps:$idx:tile-data:book"
  done < <("$PLISTBUDDY" -c "Print :persistent-apps" "$DOTFILES/macos/dock-backup.plist" 2>/dev/null |
    awk '/^    Dict \{$/ { print n++ }')
fi
plist_delete "$DOTFILES/macos/dock-backup.plist" "persistent-others"
