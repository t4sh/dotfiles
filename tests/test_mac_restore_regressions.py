"""Focused fixtures for macOS restore and setup-health edge cases."""
import importlib.util
import errno
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
spec = importlib.util.spec_from_file_location("zed_settings", ROOT / "scripts/zed_settings.py")
zed_settings = importlib.util.module_from_spec(spec)
spec.loader.exec_module(zed_settings)
vault_spec = importlib.util.spec_from_file_location("vault_integrity", ROOT / "scripts/vault-integrity.py")
vault = importlib.util.module_from_spec(vault_spec)
vault_spec.loader.exec_module(vault)


class MacRestoreRegressionTests(unittest.TestCase):
    def test_zed_restore_materialization_preserves_live_agent_definitions(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            snapshot = root / "snapshot.json"
            live = root / "live.json"
            snapshot.write_text('/* leading brace { belongs to a comment */\n{\n  // portable profile comment\n  "theme": "saved",\n  "agent_servers": {"codex": {"type": "registry"}}\n}\n')
            local = {
                "agent": {"kind": "fixture-local"},
                "context_servers": {"private-context": {"url": "fixture-only"}},
            }
            live.write_text(json.dumps({"theme": "local-drift", **local}))

            result = zed_settings.preserve_local(snapshot, live)
            output = root / "output.json"
            output.write_text(result)
            parsed = zed_settings.read_settings(output)

            self.assertEqual(parsed["theme"], "saved")
            self.assertEqual(parsed["agent_servers"], {"codex": {"type": "registry"}})
            self.assertEqual(parsed["agent"], local["agent"])
            self.assertEqual(parsed["context_servers"], local["context_servers"])
            self.assertIn("// portable profile comment", output.read_text())

    def test_zed_rejects_machine_local_snapshot_fields_even_on_first_restore(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            snapshot = repo / "apps/zed/settings.json"
            snapshot.parent.mkdir(parents=True)
            (snapshot.parent / "keymap.json").write_text("[]")
            for forbidden, other in (("agent", "context_servers"), ("context_servers", "agent")):
                snapshot.write_text(json.dumps({forbidden: {}}))
                live = repo / "live.json"
                live.write_text(json.dumps({other: {}}))
                for source in (live, None):
                    with self.assertRaisesRegex(ValueError, "machine-local"):
                        zed_settings.preserve_local(snapshot, source)
                result = subprocess.run([sys.executable, ROOT / "scripts/check-zed.py", "--repo",
                                         repo, "--snapshot-only"], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("machine-local", result.stderr + result.stdout)

    @unittest.skipUnless(sys.platform == "darwin", "restore-apps.sh is a macOS workflow")
    def test_zed_preflight_accepts_either_valid_snapshot_alone(self):
        for name, content in (("settings.json", "{}"), ("keymap.json", "[]")):
            with self.subTest(snapshot=name), tempfile.TemporaryDirectory() as temporary:
                repo = Path(temporary)
                (repo / "apps/zed").mkdir(parents=True)
                (repo / "apps/zed" / name).write_text(content)
                result = subprocess.run([sys.executable, ROOT / "scripts/check-zed.py", "--repo",
                                         repo, "--snapshot-only"], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        # Restore skips a snapshot path that is not a regular file; so does the check.
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            (repo / "apps/zed/settings.json").mkdir(parents=True)
            (repo / "apps/zed/keymap.json").write_text("[]")
            result = subprocess.run([sys.executable, ROOT / "scripts/check-zed.py", "--repo",
                                     repo, "--snapshot-only"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        # With neither snapshot there is nothing to restore; say so instead of passing.
        with tempfile.TemporaryDirectory() as temporary:
            (Path(temporary) / "apps/zed").mkdir(parents=True)
            result = subprocess.run([sys.executable, ROOT / "scripts/check-zed.py", "--repo",
                                     temporary, "--snapshot-only"], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("no Zed snapshot found", result.stdout)

    @unittest.skipUnless(sys.platform == "darwin", "restore-apps.sh is a macOS workflow")
    def test_full_restore_rejects_zed_snapshot_before_restoring_anything(self):
        # Restore installs whichever snapshot exists, so each shape is checked first.
        rejected = (
            ({"settings.json": json.dumps({"agent": {}}), "keymap.json": "[]"}, "machine-local"),
            ({"settings.json": json.dumps({"agent": {}})}, "machine-local"),
            ({"keymap.json": "{"}, "Zed check could not complete"),
        )
        for snapshots, reason in rejected:
            with self.subTest(snapshots=sorted(snapshots)):
                self.assert_full_restore_stops_before_restoring(snapshots, reason)

    @unittest.skipUnless(sys.platform == "darwin", "restore-apps.sh is a macOS workflow")
    def test_full_restore_rejects_unmergeable_live_zed_settings_before_restoring_anything(self):
        # The restore merges local sections from the live file, so it is tried first too.
        snapshots = {"settings.json": "{}", "keymap.json": "[]"}
        for live in ('{"agent": ', "[]"):
            for arguments in ((), ("--only", "zed")):
                with self.subTest(live=live, arguments=arguments):
                    self.assert_full_restore_stops_before_restoring(
                        snapshots, "Zed settings cannot be merged", live, arguments)

    def test_empty_or_comment_only_live_zed_settings_hold_nothing_to_keep(self):
        with tempfile.TemporaryDirectory() as temporary:
            snapshot, live = Path(temporary) / "snapshot.json", Path(temporary) / "live.json"
            snapshot.write_text('{\n  "theme": "One Dark"\n}\n')
            for content in ("", "  \n", "// defaults only\n/* nothing set */\n"):
                with self.subTest(content=content):
                    live.write_text(content)
                    self.assertEqual(zed_settings.preserve_local(snapshot, live), snapshot.read_text())
            live.write_bytes(b'{\r// a local comment\r"agent":{"fixture":true}\r}')
            merged = zed_settings.preserve_local(snapshot, live)
            self.assertEqual(zed_settings.parse_jsonc(merged)["agent"], {"fixture": True})
            for content in (b'{"agent": ', b"[]", b"\xff\xfe{\x00}\x00"):
                with self.subTest(content=content):
                    live.write_bytes(content)
                    with self.assertRaisesRegex(ValueError, f"live Zed settings {live}"):
                        zed_settings.preserve_local(snapshot, live)
            # A live settings directory cannot supply local sections.
            live.unlink()
            live.mkdir()
            with self.assertRaisesRegex(ValueError, "not a regular file"):
                zed_settings.preserve_local(snapshot, live)

    @unittest.skipUnless(sys.platform == "darwin", "restore-apps.sh is a macOS workflow")
    def test_editor_restore_rejects_an_empty_homebrew_prefix(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo, home, fakebin = self.zed_restore_fixture(Path(temporary), {})
            (repo / "apps/vscode").mkdir(parents=True)
            (repo / "apps/vscode/settings.json").write_text('{"path": "__HOMEBREW_PREFIX__/bin/example"}\n')
            brew = fakebin / "brew"
            # A successful command with no output would turn the path into /bin/example.
            brew.write_text("#!/bin/sh\nexit 0\n")
            brew.chmod(0o755)
            result = self.invoke_zed_restore(repo, home, fakebin, ())
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Homebrew is required to materialize editor paths", result.stderr)
            self.assertFalse((home / "Library/Application Support/Code/User/settings.json").exists())

    @unittest.skipUnless(sys.platform == "darwin", "restore-apps.sh is a macOS workflow")
    def test_sublime_restore_rejects_an_empty_or_missing_homebrew_prefix(self):
        for empty_output in (True, False):
            with self.subTest(empty_output=empty_output), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                repo, home, fakebin = self.zed_restore_fixture(root, {})
                shutil.copy2(ROOT / "scripts/sync-sublime-settings.sh", repo / "scripts")
                (repo / "scripts/check-sublime.py").write_text("pass\n")
                snapshot = repo / "apps/sublime-text/GutterColor.sublime-settings"
                snapshot.parent.mkdir(parents=True)
                snapshot.write_text('{"path":"__HOMEBREW_PREFIX__/bin/example"}\n')
                live = home / "Library/Application Support/Sublime Text/Packages/User" / snapshot.name
                live.parent.mkdir(parents=True)
                original = b'{"path":"/existing/example"}\n'
                live.write_bytes(original)
                brew = fakebin / "brew"
                brew.write_text("#!/bin/sh\nexit 0\n" if empty_output else
                                '#!/bin/sh\nprintf "%s\\n" "$HOME/missing-prefix"\n')
                brew.chmod(0o755)

                result = self.invoke_zed_restore(repo, home, fakebin, ())

                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("Homebrew is required to materialize Sublime Text paths", result.stderr)
                self.assertEqual(live.read_bytes(), original)

    @unittest.skipUnless(sys.platform == "darwin", "restore-apps.sh is a macOS workflow")
    def test_zed_restore_stops_when_a_snapshot_cannot_be_materialized(self):
        def failing_brew_prefix(home, fakebin):
            brew = fakebin / "brew"
            brew.write_text("#!/bin/sh\nexit 1\n")
            brew.chmod(0o755)

        def directory_at_live_keymap(home, fakebin):
            (home / ".config/zed/keymap.json").mkdir(parents=True)

        cases = (
            # An empty prefix would turn the path into /bin/example.
            ({"settings.json": '{"path": "__HOMEBREW_PREFIX__/bin/example"}'},
             failing_brew_prefix, "Homebrew is required"),
            ({"keymap.json": '["__HOMEBREW_PREFIX__/bin/example"]'},
             failing_brew_prefix, "Homebrew is required"),
            # cp would copy the keymap inside the directory.
            ({"keymap.json": "[]"}, directory_at_live_keymap, "is not a regular file"),
        )
        for snapshots, prepare, reason in cases:
            for arguments in ((), ("--only", "zed")):
                with self.subTest(snapshots=sorted(snapshots), reason=reason, arguments=arguments):
                    self.assert_full_restore_stops_before_restoring(
                        snapshots, reason, arguments=arguments, prepare=prepare)

    def zed_restore_fixture(self, root, snapshots):
        repo, home, fakebin = (root / name for name in ("repo", "home", "bin"))
        (repo / "scripts/lib").mkdir(parents=True)
        (repo / "apps/zed").mkdir(parents=True)
        home.mkdir()
        fakebin.mkdir()
        for name in ("restore-apps.sh", "check-zed.py", "zed_settings.py", "backup_metadata.py",
                     "validate-manifests.sh", "lib/running-app-gate.sh"):
            shutil.copy2(ROOT / "scripts" / name, repo / "scripts" / name)
        (repo / "apps.tsv").write_text("# Zed restore fixture\n")
        for name, content in snapshots.items():
            (repo / "apps/zed" / name).write_text(content)
        for name, body in (("osascript", "echo false"), ("defaults", "exit 99"),
                            ("killall", "exit 99"), ("open", "exit 99")):
            stub = fakebin / name
            stub.write_text(f"#!/bin/sh\n{body}\n")
            stub.chmod(0o755)
        # The public checkout may run on a host with Tower installed, but this
        # isolated restore fixture must never call the real verifier workflow.
        (repo / "scripts/restore-github-signing.sh").write_text("#!/bin/sh\nexit 0\n")
        return repo, home, fakebin

    def invoke_zed_restore(self, repo, home, fakebin, arguments, terminal=False, term_program="Terminal"):
        command = ["bash", repo / "scripts/restore-apps.sh", *arguments]
        if terminal and arguments == ("--only", "zed"):
            command = ["make", "-f", ROOT / "Makefile", "restore-zed"]
        env = dict(os.environ, HOME=str(home), DOTFILES=str(repo), TERM_PROGRAM=term_program, ZED_TERM="",
                   DOTFILES_OPEN_BIN=str(fakebin / "open"),
                   PATH=str(fakebin) + os.pathsep + os.environ["PATH"])
        options = {"cwd": repo, "env": env, "capture_output": True, "text": True, "timeout": 20}
        if not terminal:
            return subprocess.run(command, stdin=subprocess.DEVNULL, **options)
        master, slave = os.openpty()
        try:
            os.write(master, b"n\n\x04")
            return subprocess.run(command, stdin=slave, **options)
        finally:
            os.close(slave)
            os.close(master)

    def assert_full_restore_stops_before_restoring(self, snapshots, reason, live=None, arguments=(),
                                                   prepare=None, terminal=False):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, home, fakebin = self.zed_restore_fixture(root, snapshots)
            if live is not None:
                (home / ".config/zed").mkdir(parents=True)
                (home / ".config/zed/settings.json").write_text(live)
            if prepare is not None:
                prepare(home, fakebin)
            paths = sorted(home.rglob("*"))
            content = {p: p.read_bytes() for p in paths if p.is_file()}
            links = {p: p.readlink() for p in paths if p.is_symlink()}
            # If the preflight regresses, the app gate must not reach real apps.
            gate_reached = root / "gate-reached"
            osascript = fakebin / "osascript"
            osascript.write_text(f'#!/bin/sh\ntouch "{gate_reached}"\necho false\n')
            result = self.invoke_zed_restore(repo, home, fakebin, arguments, terminal)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(reason, result.stderr)
            self.assertNotIn("override", result.stderr.lower())
            self.assertFalse(gate_reached.exists(), "the running-app gate was reached")
            self.assertNotIn("Restoring app preferences", result.stdout)
            self.assertEqual(sorted(home.rglob("*")), paths)
            self.assertEqual({p: p.read_bytes() for p in content}, content)
            self.assertEqual({p: p.readlink() for p in links}, links)

    @unittest.skipUnless(sys.platform == "darwin", "exercises native restore in a terminal")
    def test_zed_restore_refuses_write_protection_before_changing_either_file(self):
        snapshots = {"settings.json": '{"theme":"managed"}\n', "keymap.json": '[{"bindings":{}}]\n'}
        for name in snapshots:
            for protection in ("mode", "ACL"):
                def prepare(home, _):
                    keymap = home / ".config/zed/keymap.json"
                    keymap.write_text("[]\n")
                    path = keymap.with_name(name)
                    if protection == "mode":
                        path.chmod(0o444)
                    else:
                        subprocess.run(["/bin/chmod", "+a", "everyone deny write", path], check=True)

                for arguments in ((), ("--only", "zed")):
                    with self.subTest(name=name, protection=protection, arguments=arguments):
                        self.assert_full_restore_stops_before_restoring(
                            snapshots, "write-protected:", live='{"theme":"saved"}\n',
                            arguments=arguments, prepare=prepare, terminal=True)

    @unittest.skipUnless(sys.platform == "darwin", "exercises native restore in a terminal")
    def test_zed_restore_updates_linked_targets_and_keeps_the_links(self):
        snapshots = {"settings.json": '{"theme":"managed"}\n', "keymap.json": '[{"bindings":{}}]\n'}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, home, fakebin = self.zed_restore_fixture(root, snapshots)
            zed = home / ".config/zed"
            zed.mkdir(parents=True)
            shared = zed / "shared"
            shared.mkdir()
            settings = shared / "settings.json"
            settings.write_text('{"theme":"saved","agent":{"fixture":true}}\n')
            keymap = shared / ("k" * os.pathconf(shared, "PC_NAME_MAX"))
            keymap.write_text("[]\n")
            keymap.chmod(0o640)
            os.chflags(keymap, stat.UF_HIDDEN)
            subprocess.run(["/bin/chmod", "+a", "everyone allow readattr", keymap], check=True)
            acl = subprocess.check_output(["/bin/ls", "-le", keymap], text=True).splitlines()[1:]
            self.assertTrue(acl)
            attribute = "com.example.zed-restore"
            subprocess.run(["/usr/bin/xattr", "-w", attribute, "fixture", keymap], check=True)
            paths = {zed / "settings.json": Path("shared/settings.json"), zed / "keymap.json": keymap}
            for path, target in paths.items():
                path.symlink_to(target)

            result = self.invoke_zed_restore(repo, home, fakebin, ("--only", "zed"), terminal=True)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for path in paths:
                self.assertTrue(path.is_symlink(), f"restore replaced the link at {path.name}")
            self.assertEqual({p: p.readlink() for p in paths}, paths)
            self.assertEqual(zed_settings.read_settings(settings), {"theme": "managed", "agent": {"fixture": True}})
            self.assertEqual(keymap.read_text(), snapshots["keymap.json"])
            self.assertEqual(keymap.stat().st_mode & 0o777, 0o640)
            self.assertTrue(keymap.stat().st_flags & stat.UF_HIDDEN)
            self.assertEqual(subprocess.check_output(["/bin/ls", "-le", keymap], text=True).splitlines()[1:], acl)
            self.assertEqual(subprocess.check_output(
                ["/usr/bin/xattr", "-p", attribute, keymap], text=True).strip(), "fixture")
            self.assertFalse(list(home.rglob(".dotfiles-zed-*")))

    @unittest.skipUnless(sys.platform == "darwin", "exercises native restore in a terminal")
    def test_zed_restore_rechecks_destinations_after_the_app_gate(self):
        snapshots = {"settings.json": '{"theme":"managed"}\n', "keymap.json": '[{"bindings":{}}]\n'}
        with tempfile.TemporaryDirectory() as temporary:
            repo, home, fakebin = self.zed_restore_fixture(Path(temporary), snapshots)
            zed = home / ".config/zed"
            zed.mkdir(parents=True)
            settings, keymap = zed / "settings.json", zed / "keymap.json"
            previous = {settings: '{"theme":"saved"}\n', keymap: "[]\n"}
            for path, text in previous.items():
                path.write_text(text)
            (fakebin / "osascript").write_text(
                '#!/bin/sh\n/bin/chmod 444 "$HOME/.config/zed/keymap.json" || exit 1\necho false\n')

            result = self.invoke_zed_restore(repo, home, fakebin, ("--only", "zed"), terminal=True)

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("write-protected:", result.stderr)
            self.assertEqual({p: p.read_text() for p in previous}, previous)
            self.assertFalse(list(home.rglob(".dotfiles-zed-*")))

    def test_zed_restore_refuses_a_link_to_a_snapshot_in_the_checkout(self):
        snapshot_data = '{"theme":"managed"}\n'
        with tempfile.TemporaryDirectory() as temporary:
            repo, home, fakebin = self.zed_restore_fixture(Path(temporary), {"settings.json": snapshot_data})
            live = home / ".config/zed/settings.json"
            live.parent.mkdir(parents=True)
            snapshot = repo / "apps/zed/settings.json"
            live.symlink_to(snapshot)

            result = self.invoke_zed_restore(repo, home, fakebin, ("--only", "zed"))

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("resolves inside the dotfiles checkout", result.stderr)
            self.assertEqual(live.readlink(), snapshot)
            self.assertEqual(snapshot.read_text(), snapshot_data)

    def test_zed_restore_rejects_a_differently_cased_checkout_alias(self):
        portable = '{"path":"__HOMEBREW_PREFIX__/bin/example"}\n'
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, home, fakebin = self.zed_restore_fixture(root, {"settings.json": portable})
            alias = root / repo.name.upper()
            if not alias.exists() or not alias.samefile(repo):
                self.skipTest("the fixture volume is case-sensitive")
            brew = fakebin / "brew"
            brew.write_text(f'#!/bin/sh\nprintf "%s\\n" "{fakebin}"\n')
            brew.chmod(0o755)
            live = home / ".config/zed/settings.json"
            live.parent.mkdir(parents=True)
            target = alias / "apps/zed/settings.json"
            live.symlink_to(target)

            result = self.invoke_zed_restore(repo, home, fakebin, ("--only", "zed"))

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("resolves inside the dotfiles checkout", result.stderr)
            self.assertEqual(live.readlink(), target)
            self.assertEqual((repo / "apps/zed/settings.json").read_text(), portable)

    def zed_pair(self, root):
        snapshots = {"settings.json": '{"theme":"managed"}\n', "keymap.json": '[{"bindings":{}}]\n'}
        repo, home, fakebin = self.zed_restore_fixture(root, snapshots)
        directory = home / ".config/zed"
        directory.mkdir(parents=True)
        originals = {directory / "settings.json": '{"theme":"saved","agent":{"fixture":true}}\n',
                     directory / "keymap.json": "[]\n"}
        for path, text in originals.items():
            path.write_text(text)
        return repo, home, fakebin, originals

    @unittest.skipUnless(sys.platform == "darwin" and os.geteuid() != 0,
                         "exercises native directory search permissions as a regular user")
    def test_zed_restore_accepts_a_search_only_parent_without_python_o_search(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo, _, _, originals = self.zed_pair(Path(temporary))
            settings, keymap = originals
            parent = settings.parent
            parent.chmod(0o300)
            try:
                with self.assertRaises(PermissionError):
                    os.listdir(parent)
                plan = zed_settings.plan_restore(repo.resolve(), parent)
                with patch.dict(vars(os)):
                    vars(os).pop("O_SEARCH", None)
                    zed_settings.install_restore(plan, repo.resolve())
                self.assertEqual(stat.S_IMODE(parent.stat().st_mode), 0o300)
                self.assertEqual(zed_settings.read_settings(settings),
                                 {"theme": "managed", "agent": {"fixture": True}})
                self.assertEqual(keymap.read_text(), '[{"bindings":{}}]\n')
                self.assertFalse((parent / zed_settings.STAGING).exists())
            finally:
                parent.chmod(0o700)

    @unittest.skipUnless(sys.platform == "darwin", "exercises macOS delete ACLs")
    def test_zed_restore_refuses_a_delete_denied_keymap_before_restoring(self):
        for arguments in ((), ("--only", "zed")):
            with self.subTest(arguments=arguments), tempfile.TemporaryDirectory() as temporary:
                repo, home, fakebin, originals = self.zed_pair(Path(temporary))
                settings, keymap = originals
                subprocess.run(["/bin/chmod", "+a", "everyone deny delete", keymap], check=True)
                try:
                    with keymap.open("r+b"):
                        pass  # Writing is allowed. Replacing the entry is forbidden.
                    gate = fakebin / "osascript"
                    gate.write_text('#!/bin/sh\ntouch "$HOME/gate-reached"\necho false\n')
                    result = self.invoke_zed_restore(repo, home, fakebin, arguments, terminal=True)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(settings.read_text(), originals[settings])
                    self.assertEqual(keymap.read_text(), originals[keymap])
                    self.assertIn("cannot replace", result.stderr)
                    self.assertFalse((home / "gate-reached").exists())
                    self.assertFalse(list(home.rglob(".dotfiles-zed-*")))
                finally:
                    for path in home.rglob("keymap.json"):
                        subprocess.run(["/bin/chmod", "-N", path], check=True)

    def test_full_restore_skips_write_protected_host_zed(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo, home, fakebin, originals = self.zed_pair(Path(temporary))
            settings, _ = originals
            settings.chmod(0o444)
            (fakebin / "osascript").write_text(
                '#!/bin/sh\ncase "$*" in\n*"is running"*) echo true ;;\n*) exit 98 ;;\nesac\n')
            (fakebin / "defaults").write_text(
                '#!/bin/sh\ntest "$1" = import || exit 97\nprintf "fixture imported\\n" > "$HOME/restored-marker"\n')
            (repo / "apps.tsv").write_text("com.example.fixture\tFixture\tapps/fixture/prefs.plist\t-\n")
            snapshot = repo / "apps/fixture/prefs.plist"
            snapshot.parent.mkdir()
            snapshot.write_text("fixture for stubbed defaults\n")

            result = self.invoke_zed_restore(repo, home, fakebin, (), term_program="zed")

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("hosts this restore", result.stdout)
            self.assertTrue((home / "restored-marker").exists())
            self.assertEqual({p: p.read_text() for p in originals}, originals)

    def test_zed_restore_preserves_a_save_at_the_rename_boundary(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo, _, _, originals = self.zed_pair(Path(temporary))
            settings, keymap = originals
            plan = zed_settings.plan_restore(repo.resolve(), settings.parent)
            saved = '[{"bindings":{"fixture":"editor save"}}]\n'
            edited = False
            rename = zed_settings.rename_noreplace

            def save_then_claim(source, destination, parent_fd=None, *, source_fd=None):
                nonlocal edited
                if not edited and source == keymap.name and os.path.samestat(os.fstat(source_fd), keymap.parent.stat()):
                    keymap.write_text(saved)
                    edited = True
                return rename(source, destination, parent_fd, source_fd=source_fd)

            with patch.object(zed_settings, "rename_noreplace", save_then_claim):
                with self.assertRaisesRegex(ValueError, "changed during claim"):
                    zed_settings.install_restore(plan, repo.resolve())
            self.assertTrue(edited)
            self.assertEqual(settings.read_text(), originals[settings])
            self.assertEqual(keymap.read_text(), saved)
            self.assertFalse(list(settings.parent.glob(".dotfiles-zed-*")))

    def test_zed_restore_rolls_back_a_failed_second_install_and_can_retry(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo, _, _, originals = self.zed_pair(Path(temporary))
            settings, keymap = originals
            identities = {path: path.stat().st_ino for path in originals}
            plan = zed_settings.plan_restore(repo.resolve(), settings.parent)
            rename = zed_settings.rename_noreplace
            failed = False

            def fail_keymap_install(source, destination, parent_fd=None, *, source_fd=None):
                nonlocal failed
                if destination == keymap.name and not failed:
                    failed = True
                    self.assertEqual(zed_settings.read_settings(settings)["theme"], "managed")
                    raise OSError(errno.EIO, "fixture keymap installation error")
                return rename(source, destination, parent_fd, source_fd=source_fd)

            with patch.object(zed_settings, "rename_noreplace", fail_keymap_install):
                with self.assertRaisesRegex(OSError, "fixture keymap installation error"):
                    zed_settings.install_restore(plan, repo.resolve())
            self.assertTrue(failed)
            self.assertEqual({path: path.read_text() for path in originals}, originals)
            self.assertEqual({path: path.stat().st_ino for path in originals}, identities)
            self.assertFalse(list(settings.parent.glob(".dotfiles-zed-*")))
            zed_settings.install_restore(zed_settings.plan_restore(repo.resolve(), settings.parent), repo.resolve())
            self.assertEqual(zed_settings.read_settings(settings), {"theme": "managed", "agent": {"fixture": True}})
            self.assertEqual(keymap.read_bytes(), (repo / "apps/zed/keymap.json").read_bytes())

    def test_zed_restore_keeps_a_new_save_at_the_install_boundary(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo, _, _, originals = self.zed_pair(Path(temporary))
            settings, keymap = originals
            plan = zed_settings.plan_restore(repo.resolve(), settings.parent)
            rename = zed_settings.rename_noreplace
            saved = '[{"bindings":{"fixture":"editor save after claim"}}]\n'
            edited = False

            def save_then_install(source, destination, parent_fd=None, *, source_fd=None):
                nonlocal edited
                if not edited and destination == keymap.name:
                    self.assertFalse(keymap.exists())
                    keymap.write_text(saved)
                    edited = True
                return rename(source, destination, parent_fd, source_fd=source_fd)

            with patch.object(zed_settings, "rename_noreplace", save_then_install):
                with self.assertRaisesRegex(ValueError, "changed during install"):
                    zed_settings.install_restore(plan, repo.resolve())
            self.assertTrue(edited)
            self.assertEqual(settings.read_text(), originals[settings])
            self.assertEqual(keymap.read_text(), saved)
            [recovery] = list(settings.parent.glob(".dotfiles-zed-*"))
            self.assertEqual((recovery / "original-keymap.json").read_text(), originals[keymap])
            with self.assertRaisesRegex(ValueError, "recovery data remains"):
                zed_settings.plan_restore(repo.resolve(), settings.parent)

    def test_zed_restore_keeps_a_save_during_rollback(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo, _, _, originals = self.zed_pair(Path(temporary))
            settings, keymap = originals
            plan = zed_settings.plan_restore(repo.resolve(), settings.parent)
            rename = zed_settings.rename_noreplace
            saved = '{"theme":"save-during-rollback","agent":{"fixture":true}}\n'
            failed = False
            edited = False

            def fail_then_save_during_rollback(source, destination, parent_fd=None, *, source_fd=None):
                nonlocal failed, edited
                if not failed and destination == keymap.name:
                    failed = True
                    raise OSError(errno.EIO, "fixture keymap installation error")
                if failed and not edited and source == settings.name:
                    temporary_save = settings.with_suffix(".save")
                    temporary_save.write_text(saved)
                    os.replace(temporary_save, settings)
                    edited = True
                return rename(source, destination, parent_fd, source_fd=source_fd)

            with patch.object(zed_settings, "rename_noreplace", fail_then_save_during_rollback):
                with self.assertRaisesRegex(OSError, "fixture keymap installation error"):
                    zed_settings.install_restore(plan, repo.resolve())
            self.assertTrue(edited)
            self.assertEqual(settings.read_text(), saved)
            self.assertEqual(keymap.read_text(), originals[keymap])
            [recovery] = list(settings.parent.glob(".dotfiles-zed-*"))
            self.assertEqual((recovery / "original-settings.json").read_text(), originals[settings])

    def test_zed_restore_claim_cannot_be_redirected_into_the_checkout(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo, _, _, originals = self.zed_pair(Path(temporary))
            settings, _ = originals
            live_dir = settings.parent
            moved_dir = live_dir.with_name("moved-zed")
            snapshots = {path: path.read_bytes() for path in (repo / "apps/zed").iterdir()}
            plan = zed_settings.plan_restore(repo.resolve(), live_dir)
            rename = zed_settings.rename_noreplace
            moved = False

            def move_then_claim(source, destination, parent_fd=None, *, source_fd=None):
                nonlocal moved
                if not moved and source == settings.name:
                    live_dir.rename(moved_dir)
                    live_dir.symlink_to(repo / "apps/zed", target_is_directory=True)
                    moved = True
                return rename(source, destination, parent_fd, source_fd=source_fd)

            with patch.object(zed_settings, "rename_noreplace", move_then_claim):
                with self.assertRaisesRegex(ValueError, "resolves inside the dotfiles checkout"):
                    zed_settings.install_restore(plan, repo.resolve())
            self.assertTrue(moved)
            self.assertEqual(live_dir.readlink(), repo / "apps/zed")
            self.assertEqual({path: path.read_bytes() for path in snapshots}, snapshots)
            self.assertEqual({path: (moved_dir / path.name).read_text() for path in originals}, originals)
            self.assertFalse(list(moved_dir.glob(".dotfiles-zed-*")))

    def test_zed_without_local_sections_preserves_snapshot_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            snapshot = root / "snapshot.json"
            live = root / "live.json"
            original = '{\n  // keep comment and formatting\n  "theme": "saved",\n}\n'
            snapshot.write_text(original)
            live.write_text('{"theme":"local"}\n')
            output = root / "output.json"
            subprocess.run([sys.executable, str(ROOT / "scripts/zed_settings.py"), "preserve-local",
                            "--snapshot", str(snapshot), "--live", str(live), "--output", str(output)], check=True)
            self.assertEqual(output.read_text(), original)

    def test_zed_restore_materializes_snapshot_before_preserving_live_sections(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo = root / "repo"
            home = root / "home"
            fakebin = root / "bin"
            (repo / "scripts/lib").mkdir(parents=True)
            (repo / "apps/zed").mkdir(parents=True)
            (home / ".config/zed").mkdir(parents=True)
            fakebin.mkdir()
            for relative in ("scripts/restore-apps.sh", "scripts/validate-manifests.sh",
                             "scripts/check-zed.py", "scripts/zed_settings.py", "scripts/backup_metadata.py",
                             "scripts/lib/running-app-gate.sh"):
                shutil.copy2(ROOT / relative, repo / relative)
            (repo / "apps.tsv").write_text("# no plist snapshots\n")
            (repo / "apps/zed/settings.json").write_text(
                '/* leading brace { belongs to a comment */\n{\n  // portable comment\n  "path": "__HOMEBREW_PREFIX__/bin/snapshot",\n'
                '  "agent_servers": {"codex-acp": {"type": "registry"}}\n}\n')
            (repo / "apps/zed/keymap.json").write_text("[]\n")
            local_sections = {
                "agent": {"command": "__HOMEBREW_PREFIX__/bin/local"},
                "context_servers": {"local-context": {"url": "fixture-only"}},
            }
            live = home / ".config/zed/settings.json"
            live.write_text(json.dumps({"path": "local-drift", **local_sections}))
            prefix = fakebin / "brew"
            prefix.write_text("#!/bin/sh\n[ \"$1\" = --prefix ] && printf '/opt/homebrew\\n'\n")
            prefix.chmod(0o755)
            osascript = fakebin / "osascript"
            osascript.write_text("#!/bin/sh\necho false\n")
            osascript.chmod(0o755)

            result = subprocess.run(
                ["bash", str(repo / "scripts/restore-apps.sh"), "--only", "zed"],
                env=dict(os.environ, HOME=str(home), DOTFILES=str(repo), TERM_PROGRAM="Terminal",
                         PATH=str(fakebin) + os.pathsep + os.environ["PATH"]),
                capture_output=True, text=True, timeout=20,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            restored = zed_settings.read_settings(live)
            self.assertEqual(restored["path"], "/opt/homebrew/bin/snapshot")
            self.assertEqual(restored["agent_servers"], {"codex-acp": {"type": "registry"}})
            self.assertEqual(restored["agent"], local_sections["agent"])
            self.assertEqual(restored["context_servers"], local_sections["context_servers"])
            self.assertIn("// portable comment", live.read_text())

            sanitized_root = root / "sanitized"
            snapshot = sanitized_root / "apps/zed/settings.json"
            snapshot.parent.mkdir(parents=True)
            original = (repo / "apps/zed/settings.json").read_bytes()
            shutil.copy2(live, snapshot)
            sanitized = subprocess.run(
                ["bash", str(ROOT / "scripts/sanitize-app-prefs.sh")],
                env=dict(os.environ, HOME=str(home), DOTFILES=str(sanitized_root)),
                capture_output=True, text=True, timeout=20,
            )
            self.assertEqual(sanitized.returncode, 0, sanitized.stdout + sanitized.stderr)
            self.assertEqual(snapshot.read_bytes(), original)

    def test_setup_status_marks_soft_skipped_drift_unknown(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "scripts").mkdir()
            (root / "config").mkdir()
            (root / "scripts/lib").mkdir()
            (root / "macos").mkdir()
            home = root / "home"
            home.mkdir()
            (root / "Brewfile").write_text('cask "browser"\n')
            (root / "config/app-groups.tsv").write_text("Key\tGroup\ncask:browser\tessentials\n")
            for name in ("setup_status.py", "app_groups.py"):
                shutil.copy2(ROOT / "scripts" / name, root / "scripts" / name)
            for name in ("brewfile.sh", "link.sh", "check-services.sh", "check-hooks.sh"):
                script = root / "scripts" / name
                script.write_text("#!/bin/sh\nexit 0\n")
                script.chmod(0o755)
            shutil.copy2(ROOT / "scripts/audit-apps-drift.sh", root / "scripts/audit-apps-drift.sh")
            shutil.copy2(ROOT / "scripts/validate-manifests.sh", root / "scripts/validate-manifests.sh")
            (root / "scripts/lib/plist_drift.py").write_text("pass\n")
            (root / "scripts/gen-skillsfile.py").write_text("pass\n")
            (root / "macos/defaults.sh").write_text("#!/bin/sh\nexit 0\n")
            fakebin = root / "bin"
            fakebin.mkdir()
            brew = fakebin / "brew"
            brew.write_text("#!/bin/sh\nprintf 'browser\\n'\n")
            brew.chmod(0o755)

            result = subprocess.run(
                [sys.executable, "-B", str(root / "scripts/setup_status.py"), "--groups", "essentials"],
                env=dict(os.environ, HOME=str(home), DOTFILES=str(root),
                         APPS_MANIFEST=str(root / "missing-apps.tsv"),
                         PATH=str(fakebin) + os.pathsep + os.environ["PATH"]),
                capture_output=True, text=True, timeout=20,
            )

            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("UNKNOWN  All saved preferences (including deferred apps)", result.stdout)
            self.assertNotIn("PASS     All saved preferences", result.stdout)
            audit_env = dict(os.environ, DOTFILES=str(root),
                             APPS_MANIFEST=str(root / "missing-apps.tsv"))
            ordinary = subprocess.run(["bash", str(root / "scripts/audit-apps-drift.sh"),
                                       "--check", "--strict"], env=audit_env,
                                      capture_output=True, text=True)
            machine = subprocess.run(["bash", str(root / "scripts/audit-apps-drift.sh"),
                                      "--check", "--strict", "--machine-status"], env=audit_env,
                                     capture_output=True, text=True)
            self.assertEqual(ordinary.returncode, 0, ordinary.stdout + ordinary.stderr)
            self.assertEqual(machine.returncode, 3, machine.stdout + machine.stderr)

    def test_mounted_vault_rejects_future_snapshot_timestamp(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "mounted-vault"
            stamp = "20990101-000000"
            payload = source / stamp / "payload/secrets"
            payload.mkdir(parents=True)
            (payload / "fixture.txt").write_text("fixture\n")
            home = root / "home"
            home.mkdir()
            result = subprocess.run(
                ["bash", str(ROOT / "scripts/secrets-health.sh")],
                env=dict(os.environ, HOME=str(home), DOTFILES=str(ROOT),
                         DOTFILES_RESTORE_SOURCE=str(source)),
                capture_output=True, text=True, timeout=20,
            )

            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("vault snapshot timestamp is in the future", result.stderr)

    def test_snapshot_age_shared_boundaries(self):
        now = datetime(2026, 11, 21, 12, 0, 0)
        near_future = (now + timedelta(hours=25)).strftime("%Y%m%d-%H%M%S")
        far_future = (now + timedelta(hours=27)).strftime("%Y%m%d-%H%M%S")
        stale = (now - timedelta(days=31)).strftime("%Y%m%d-%H%M%S")
        self.assertEqual(vault.snapshot_age_days([near_future], 30, now), 0)
        with self.assertRaisesRegex(ValueError, "timestamp is in the future"):
            vault.snapshot_age_days([far_future], 30, now)
        with self.assertRaisesRegex(ValueError, "31 days old"):
            vault.snapshot_age_days([stale], 30, now)


if __name__ == "__main__":
    unittest.main()
