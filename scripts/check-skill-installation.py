#!/usr/bin/env python3
"""Check installed skill resources; optionally probe the versioned local engine.

Checks are offline and read-only. Installation flags permit engine or browser
dependency downloads. Never run a skill workflow as an installation check.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys


def check_resources(root):
    errors = []
    lock = json.loads((root / "agents/.skill-lock.json").read_text())
    for name in lock["skills"]:
        if not (root / "agents/skills" / name / "SKILL.md").is_file():
            errors.append(f"{name}: SKILL.md is missing")
    manifest = json.loads((root / "config/skill-install-resources.json").read_text())
    for entry in manifest["resources"]:
        target = root / entry["path"]
        if not target.is_file():
            errors.append(f"{entry['path']}: required external skill resource is missing")
        elif hashlib.sha256(target.read_bytes()).hexdigest() != entry["sha256"]:
            errors.append(f"{entry['path']}: resource checksum differs from its source record")
    for target in (root / "agents/skills").rglob("*"):
        if target.is_symlink() and not target.exists():
            errors.append(f"{target.relative_to(root)}: broken symlink")
    return errors


def check_engine(root, engine_home):
    scripts = root / "agents/skills/impeccable/scripts"
    version = (scripts / "VERSION").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version):
        return ["Impeccable: invalid engine VERSION"]
    os_name = {"Darwin": "darwin", "Linux": "linux", "Windows": "windows"}.get(platform.system())
    arch = {"arm64": "arm64", "aarch64": "arm64", "x86_64": "x64", "AMD64": "x64"}.get(platform.machine())
    if not os_name or not arch:
        return ["Impeccable: unsupported platform for the engine readiness check"]
    name = "impeccable.exe" if os_name == "windows" else "impeccable"
    candidates = [scripts / "bin" / f"{os_name}-{arch}" / name, engine_home / "bin" / version / name]
    if os.environ.get("IMPECCABLE_BIN"):
        candidates.insert(0, Path(os.environ["IMPECCABLE_BIN"]))
    for binary in candidates:
        if not binary.is_file():
            continue
        if not os.access(binary, os.X_OK):
            return [f"Impeccable engine {version}: installed binary is not executable"]
        try:
            result = subprocess.run(
                [str(binary), "engine-probe"], capture_output=True, text=True, timeout=10,
                env=dict(os.environ, IMPECCABLE_LAUNCHER_PROBE="1"),
            )
        except (OSError, subprocess.TimeoutExpired):
            return [f"Impeccable engine {version}: handshake could not run"]
        if result.returncode or result.stdout.strip() != f"impeccable-engine {version}":
            return [f"Impeccable engine {version}: handshake/version mismatch"]
        return []
    return [f"Impeccable engine {version} is missing; run: make skills-engine"]


def install_engine(root, engine_home):
    """Idempotent setup; the vendored launcher owns downloads and checksums."""
    errors = check_engine(root, engine_home)
    if not errors:
        return []
    scripts = root / "agents/skills/impeccable/scripts"
    version = (scripts / "VERSION").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version):
        return errors
    if platform.system() == "Windows":
        return ["On Windows run: dot skill-engine -Apply"]
    env = dict(os.environ, IMPECCABLE_HOME=str(engine_home.resolve()))
    env.pop("IMPECCABLE_LAUNCHER_PROBE", None)
    try:
        result = subprocess.run(
            ["sh", str(scripts / "impeccable"), "engine-probe"],
            env=env, capture_output=True, text=True, timeout=180,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return [f"Impeccable engine setup could not complete: {exc}"]
    if result.returncode or result.stdout.strip() != f"impeccable-engine {version}":
        detail = result.stderr.strip() or result.stdout.strip()
        return [f"Impeccable engine {version} setup failed (exit {result.returncode}): {detail}",
                "Check network access, cache permissions and IMPECCABLE_BIN/PATH overrides; retry: make skills-engine"]
    return check_engine(root, engine_home)


def check_browser_dependency(root):
    dependency = root / "agents/skills/fluid-functionalism/scripts/node_modules/playwright-core/package.json"
    if not dependency.is_file():
        return ["Fluid Functionalism: playwright-core is missing; run: make skills-browser"]
    node = Path.home() / ".local/bin/node-stable"
    if not node.is_file() and platform.system() == "Windows":
        node = Path(shutil.which("node") or str(node))
    if not node.is_file():
        return ["Fluid Functionalism: stable Node is missing; run: make shims"]
    try:
        result = subprocess.run(
            [str(node), "--input-type=module", "-e",
             'import {createRequire} from "node:module"; '
             'import {join} from "node:path"; '
             'const {chromium} = createRequire(join(process.argv[1], "audit.mjs"))("playwright-core"); '
             'if (typeof chromium?.launch !== "function") throw new Error("Chromium launcher unavailable");',
             str(dependency.parents[2])],
            capture_output=True, text=True, timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return [f"Fluid Functionalism: dependency check could not run: {exc}"]
    if result.returncode:
        return ["Fluid Functionalism: playwright-core cannot load its Chromium launcher; run: make skills-browser"]
    return []


def install_browser_dependency(root):
    """Use the stable Node/npm pair and leave vendored source and locks untouched."""
    scripts = root / "agents/skills/fluid-functionalism/scripts"
    node = Path.home() / ".local/bin/node-stable"
    npm = (Path.home() / ".local/bin/npx-stable").resolve().with_name("npm-cli.js")
    if not node.is_file() or not npm.is_file():
        return ["Fluid Functionalism: stable Node/npm are missing; run: make shims"]
    if not (scripts / "package.json").is_file():
        return ["Fluid Functionalism: scripts/package.json is missing; restore the managed skill first"]
    try:
        result = subprocess.run(
            [str(node), str(npm), "install", "--prefix", str(scripts),
             "--ignore-scripts", "--no-package-lock", "--no-audit", "--no-fund"],
            capture_output=True, text=True, timeout=180,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return [f"Fluid Functionalism: dependency installation could not complete: {exc}"]
    if result.returncode:
        return [f"Fluid Functionalism: dependency installation failed (exit {result.returncode}): {result.stderr.strip()}"]
    return check_browser_dependency(root)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--runtime", action="store_true", help="also require a working version-matched Impeccable engine")
    mode.add_argument("--engine-only", action="store_true", help="check only Impeccable's engine, offline")
    mode.add_argument("--install-engine", action="store_true", help="install and verify Impeccable's pinned engine through its launcher")
    mode.add_argument("--browser-only", action="store_true", help="check Fluid Functionalism's browser dependency offline")
    mode.add_argument("--install-browser", action="store_true", help="install Fluid Functionalism's browser dependency without lifecycle scripts")
    parser.add_argument("--engine-home", type=Path, default=Path(os.environ.get("IMPECCABLE_HOME", Path.home() / ".impeccable")))
    args = parser.parse_args()
    try:
        if args.browser_only or args.install_browser:
            errors = (install_browser_dependency if args.install_browser else check_browser_dependency)(args.root)
            for error in errors:
                print(error, file=sys.stderr)
            if not errors:
                print("Fluid Functionalism browser dependency verified")
            return 1 if errors else 0
        if args.engine_only or args.install_engine:
            errors = (install_engine if args.install_engine else check_engine)(args.root, args.engine_home)
            for error in errors:
                print(error, file=sys.stderr)
            if not errors:
                print("Impeccable engine verified")
            return 1 if errors else 0
        errors = check_resources(args.root)
        if args.runtime:
            errors += check_engine(args.root, args.engine_home)
            errors += check_browser_dependency(args.root)
    except (OSError, ValueError, KeyError) as exc:
        print(f"Skill installation check could not complete: {exc}", file=sys.stderr)
        return 1
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        return 1
    print("Skill installation resources verified" + ("; Impeccable engine and Fluid Functionalism dependency ready" if args.runtime else "; runtime checks: make skills-runtime"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
