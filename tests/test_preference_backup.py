import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import backup_metadata
sys.path.remove(str(ROOT / 'scripts'))


class PreferenceBackupTests(unittest.TestCase):
    def record_directories(self, base, repo, target):
        subprocess.run([
            sys.executable, ROOT / "scripts/publish-app-backup.py", "record-directories",
            "--base", base, "--destination", repo, "--target", target,
        ], check=True, capture_output=True)

    def review(self, stage, previous, answers, *options):
        if not hasattr(os, 'openpty'):
            self.skipTest('terminal review needs a pseudo-terminal')
        master, slave = os.openpty()
        try:
            os.write(master, answers.encode() + b'\x04')
            return subprocess.run(
                [sys.executable, str(ROOT / 'scripts/stabilize-plist-backups.py'),
                 str(stage), str(previous), '--review-macos', *options], stdin=slave,
                capture_output=True, text=True, timeout=10)
        finally:
            os.close(master)
            os.close(slave)

    @unittest.skipUnless(sys.platform == "darwin", "uses the Mac backup and zsh terminal")
    def test_dotbackup_reviews_and_commits_only_selected_public_snapshots(self):
        dock = Path("macos/dock-backup.plist")
        layout = Path("macos/dock-layout.plist")
        terminal = Path("apps/terminal/terminal.plist")
        saved_tiles = [
            {"tile-data": {"file-data": {"_CFURLString": f"file:///Applications/{app}.app/"}}}
            for app in ("Terminal", "Safari")
        ]
        moved_tiles = saved_tiles[::-1]
        dock_policy = {f"{key}-immutable": True for key in ("size", "position", "contents", "autohide")}
        dock_policy.update({"autohide": False, "recent-apps": []})
        prior_terminal = plistlib.dumps({"profile": "saved"}, fmt=plistlib.FMT_BINARY)

        for keep_dock in (True, False):
            with self.subTest(keep_dock=keep_dock), tempfile.TemporaryDirectory() as temporary:
                fixture = Path(temporary)
                home, bin_dir, exports = (fixture / name for name in ("home", "bin", "exports"))
                repo = home / ".dotfiles"
                for directory in (repo / terminal.parent, repo / "macos", repo / "services",
                                  repo / "agents/skills", bin_dir, exports):
                    directory.mkdir(parents=True, exist_ok=True)
                shutil.copytree(ROOT / "scripts", repo / "scripts")
                for name in ("Makefile", ".node-version", ".gitignore", ".gitleaks.toml"):
                    shutil.copy2(ROOT / name, repo / name)

                def put(path, content):
                    (repo / path).write_bytes(content)

                put("apps.tsv", b"# Review fixture\n")
                put("Brewfile", b'brew "fixture"\n')
                put("Skillsfile", b"# Fixture\n")
                put("THIRD_PARTY_NOTICES.md", b"# Fixture\n")
                put("agents/.skill-lock.json", b"{}\n")
                put("agents/skills/README.md", b"# Fixture\n")
                put("services/README.md", b"# Fixture\n")
                put(dock, plistlib.dumps({"persistent-apps": saved_tiles, **dock_policy}))
                put(layout, plistlib.dumps({"persistent-apps": saved_tiles}))
                put(terminal, prior_terminal)
                put("unrelated.txt", b"saved\n")

                # Replace external reads and vault operations in the disposable
                # checkout. Keep the real review, sanitation and publisher.
                put("macos/defaults.sh", b'#!/bin/sh\ntest "$1" = --check\n')
                put("scripts/touch-id-sudo.sh", b'#!/bin/sh\ntest "$1" = --check\n')
                put("scripts/audit-brewfile.sh", b"#!/bin/sh\nexit 0\n")
                put("scripts/gen-skillsfile.py", b"pass\n")
                put("scripts/backup-text-replacements.py", b"pass\n")
                put("scripts/brewfile.sh", b'#!/bin/sh\ntest "$1" = dump && cp "$DOTFILES/Brewfile" "$2"\n')
                (exports / "com.apple.dock").write_bytes(plistlib.dumps({
                    "persistent-apps": moved_tiles,
                    "recent-apps": [{"fixture": "private Dock history"}],
                }))
                (exports / "com.apple.Terminal").write_bytes(plistlib.dumps({
                    "profile": "current", "SecureKeyboardEntry": True,
                }))
                defaults = bin_dir / "defaults"
                defaults.write_text(
                    '#!/bin/sh\n[ "$1" = export ] || exit 1\n'
                    'exec /bin/cp "$FIXTURE_EXPORTS/$2" "$3"\n'
                )
                defaults.chmod(0o755)
                scanner = bin_dir / "gitleaks"
                scanner.write_text("#!/bin/sh\nexit 0\n")
                scanner.chmod(0o755)

                env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
                for key in ("DOTFILES_REVIEW_MAC_PREFERENCES", "DOTFILES_BACKUP_LOCK_HELD",
                            "DOTFILES_BACKUP_UMASK", "OVERRIDE", "MAKEFLAGS", "MFLAGS", "MAKEOVERRIDES"):
                    env.pop(key, None)
                env.update(HOME=str(home), ZDOTDIR=str(home), DOTFILES=str(repo),
                           PATH=f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                           FIXTURE_EXPORTS=str(exports), PYTHONDONTWRITEBYTECODE="1",
                           GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1",
                           GIT_AUTHOR_NAME="Backup Fixture", GIT_COMMITTER_NAME="Backup Fixture",
                           GIT_AUTHOR_EMAIL="fixture@example.test", GIT_COMMITTER_EMAIL="fixture@example.test")

                def git(*args):
                    return subprocess.check_output(["git", *args], cwd=repo, env=env, text=True)

                git("init", "-q")
                git("add", ".")
                git("commit", "-qm", "seed public backup fixture")
                # Model the missed-prompt case: the working Dock already has
                # the live order, with the previous order in the index.
                working_policy = {**dock_policy, "tilesize": 48}
                put(dock, plistlib.dumps({"persistent-apps": moved_tiles, **working_policy}))
                for path in (dock, layout, terminal):
                    (repo / path).chmod(0o444)
                put("unrelated.txt", b"already staged\n")
                git("add", "unrelated.txt")

                master, slave = os.openpty()
                try:
                    os.write(master, (b"Y\nn\n" if keep_dock else b"n\nY\n") + b"Y\n\x04")
                    # Stub the line editor only. The confirmation and commit
                    # still run through the real alias with a terminal.
                    result = subprocess.run(
                        ["zsh", "-f", "-c",
                         'source "$1"; vared() { msg="review public backup"; }; eval dotbackup',
                         "fixture", ROOT / "zsh/lib/42-aliases-git.zsh"],
                        cwd=repo, env=env, stdin=slave, capture_output=True, text=True, timeout=60,
                    )
                finally:
                    os.close(slave)
                    os.close(master)

                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 0, output)
                self.assertEqual(output.count("Keep current? [Y/n]"), 2, output)
                self.assertIn("Saved shows the Git index order", output)
                self.assertIn("Stage only these managed backup paths and commit?", output)
                self.assertNotIn("SecureKeyboardEntry", output)
                tiles = moved_tiles if keep_dock else saved_tiles
                self.assertEqual(plistlib.loads((repo / dock).read_bytes()),
                                 {"persistent-apps": tiles, **working_policy})
                self.assertEqual(plistlib.loads((repo / layout).read_bytes()), {"persistent-apps": tiles})
                if keep_dock:
                    self.assertEqual((repo / terminal).read_bytes(), prior_terminal)
                else:
                    self.assertEqual(plistlib.loads((repo / terminal).read_bytes()), {"profile": "current"})
                for path in (dock, layout, terminal):
                    self.assertEqual((repo / path).stat().st_mode & 0o777, 0o444, path)
                committed = git("diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD").splitlines()
                self.assertEqual(committed, [str(dock), str(layout)] if keep_dock else [str(terminal), str(dock)])
                self.assertEqual(git("diff", "--cached", "--name-only").splitlines(), ["unrelated.txt"])
                self.assertEqual(git("show", "HEAD:unrelated.txt"), "saved\n")

    def test_public_dock_capture_replays_allowlisted_tiles_and_drops_live_payloads(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "macos").mkdir()
            (root / "apps").mkdir()
            (root / ".node-version").write_text("v22.23.1\n")
            allowed = {
                "tile-data": {"file-data": {
                    "_CFURLString": "file:///System/Applications/Utilities/Terminal.app/",
                    "_CFURLStringType": 0,
                }},
            }
            (root / "macos/dock-layout.plist").write_bytes(
                plistlib.dumps({"persistent-apps": [allowed, {"tile-type": "spacer-tile"}]})
            )
            saved = root / "macos/dock-backup.plist"
            saved.write_bytes(plistlib.dumps({
                "persistent-apps": [allowed], "autohide": False, "tilesize": 48,
            }))
            saved.chmod(0o444)

            live_allowed = {
                "tile-type": "file-tile",
                "tile-data": {
                    "file-data": {
                        "_CFURLString": "file:///private/var/folders/fixture/Terminal.app/",
                        "_CFURLStringType": 0,
                    },
                    "display-label": "private label",
                    "book": b"private bookmark bytes",
                },
                "GUID": 987654,
            }
            unknown = {
                "tile-type": "file-tile",
                "tile-data": {"file-data": {
                    "_CFURLString": "file:///Applications/Unapproved.app/",
                    "_CFURLStringType": 0,
                }},
            }
            capture = root / "capture.plist"
            capture.write_bytes(plistlib.dumps({
                "persistent-apps": [live_allowed, unknown, {"tile-type": "spacer-tile", "GUID": 42}],
                "persistent-others": [{"private": "folder tile"}],
                "recent-apps": [{"private": "recent item"}],
                "unreviewed-private-key": "personal capture",
            }))
            env = {**os.environ, "DOTFILES": str(root), "HOME": str(root / "home")}
            result = subprocess.run(
                ["bash", str(ROOT / "scripts/sanitize-app-prefs.sh"), str(capture)],
                env=env, capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            snapshot = plistlib.loads(saved.read_bytes())
            self.assertEqual(snapshot["persistent-apps"], [allowed, {"tile-type": "spacer-tile"}])
            self.assertNotIn("persistent-others", snapshot)
            self.assertEqual(snapshot["autohide"], False)
            self.assertEqual(snapshot["tilesize"], 48)
            self.assertEqual(snapshot["recent-apps"], [])
            self.assertNotIn("unreviewed-private-key", snapshot)
            self.assertEqual(saved.stat().st_mode & 0o777, 0o444)

    @unittest.skipUnless(sys.platform == "darwin", "uses native Mac capture and a terminal")
    def test_review_replays_an_already_captured_dock_move(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            stage, previous = root / "stage", root / "previous"
            dock = Path("macos/dock-backup.plist")
            tiles = [{"tile-type": "file-tile", "tile-data": {"file-data": {
                "_CFURLString": f"file:///Applications/{name}.app/"}}} for name in ("Terminal", "Tower")]
            indexed = root / "index.plist"
            indexed.write_bytes(plistlib.dumps({"persistent-apps": tiles, "tilesize": 32}))
            captured = {"persistent-apps": tiles[::-1], "tilesize": 48}
            for tree in (stage, previous):
                (tree / "macos").mkdir(parents=True)
                (tree / dock).write_bytes(plistlib.dumps(captured))
            layout = stage / "macos/dock-layout.plist"
            layout.write_bytes(plistlib.dumps({"persistent-apps": tiles}))
            layout.chmod(0o444)
            for answer, expected in (("y\n", tiles[::-1]), ("n\n", tiles)):
                result = self.review(stage, previous, answer, "--indexed-dock", str(indexed))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.count("Keep current?"), 1)
                self.assertIn("Terminal → Tower", result.stdout)
                self.assertEqual(plistlib.loads((stage / dock).read_bytes()),
                                 {"persistent-apps": expected, "tilesize": 48})

                fallback = plistlib.loads(layout.read_bytes())
                self.assertEqual(layout.stat().st_mode & 0o777, 0o444)
                self.assertEqual(fallback["persistent-apps"], expected)
                self.assertEqual(set(fallback), {"persistent-apps"})

    def test_fallback_rebuilds_reviewed_tiles_without_full_snapshot(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "macos").mkdir()
            tiles = [{"tile-type": "file-tile", "tile-data": {"file-data": {
                "_CFURLString": "file://__HOME__/My App.app/"}}}, {"tile-type": "spacer-tile"}]
            (root / "macos/dock-layout.plist").write_bytes(plistlib.dumps({"persistent-apps": tiles}))
            calls = root / "calls"
            defaults = root / "defaults"
            defaults.write_text("#!/usr/bin/env python3\nimport json, os, sys\n"
                                "with open(os.environ['CALLS'], 'a') as f: print(json.dumps(sys.argv[1:]), file=f)\n")
            defaults.chmod(0o755)
            killall = root / "killall"
            killall.write_text('#!/bin/sh\ntest "$1" = Dock\n')
            killall.chmod(0o755)
            env = {**os.environ, "HOME": str(root), "DOTFILES": str(root),
                   "CALLS": str(calls), "PATH": str(root) + ":" + os.environ["PATH"]}
            subprocess.run(["bash", ROOT / "macos/dock-dev.sh"], check=True, env=env, capture_output=True)
            write, clear = map(json.loads, calls.read_text().splitlines())
            self.assertEqual(write[:4], ["write", "com.apple.dock", "persistent-apps", "-array"])
            tiles[0]["tile-data"]["file-data"]["_CFURLString"] = "file://" + quote(str(root) + "/My App.app/")
            self.assertEqual([plistlib.loads(arg.encode()) for arg in write[4:]], tiles)
            self.assertEqual(clear, ["write", "com.apple.dock", "persistent-others", "-array"])

    def test_macos_review_declines_changed_app_file_without_showing_contents(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            stage, previous = root / "stage", root / "previous"
            (stage / "apps/editor").mkdir(parents=True)
            (previous / "apps/editor").mkdir(parents=True)
            saved = previous / "apps/editor/settings.json"
            candidate = stage / "apps/editor/settings.json"
            saved.write_text('{"fontSize": 14}\n')
            candidate.write_text('{"fontSize": 18, "private": "do not print"}\n')

            saved.chmod(0o600)
            candidate.chmod(0o644)
            result = self.review(stage, previous, "n\n")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(candidate.stat().st_mode & 0o777, 0o600)
            self.assertIn("apps/editor/settings.json", result.stdout)
            self.assertNotIn("do not print", result.stdout)
            self.assertEqual(candidate.read_bytes(), saved.read_bytes())

    def test_type_changes_get_their_own_review_and_keep_selected_types(self):
        with tempfile.TemporaryDirectory() as td:
            stage, previous = Path(td) / "stage", Path(td) / "previous"
            for tree in (stage, previous):
                (tree / "macos").mkdir(parents=True)
            saved, current = (tree / "macos/trackpad.plist" for tree in (previous, stage))
            saved.write_bytes(plistlib.dumps({"array": [True], "flag": True, "nested": {"v": 1}}))
            current.write_bytes(plistlib.dumps({"array": [1], "flag": 1, "nested": {"v": 1.0}}))
            drift = subprocess.run([sys.executable, ROOT / "scripts/lib/plist_drift.py", current, saved],
                                   capture_output=True, text=True)
            self.assertEqual(drift.returncode, 1)
            result = self.review(stage, previous, "n\ny\ny\n")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.count("Keep current?"), 3)
            selected = plistlib.loads(current.read_bytes())
            self.assertIs(type(selected["array"][0]), bool)
            self.assertIs(type(selected["flag"]), int)
            self.assertIs(type(selected["nested"]["v"]), float)

    def test_app_plist_data_converted_to_native_value_is_reviewed(self):
        with tempfile.TemporaryDirectory() as td:
            stage, previous = Path(td) / "stage", Path(td) / "previous"
            path = Path("apps/example/settings.plist")
            for tree, setting in ((previous, b'{"enabled":true}'), (stage, {"enabled": True})):
                (tree / path).parent.mkdir(parents=True)
                (tree / path).write_bytes(plistlib.dumps({"setting": setting}))
            result = self.review(stage, previous, "y\n")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Keep current?", result.stdout)
            self.assertIsInstance(plistlib.loads((stage / path).read_bytes())["setting"], dict)

    def test_system_setting_answer_preserves_published_metadata(self):
        for answer, expected in (("n", False), ("y", True)):
            with self.subTest(answer=answer), tempfile.TemporaryDirectory() as td:
                root = Path(td)
                stage, previous, base, repo = (root / k for k in ("stage", "previous", "base", "repo"))
                relative = Path("macos/trackpad.plist")
                for tree in (stage, previous, base, repo):
                    path = tree / relative
                    path.parent.mkdir(parents=True)
                    path.write_bytes(plistlib.dumps({"TrackpadRightClick": tree == stage}))
                    path.chmod(0o600 if tree in (base, repo) else 0o644)
                    if sys.platform == "darwin" and tree in (base, repo):
                        subprocess.run(["xattr", "-w", "com.example.saved", "fixture", path], check=True)
                self.record_directories(base, repo, "macos")
                result = self.review(stage, previous, answer + "\n", "--base", str(base))
                self.assertEqual(result.returncode, 0, result.stderr)
                recovery = root / "recovery"
                recovery.mkdir()
                subprocess.run([sys.executable, ROOT / "scripts/publish-app-backup.py", "publish",
                                "--candidate", stage, "--base", base, "--destination", repo,
                                "--rollback", recovery, "--target", "macos"], check=True, capture_output=True)
                published = repo / relative
                self.assertEqual(plistlib.loads(published.read_bytes())["TrackpadRightClick"], expected)
                self.assertEqual(published.stat().st_mode & 0o777, 0o600)
                if sys.platform == "darwin":
                    self.assertEqual(subprocess.check_output(["xattr", "-p", "com.example.saved", published],
                                                             text=True).strip(), "fixture")
                self.assertEqual((recovery / "journal.jsonl").exists(), expected)

    def test_declining_metadata_only_change_preserves_saved_mode_at_publication(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            stage, previous, base, repo = (root / name for name in ("stage", "previous", "base", "repo"))
            relative = Path("apps/editor/settings.json")
            for tree, mode in ((stage, 0o644), (previous, 0o644), (base, 0o600), (repo, 0o600)):
                path = tree / relative
                path.parent.mkdir(parents=True)
                path.write_text("{}")
                path.chmod(mode)
            result = self.review(stage, previous, "n\n", "--base", str(base))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("changed mode", result.stdout)
            recovery = root / "recovery"
            recovery.mkdir()
            self.record_directories(base, repo, "apps")
            subprocess.run([sys.executable, ROOT / "scripts/publish-app-backup.py", "publish",
                            "--candidate", stage, "--base", base, "--destination", repo,
                            "--rollback", recovery, "--target", "apps"], check=True, capture_output=True)
            self.assertEqual((repo / relative).stat().st_mode & 0o777, 0o600)
            self.assertFalse((recovery / "journal.jsonl").exists())

    @unittest.skipUnless(sys.platform == "darwin", "quarantine records are a macOS attribute")
    def test_app_assigned_attributes_alone_are_not_reviewed(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            stage, previous, base = (root / name for name in ("stage", "previous", "base"))
            relative = Path("apps/editor/settings.json")
            for tree in (stage, previous, base):
                path = tree / relative
                path.parent.mkdir(parents=True)
                path.write_text("{}")
            subprocess.run(["xattr", "-w", "com.apple.quarantine", "0081;00000000;Fixture;",
                            base / relative], check=True)
            # End of input would abort the review if any prompt were shown.
            result = self.review(stage, previous, "", "--base", str(base))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn("Keep current?", result.stdout)
            # The saved stamp is kept, so publication sees no change either.
            stamps = [subprocess.check_output(["xattr", "-p", "com.apple.quarantine", tree / relative])
                      for tree in (stage, base)]
            self.assertEqual(stamps[0], stamps[1])

            # A read-only capture is left exactly as it is rather than half restamped.
            subprocess.run(["xattr", "-d", "com.apple.quarantine", stage / relative], check=True)
            (stage / relative).chmod(0o444)
            (base / relative).chmod(0o444)
            (previous / relative).chmod(0o444)
            result = self.review(stage, previous, "", "--base", str(base))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn("Keep current?", result.stdout)
            unstamped = subprocess.run(["xattr", "-p", "com.apple.quarantine", stage / relative],
                                       capture_output=True)
            self.assertNotEqual(unstamped.returncode, 0, unstamped.stdout)

    def test_macos_review_handles_first_system_capture_and_eof_without_traceback(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            stage, previous = root / "stage", root / "previous"
            (stage / "macos").mkdir(parents=True)
            (previous / "macos").mkdir(parents=True)
            candidate = stage / "macos/symbolichotkeys.plist"
            candidate.write_bytes(plistlib.dumps({
                "AppleSymbolicHotKeys": {
                    "10": {"enabled": True, "value": {"parameters": [1, 2]}},
                },
            }))

            rejected = self.review(stage, previous, "n\ny\ny\n")
            self.assertEqual(rejected.returncode, 0, rejected.stderr)
            self.assertIn("AppleSymbolicHotKeys.10.enabled", rejected.stdout)
            self.assertNotIn("enabled", plistlib.loads(candidate.read_bytes())["AppleSymbolicHotKeys"]["10"])

            candidate.write_bytes(plistlib.dumps({"new": True}))
            incomplete = self.review(stage, previous, "")
            self.assertNotEqual(incomplete.returncode, 0)
            self.assertNotIn("Traceback", incomplete.stderr)

    def test_macos_review_mixes_nested_setting_choices(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            stage, previous = root / "stage", root / "previous"
            (stage / "macos").mkdir(parents=True)
            (previous / "macos").mkdir(parents=True)
            relative = "macos/symbolichotkeys.plist"
            saved = {"AppleSymbolicHotKeys": {"10": {
                "enabled": False, "value": {"parameters": [1, 2]},
            }}}
            current = {"AppleSymbolicHotKeys": {"10": {
                "enabled": True, "value": {"parameters": [3, 4]},
            }}}
            (previous / relative).write_bytes(plistlib.dumps(saved, fmt=plistlib.FMT_BINARY))
            (stage / relative).write_bytes(plistlib.dumps(current, fmt=plistlib.FMT_BINARY))

            result = self.review(stage, previous, "n\ny\n")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("AppleSymbolicHotKeys.10.enabled", result.stdout)
            self.assertIn("AppleSymbolicHotKeys.10.value.parameters", result.stdout)
            reviewed = plistlib.loads((stage / relative).read_bytes())
            self.assertFalse(reviewed["AppleSymbolicHotKeys"]["10"]["enabled"])
            self.assertEqual(reviewed["AppleSymbolicHotKeys"]["10"]["value"]["parameters"], [3, 4])

    def test_macos_review_declines_every_setting_in_first_capture(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            stage, previous = root / "stage", root / "previous"
            (stage / "macos").mkdir(parents=True)
            (previous / "macos").mkdir(parents=True)
            candidate = stage / "macos/dock-backup.plist"
            candidate.write_bytes(plistlib.dumps({"show-recents": True}))

            result = self.review(stage, previous, "n\n")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(candidate.exists())

    def test_plist_capture_preserves_bytes_for_housekeeping_and_key_order(self):
        with tempfile.TemporaryDirectory() as td:
            previous, stage = Path(td) / 'previous', Path(td) / 'stage'
            relative = 'macos/services.plist'
            saved, candidate = previous / relative, stage / relative
            saved.parent.mkdir(parents=True)
            candidate.parent.mkdir(parents=True)
            original = {'Services': {'enabled': True, 'order': ['a', 'b']},
                        'SULastCheckTime': 1, 'JSON': b'{"a":1,"b":2}'}
            saved.write_bytes(plistlib.dumps(original, fmt=plistlib.FMT_BINARY, sort_keys=False))
            command = ['python3', str(ROOT / 'scripts/stabilize-plist-backups.py'),
                       str(stage), str(previous)]
            for fmt in (plistlib.FMT_XML, plistlib.FMT_BINARY):
                changed = {'JSON': b'{"b":2,"a":1}', 'SULastCheckTime': 2,
                           'Services': original['Services'], 'GTUserDefaultsStartupCount': 3}
                candidate.write_bytes(plistlib.dumps(changed, fmt=fmt, sort_keys=False))
                result = subprocess.run(command, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(candidate.read_bytes(), saved.read_bytes())

            # Real changes and ordered collections must still reach the snapshot.
            for settings in ({'enabled': False, 'order': ['a', 'b']},
                             {'enabled': True, 'order': ['b', 'a']}):
                candidate.write_bytes(plistlib.dumps({**original, 'Services': settings}))
                expected = candidate.read_bytes()
                result = subprocess.run(command, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(candidate.read_bytes(), expected)

            # Do not mask broken captures or prevent repair of a bad old snapshot.
            saved.write_bytes(b'invalid')
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
            saved.write_bytes(plistlib.dumps(original))
            candidate.write_bytes(b'invalid')
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)

    def test_plist_stabilization_preserves_neighbor_through_publication(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            stage, previous, base, repo = (root / name for name in ("stage", "previous", "base", "repo"))
            relative = Path("services/fixture.workflow/Contents/Info.plist")
            neighbor = relative.with_name(relative.name + ".stabilizing")
            settings = {"zeta": 1, "alpha": 2}
            saved_bytes = plistlib.dumps(settings, fmt=plistlib.FMT_XML, sort_keys=False)
            captured_bytes = plistlib.dumps(settings, fmt=plistlib.FMT_XML, sort_keys=True)
            sentinel = b"unrelated tracked neighbor\n"
            for tree in (stage, previous, base, repo):
                (tree / relative).parent.mkdir(parents=True)
                (tree / relative).write_bytes(saved_bytes)
                (tree / neighbor).write_bytes(sentinel)
            (stage / relative).write_bytes(captured_bytes)

            result = subprocess.run(
                [sys.executable, str(ROOT / "scripts/stabilize-plist-backups.py"),
                 str(stage), str(previous)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((stage / neighbor).read_bytes(), sentinel)

            recovery = root / "recovery"
            recovery.mkdir()
            self.record_directories(base, repo, "services")
            result = subprocess.run(
                [sys.executable, str(ROOT / "scripts/publish-app-backup.py"), "publish",
                 "--base", str(base), "--candidate", str(stage), "--destination", str(repo),
                 "--rollback", str(recovery), "--target", "services"],
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((repo / neighbor).read_bytes(), sentinel)
            self.assertEqual((repo / relative).read_bytes(), saved_bytes)

    def test_plist_stabilization_failure_leaves_candidate_and_neighbor_untouched(self):
        scripts = str(ROOT / "scripts")
        sys.path.insert(0, scripts)
        try:
            spec = importlib.util.spec_from_file_location(
                "stabilize_plist_backups_test", ROOT / "scripts/stabilize-plist-backups.py")
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
        finally:
            sys.path.remove(scripts)

        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            candidate = root / "Info.plist"
            saved = root / "saved.plist"
            neighbor = root / "Info.plist.stabilizing"
            original = plistlib.dumps({"zeta": 0}, fmt=plistlib.FMT_XML)
            neighbor_bytes = b"unrelated neighbor\n"
            candidate.write_bytes(plistlib.dumps({"zeta": 1}, fmt=plistlib.FMT_XML))
            saved.write_bytes(original)
            neighbor.write_bytes(neighbor_bytes)
            candidate_bytes = candidate.read_bytes()

            with mock.patch("backup_metadata.apply_file_metadata", side_effect=OSError("fixture failure")):
                with self.assertRaisesRegex(OSError, "fixture failure"):
                    module.keep_saved_bytes(candidate, saved)

            self.assertEqual(candidate.read_bytes(), candidate_bytes)
            self.assertEqual(neighbor.read_bytes(), neighbor_bytes)
            self.assertEqual(list(root.glob(".stabilizing.*")), [])

    def test_read_only_equivalent_app_plist_is_retained_with_its_own_mode(self):
        with tempfile.TemporaryDirectory() as td:
            previous, stage = Path(td) / 'previous', Path(td) / 'stage'
            relative = 'apps/reader/reader.plist'
            saved, candidate = previous / relative, stage / relative
            saved.parent.mkdir(parents=True)
            candidate.parent.mkdir(parents=True)
            settings = {'b': 2, 'a': 1}
            saved.write_bytes(plistlib.dumps(settings, sort_keys=False))
            command = [sys.executable, str(ROOT / 'scripts/stabilize-plist-backups.py'),
                       str(stage), str(previous)]
            # Identical bytes, then the same values in another key order.
            for captured in (saved.read_bytes(), plistlib.dumps(settings, sort_keys=True)):
                with self.subTest(identical=captured == saved.read_bytes()):
                    if candidate.exists():
                        candidate.chmod(0o644)
                    candidate.write_bytes(captured)
                    candidate.chmod(0o444)
                    result = subprocess.run(command, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(candidate.read_bytes(), saved.read_bytes())
                    self.assertEqual(candidate.stat().st_mode & 0o777, 0o444)
                    self.assertEqual(sorted(p.name for p in candidate.parent.iterdir()), ['reader.plist'])

    def test_first_system_plist_capture_with_mixed_review_answers(self):
        with tempfile.TemporaryDirectory() as td:
            previous, stage = Path(td) / 'previous', Path(td) / 'stage'
            relative = Path('macos/bluetooth-mouse.plist')
            candidate = stage / relative
            previous.mkdir()
            candidate.parent.mkdir(parents=True)
            candidate.write_bytes(plistlib.dumps({'Keep': True, 'Skip': True}))
            result = self.review(stage, previous, 'y\nn\n')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(plistlib.loads(candidate.read_bytes()), {'Keep': True})

    def test_accepted_system_plist_uses_saved_metadata(self):
        with tempfile.TemporaryDirectory() as td:
            previous, stage = Path(td) / 'previous', Path(td) / 'stage'
            relative = Path('macos/bluetooth-mouse.plist')
            saved, candidate = previous / relative, stage / relative
            saved.parent.mkdir(parents=True)
            candidate.parent.mkdir(parents=True)
            saved.write_bytes(plistlib.dumps({'Setting': False}))
            candidate.write_bytes(plistlib.dumps({'Setting': True}))
            saved.chmod(0o600)
            candidate.chmod(0o644)
            result = self.review(stage, previous, 'y\n')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(plistlib.loads(candidate.read_bytes()), {'Setting': True})
            self.assertEqual(candidate.stat().st_mode & 0o777, 0o600)

    def test_read_only_unchanged_system_plist_review_does_not_write(self):
        with tempfile.TemporaryDirectory() as td:
            previous, stage = Path(td) / 'previous', Path(td) / 'stage'
            relative = Path('macos/bluetooth-mouse.plist')
            saved, candidate = previous / relative, stage / relative
            saved.parent.mkdir(parents=True)
            candidate.parent.mkdir(parents=True)
            payload = plistlib.dumps({'FixtureSetting': True})
            saved.write_bytes(payload)
            candidate.write_bytes(payload)
            for path in (saved, candidate):
                if sys.platform == "darwin":
                    subprocess.run(["/usr/bin/xattr", "-w", "com.apple.quarantine",
                                    "0081;61100000;Fixture;00000000-0000-0000-0000-000000000000", path],
                                   check=True)
                    subprocess.run(["/bin/chmod", "+a", "everyone deny writeextattr", path], check=True)
                path.chmod(0o444)
            captured_inode = candidate.stat().st_ino
            captured_metadata = backup_metadata.fingerprint(candidate)

            result = self.review(stage, previous, '')

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(candidate.read_bytes(), payload)
            self.assertEqual(candidate.stat().st_ino, captured_inode)
            self.assertEqual(backup_metadata.fingerprint(candidate), captured_metadata)
            self.assertEqual(candidate.stat().st_mode & 0o777, 0o444)
            self.assertEqual(list(candidate.parent.iterdir()), [candidate])

    def test_declined_read_only_system_plist_change_uses_atomic_saved_bytes(self):
        with tempfile.TemporaryDirectory() as td:
            previous, stage = Path(td) / 'previous', Path(td) / 'stage'
            relative = Path('macos/bluetooth-mouse.plist')
            saved, candidate = previous / relative, stage / relative
            saved.parent.mkdir(parents=True)
            candidate.parent.mkdir(parents=True)
            old = plistlib.dumps({'FixtureSetting': True})
            saved.write_bytes(old)
            candidate.write_bytes(plistlib.dumps({'FixtureSetting': False}))
            candidate.chmod(0o444)

            result = self.review(stage, previous, 'n\n')

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(candidate.read_bytes(), old)
            self.assertEqual(candidate.stat().st_mode & 0o777, 0o644)
            self.assertEqual([path.name for path in candidate.parent.iterdir()],
                             ['bluetooth-mouse.plist'])

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS quarantine metadata')
    def test_read_only_equivalent_plist_keeps_quarantine_and_saved_bytes(self):
        with tempfile.TemporaryDirectory() as td:
            previous, stage = Path(td) / 'previous', Path(td) / 'stage'
            relative = Path('apps/reader/reader.plist')
            saved, candidate = previous / relative, stage / relative
            saved.parent.mkdir(parents=True)
            candidate.parent.mkdir(parents=True)
            settings = {'b': 2, 'a': 1}
            saved.write_bytes(plistlib.dumps(settings, sort_keys=False))
            candidate.write_bytes(plistlib.dumps(settings, sort_keys=True))
            quarantine = '0081;61100000;Fixture;00000000-0000-0000-0000-000000000000'
            subprocess.run(
                ['/usr/bin/xattr', '-w', 'com.apple.quarantine', quarantine, str(candidate)],
                check=True, capture_output=True, text=True,
            )
            subprocess.run(
                ['/bin/chmod', '+a', 'everyone deny writeextattr', str(candidate)],
                check=True, capture_output=True, text=True,
            )
            candidate.chmod(0o444)
            saved_acl = backup_metadata.fingerprint(candidate)['acl']
            denied_update = subprocess.run(
                ['/usr/bin/xattr', '-w', 'com.apple.quarantine',
                 '0081;61100000;Changed;00000000-0000-0000-0000-000000000000', str(candidate)],
                capture_output=True, text=True,
            )
            self.assertNotEqual(denied_update.returncode, 0)

            result = subprocess.run(
                [sys.executable, str(ROOT / 'scripts/stabilize-plist-backups.py'),
                 str(stage), str(previous)], capture_output=True, text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(candidate.read_bytes(), saved.read_bytes())
            self.assertEqual(candidate.stat().st_mode & 0o777, 0o444)
            self.assertEqual(backup_metadata.fingerprint(candidate)['acl'], saved_acl)
            self.assertEqual(
                subprocess.check_output(
                    ['/usr/bin/xattr', '-p', 'com.apple.quarantine', str(candidate)], text=True
                ).strip(),
                quarantine,
            )

    @unittest.skipUnless(shutil.which('plutil') and Path('/usr/libexec/PlistBuddy').exists(),
                         'requires macOS plist tools')
    def test_retained_snapshot_still_gets_current_sanitization(self):
        with tempfile.TemporaryDirectory() as td:
            previous, stage = Path(td) / 'previous', Path(td) / 'stage'
            for root in (previous, stage):
                (root / 'apps/terminal').mkdir(parents=True)
                (root / '.node-version').write_text('v22.23.1\n')
                terminal = root / 'apps/terminal/terminal.plist'
                terminal.write_bytes(plistlib.dumps({'SecureKeyboardEntry': True, 'setting': True},
                                                      fmt=plistlib.FMT_BINARY))
                terminal.chmod(0o444)
            audit = subprocess.run(['bash', str(ROOT / 'scripts/audit-app-prefs.sh')],
                                   env={**os.environ, 'DOTFILES': str(stage)}, capture_output=True, text=True)
            self.assertEqual(audit.returncode, 1, audit.stdout + audit.stderr)
            self.assertIn('machine-local app preferences remain in apps/terminal/terminal.plist', audit.stdout)
            for root in (stage, previous):
                result = subprocess.run(['bash', str(ROOT / 'scripts/sanitize-app-prefs.sh')],
                                        env={**os.environ, 'DOTFILES': str(root)},
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            command = ['python3', str(ROOT / 'scripts/stabilize-plist-backups.py'),
                       str(stage), str(previous)]
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
            terminal = stage / 'apps/terminal/terminal.plist'
            self.assertEqual(plistlib.loads(terminal.read_bytes()), {'setting': True})
            self.assertTrue(terminal.read_bytes().startswith(b'bplist00'))
            self.assertEqual(terminal.stat().st_mode & 0o777, 0o444)


if __name__ == '__main__':
    unittest.main()
