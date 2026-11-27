#!/usr/bin/env python3
"""Remove machine-local values from disposable app preference exports."""

import argparse
from copy import deepcopy
from pathlib import Path
import plistlib
from urllib.parse import unquote
from xml.parsers.expat import ExpatError

from backup_metadata import replace_bytes


# Each policy names keys in the top-level dictionary, including literal dots.
LOCAL_KEYS = {
    # Secure Keyboard Entry is each Mac's choice and affects Touch ID prompts.
    "apps/terminal/terminal.plist": ("SecureKeyboardEntry",),
    "apps/betterzip/betterzip.plist": ("MIBLogs", "MIBTempFolders", "MIBRegCode"),
    "apps/tower/tower.plist": (
        "GTLicenseActivationLastUpdatedDate",
        "GTLicenseActivationState",
        "GTUserDefaultsMigratedPinnedBranchesRepositories",
        "GTUserDefaultsMigratedStackedBranchesRepositories",
        "GTUserDefaultsQuickOpenIgnoredFilePaths",
        "MSAppCenterInstallId",
        "MSAppCenterPastDevices",
        "MSAppCenterSessionIdHistory",
        "MSAppCenterUserIdHistory",
        "NSOSPLastRootDirectory",
    ),
    "apps/clop/clop.plist": ("workdir", "imageDirs", "videoDirs", "NSOSPLastRootDirectory"),
    "apps/gifski/gifski.plist": ("previousSaveDirectory", "NSOSPLastRootDirectory"),
    # Restore takes IINA's output folder from the selected screenshot policy.
    "apps/iina/iina.plist": ("screenShotFolder", "NSOSPLastRootDirectory", "iinaLastPlayedFilePath"),
    "apps/pearcleaner/pearcleaner.plist": ("settings.folders.apps", "settings.lipo.excludedApps"),
}
DOCK = "macos/dock-backup.plist"
TOWER_SEPARATOR = "GTToolbarItemIdentifierDetailTrackingSeparator"
INVALID_PLIST = (ValueError, plistlib.InvalidFileException, ExpatError)


def normalize_app(relative, settings):
    for key in LOCAL_KEYS[relative]:
        settings.pop(key, None)
    if relative == "apps/betterzip/betterzip.plist":
        presets = settings.get("MIBSavePresets", [])
        if not isinstance(presets, list):
            raise ValueError("BetterZip save presets must be an array")
        for preset in presets:
            if isinstance(preset, dict):
                preset.pop("password", None)
    elif relative == "apps/tower/tower.plist":
        if "GTUserDefaultsDefaultCloningDirectory" in settings:
            settings["GTUserDefaultsDefaultCloningDirectory"] = "~/Projects"
        for key in list(settings):
            if key.startswith(("NSWindow Frame", "NSSplitView Subview Frames")):
                del settings[key]
        toolbar = settings.get("NSToolbar Configuration MainWindowToolbar.BigSur")
        if isinstance(toolbar, dict) and isinstance(toolbar.get("TB Item Identifiers"), list):
            items = toolbar["TB Item Identifiers"]
            for index, item in enumerate(items):
                if isinstance(item, str) and item.startswith(TOWER_SEPARATOR + ".0x"):
                    items[index] = TOWER_SEPARATOR


def normalize_dock(data):
    # Keep portable app tile URLs and policy, and remove machine-assigned data.
    data["size-immutable"] = True
    data["position-immutable"] = True
    data["contents-immutable"] = True
    data.setdefault("autohide", False)
    data["autohide-immutable"] = True
    for key in ("mod-count", "last-analytics-stamp", "trash-full",
                "lastShowIndicatorTime", "persistent-others"):
        data.pop(key, None)

    home = "file://" + str(Path.home())
    tiles = data.get("persistent-apps", [])
    if not isinstance(tiles, list):
        raise ValueError("Dock persistent-apps must be an array")
    for tile in tiles:
        if not isinstance(tile, dict):
            raise ValueError("Dock tile must be a dictionary")
        tile_data = tile.get("tile-data", {})
        if not isinstance(tile_data, dict):
            raise ValueError("Dock tile-data must be a dictionary")
        for key in ("book", "file-mod-date", "parent-mod-date"):
            tile_data.pop(key, None)
        file_data = tile_data.get("file-data", {})
        if not isinstance(file_data, dict):
            raise ValueError("Dock tile file-data must be a dictionary")
        url = file_data.get("_CFURLString", "")
        if not isinstance(url, str):
            raise ValueError("Dock tile URL must be a string")
        decoded = unquote(url)
        if decoded.startswith(home + "/"):
            file_data["_CFURLString"] = "file://__HOME__" + decoded[len(home):]


def process(relative, snapshot, *, capture=None, comparison=False, check=False):
    if snapshot.is_symlink() or (snapshot.exists() and not snapshot.is_file()):
        raise ValueError(f"expected a regular preference snapshot: {relative}")
    if capture is None and not snapshot.exists():
        return
    source = capture or snapshot
    raw = source.read_bytes()
    try:
        saved = plistlib.loads(raw)
        if not isinstance(saved, dict):
            raise ValueError("preference root must be a dictionary")
        portable = deepcopy(saved)
        if relative == DOCK:
            normalize_dock(portable)
        else:
            normalize_app(relative, portable)
    except INVALID_PLIST:
        # A bad saved copy can be replaced by a valid capture. The final audit
        # still rejects it if the operator declines to replace it.
        if comparison:
            return
        raise ValueError(f"invalid app preference plist: {relative}") from None

    if check:
        if portable != saved:
            raise ValueError(f"machine-local app preferences remain in {relative}; capture a sanitized snapshot")
        return
    if relative != DOCK and portable == saved:
        return
    payload = plistlib.dumps(portable, fmt=plistlib.FMT_BINARY if raw.startswith(b"bplist") else plistlib.FMT_XML,
                             sort_keys=relative == DOCK)
    if snapshot.exists():
        if payload != (raw if source == snapshot else snapshot.read_bytes()):
            replace_bytes(snapshot, payload, snapshot)
    else:
        replace_bytes(snapshot, payload, source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("dock_capture", nargs="?", type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--comparison", action="store_true")
    mode.add_argument("--check", action="store_true", help="verify the app plist policies without editing files")
    args = parser.parse_args()
    try:
        for relative in LOCAL_KEYS:
            process(relative, args.root / relative, comparison=args.comparison, check=args.check)
        if not args.check:
            process(DOCK, args.root / DOCK, capture=args.dock_capture, comparison=args.comparison)
    except (OSError, ValueError) as error:
        raise SystemExit(f"App plist sanitation: {error}")
