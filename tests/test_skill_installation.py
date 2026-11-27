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

    def test_known_hallmark_metadata_warns_without_blocking_skills_check(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            skill = root / "agents/skills/hallmark"
            metadata = skill / "agents/openai.yaml"
            metadata.parent.mkdir(parents=True)
            metadata.write_bytes(b"dependencies: []\n")
            (skill / "SKILL.md").write_text("fixture")
            (root / "agents/.skill-lock.json").write_text(
                '{"skills": {"hallmark": {"skillPath": "skills/hallmark/SKILL.md"}}}'
            )
            (root / "config").mkdir()
            (root / "config/skill-install-resources.json").write_text('{"resources": []}')

            pin = ("hallmark", hashlib.sha256(metadata.read_bytes()).hexdigest())
            with patch.dict(CHECK.KNOWN_METADATA_WARNINGS, {pin: "fixture"}, clear=True):
                warnings = []
                self.assertEqual([], CHECK.check_resources(root, warnings))
                self.assertEqual(len(warnings), 1)
                self.assertIn("known pinned metadata issue", warnings[0])
                metadata.write_text("dependencies: [] # changed upstream\n")
                self.assertTrue(CHECK.check_resources(root))
                metadata.write_text("dependencies: {tools: []}\n")
                self.assertEqual(([], []), CHECK.check_optional_metadata(root, ["hallmark"]))

    def test_new_invalid_codex_metadata_fails_with_actionable_schema_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            skill = root / "agents/skills/example/agents"
            skill.mkdir(parents=True)
            (skill / "openai.yaml").write_text(
                "interface:\n  display_name: Example\n  default_prompts:\n    - prompt\n\ndependencies: []\n"
            )

            errors, warnings = CHECK.check_optional_metadata(root, ["example"])
            self.assertEqual([], warnings)
            self.assertEqual(2, len(errors))
            self.assertTrue(any("default_prompt" in error for error in errors))
            self.assertTrue(any("dependencies` must be a mapping/object" in error for error in errors))

            for document, issue in (
                ("interface: {default_prompt: [one, two]}", "must be a string"),
                ("policy: {allow_implicit_invocation: 'false'}", "must be a boolean"),
                ("dependencies: {tools: [bad]}", "list of mappings"),
                ("dependencies: [", "invalid YAML"),
            ):
                with self.subTest(document=document):
                    (skill / "openai.yaml").write_text(document)
                    errors, warnings = CHECK.check_optional_metadata(root, ["example"])
                    self.assertFalse(warnings)
                    self.assertIn(issue, errors[0])

    def test_codex_metadata_accepts_nested_tools_list_with_yaml_comments_and_indentation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            metadata = root / "agents/skills/example/agents/openai.yaml"
            metadata.parent.mkdir(parents=True)
            metadata.write_text(
                "interface:\n   display_name: Example\n   default_prompt: Make a thing # visible prompt\n"
                "   icon_small_url: https://example.test/small.svg\n"
                "   icon_large_url: https://example.test/large.svg\n"
                "dependencies: # object, not sequence\n   tools:\n   - type: mcp\n"
                "     value: example\n     command: run\n     description: Fixture\n"
                "     transport: stdio\n     url: https://example.test\n"
            )

            self.assertEqual(([], []), CHECK.check_optional_metadata(root, ["example"]))

    def test_codex_metadata_rejects_non_string_tool_fields_and_interface_urls(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            metadata = root / "agents/skills/example/agents/openai.yaml"
            metadata.parent.mkdir(parents=True)
            invalid_documents = (
                ("interface: {display_name: [bad]}", "interface.display_name"),
                ("interface: {short_description: false}", "interface.short_description"),
                ("interface: {default_prompt: [bad]}", "interface.default_prompt"),
                ("interface: {brand_color: false}", "interface.brand_color"),
                ("interface: {icon_small: [bad]}", "interface.icon_small"),
                ("interface: {icon_large: false}", "interface.icon_large"),
                ("interface: {icon_small_url: [bad]}", "interface.icon_small_url"),
                ("interface: {icon_large_url: false}", "interface.icon_large_url"),
                ("dependencies: {tools: [{type: 1, value: example}]}", "tools[0].type"),
                ("dependencies: {tools: [{type: mcp, value: false}]}", "tools[0].value"),
                ("dependencies: {tools: [{type: mcp, value: example, command: [run]}]}", "tools[0].command"),
                ("dependencies: {tools: [{type: mcp, value: example, description: 1}]}", "tools[0].description"),
                ("dependencies: {tools: [{type: mcp, value: example, transport: false}]}", "tools[0].transport"),
                ("dependencies: {tools: [{type: mcp, value: example, url: [bad]}]}", "tools[0].url"),
                ("dependencies: {tools: [{value: example}]}", "tools[0].type"),
                ("dependencies: {tools: [{type: mcp}]}", "tools[0].value"),
            )
            for document, field in invalid_documents:
                with self.subTest(field=field, document=document):
                    metadata.write_text(document)
                    errors, warnings = CHECK.check_optional_metadata(root, ["example"])
                    self.assertEqual([], warnings)
                    self.assertTrue(any(field in error for error in errors), errors)

    def test_init_rulebook_vendored_tree_matches_its_locked_source_hash(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            skill_dir = root / "agents/skills/init-rulebook"
            shutil.copytree(ROOT / "agents/skills/init-rulebook", skill_dir)
            lock = json.loads((ROOT / "agents/.skill-lock.json").read_text())
            (root / "agents").mkdir(exist_ok=True)
            (root / "agents/.skill-lock.json").write_text(json.dumps(lock))

            self.assertEqual([], CHECK.check_init_rulebook_snapshot(root, lock))
            # Browsing the folder in Finder must not look like a local patch.
            for folder in (skill_dir, skill_dir / "references"):
                (folder / ".DS_Store").write_bytes(b"finder view state")
            # Git tracks no directory that holds nothing but that file.
            (skill_dir / "visited").mkdir()
            (skill_dir / "visited/.DS_Store").write_bytes(b"finder view state")
            self.assertEqual([], CHECK.check_init_rulebook_snapshot(root, lock))
            # Only Finder's own file is exempt, not other content under that name.
            (skill_dir / "visited/.DS_Store").unlink()
            (skill_dir / "visited/.DS_Store").mkdir()
            (skill_dir / "visited/.DS_Store/payload").write_text("not Finder metadata\n")
            self.assertTrue(CHECK.check_init_rulebook_snapshot(root, lock))
            shutil.rmtree(skill_dir / "visited")
            (skill_dir / "SKILL.md").write_text((skill_dir / "SKILL.md").read_text() + "\nlocal edit\n")
            errors = CHECK.check_init_rulebook_snapshot(root, lock)
            self.assertTrue(any("vendored tree differs" in error for error in errors))

    @unittest.skipIf(os.name == "nt", "Windows symlink creation may require elevated privileges")
    def test_broken_symlink_check_skips_claude_cache(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            skills = root / "agents/skills"
            cache = skills / "synced/account/skill"
            cache.mkdir(parents=True)
            (cache / "broken").symlink_to("missing")
            (skills / "broken").symlink_to("missing")
            (root / "agents/.skill-lock.json").write_text('{"skills": {}}')
            (root / "config").mkdir()
            (root / "config/skill-install-resources.json").write_text('{"resources": []}')

            self.assertEqual(CHECK.check_resources(root), ["agents/skills/broken: broken symlink"])

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
            helpers = ROOT / "agents/skills/localhost-screenshots/assets/scripts"
            url = "http://localhost:3000"
            cases = {name: [url] for name in ("quick.js", "multi-breakpoint.js", "screenshot-a11y.js")}
            if "assets/scripts/capture.js" in (helpers.parents[1] / "SKILL.md").read_text():
                cases["capture.js"] = ["--base-url", url, "--out", "captures"]
            for name, args in cases.items():
                with self.subTest(name=name):
                    result = subprocess.run(
                        [str(node), str(helpers / name), *args], cwd=project,
                        capture_output=True, text=True, timeout=10,
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("PROJECT_PLAYWRIGHT_LOADED", result.stderr)


if __name__ == "__main__":
    unittest.main()
