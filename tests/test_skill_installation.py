"""Missing resources and engines must fail instead of a lock-only clean bill."""
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
import subprocess
import shutil
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("installation", ROOT / "scripts/check-skill-installation.py")
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class SkillInstallationTests(unittest.TestCase):
    @unittest.skipIf(os.name == "nt", "Unix installer; Windows has its own setup command")
    def test_engine_install_then_offline_check_and_idempotent_repair(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {}, clear=True):
            root = Path(tmp)
            scripts = root / "agents/skills/impeccable/scripts"
            scripts.mkdir(parents=True)
            (scripts / "VERSION").write_text("1.2.3")
            cache = root / "engine cache"
            launcher = scripts / "impeccable"
            launcher.write_text('''#!/bin/sh
set -eu
[ "$1" = engine-probe ]
[ -z "${IMPECCABLE_LAUNCHER_PROBE:-}" ]
mkdir -p "$IMPECCABLE_HOME/bin/1.2.3"
printf '#!/bin/sh\\necho impeccable-engine 1.2.3\\n' > "$IMPECCABLE_HOME/bin/1.2.3/impeccable"
chmod +x "$IMPECCABLE_HOME/bin/1.2.3/impeccable"
echo impeccable-engine 1.2.3
''')
            self.assertIn("make skills-engine", CHECK.check_engine(root, cache)[0])
            self.assertFalse(cache.exists(), "offline check must not create the cache")
            with patch.dict(os.environ, {"IMPECCABLE_LAUNCHER_PROBE": "1"}):
                self.assertEqual([], CHECK.install_engine(root, cache))
            self.assertEqual([], CHECK.check_engine(root, cache))
            # A ready engine must not invoke the installer again.
            launcher.write_text("exit 91\n")
            self.assertEqual([], CHECK.install_engine(root, cache))
            binary = cache / "bin/1.2.3/impeccable"
            binary.write_text("#!/bin/sh\necho impeccable-engine 1.2.2\n")
            self.assertIn("mismatch", CHECK.check_engine(root, cache)[0])
            self.assertIn("exit 91", CHECK.install_engine(root, cache)[0])

    @unittest.skipIf(os.name == "nt", "Unix installer; Windows has its own setup command")
    def test_engine_installer_does_not_accept_success_without_a_ready_engine(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {}, clear=True):
            root = Path(tmp)
            scripts = root / "agents/skills/impeccable/scripts"
            scripts.mkdir(parents=True)
            (scripts / "VERSION").write_text("1.2.3")
            launcher = scripts / "impeccable"
            launcher.write_text("echo impeccable-engine 1.2.2\n")
            self.assertIn("setup failed", CHECK.install_engine(root, root / "cache")[0])
            launcher.write_text("echo impeccable-engine 1.2.3\n")
            self.assertIn("missing", CHECK.install_engine(root, root / "cache")[0])

    def test_engine_installer_rejects_invalid_version_before_running_launcher(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            scripts = root / "agents/skills/impeccable/scripts"
            scripts.mkdir(parents=True)
            (scripts / "VERSION").write_text("../../unexpected")
            with patch.object(CHECK.subprocess, "run") as run:
                self.assertIn("invalid", CHECK.install_engine(root, root / "cache")[0])
                run.assert_not_called()

    @unittest.skipIf(os.name == "nt", "Unix launcher fixture")
    def test_offline_probe_sets_no_download_guard_and_checks_exit_status(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {}, clear=True):
            root = Path(tmp)
            scripts = root / "agents/skills/impeccable/scripts"
            scripts.mkdir(parents=True)
            (scripts / "VERSION").write_text("1.2.3")
            override = root / "launcher"
            override.write_text('#!/bin/sh\n[ "$IMPECCABLE_LAUNCHER_PROBE" = 1 ] || exit 99\necho impeccable-engine 1.2.3\n')
            override.chmod(0o755)
            with patch.dict(os.environ, {"IMPECCABLE_BIN": str(override)}):
                self.assertEqual([], CHECK.check_engine(root, root / "cache"))
                with override.open("a") as stream:
                    stream.write("exit 23\n")
                self.assertIn("mismatch", CHECK.check_engine(root, root / "cache")[0])
            self.assertFalse((root / "cache").exists())

    def test_required_resource_missing_and_modified(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "agents/skills/example").mkdir(parents=True)
            (root / "agents/skills/example/SKILL.md").write_text("example")
            (root / "agents/.skill-lock.json").write_text(json.dumps({"skills": {"example": {}}}))
            (root / "config").mkdir()
            (root / "config/skill-install-resources.json").write_text(json.dumps({"resources": [{"path": "agents/CONNECTORS.md", "sha256": hashlib.sha256(b"expected").hexdigest()}]}))
            self.assertIn("missing", CHECK.check_resources(root)[0])
            resource = root / "agents/CONNECTORS.md"
            resource.write_text("wrong")
            self.assertIn("checksum", CHECK.check_resources(root)[0])
            resource.write_text("expected")
            self.assertEqual([], CHECK.check_resources(root))

    @unittest.skipIf(os.name == "nt", "shell fixture exercises the Mac/Linux binary cache")
    def test_engine_missing_wrong_version_and_ready(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {}, clear=True):
            root = Path(tmp)
            scripts = root / "agents/skills/impeccable/scripts"
            scripts.mkdir(parents=True)
            (scripts / "VERSION").write_text("1.2.3")
            cache = root / "cache"
            self.assertIn("missing", CHECK.check_engine(root, cache)[0])
            binary = cache / "bin/1.2.3/impeccable"
            binary.parent.mkdir(parents=True)
            binary.write_text("#!/bin/sh\necho impeccable-engine 1.2.2\n")
            binary.chmod(0o755)
            self.assertIn("mismatch", CHECK.check_engine(root, cache)[0])
            binary.write_text("#!/bin/sh\necho impeccable-engine 1.2.3\n")
            self.assertEqual([], CHECK.check_engine(root, cache))

    def test_fluid_dependency_is_not_inferred_from_the_skill_lock(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.assertIn("missing", CHECK.check_browser_dependency(root)[0])
            dependency = root / "agents/skills/fluid-functionalism/scripts/node_modules/playwright-core/package.json"
            dependency.parent.mkdir(parents=True)
            dependency.write_text('{"name":"playwright-core","main":"index.js"}')
            if not (Path.home() / ".local/bin/node-stable").is_file() and not (os.name == "nt" and shutil.which("node")):
                self.assertIn("Node is missing", CHECK.check_browser_dependency(root)[0])
                return
            self.assertIn("cannot load", CHECK.check_browser_dependency(root)[0])
            (dependency.parent / "index.js").write_text('module.exports = { chromium: { launch() {} } };')
            self.assertEqual([], CHECK.check_browser_dependency(root))

    @unittest.skipIf(os.name == "nt", "Mac stable-runtime installer fixture")
    def test_fluid_installer_repairs_dependency_without_lifecycle_scripts_or_lock(self):
        node = Path.home() / ".local/bin/node-stable"
        if not node.is_file():
            self.skipTest("stable Node is unavailable")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            scripts = root / "agents/skills/fluid-functionalism/scripts"
            scripts.mkdir(parents=True)
            (scripts / "package.json").write_text('{"dependencies":{"playwright-core":"^1.55.0"}}')
            home = root / "home"
            shims = home / ".local/bin"
            shims.mkdir(parents=True)
            (shims / "node-stable").symlink_to(node.resolve())
            npm_dir = home / "npm/bin"
            npm_dir.mkdir(parents=True)
            (npm_dir / "npx-cli.js").write_text("")
            (shims / "npx-stable").symlink_to(npm_dir / "npx-cli.js")
            npm = npm_dir / "npm-cli.js"
            npm.write_text('''
const fs = require('node:fs');
const path = require('node:path');
const args = process.argv.slice(2);
for (const flag of ['install', '--ignore-scripts', '--no-package-lock', '--no-audit', '--no-fund']) {
  if (!args.includes(flag)) throw new Error('Missing install safeguard: ' + flag);
}
const scripts = args[args.indexOf('--prefix') + 1];
const target = path.join(scripts, 'node_modules/playwright-core');
fs.mkdirSync(target, {recursive: true});
fs.writeFileSync(path.join(target, 'package.json'), '{"main":"index.js"}');
fs.writeFileSync(path.join(target, 'index.js'), 'exports.chromium = { launch() {} };');
''')
            with patch.object(CHECK.Path, "home", return_value=home):
                self.assertIn("missing", CHECK.check_browser_dependency(root)[0])
                self.assertEqual([], CHECK.install_browser_dependency(root))
                self.assertEqual([], CHECK.check_browser_dependency(root))
                self.assertFalse((scripts / "package-lock.json").exists())
                (scripts / "node_modules/playwright-core/index.js").write_text("throw new Error('broken installation')")
                self.assertIn("cannot load", CHECK.check_browser_dependency(root)[0])
                self.assertEqual([], CHECK.install_browser_dependency(root))
                npm.write_text("process.stderr.write('INSTALL_FAILED'); process.exit(19)")
                self.assertIn("exit 19", CHECK.install_browser_dependency(root)[0])

    def test_screenshot_helpers_resolve_the_projects_playwright(self):
        node = Path.home() / ".local/bin/node-stable"
        if not node.exists():
            found = shutil.which("node")
            if not found:
                self.skipTest("Node is unavailable")
            node = Path(found)
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            package = project / "node_modules/playwright"
            package.mkdir(parents=True)
            # A sentinel proves the project module was reached, without a browser.
            (package / "index.js").write_text("exports.chromium = { launch() { throw new Error('PROJECT_PLAYWRIGHT_LOADED'); } };\n")
            for helper in (ROOT / "agents/skills/localhost-screenshots/assets/scripts").glob("*.js"):
                result = subprocess.run([str(node), str(helper)], cwd=project, capture_output=True, text=True, timeout=10)
                self.assertIn("PROJECT_PLAYWRIGHT_LOADED", result.stderr, helper.name)
                self.assertNotIn("Missing dependency", result.stderr, helper.name)


if __name__ == "__main__":
    unittest.main()
