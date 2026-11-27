#!/usr/bin/env python3
"""Inventory Keychain references in env profiles without reading passwords."""

import argparse
import os
from pathlib import Path
import pwd
import re
import subprocess
import sys


PROFILE = re.compile(r"[A-Za-z0-9_.-]+\Z")
KEY = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")
SERVICE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._/-]{0,127}\Z")
ASSIGNMENT = re.compile(r"(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*\Z")
REFERENCE = re.compile(r"(?:'([^']*)'|\"([^\"]*)\"|([^\s#'\"]+))\s*(?:#.*)?\Z")


class InvalidProfile(Exception):
    """An env profile contains an unsafe or ambiguous Keychain reference."""


def references(env_dir):
    """Return validated (profile, key, service) tuples; never execute assignments."""
    if not env_dir.is_dir():
        raise InvalidProfile("profile directory missing or unreadable")
    found = []
    try:
        paths = sorted(env_dir.glob("*.env"))
        for path in paths:
            profile = path.name[:-4]
            if not PROFILE.fullmatch(profile) or path.is_symlink() or not path.is_file():
                raise InvalidProfile("unsafe profile path")
            seen = set()
            for raw in path.read_text(encoding="utf-8").splitlines():
                line = raw.lstrip("\ufeff").strip()
                if not line or line.startswith("#"):
                    continue
                assignment = ASSIGNMENT.fullmatch(line)
                if not assignment:
                    if "keychain://" in line:
                        raise InvalidProfile("malformed Keychain reference")
                    continue
                key, raw_value = assignment.groups()
                if not KEY.fullmatch(key) or key in seen:
                    raise InvalidProfile("unsafe or duplicate variable name")
                seen.add(key)
                if "keychain://" not in raw_value:
                    continue  # Includes intentional literal backup credentials.
                value_match = REFERENCE.fullmatch(raw_value)
                if not value_match:
                    raise InvalidProfile("malformed Keychain reference")
                value = next(part for part in value_match.groups() if part is not None)
                if not value.startswith("keychain://"):
                    raise InvalidProfile("malformed Keychain reference")
                service = value[len("keychain://"):]
                if not SERVICE.fullmatch(service):
                    raise InvalidProfile("unsafe or duplicate Keychain reference")
                found.append((profile, key, service))
    except (OSError, UnicodeError) as exc:
        raise InvalidProfile("profile directory or file unreadable") from exc
    return found


def requirements(path):
    wanted = set()
    try:
        for line in path.read_text().splitlines():
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) != 2 or not PROFILE.fullmatch(fields[0]) or not KEY.fullmatch(fields[1]):
                raise InvalidProfile("invalid requirements")
            pair = tuple(fields)
            if pair in wanted:
                raise InvalidProfile("duplicate requirement")
            wanted.add(pair)
    except (OSError, UnicodeError) as exc:
        raise InvalidProfile("requirements unavailable") from exc
    return wanted


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env-dir", type=Path, default=Path.home() / ".secrets/config/env")
    parser.add_argument("--list", action="store_true", help="list references without querying Keychain")
    parser.add_argument("--requirements", type=Path, default=Path(__file__).resolve().parents[1] / "config/keychain-profiles.tsv", help="required profile/variable TSV")
    args = parser.parse_args(argv)
    try:
        found = references(args.env_dir)
        wanted = requirements(args.requirements)
    except InvalidProfile:
        print("keychain profiles: invalid or unreadable profile (details hidden)", file=sys.stderr)
        return 2
    missing = wanted - {(profile, key) for profile, key, _ in found}
    if missing:
        for profile, key in sorted(missing):
            print("{}: {}: required reference missing; restore profile from vault".format(profile, key))
        if args.list:
            for profile, key, service in found:
                print("{}: {} -> {}".format(profile, key, service))
        return 1
    if not found:
        print("keychain profiles: no references")
        return 0
    if args.list:
        for profile, key, service in found:
            print("{}: {} -> {}".format(profile, key, service))
        return 0

    try:
        account = pwd.getpwuid(os.getuid()).pw_name
    except KeyError:
        print("keychain profiles: current account unavailable", file=sys.stderr)
        return 2
    results = {}
    unavailable = False
    for _, _, service in found:
        if service in results:
            continue
        try:
            result = subprocess.run(
                ["/usr/bin/security", "find-generic-password", "-s", service, "-a", account],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5, check=False,
            )
            results[service] = result.returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            results[service] = False
            unavailable = True
    for profile, key, service in found:
        print("{}: {} -> {}: {}".format(profile, key, service, "present" if results[service] else "missing"))
    if unavailable:
        print("keychain profiles: Keychain query unavailable", file=sys.stderr)
        return 2
    if not all(results.values()):
        print("keychain profiles: one or more items missing", file=sys.stderr)
        return 1
    print("keychain profiles: references present (passwords and API access unverified)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
