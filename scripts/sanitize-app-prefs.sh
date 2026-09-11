#!/usr/bin/env bash
# Normalize portable app pref snapshots after `make backup` copies live files.
# - Editors: standard Homebrew roots → __HOMEBREW_PREFIX__ restore token
# - Sublime: /Users/<user>/.nvm/... → ~/.nvm/versions/node/<dotfiles-default>/bin
# - VS Code: drop yaml.schemas entries with machine-specific file:// paths
# - Binary plists: remove keys that store local home paths, file bookmarks,
#   account-revealing cloud folder names, or intentionally per-machine policy.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES="${DOTFILES:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
APPS="$DOTFILES/apps"
# Literal tilde is written into portable Sublime settings; do not expand it here.
NODE_DEFAULT="$(tr -d '[:space:]' < "$DOTFILES/.node-version" 2>/dev/null || printf 'v22.22.0')"
# shellcheck disable=SC2088
NVM_NODE_BIN="~/.nvm/versions/node/$NODE_DEFAULT/bin"
PLISTBUDDY=/usr/libexec/PlistBuddy
NODE_STABLE="$HOME/.local/bin/node-stable"
HOMEBREW_TOKEN="__HOMEBREW_PREFIX__"

plist_delete() {
  local plist="$1" key="$2"
  [[ -f "$plist" ]] || return 0
  "$PLISTBUDDY" -c "Delete :$key" "$plist" >/dev/null 2>&1 || true
}

plist_set_bool() {
  local plist="$1" key="$2" value="$3"
  [[ -f "$plist" ]] || return 0
  "$PLISTBUDDY" -c "Set :$key $value" "$plist" 2>/dev/null ||
    "$PLISTBUDDY" -c "Add :$key bool $value" "$plist"
}

plist_top_level_keys_matching() {
  local plist="$1" pattern="$2"
  [[ -f "$plist" ]] || return 0
  LC_ALL=C "$PLISTBUDDY" -c Print "$plist" 2>/dev/null |
    LC_ALL=C awk -v pattern="$pattern" '
      /^    [^ ].* =/ {
        key = $0
        sub(/^    /, "", key)
        sub(/ =.*$/, "", key)
        if (key ~ pattern) print key
      }
    '
}

normalize_tower_toolbar() {
  local plist="$1" idx=0 item
  [[ -f "$plist" ]] || return 0
  while item="$("$PLISTBUDDY" -c \
    "Print :\"NSToolbar Configuration MainWindowToolbar.BigSur\":\"TB Item Identifiers\":$idx" \
    "$plist" 2>/dev/null)"; do
    case "$item" in
      GTToolbarItemIdentifierDetailTrackingSeparator.0x*)
        "$PLISTBUDDY" -c \
          "Set :\"NSToolbar Configuration MainWindowToolbar.BigSur\":\"TB Item Identifiers\":$idx GTToolbarItemIdentifierDetailTrackingSeparator" \
          "$plist"
        ;;
    esac
    idx=$((idx + 1))
  done
}

# Secure Keyboard Entry blocks other processes from observing Terminal input,
# but it also prevents the system Touch ID authorization panel from taking
# focus. Keep that security/UX choice local to each Mac instead of restoring it
# from a portable Terminal profile snapshot.
plist_delete "$APPS/terminal/terminal.plist" SecureKeyboardEntry

# Normalize Package Control's captured dependency list in backup and drift
# staging. Never rewrite the running editor merely to sort its package list.
if [[ -f "$APPS/sublime-text/Package Control.sublime-settings" ]]; then
  "${PYTHON_BIN:-python3}" - "$APPS/sublime-text/Package Control.sublime-settings" <<'PY'
import json
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
tokens = r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/'
text = re.sub(tokens, lambda m: m[0] if m[0].startswith('"') else " ", path.read_text())
text = re.sub(r'"(?:\\.|[^"\\])*"|,\s*(?=[}\]])',
              lambda m: m[0] if m[0].startswith('"') else "", text)
settings = json.loads(text)
if "installed_packages" in settings:
    packages = settings["installed_packages"]
    if not isinstance(packages, list) or not all(isinstance(name, str) for name in packages):
        raise ValueError("Package Control installed_packages must be a list of names")
    settings["installed_packages"] = sorted(set(packages), key=lambda name: (name.casefold(), name))
path.write_text(json.dumps(settings, indent=2, sort_keys=True) + "\n")
PY
fi

f="$APPS/sublime-text/SublimeLinter.sublime-settings"
if [[ -f "$f" ]]; then
  perl -i -pe '
    s#/Users/[^/]+/\.nvm/versions/node/[^"/]+/bin#'"$NVM_NODE_BIN"'#g;
    s#~/\.nvm/versions/node/[^"/]+/bin#'"$NVM_NODE_BIN"'#g;
  ' "$f"
fi

# External-agent default/favorite options are machine-local runtime and
# security state, not portable preference policy. Remove these observed fields
# for every configured agent before backups reach Git.
if [[ -f "$APPS/zed/settings.json" ]]; then
  perl -0i -pe '
    s/^  "(?:agent|context_servers)"\s*:\s*\{.*?^  \},?\n//msg;
    for my $key (qw(default_config_options favorite_config_option_values)) {
      s/,\s*"\Q$key\E"\s*:\s*\{[^{}]*\}//g;
      s/"\Q$key\E"\s*:\s*\{[^{}]*\}\s*,?//g;
    }
    s/^[ \t]+$//mg;
    s/\{\n(?:[ \t]*\n)+([ \t]*"type"\s*:\s*"registry")/\{\n$1/g;
  ' "$APPS/zed/settings.json"
fi

for f in \
  "$APPS/sublime-text/GutterColor.sublime-settings" \
  "$APPS/sublime-text/SublimeLinter.sublime-settings" \
  "$APPS/vscode/settings.json" \
  "$APPS/cursor/settings.json" \
  "$APPS/zed/settings.json" \
  "$APPS/zed/keymap.json"; do
  [[ -f "$f" ]] || continue
  HOMEBREW_TOKEN="$HOMEBREW_TOKEN" perl -i -pe '
    s#/(?:opt/homebrew|usr/local)(?=/(?:bin|sbin)(?:/|"))#$ENV{HOMEBREW_TOKEN}#g;
  ' "$f"
done

resolve_node() {
  if [[ -x "$NODE_STABLE" ]]; then
    printf '%s' "$NODE_STABLE"
    return 0
  fi
  # Broken shim (e.g. nvm upgraded past .node-version) — fall back to PATH.
  if command -v node >/dev/null 2>&1; then
    command -v node
    return 0
  fi
  return 1
}

sanitize_editor_settings() {
  local path="$1" node_bin
  [[ -f "$path" ]] && grep -q '/Users/' "$path" 2>/dev/null || return 0
  if ! node_bin="$(resolve_node)"; then
    echo "sanitize-app-prefs: need node to strip machine paths from $path" >&2
    echo "  fix: ln -sf \"\$NVM_DIR/versions/node/\$(<.node-version)/bin/node\" ~/.local/bin/node-stable" >&2
    exit 1
  fi
  if [[ "$node_bin" != "$NODE_STABLE" ]]; then
    echo "sanitize-app-prefs: node-stable missing/broken; using $node_bin" >&2
  fi
  EDITOR_SETTINGS="$path" "$node_bin" <<'NODE'
const fs = require("fs");
const path = process.env.EDITOR_SETTINGS;
if (!path) process.exit(1);
let s = fs.readFileSync(path, "utf8");

function skipTrivia(pos) {
  while (pos < s.length) {
    if (/\s/.test(s[pos])) { pos++; continue; }
    if (s[pos] === "/" && s[pos + 1] === "/") {
      pos += 2;
      while (pos < s.length && s[pos] !== "\n") pos++;
      continue;
    }
    if (s[pos] === "/" && s[pos + 1] === "*") {
      pos += 2;
      while (pos + 1 < s.length && !(s[pos] === "*" && s[pos + 1] === "/")) pos++;
      pos += 2;
      continue;
    }
    break;
  }
  return pos;
}

function findSchemasOpen() {
  let pos = 0;
  while (pos < s.length) {
    if (s[pos] === "/" && s[pos + 1] === "/") {
      pos += 2;
      while (pos < s.length && s[pos] !== "\n") pos++;
      continue;
    }
    if (s[pos] === "/" && s[pos + 1] === "*") {
      pos += 2;
      while (pos + 1 < s.length && !(s[pos] === "*" && s[pos + 1] === "/")) pos++;
      pos += 2;
      continue;
    }
    if (s[pos] !== '"' && s[pos] !== "'") { pos++; continue; }

    const start = pos;
    const delimiter = s[pos++];
    let escaped = false;
    while (pos < s.length) {
      const ch = s[pos++];
      if (escaped) escaped = false;
      else if (ch === "\\") escaped = true;
      else if (ch === delimiter) break;
    }
    if (delimiter !== '"' || s.slice(start, pos) !== '"yaml.schemas"') continue;

    let next = skipTrivia(pos);
    if (s[next] !== ":") continue;
    next = skipTrivia(next + 1);
    if (s[next] === "{") return next;
  }
  return -1;
}

const open = findSchemasOpen();
if (open < 0) {
  const output = redactLocalPathsInComments(s);
  if (output !== s) fs.writeFileSync(path, output);
  process.exit(0);
}
let i = open + 1;
let depth = 1;
let quote = "";
let escaped = false;
let lineComment = false;
let blockComment = false;
while (i < s.length && depth > 0) {
  const ch = s[i];
  const next = s[i + 1] || "";
  if (lineComment) {
    if (ch === "\n") lineComment = false;
  } else if (blockComment) {
    if (ch === "*" && next === "/") { blockComment = false; i++; }
  } else if (quote) {
    if (escaped) escaped = false;
    else if (ch === "\\") escaped = true;
    else if (ch === quote) quote = "";
  } else if (ch === '"' || ch === "'") {
    quote = ch;
  } else if (ch === "/" && next === "/") {
    lineComment = true; i++;
  } else if (ch === "/" && next === "*") {
    blockComment = true; i++;
  } else if (ch === "{") depth++;
  else if (ch === "}") depth--;
  i++;
}
if (depth !== 0) process.exit(1);

const close = i - 1;
const body = s.slice(open + 1, close);
const entries = [];
let start = 0;
depth = 0; quote = ""; escaped = false; lineComment = false; blockComment = false;
for (let j = 0; j < body.length; j++) {
  const ch = body[j];
  const next = body[j + 1] || "";
  if (lineComment) {
    if (ch === "\n") lineComment = false;
  } else if (blockComment) {
    if (ch === "*" && next === "/") { blockComment = false; j++; }
  } else if (quote) {
    if (escaped) escaped = false;
    else if (ch === "\\") escaped = true;
    else if (ch === quote) quote = "";
  } else if (ch === '"' || ch === "'") {
    quote = ch;
  } else if (ch === "/" && next === "/") {
    lineComment = true; j++;
  } else if (ch === "/" && next === "*") {
    blockComment = true; j++;
  } else if (ch === "{" || ch === "[") depth++;
  else if (ch === "}" || ch === "]") depth--;
  else if (ch === "," && depth === 0) {
    entries.push(body.slice(start, j));
    start = j + 1;
  }
}
entries.push(body.slice(start));

function withoutComments(text) {
  let result = "";
  let pos = 0;
  let delimiter = "";
  let escaped = false;
  while (pos < text.length) {
    const ch = text[pos];
    const next = text[pos + 1] || "";
    if (delimiter) {
      result += ch;
      if (escaped) escaped = false;
      else if (ch === "\\") escaped = true;
      else if (ch === delimiter) delimiter = "";
      pos++;
    } else if (ch === '"' || ch === "'") {
      delimiter = ch;
      result += ch;
      pos++;
    } else if (ch === "/" && next === "/") {
      pos += 2;
      while (pos < text.length && text[pos] !== "\n") pos++;
    } else if (ch === "/" && next === "*") {
      pos += 2;
      while (pos + 1 < text.length && !(text[pos] === "*" && text[pos + 1] === "/")) pos++;
      pos += 2;
    } else {
      result += ch;
      pos++;
    }
  }
  return result;
}

function redactLocalPathsInComments(text) {
  const localPath = /\/Users\/[^\/\s<"']+/g;
  let result = "";
  let pos = 0;
  let delimiter = "";
  let escaped = false;
  while (pos < text.length) {
    const ch = text[pos];
    const next = text[pos + 1] || "";
    if (delimiter) {
      result += ch;
      if (escaped) escaped = false;
      else if (ch === "\\") escaped = true;
      else if (ch === delimiter) delimiter = "";
      pos++;
    } else if (ch === '"' || ch === "'") {
      delimiter = ch;
      result += ch;
      pos++;
    } else if (ch === "/" && next === "/") {
      const end = text.indexOf("\n", pos);
      const stop = end < 0 ? text.length : end;
      result += text.slice(pos, stop).replace(localPath, "~");
      pos = stop;
    } else if (ch === "/" && next === "*") {
      const end = text.indexOf("*/", pos + 2);
      const stop = end < 0 ? text.length : end + 2;
      result += text.slice(pos, stop).replace(localPath, "~");
      pos = stop;
    } else {
      result += ch;
      pos++;
    }
  }
  return result;
}

const kept = entries.filter((entry) => !withoutComments(entry).includes("/Users/"));
let output = s;
if (kept.length !== entries.length) {
  output = s.slice(0, open + 1) + kept.join(",") + s.slice(close);
}
output = redactLocalPathsInComments(output);
if (output !== s) fs.writeFileSync(path, output);
NODE
}

sanitize_editor_settings "$APPS/vscode/settings.json"
sanitize_editor_settings "$APPS/cursor/settings.json"
sanitize_editor_settings "$APPS/zed/settings.json"
# Zed keymaps are arrays; this call only redacts machine paths in comments.
sanitize_editor_settings "$APPS/zed/keymap.json"

# BetterZip records recent archive log names and absolute source paths. This is
# runtime history, not portable preference policy, and must never enter backups.
plist_delete "$APPS/betterzip/betterzip.plist" "MIBLogs"
plist_delete "$APPS/betterzip/betterzip.plist" "MIBTempFolders"

# Tower stores license state, App Center device/session identity, repository-ID
# migration caches, and home-directory quick-open state. Remove those values,
# but preserve the main-window toolbar layout while normalizing its
# process-derived tracking-separator identifier.
for key in \
  GTLicenseActivationLastUpdatedDate \
  GTLicenseActivationState \
  GTUserDefaultsMigratedPinnedBranchesRepositories \
  GTUserDefaultsMigratedStackedBranchesRepositories \
  MSAppCenterInstallId \
  MSAppCenterPastDevices \
  MSAppCenterSessionIdHistory \
  MSAppCenterUserIdHistory \
  NSOSPLastRootDirectory; do
  plist_delete "$APPS/tower/tower.plist" "$key"
done
if [[ -f "$APPS/tower/tower.plist" ]]; then
  "$PLISTBUDDY" -c "Set :GTUserDefaultsDefaultCloningDirectory ~/Projects" \
    "$APPS/tower/tower.plist" 2>/dev/null || true
  plist_delete "$APPS/tower/tower.plist" "GTUserDefaultsQuickOpenIgnoredFilePaths"
  normalize_tower_toolbar "$APPS/tower/tower.plist"
  while IFS= read -r key; do
    plist_delete "$APPS/tower/tower.plist" "\"$key\""
  done < <(plist_top_level_keys_matching \
    "$APPS/tower/tower.plist" '^(NSWindow Frame|NSSplitView Subview Frames)')
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
  # Preserve the declared locked-Dock policy even if macOS rewrites these flags
  # before a backup: fixed size/position/items and auto-hide permanently off.
  plist_set_bool "$DOTFILES/macos/dock-backup.plist" "size-immutable" true
  plist_set_bool "$DOTFILES/macos/dock-backup.plist" "position-immutable" true
  plist_set_bool "$DOTFILES/macos/dock-backup.plist" "contents-immutable" true
  plist_set_bool "$DOTFILES/macos/dock-backup.plist" "autohide" false
  plist_set_bool "$DOTFILES/macos/dock-backup.plist" "autohide-immutable" true
  for key in \
    mod-count \
    last-analytics-stamp \
    trash-full \
    lastShowIndicatorTime; do
    plist_delete "$DOTFILES/macos/dock-backup.plist" "$key"
  done

  idx=0
  while "$PLISTBUDDY" -c "Print :persistent-apps:$idx" "$DOTFILES/macos/dock-backup.plist" \
    >/dev/null 2>&1; do
    plist_delete "$DOTFILES/macos/dock-backup.plist" "persistent-apps:$idx:tile-data:book"
    plist_delete "$DOTFILES/macos/dock-backup.plist" "persistent-apps:$idx:tile-data:file-mod-date"
    plist_delete "$DOTFILES/macos/dock-backup.plist" "persistent-apps:$idx:tile-data:parent-mod-date"
    idx=$((idx + 1))
  done
  # Some apps (Hermes Desktop) are installed beneath the operator's home.
  # Store a portable marker; dock.sh expands it only at restore time.
  python3 - "$DOTFILES/macos/dock-backup.plist" <<'PY'
from pathlib import Path
import plistlib
import sys
from urllib.parse import unquote
p = Path(sys.argv[1])
raw = p.read_bytes()
data = plistlib.loads(raw)
home = str(Path.home())
for tile in data.get("persistent-apps", []):
    file_data = tile.get("tile-data", {}).get("file-data", {})
    url = file_data.get("_CFURLString", "")
    if unquote(url).startswith("file://" + home + "/"):
        file_data["_CFURLString"] = "file://__HOME__" + unquote(url)[len("file://" + home):]
p.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_BINARY if raw.startswith(b"bplist") else plistlib.FMT_XML))
PY
fi
plist_delete "$DOTFILES/macos/dock-backup.plist" "persistent-others"

# Public snapshots exclude app identity and device/application inventories.
DOTFILES="$DOTFILES" python3 - <<'PUBLIC_PREFS'
import os, plistlib, re
from pathlib import Path
root = Path(os.environ['DOTFILES']) / 'apps'
for path in root.rglob('*.plist'):
    app = path.parent.name
    if not path.exists():
        continue
    data = plistlib.loads(path.read_bytes())
    original = dict(data)
    for key in list(data):
        if (re.search(r'Paddle|Zephyr|SUUpdateGroupIdentifier', key)
            or (app == 'clop' and key == 'savedPipelines')
            or (app == 'thaw' and (key.startswith('MenuBarItemManager.')
                or key in ('KnownDisplays', 'DisplayIceBarConfigurations',
                           'GlobalDisplayConfiguration', 'NewItemsPlacementData',
                           'MenuBarAppearanceConfigurationV2', 'UnconfirmedSpacingProfileScope')))):
            del data[key]
    if data != original:
        path.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_BINARY))
PUBLIC_PREFS
