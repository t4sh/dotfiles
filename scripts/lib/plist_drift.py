#!/usr/bin/env python3
"""Compare an already-sanitized `defaults export` against a repo pref snapshot.

Invoked by scripts/audit-apps-drift.sh once per apps.tsv row. The caller runs
the live export through scripts/sanitize-app-prefs.sh first, so keys that
sanitization strips before commit never reach this comparison.

    plist_drift.py <live.plist> <repo.plist>

Exit codes:
    0  equivalent after dropping volatile keys
    1  meaningful drift (key-level report on stdout)
    2  unreadable input

Volatile keys are dropped because macOS rewrites them on ordinary use (window
geometry, menu-bar item placement, update-check timestamps, launch counters).
Reporting them would make every snapshot look stale within minutes of a
`make backup` and train the operator to ignore the check. Anything not matched
here is treated as a real setting and reported.
"""

from __future__ import annotations

import json
import plistlib
import re
import sys

# Matched case-insensitively. Keep patterns free of inline (?i) groups: Python
# rejects mid-expression global flags once these are joined with "|".
VOLATILE_KEY_PATTERNS = (
    # AppKit window / toolbar / table geometry and UI restoration state.
    r"^NS(Window|StatusItem|SplitView|Toolbar|TableView|OutlineView|ScrollView|Nav|OSP)",
    r"^NSTreatUnknownArgumentsAsOpen$",
    # Sparkle update-check bookkeeping. SUEnableAutomaticChecks and
    # SUAutomaticallyUpdate are real user settings, so they stay in scope.
    r"^SU(LastCheckTime|LastProfileSubmit|SkippedVersion|HasLaunchedBefore)",
    # Dated one-shot migration flags, e.g. Maccy's "2025-07-04-add-jpeg-heic".
    r"^\d{4}-\d{2}-\d{2}[-_]",
    # Generic per-launch counters, timestamps, and recents.
    r"last(launch|run|used|open|check|seen|update|sync|active|version|connected|unseen|played)",
    r"^LastTerminalStartTime$",
    r"(launch|run|usage|open|session|activation)count",
    r"^recent",
    r"recent(documents|searches|items|files)",
    r"(firstlaunch|hasrun|haslaunched|installdate|installtime)",
    r"(cachedate|cacheversion|updatetimestamp)",
    r"(updatedate|lastupdated)(key)?$",
    r"^mod-count$",
    r"^(parent-)?file-mod-date$",
    r"^parent-mod-date$",
    r"^last-analytics-stamp$",
    r"^trash-full$",
    r"^persistedWindowOrder$",
    # Thaw discovers menu-bar instances dynamically. Identifiers, section
    # ordering, per-display appearance caches, and display IDs are runtime
    # inventory rather than portable preference policy.
    r"^MenuBarItemManager\.",
    r"^MenuBarAppearanceConfigurationV2$",
    r"^KnownDisplays$",
    # Sindresorhus app bookkeeping (review prompt cadence, last launched build).
    r"^SS(App)?_(requestReview|previousLaunchedVersion|firstLaunchDate)",
    # Hardware-derived identity and live display state (BetterDisplay). These are
    # keyed by per-machine display IDs and IOService paths, so restoring them
    # onto different hardware is wrong, not merely stale.
    r"^(displayConfigurationId|storedIdentifiers|resolutionFavorites|settingsPaneId)",
    r"^value@.*(brightness|contrast|volume)",
    # macOS input-source runtime state.
    r"^Apple(InputSourceHistory|SelectedInputSources|SavedCurrentInputSource|InputSourceUpdateTime)$",
)

VOLATILE_KEY_RE = re.compile("|".join(VOLATILE_KEY_PATTERNS), re.IGNORECASE)


def strip_volatile(value):
    """Recursively drop volatile dict keys so nested UI state is ignored too."""
    if isinstance(value, dict):
        return {
            key: strip_volatile(item)
            for key, item in value.items()
            if not VOLATILE_KEY_RE.search(key)
        }
    if isinstance(value, list):
        return [strip_volatile(item) for item in value]
    if isinstance(value, bytes):
        try:
            decoded = json.loads(value.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return value
        # Several Swift apps store Codable settings as plist Data. Compare
        # their JSON meaning, not serialization key order.
        return strip_volatile(decoded)
    return value


def load(path: str):
    with open(path, "rb") as handle:
        return strip_volatile(plistlib.load(handle))


def describe(value) -> str:
    text = repr(value)
    return text if len(text) <= 120 else text[:117] + "..."


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <live.plist> <repo.plist>", file=sys.stderr)
        return 2

    live_path, repo_path = sys.argv[1], sys.argv[2]
    try:
        live = load(live_path)
    except Exception as exc:  # noqa: BLE001 - surface any parse failure verbatim
        print(f"unreadable live export: {exc}", file=sys.stderr)
        return 2
    try:
        repo = load(repo_path)
    except Exception as exc:  # noqa: BLE001
        print(f"unreadable repo snapshot: {exc}", file=sys.stderr)
        return 2

    if not isinstance(live, dict) or not isinstance(repo, dict):
        return 0 if live == repo else 1

    only_live = sorted(set(live) - set(repo))
    only_repo = sorted(set(repo) - set(live))
    changed = sorted(key for key in set(live) & set(repo) if live[key] != repo[key])

    if not (only_live or only_repo or changed):
        return 0

    for key in only_live:
        print(f"      + {key} = {describe(live[key])}   (live only)")
    for key in only_repo:
        print(f"      - {key} = {describe(repo[key])}   (repo only)")
    for key in changed:
        print(f"      ~ {key}: repo {describe(repo[key])} -> live {describe(live[key])}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
