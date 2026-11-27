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
NODE_STABLE="$HOME/.local/bin/node-stable"
HOMEBREW_TOKEN="__HOMEBREW_PREFIX__"

# All text editors work on a writable copy. The resulting bytes are installed
# only after the transform succeeds, using the snapshot's own mode and metadata.
edit_text_snapshot() (
  local path="$1" work copy
  shift
  [[ -e "$path" || -L "$path" ]] || return 0
  if [[ ! -f "$path" || -L "$path" ]]; then
    echo "expected a regular preference snapshot: $path" >&2
    return 1
  fi
  work="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-sanitize.XXXXXX")"
  trap 'rm -rf -- "$work"' EXIT
  copy="$work/$(basename "$path")"
  cat "$path" > "$copy"
  "$@" "$copy"
  if ! cmp -s "$copy" "$path"; then
    "${PYTHON_BIN:-python3}" "$SCRIPT_DIR/backup_metadata.py" "$copy" "$path"
  fi
)

# Public-only bookmark and device-inventory policies still apply after the
# shared app-plist sanitation. Work on disposable bytes so protected snapshots
# retain their original metadata when the sanitizer changes content.
edit_public_app_plist() (
  local path="$1" work copy
  [[ -e "$path" || -L "$path" ]] || return 0
  if [[ ! -f "$path" || -L "$path" ]]; then
    echo "expected a regular preference snapshot: $path" >&2
    return 1
  fi
  work="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-sanitize.XXXXXX")"
  trap 'rm -rf -- "$work"' EXIT
  copy="$work/$(basename "$path")"
  cat "$path" > "$copy"
  python3 "$SCRIPT_DIR/public-plist-bookmarks.py" sanitize "$copy"
  python3 - "$copy" "$(basename "$(dirname "$path")")" <<'PY'
import plistlib
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
app = sys.argv[2]
raw = path.read_bytes()
prefs = plistlib.loads(raw)
if not isinstance(prefs, dict):
    raise ValueError("preference root must be a dictionary")
for key in list(prefs):
    if (re.search(r"Paddle|Zephyr|SUUpdateGroupIdentifier", key)
        or (app == "clop" and key == "savedPipelines")
        or (app == "thaw" and (key.startswith("MenuBarItemManager.")
            or key in ("KnownDisplays", "DisplayIceBarConfigurations",
                       "GlobalDisplayConfiguration", "NewItemsPlacementData",
                       "MenuBarAppearanceConfigurationV2", "UnconfirmedSpacingProfileScope")))):
        del prefs[key]
path.write_bytes(plistlib.dumps(prefs, fmt=plistlib.FMT_BINARY if raw.startswith(b"bplist") else plistlib.FMT_XML))
PY
  if ! cmp -s "$copy" "$path"; then
    "${PYTHON_BIN:-python3}" "$SCRIPT_DIR/backup_metadata.py" "$copy" "$path"
  fi
)

# Normalize Package Control's captured dependency list in backup and drift
# staging. Never rewrite the running editor merely to sort its package list.
normalize_sublime_packages() {
  "${PYTHON_BIN:-python3}" - "$1" <<'PY'
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
}

normalize_sublime_linter() {
  perl -i -pe '
    s#/Users/[^/]+/\.nvm/versions/node/[^"/]+/bin#'"$NVM_NODE_BIN"'#g;
    s#~/\.nvm/versions/node/[^"/]+/bin#'"$NVM_NODE_BIN"'#g;
  ' "$1"
  normalize_homebrew_paths "$1"
}

# External-agent default/favorite options are machine-local runtime and
# security state, not portable preference policy. Remove these observed fields
# for every configured agent before backups reach Git.
sanitize_zed_settings() {
  # Remove root agent/context_servers members by JSONC structure: comments and
  # strings are masked first, so braces inside them never count, and invalid
  # input fails closed without rewriting the snapshot.
  python3 - "$1" <<'PY'
import json
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
tokens = r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/'
# Both masks keep every offset: comments become spaces, so commas stay visible
# in `uncommented` for the separator scan; `masked` also drops trailing commas.
uncommented = re.sub(tokens, lambda m: m[0] if m[0].startswith('"') else
                     re.sub(r"[^\n]", " ", m[0]), text)
masked = re.sub(r'"(?:\\.|[^"\\])*"|,(?=\s*[}\]])',
                lambda m: m[0] if m[0].startswith('"') else " ", uncommented)
try:
    if not isinstance(json.loads(masked), dict):
        raise ValueError("root is not an object")
    decoder = json.JSONDecoder()
    pos = masked.index("{") + 1
    removals = []
    while True:
        while masked[pos].isspace() or masked[pos] == ",":
            pos += 1
        if masked[pos] == "}":
            break
        key_start = pos
        key, pos = decoder.raw_decode(masked, pos)
        pos = masked.index(":", pos) + 1
        while masked[pos].isspace():
            pos += 1
        _, end = decoder.raw_decode(masked, pos)
        if key in ("agent", "context_servers"):
            line_start = text.rfind("\n", 0, key_start) + 1
            start = line_start if not text[line_start:key_start].strip() else key_start
            # The member's separator may follow comments or newlines; remove it
            # with the member. Trim real whitespace only, preserving whole comments.
            after = re.compile(r"\s*").match(uncommented, end).end()
            if uncommented[after] == ",":
                end = after + 1
            end = re.compile(r"[ \t]*\n?").match(text, end).end()
            removals.append((start, end))
        pos = end
except (ValueError, IndexError) as error:
    print(f"invalid Zed JSONC: {path}: {error}", file=sys.stderr)
    sys.exit(1)
for start, end in reversed(removals):
    text = text[:start] + text[end:]
# Never write a result that no longer parses or still holds a removed member.
check = re.sub(tokens, lambda m: m[0] if m[0].startswith('"') else " ", text)
check = re.sub(r'"(?:\\.|[^"\\])*"|,(?=\s*[}\]])',
               lambda m: m[0] if m[0].startswith('"') else " ", check)
try:
    result = json.loads(check)
except ValueError:
    result = None
if not isinstance(result, dict) or {"agent", "context_servers"} & set(result):
    print(f"invalid Zed JSONC after sanitizing: {path}", file=sys.stderr)
    sys.exit(1)
open(path, "w", encoding="utf-8").write(text)
PY
  perl -0i -pe '
    for my $key (qw(default_config_options favorite_config_option_values)) {
      s/,\s*"\Q$key\E"\s*:\s*\{[^{}]*\}//g;
      s/"\Q$key\E"\s*:\s*\{[^{}]*\}\s*,?//g;
    }
    s/^[ \t]+$//mg;
    s/\{\n(?:[ \t]*\n)+([ \t]*"type"\s*:\s*"registry")/\{\n$1/g;
  ' "$1"
  sanitize_editor_settings "$1"
}

normalize_homebrew_paths() {
  HOMEBREW_TOKEN="$HOMEBREW_TOKEN" perl -i -pe '
    s#/(?:opt/homebrew|usr/local)(?=/(?:bin|sbin)(?:/|"))#$ENV{HOMEBREW_TOKEN}#g;
  ' "$1"
}

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
  normalize_homebrew_paths "$path"
  grep -q '/Users/' "$path" || return 0
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

edit_text_snapshot "$APPS/sublime-text/Package Control.sublime-settings" normalize_sublime_packages
edit_text_snapshot "$APPS/sublime-text/GutterColor.sublime-settings" normalize_homebrew_paths
edit_text_snapshot "$APPS/sublime-text/SublimeLinter.sublime-settings" normalize_sublime_linter
edit_text_snapshot "$APPS/vscode/settings.json" sanitize_editor_settings
edit_text_snapshot "$APPS/cursor/settings.json" sanitize_editor_settings
edit_text_snapshot "$APPS/zed/settings.json" sanitize_zed_settings
# Zed keymaps are arrays. The editor sanitizer only rewrites portable paths.
edit_text_snapshot "$APPS/zed/keymap.json" sanitize_editor_settings

public_dock_capture=""
trap '[[ -z "$public_dock_capture" ]] || rm -f -- "$public_dock_capture"' EXIT
if (( $# > 0 )) && [[ "$1" != --* ]]; then
  dock_source="$1"
  allowlist="$DOTFILES/macos/dock-layout.plist"
  if [[ ! -f "$allowlist" || -L "$allowlist" ]]; then
    echo "missing public Dock layout allowlist" >&2
    exit 1
  fi
  if [[ -f "$dock_source" ]]; then
    public_dock_capture="$(mktemp "${TMPDIR:-/tmp}/dotfiles-dock-public.XXXXXX")"
    python3 - "$dock_source" "$allowlist" "$DOTFILES/macos/dock-backup.plist" "$public_dock_capture" <<'PY_DOCK_ALLOWLIST'
from copy import deepcopy
from pathlib import Path
import plistlib
import sys
from urllib.parse import unquote, urlsplit

source, allowlist, saved_path, destination = map(Path, sys.argv[1:])
if allowlist.is_symlink() or not allowlist.is_file():
    raise SystemExit("missing public Dock layout allowlist")
raw = source.read_bytes()
capture = plistlib.loads(raw)
saved = plistlib.loads(saved_path.read_bytes()) if saved_path.is_file() and not saved_path.is_symlink() else {}
approved = plistlib.loads(allowlist.read_bytes()).get("persistent-apps", [])
tiles = capture.get("persistent-apps", [])
if not isinstance(approved, list) or not all(isinstance(tile, dict) for tile in approved):
    raise SystemExit("invalid public Dock layout allowlist")
if not isinstance(tiles, list) or not all(isinstance(tile, dict) for tile in tiles):
    raise SystemExit("invalid Dock capture")

def app_name(tile):
    url = tile.get("tile-data", {}).get("file-data", {}).get("_CFURLString", "")
    if not isinstance(url, str):
        return ""
    return Path(unquote(urlsplit(url).path).rstrip("/")).name.removesuffix(".app").casefold()

public_tiles = {app_name(tile): tile for tile in approved if app_name(tile)}
selected = []
for tile in tiles:
    identity = app_name(tile)
    if identity in public_tiles:
        # Reuse only the reviewed public template, never live labels, URLs,
        # bookmarks, GUIDs, or other Dock metadata.
        selected.append(deepcopy(public_tiles[identity]))
    elif tile.get("tile-type") in {"spacer-tile", "small-spacer-tile"}:
        selected.append({"tile-type": tile["tile-type"]})
public_capture = deepcopy(saved) if isinstance(saved, dict) else {}
public_capture["persistent-apps"] = selected
if "recent-apps" in capture or "recent-apps" in public_capture:
    public_capture["recent-apps"] = []
public_capture.pop("persistent-others", None)
destination.write_bytes(plistlib.dumps(
    public_capture, fmt=plistlib.FMT_BINARY if raw.startswith(b"bplist") else plistlib.FMT_XML,
    sort_keys=False))
PY_DOCK_ALLOWLIST
    shift
    set -- "$public_dock_capture" "$@"
  fi
fi
"${PYTHON_BIN:-python3}" "$SCRIPT_DIR/sanitize-app-plists.py" "$DOTFILES" "$@"

if [[ -d "$APPS" ]]; then
  while IFS= read -r -d '' bookmark_snapshot; do
    edit_public_app_plist "$bookmark_snapshot"
  done < <(find "$APPS" -type f -name '*.plist' -print0)
fi

# Editor trust and confirmation policy applies even when a capture has no
# machine path to trigger the path-redaction transform.
for editor in zed vscode cursor; do
  editor_snapshot="$APPS/$editor/settings.json"
  [[ -f "$editor_snapshot" ]] || continue
  edit_text_snapshot "$editor_snapshot" python3 "$SCRIPT_DIR/public-editor-policy.py" sanitize --editor "$editor"
done
