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


# This exact upstream file remains installed until a corrected release is available.
KNOWN_METADATA_WARNINGS = {
    ("hallmark", "0bc6fa7d573c926e8d3fe04a5afc8191096e5aa7287598a59b6c7e6321b53298"):
        "upstream uses unsupported `default_prompts` and list-shaped `dependencies`; track https://github.com/Nutlope/hallmark/pull/149",
}


# Finder writes this into any folder it displays. It is ignored by Git, so it is
# never part of a source snapshot.
FINDER_METADATA = ".DS_Store"
# Git records no entry for a directory that holds no files.
EMPTY_TREE = hashlib.sha1(b"tree 0\0").hexdigest()


def git_tree_hash(path, modes=None, prefix=""):
    """Return the Git tree object hash for a directory, without touching Git state."""
    modes = modes or {}
    entries = []
    for child in path.iterdir():
        if child.name == FINDER_METADATA and child.is_file() and not child.is_symlink():
            continue
        relative = f"{prefix}/{child.name}" if prefix else child.name
        if child.is_symlink():
            mode = b"120000"
            contents = os.fsencode(os.readlink(child))
            oid = hashlib.sha1(b"blob " + str(len(contents)).encode() + b"\0" + contents).digest()
        elif child.is_dir():
            subtree = git_tree_hash(child, modes, relative)
            if subtree == EMPTY_TREE:
                continue
            mode = b"40000"
            oid = bytes.fromhex(subtree)
        else:
            mode = modes.get(relative)
            if mode is None:
                mode = b"100755" if child.stat().st_mode & 0o111 else b"100644"
            contents = child.read_bytes()
            oid = hashlib.sha1(b"blob " + str(len(contents)).encode() + b"\0" + contents).digest()
        name = os.fsencode(child.name)
        sort_name = name + (b"/" if mode == b"40000" else b"")
        entries.append((sort_name, mode + b" " + name + b"\0" + oid))
    body = b"".join(raw for _, raw in sorted(entries, key=lambda entry: entry[0]))
    return hashlib.sha1(b"tree " + str(len(body)).encode() + b"\0" + body).hexdigest()


def git_index_modes(root, path):
    """Read tracked modes when available so Windows file-mode bits are ignored."""
    try:
        prefix = path.relative_to(root).as_posix()
        result = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-s", "--", prefix],
            capture_output=True, text=True, timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return {}
    if result.returncode:
        return {}
    modes = {}
    for line in result.stdout.splitlines():
        match = re.match(r"^(100644|100755|120000) [0-9a-f]+ [0-3]\t(.+)$", line)
        if match:
            tracked_path = match.group(2).replace("\\", "/")
            relative = tracked_path[len(prefix.rstrip("/")) + 1:]
            modes[relative] = match.group(1).encode()
    return modes


def check_init_rulebook_snapshot(root, lock):
    entry = lock.get("skills", {}).get("init-rulebook")
    if not entry:
        return []
    errors = []
    if not entry.get("skillPath", "").endswith("/SKILL.md"):
        return ["init-rulebook: lock skillPath must identify a SKILL.md"]
    skill_dir = root / "agents/skills/init-rulebook"
    if not (skill_dir / "SKILL.md").is_file():
        return errors + ["init-rulebook: locked source snapshot is missing"]
    expected = entry.get("skillFolderHash", "")
    if not re.fullmatch(r"[0-9a-f]{40}", expected):
        return errors + ["init-rulebook: lock does not contain a valid Git tree hash"]
    modes = git_index_modes(root, skill_dir) if os.name == "nt" else {}
    actual = git_tree_hash(skill_dir, modes)
    if actual != expected:
        errors.append("init-rulebook: vendored tree differs from the locked source snapshot")
    return errors


def metadata_shape_issues(metadata):
    if not isinstance(metadata, dict):
        return ["Codex metadata must be a mapping"]
    errors = []
    for section in ("interface", "dependencies", "policy"):
        if metadata.get(section) is not None and not isinstance(metadata[section], dict):
            errors.append(f"`{section}` must be a mapping/object")
    interface = metadata.get("interface")
    if isinstance(interface, dict):
        if "default_prompts" in interface:
            errors.append("unsupported `interface.default_prompts`; use `interface.default_prompt`")
        for field in ("display_name", "short_description", "default_prompt", "brand_color",
                      "icon_small", "icon_large", "icon_small_url", "icon_large_url"):
            if interface.get(field) is not None and not isinstance(interface[field], str):
                errors.append(f"`interface.{field}` must be a string")
    policy = metadata.get("policy")
    if isinstance(policy, dict) and policy.get("allow_implicit_invocation") is not None:
        if not isinstance(policy["allow_implicit_invocation"], bool):
            errors.append("`policy.allow_implicit_invocation` must be a boolean")
    dependencies = metadata.get("dependencies")
    if isinstance(dependencies, dict) and "tools" in dependencies:
        tools = dependencies["tools"]
        if not isinstance(tools, list):
            errors.append("`dependencies.tools` must be a list of mappings")
        else:
            for index, tool in enumerate(tools):
                field_prefix = f"`dependencies.tools[{index}]`"
                if not isinstance(tool, dict):
                    errors.append(
                        f"{field_prefix} must be a mapping in the dependencies.tools list of mappings"
                    )
                    continue
                for field in ("type", "value"):
                    if not isinstance(tool.get(field), str):
                        errors.append(f"`dependencies.tools[{index}].{field}` must be a string")
                for field in ("command", "description", "transport", "url"):
                    if tool.get(field) is not None and not isinstance(tool[field], str):
                        errors.append(f"`dependencies.tools[{index}].{field}` must be a string")
    return errors


def check_optional_metadata(root, names):
    # Use the same safe, offline parser across bootstrap environments.
    vendor = str(Path(__file__).resolve().parent / "vendor")
    if vendor not in sys.path:
        sys.path.insert(0, vendor)
    from ruamel.yaml import YAML, YAMLError

    errors = []
    warnings = []
    for skill in sorted(names):
        path = root / "agents/skills" / skill / "agents/openai.yaml"
        if not path.is_file():
            continue
        raw = path.read_bytes()
        try:
            metadata = YAML(typ="safe", pure=True).load(raw.decode("utf-8-sig"))
        except (UnicodeError, YAMLError):
            errors.append(f"{path.relative_to(root)}: invalid YAML")
            continue
        issues = metadata_shape_issues(metadata)
        if not issues:
            continue
        known = KNOWN_METADATA_WARNINGS.get((skill, hashlib.sha256(raw).hexdigest()))
        if known:
            warnings.append(f"{path.relative_to(root)}: known pinned metadata issue: {known}")
        else:
            errors.extend(f"{path.relative_to(root)}: {issue}" for issue in issues)
    return errors, warnings


def check_resources(root, warnings=None):
    errors = []
    skills_dir = root / "agents/skills"
    lock = json.loads((root / "agents/.skill-lock.json").read_text())
    for name in lock["skills"]:
        if not (skills_dir / name / "SKILL.md").is_file():
            errors.append(f"{name}: SKILL.md is missing")
    errors.extend(check_init_rulebook_snapshot(root, lock))
    manifest = json.loads((root / "config/skill-install-resources.json").read_text())
    for entry in manifest["resources"]:
        target = root / entry["path"]
        if not target.is_file():
            errors.append(f"{entry['path']}: required external skill resource is missing")
        elif hashlib.sha256(target.read_bytes()).hexdigest() != entry["sha256"]:
            errors.append(f"{entry['path']}: resource checksum differs from its source record")
    claude_cache = skills_dir / "synced"
    for current, directories, files in os.walk(skills_dir):
        directory = Path(current)
        directories[:] = [name for name in directories if directory / name != claude_cache]
        for name in directories + files:
            target = directory / name
            if target != claude_cache and target.is_symlink() and not target.exists():
                errors.append(f"{target.relative_to(root)}: broken symlink")
    metadata_errors, metadata_warnings = check_optional_metadata(root, lock["skills"])
    errors.extend(metadata_errors)
    if warnings is not None:
        warnings.extend(metadata_warnings)
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
        warnings = []
        errors = check_resources(args.root, warnings)
        if args.runtime:
            errors += check_engine(args.root, args.engine_home)
            errors += check_browser_dependency(args.root)
    except (OSError, ValueError, KeyError) as exc:
        print(f"Skill installation check could not complete: {exc}", file=sys.stderr)
        return 1
    for warning in warnings:
        print(f"Warning: {warning}", file=sys.stderr)
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        return 1
    print("Skill installation resources verified" + ("; Impeccable engine and Fluid Functionalism dependency ready" if args.runtime else "; runtime checks: make skills-runtime"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
