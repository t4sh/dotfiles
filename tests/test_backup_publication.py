"""Filesystem interleavings that matter when publishing an app backup."""

import contextlib
import errno
import importlib.util
import io
import json
import os
import shutil
import subprocess
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location("publisher", SCRIPTS / "publish-app-backup.py")
publisher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(publisher)


class PublicationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        self.base, self.candidate, self.repo, self.recovery = [
            root / name for name in ("base", "candidate", "repo", "recovery")
        ]
        self.relative = Path("apps/settings")
        self.live = self.repo / self.relative
        self.editor = root / "editor-save"
        for tree, content in ((self.base, "original"), (self.candidate, "captured"), (self.repo, "original")):
            (tree / "apps").mkdir(parents=True)
            (tree / self.relative).write_text(content)
        self.recovery.mkdir()

    def publish(self):
        if not (self.base / publisher.CAPTURE_DIRECTORIES).exists():
            publisher.record_directories(self.base, self.repo, ["apps"])
        return publisher.publish(self.base, self.candidate, self.repo, self.recovery, ["apps"])

    def test_publish_requires_directory_identities_from_capture(self):
        with self.assertRaisesRegex(RuntimeError, "directory baseline missing"):
            publisher.publish(self.base, self.candidate, self.repo, self.recovery, ["apps"])
        self.assertEqual(self.live.read_text(), "original")
        self.assertFalse((self.recovery / publisher.JOURNAL).exists())

    def test_capture_identity_cannot_be_replaced_before_publication(self):
        parent = Path("apps/preferences")
        for tree in (self.base, self.repo, self.candidate):
            (tree / parent).mkdir()
        (self.candidate / parent / "new").write_text("capture")
        publisher.record_directories(self.base, self.repo, ["apps"])
        (self.repo / parent).rename(self.repo / "previous-parent")
        (self.repo / parent).mkdir()
        with self.assertRaises(FileExistsError):
            publisher.record_directories(self.base, self.repo, ["apps"])
        self.assertNotEqual(self.publish(), 0)
        self.assertEqual(list((self.repo / parent).iterdir()), [])
        self.assertEqual(list((self.repo / "previous-parent").iterdir()), [])

    def test_equal_empty_replacement_directory_is_not_published_as_deleted(self):
        empty = Path("apps/empty")
        for tree in (self.base, self.repo):
            (tree / empty).mkdir()
        publisher.record_directories(self.base, self.repo, ["apps"])
        (self.repo / empty).rename(self.repo / "previous-empty")
        (self.repo / empty).mkdir()
        self.assertNotEqual(self.publish(), 0)
        self.assertTrue((self.repo / empty).is_dir())

    def test_sparse_parent_uses_real_metadata_and_still_detects_a_later_change(self):
        relative = Path("config/codex/config.toml")
        policy = Path("config/macos-preferences.json")
        for tree in (self.repo, self.base, self.candidate):
            (tree / relative.parent).mkdir(parents=True)
            (tree / relative).write_text("saved")
        (self.repo / relative.parent).chmod(0o700)
        publisher.record_directories(self.base, self.repo, [str(relative)])
        (self.candidate / relative).write_text("selected")
        (self.candidate / policy).write_text("{}")
        # Terminal review publishes the sparse config tree for first-time policy capture.
        self.assertEqual(publisher.publish(self.base, self.candidate, self.repo, self.recovery, ["config"]), 0)
        self.assertEqual((self.repo / relative).read_text(), "selected")
        self.assertEqual((self.repo / relative.parent).stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.repo / policy).read_text(), "{}")
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        (self.repo / relative.parent).chmod(0o750)
        retry = self.recovery.with_name("new-publication")
        retry.mkdir()
        self.assertNotEqual(publisher.publish(self.base, self.candidate, self.repo, retry, ["config"]), 0)
        self.assertEqual((self.repo / relative).read_text(), "saved")

    @staticmethod
    def is_path_at_parent(path, options, expected, *, option="dst_dir_fd"):
        expected = Path(expected).resolve()
        if Path(path).resolve() == expected:
            return True
        parent_fd = options.get(option)
        if parent_fd is None or Path(path) != Path(expected.name):
            return False
        info = os.fstat(parent_fd)
        parent = expected.parent.stat()
        return (info.st_dev, info.st_ino) == (parent.st_dev, parent.st_ino)

    @staticmethod
    def is_destination(destination, options, expected):
        return PublicationTests.is_path_at_parent(destination, options, expected)

    def assert_final_install_preserves_editor(self, editor_content):
        identity = self.publish_while_editor_wins_final_install(editor_content)
        publisher.rollback(self.repo, self.recovery)
        self.assertEqual(self.live.stat().st_ino, identity)
        self.assertEqual(self.live.read_text(), editor_content)

    def publish_while_editor_wins_final_install(self, editor_content, live=None):
        live = live or self.live
        self.editor.write_text(editor_content)
        identity = self.editor.stat().st_ino
        replace = os.replace
        editor_saved = False

        def interleave(operation):
            def save_first(src, dst, *args, **kwargs):
                nonlocal editor_saved
                if not editor_saved and self.is_destination(dst, kwargs, live):
                    editor_saved = True
                    replace(self.editor, live)
                return operation(src, dst, *args, **kwargs)
            return save_first

        # Inject a completed editor save immediately before the filesystem
        # installs the candidate. Exercise both overwrite and exclusive installs.
        with patch.object(os, "replace", interleave(replace)), patch.object(os, "link", interleave(os.link)):
            status = self.publish()
        self.assertTrue(editor_saved, "fixture did not reach the destination install")
        self.assertNotEqual(status, 0)
        self.assertEqual(live.stat().st_ino, identity)
        return identity

    def claim(self, relative):
        return publisher.claim_slot(self.recovery / publisher.CLAIMS, Path(relative).as_posix())

    def test_manual_rollbacks_serialize_on_the_same_journal(self):
        from concurrent.futures import ThreadPoolExecutor
        import fcntl
        from threading import Event

        self.assertEqual(self.publish(), 0)
        entered, proceed = Event(), Event()
        restore = publisher.restore_entry_noreplace

        def pause_first(*args, **kwargs):
            if not entered.is_set():
                entered.set()
                if not proceed.wait(10):
                    raise TimeoutError("second rollback did not start")
            return restore(*args, **kwargs)

        with patch.object(publisher, "restore_entry_noreplace", pause_first), ThreadPoolExecutor(2) as pool:
            first = pool.submit(publisher.rollback, self.repo, self.recovery)
            try:
                self.assertTrue(entered.wait(10), "first rollback did not reach the restore")
                # An independent descriptor must still see the lock during the
                # mutation. Closing the journal after parsing would lose it.
                with (self.recovery / publisher.JOURNAL).open("rb") as journal:
                    with self.assertRaises(BlockingIOError):
                        fcntl.flock(journal, fcntl.LOCK_EX | fcntl.LOCK_NB)
                second = pool.submit(publisher.rollback, self.repo, self.recovery)
            finally:
                proceed.set()
            self.assertEqual(first.result(timeout=10), 0)
            self.assertEqual(second.result(timeout=10), 0)
        self.assertEqual(self.live.read_text(), "original")

    def test_final_install_does_not_overwrite_an_editor_save(self):
        self.assert_final_install_preserves_editor("independent")

    def test_final_install_conflict_is_reported_as_a_concurrent_entry(self):
        self.publish_while_editor_wins_final_install("independent")
        report = io.StringIO()
        with contextlib.redirect_stderr(report):
            status = publisher.rollback(self.repo, self.recovery)
        self.assertNotEqual(status, 0)
        self.assertIn("unresolved concurrent entry retained: apps/settings", report.getvalue())
        self.assertNotIn("uncertain", report.getvalue())
        self.assertEqual(self.live.read_text(), "independent")
        self.assertEqual(self.claim(self.relative).read_text(), "original")

    def test_save_identical_to_the_original_leaves_nothing_unresolved(self):
        self.publish_while_editor_wins_final_install("original")
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.read_text(), "original")

    def test_conflict_on_a_new_path_settles_when_the_other_writer_leaves(self):
        new = self.repo / "apps/new"
        (self.candidate / "apps/new").write_text("captured")
        self.publish_while_editor_wins_final_install("independent", new)
        self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(new.read_text(), "independent")
        new.unlink()
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertFalse(new.exists())

    def test_edited_claim_is_never_returned_as_the_original(self):
        self.publish_while_editor_wins_final_install("independent")
        self.claim(self.relative).write_text("edited through an open handle")
        self.live.unlink()
        report = io.StringIO()
        with contextlib.redirect_stderr(report):
            self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertFalse(self.live.exists())
        self.assertEqual(self.claim(self.relative).read_text(), "edited through an open handle")
        self.assertIn(str(self.recovery / publisher.OBJECTS / self.relative), report.getvalue())

    def test_unreadable_conflict_does_not_keep_other_paths_from_returning(self):
        other = Path("apps/other")
        for tree, content in ((self.base, "original"), (self.candidate, "captured"), (self.repo, "original")):
            (tree / other).write_text(content)
        self.publish_while_editor_wins_final_install("independent")
        self.assertEqual((self.repo / other).read_text(), "captured")
        self.live.chmod(0)
        self.addCleanup(self.live.chmod, 0o600)
        self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual((self.repo / other).read_text(), "original")

    def test_directory_removed_during_its_claim_returns_with_its_saved_mode(self):
        retired = Path("apps/retired")
        for tree in (self.base, self.repo):
            (tree / retired).mkdir()
            (tree / retired / "note").write_text("keep")
            (tree / retired).chmod(0o700)
        replace = os.replace

        def remove_first(src, dst, *args, **kwargs):
            if self.is_path_at_parent(src, kwargs, self.repo / retired, option="src_dir_fd"):
                os.rmdir(self.repo / retired)
            return replace(src, dst, *args, **kwargs)

        with patch.object(os, "replace", remove_first):
            self.assertNotEqual(self.publish(), 0)
        self.assertFalse((self.repo / retired).exists())
        for _ in range(2):
            self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
            self.assertEqual((self.repo / retired / "note").read_text(), "keep")
            self.assertEqual((self.repo / retired).stat().st_mode & 0o777, 0o700)

    def test_child_added_to_a_claimed_directory_keeps_the_recovery_data(self):
        retired = Path("apps/retired")
        for tree in (self.base, self.repo):
            (tree / retired).mkdir()
            (tree / retired / "note").write_text("keep")
        self.assertEqual(self.publish(), 0)
        (self.claim(retired) / "late").write_text("independent")
        self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual((self.claim(retired) / "late").read_text(), "independent")

    def retire_directory(self, mode=0o700, children=("note",)):
        """Add a directory to base and repo that the candidate no longer has."""
        retired = Path("apps/retired")
        for tree in (self.base, self.repo):
            for child in children:
                (tree / retired / child).parent.mkdir(parents=True, exist_ok=True)
                (tree / retired / child).write_text("keep")
            (tree / retired).chmod(mode)
        return retired

    def publish_while_directory_vanishes(self, retired, crash_before_recording=False):
        replace, append = os.replace, publisher.journal_append

        def remove_first(src, dst, *args, **kwargs):
            if self.is_path_at_parent(src, kwargs, self.repo / retired, option="src_dir_fd"):
                shutil.rmtree(self.repo / retired)
            return replace(src, dst, *args, **kwargs)

        def stop_before_recording(path, record):
            if record["state"] == "unresolved":
                raise KeyboardInterrupt
            return append(path, record)

        with patch.object(os, "replace", remove_first):
            if crash_before_recording:
                with patch.object(publisher, "journal_append", stop_before_recording):
                    self.assertRaises(KeyboardInterrupt, self.publish)
            else:
                self.assertNotEqual(self.publish(), 0)
        self.assertFalse((self.repo / retired).exists())

    def test_nested_directory_tree_with_its_own_mode_can_be_deleted_and_returned(self):
        retired = self.retire_directory(children=("sub/deep",))
        self.assertEqual(self.publish(), 0)
        self.assertFalse((self.repo / retired).exists())
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual((self.repo / retired / "sub/deep").read_text(), "keep")
        self.assertEqual((self.repo / retired).stat().st_mode & 0o777, 0o700)

    def test_original_is_not_restored_into_a_replacement_directory(self):
        holder = Path("apps/holder")
        for tree in (self.base, self.candidate, self.repo):
            (tree / holder).mkdir()
            (tree / holder / "stays").write_text("keep")
        for tree in (self.base, self.repo):
            (tree / holder / "retired").write_text("original")
        self.assertEqual(self.publish(), 0)
        # Another writer moves the directory aside and makes a new one in its place.
        (self.repo / holder).rename(self.repo / "apps/holder-moved")
        (self.repo / holder).mkdir()
        report = io.StringIO()
        with contextlib.redirect_stderr(report):
            self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertFalse((self.repo / holder / "retired").exists())
        self.assertEqual((self.recovery / publisher.OBJECTS / holder / "retired").read_text(), "original")
        self.assertIn("replaced by another writer", report.getvalue())

    def test_parent_swap_after_validation_does_not_redirect_rollback_write(self):
        held = Path("apps/holder")
        retired = held / "retired"
        for tree in (self.base, self.repo):
            (tree / retired).parent.mkdir(parents=True, exist_ok=True)
            (tree / retired).write_text("original")
        (self.candidate / held).mkdir()
        self.assertEqual(self.publish(), 0)
        self.assertFalse((self.repo / retired).exists())

        link = os.link
        swapped = False

        def swap_parent_then_link(source, destination, *args, **kwargs):
            nonlocal swapped
            # This is the check-to-use interleaving: rollback has already
            # validated/opened the intended parent, but has not installed the
            # original entry yet. Descriptor-relative restoration must remain
            # attached to the validated directory after its name is moved.
            if not swapped and Path(str(destination)).name == "retired":
                swapped = True
                parent = self.repo / held
                parent.rename(self.repo / "apps/holder-moved")
                parent.mkdir()
            return link(source, destination, *args, **kwargs)

        with patch.object(os, "link", swap_parent_then_link):
            publisher.rollback(self.repo, self.recovery)

        self.assertTrue(swapped, "fixture did not reach the rollback install")
        self.assertFalse((self.repo / retired).exists(), "rollback wrote into the replacement parent")
        self.assertEqual((self.repo / "apps/holder-moved/retired").read_text(), "original")

    def test_parent_swap_during_file_install_blocks_later_siblings(self):
        for tree in (self.base, self.candidate, self.repo):
            for name in ("a", "b"):
                (tree / "apps" / name).write_text("original" if tree != self.candidate else "captured")
        held = (self.repo / "apps").stat()
        link = os.link
        moved = False

        def move_before_install(source, destination, *args, **kwargs):
            nonlocal moved
            fd = kwargs.get("dst_dir_fd")
            if (not moved and Path(destination) == Path("a") and fd is not None
                    and (os.fstat(fd).st_dev, os.fstat(fd).st_ino) == (held.st_dev, held.st_ino)):
                moved = True
                (self.repo / "apps").rename(self.repo / "apps-moved")
                (self.repo / "apps").mkdir()
            return link(source, destination, *args, **kwargs)

        with patch.object(os, "link", move_before_install):
            self.assertNotEqual(self.publish(), 0)

        self.assertTrue(moved, "fixture did not move the held parent")
        self.assertEqual((self.repo / "apps-moved/a").read_text(), "captured")
        self.assertFalse((self.repo / "apps/a").exists())
        self.assertFalse((self.repo / "apps/b").exists(), "a sibling was installed in a replacement parent")
        self.assertEqual(self.claim("apps/a").read_text(), "original")

    def test_parent_swap_during_delete_keeps_original_claim_and_counts_conflict(self):
        relative = Path("apps/gone")
        for tree in (self.base, self.repo):
            (tree / relative).write_text("original")
        held = (self.repo / "apps").stat()
        replace = os.replace
        moved = False

        def move_before_claim(source, destination, *args, **kwargs):
            nonlocal moved
            fd = kwargs.get("src_dir_fd")
            if (not moved and Path(source) == Path("gone") and fd is not None
                    and (os.fstat(fd).st_dev, os.fstat(fd).st_ino) == (held.st_dev, held.st_ino)):
                moved = True
                (self.repo / "apps").rename(self.repo / "apps-moved")
                (self.repo / "apps").mkdir()
            return replace(source, destination, *args, **kwargs)

        with patch.object(os, "replace", move_before_claim):
            self.assertNotEqual(self.publish(), 0)

        self.assertTrue(moved, "fixture did not move the held parent")
        self.assertFalse((self.repo / "apps/gone").exists())
        self.assertFalse((self.repo / "apps-moved/gone").exists())
        self.assertEqual(self.claim(relative).read_text(), "original")

    def test_parent_swap_during_directory_create_keeps_recovery_and_reports_conflict(self):
        relative = Path("apps/newdir")
        (self.candidate / relative).mkdir()
        (self.candidate / relative / "note").write_text("captured")
        held = (self.repo / "apps").stat()
        rename = publisher._rename_noreplace
        moved = False

        def move_before_create(source, destination, parent_fd=None):
            nonlocal moved
            if (not moved and Path(destination) == Path("newdir") and parent_fd is not None
                    and (os.fstat(parent_fd).st_dev, os.fstat(parent_fd).st_ino)
                    == (held.st_dev, held.st_ino)):
                moved = True
                (self.repo / "apps").rename(self.repo / "apps-moved")
                (self.repo / "apps").mkdir()
            return rename(source, destination, parent_fd)

        with patch.object(publisher, "_rename_noreplace", move_before_create):
            self.assertNotEqual(self.publish(), 0)

        self.assertTrue(moved, "fixture did not move the held parent")
        self.assertTrue((self.repo / "apps-moved/newdir").is_dir())
        self.assertFalse((self.repo / "apps-moved/newdir/note").exists())
        self.assertFalse((self.repo / "apps/newdir").exists())
        record = (self.recovery / publisher.JOURNAL).read_text()
        self.assertIn('"parent_identity"', record)
        report = io.StringIO()
        with contextlib.redirect_stderr(report):
            self.assertEqual(publisher.rollback(self.repo, self.recovery), 1)
        self.assertIn("parent directory was replaced by another writer", report.getvalue())
        self.assertFalse((self.repo / "apps/newdir").exists())

    def test_new_write_with_a_moved_parent_keeps_recovery_incomplete(self):
        relative = Path("apps/newfile")
        (self.candidate / relative).write_text("captured")
        held = (self.repo / "apps").stat()
        link = os.link
        moved = False

        def move_before_install(source, destination, *args, **kwargs):
            nonlocal moved
            fd = kwargs.get("dst_dir_fd")
            if (not moved and Path(destination) == Path("newfile") and fd is not None
                    and (os.fstat(fd).st_dev, os.fstat(fd).st_ino) == (held.st_dev, held.st_ino)):
                moved = True
                (self.repo / "apps").rename(self.repo / "apps-moved")
                (self.repo / "apps").mkdir()
            return link(source, destination, *args, **kwargs)

        with patch.object(os, "link", move_before_install):
            self.assertNotEqual(self.publish(), 0)
        self.assertTrue(moved, "fixture did not move the held parent")
        self.assertEqual((self.repo / "apps-moved/newfile").read_text(), "captured")
        self.assertFalse((self.repo / "apps/newfile").exists())
        report = io.StringIO()
        with contextlib.redirect_stderr(report):
            self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertIn("parent directory was replaced by another writer", report.getvalue())

    def test_directory_create_rollback_is_idempotent_and_preinstall_interrupt_is_known(self):
        relative = Path("apps/newdir")
        (self.candidate / relative).mkdir()
        (self.candidate / relative / "note").write_text("captured")
        self.assertEqual(self.publish(), 0)
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertFalse((self.repo / relative).exists())

        self.recovery = self.recovery.with_name("recovery-interrupted")
        self.recovery.mkdir()
        rename = publisher._rename_noreplace

        def stop_before_install(source, destination, parent_fd=None):
            if Path(destination) == Path("newdir"):
                raise KeyboardInterrupt
            return rename(source, destination, parent_fd)

        with patch.object(publisher, "_rename_noreplace", stop_before_install):
            self.assertRaises(KeyboardInterrupt, self.publish)
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertFalse((self.repo / relative).exists())

    def test_retry_refuses_empty_wrong_identity_undo_claim(self):
        folder = Path("apps/newdir")
        (self.candidate / folder).mkdir()
        self.assertEqual(self.publish(), 0)
        claimed = publisher.claim_slot(self.recovery / publisher.UNDO_CLAIMS, str(folder))
        claimed.parent.mkdir(parents=True, exist_ok=True)
        (self.repo / folder).rename(claimed)
        claimed.rename(claimed.with_name("previous-inode"))
        claimed.mkdir()

        self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertTrue(claimed.is_dir())
        self.assertFalse((self.repo / folder).exists())

    def test_retry_keeps_verified_claim_when_replacement_occupies_target(self):
        folder = Path("apps/newdir")
        (self.candidate / folder).mkdir()
        self.assertEqual(self.publish(), 0)
        claimed = publisher.claim_slot(self.recovery / publisher.UNDO_CLAIMS, str(folder))
        claimed.parent.mkdir(parents=True, exist_ok=True)
        (self.repo / folder).rename(claimed)
        (claimed / "user-note").write_text("keep")
        (self.repo / folder).mkdir()

        self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual((claimed / "user-note").read_text(), "keep")
        self.assertTrue((self.repo / folder).is_dir())
        self.assertEqual(list((self.repo / folder).iterdir()), [])

    def test_legacy_cancelled_directory_with_undo_claim_is_unresolved(self):
        folder = Path("apps/newdir")
        (self.candidate / folder).mkdir()
        self.assertEqual(self.publish(), 0)
        claimed = publisher.claim_slot(self.recovery / publisher.UNDO_CLAIMS, str(folder))
        claimed.parent.mkdir(parents=True, exist_ok=True)
        (self.repo / folder).rename(claimed)
        with (self.recovery / publisher.JOURNAL).open("a") as journal:
            journal.write(json.dumps({
                "path": str(folder), "operation": "directory-create", "state": "cancelled",
                "before": None, "after": publisher.fingerprint(claimed),
                "installed_identity": publisher.identity(claimed),
                "parent_identity": publisher.identity(self.repo / "apps"),
            }, sort_keys=True) + "\n")

        self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertTrue(claimed.is_dir())

    def test_retry_preserves_user_data_in_claimed_new_directory(self):
        folder = Path("apps/newdir")
        (self.candidate / folder).mkdir()
        self.assertEqual(self.publish(), 0)
        claimed = publisher.claim_slot(self.recovery / publisher.UNDO_CLAIMS, str(folder))
        claimed.parent.mkdir(parents=True, exist_ok=True)
        (self.repo / folder).rename(claimed)
        (claimed / "user-note").write_text("keep")

        report = io.StringIO()
        with contextlib.redirect_stderr(report):
            self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)

        latest = [json.loads(line) for line in
                  (self.recovery / publisher.JOURNAL).read_text().splitlines()]
        folder_records = [record for record in latest if record["path"] == str(folder)]
        self.assertNotEqual(folder_records[-1]["state"], "cancelled")
        self.assertEqual((self.repo / folder / "user-note").read_text(), "keep")
        self.assertIn("independent directory contents preserved", report.getvalue())

    def test_retry_after_undoing_new_directory_before_completion_record(self):
        relative = Path("apps/newdir")
        (self.candidate / relative).mkdir()
        self.assertEqual(self.publish(), 0)
        append = publisher.journal_append

        def interrupt(journal, record):
            if record["path"] == str(relative) and record["state"] == "cancelled":
                raise KeyboardInterrupt
            append(journal, record)

        with patch.object(publisher, "journal_append", interrupt):
            self.assertRaises(KeyboardInterrupt, publisher.rollback, self.repo, self.recovery)
        self.assertFalse((self.repo / relative).exists())
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)

    def test_directory_metadata_record_without_identity_fails_closed(self):
        source, target = self.base / "apps", self.repo / "apps"
        record = publisher._record("apps", "directory-metadata", "restoring-metadata",
                                   publisher.fingerprint(target), publisher.fingerprint(source))
        before = publisher.fingerprint(target)
        descriptor = os.open(self.repo, os.O_RDONLY | os.O_DIRECTORY)
        try:
            with patch.object(publisher, "_make_stage") as make_stage:
                with self.assertRaisesRegex(ValueError, "lacks its installed identity"):
                    publisher.update_directory_metadata(source, target, descriptor, self.recovery / publisher.JOURNAL,
                                                        record, before, publisher.fingerprint(source))
                make_stage.assert_not_called()
        finally:
            os.close(descriptor)
        self.assertEqual(publisher.fingerprint(target), before)
        self.assertFalse((self.recovery / publisher.JOURNAL).exists())

    def test_rollback_reports_missing_directory_metadata_identity_and_restores_other_paths(self):
        self.assertEqual(self.publish(), 0)
        target = self.repo / "apps"
        before = publisher.fingerprint(target)
        record = publisher._record("apps", "directory-metadata", "applied", before, before)
        journal = self.recovery / publisher.JOURNAL
        publisher.journal_append(journal, record)
        errors = io.StringIO()

        with contextlib.redirect_stderr(errors):
            self.assertEqual(publisher.rollback(self.repo, self.recovery), 1)

        self.assertIn("directory metadata record lacks its installed identity", errors.getvalue())
        self.assertNotIn("concurrent directory preserved: apps", errors.getvalue())
        self.assertEqual(publisher.fingerprint(target), before)
        self.assertEqual(self.live.read_text(), "original")

    def test_parent_without_list_permission_can_receive_rollback_file(self):
        self.assertEqual(self.publish(), 0)
        (self.repo / "apps").chmod(0o300)
        with patch.dict(vars(os)):
            if sys.platform == "darwin":
                # Some macOS Python builds do not export the native flag.
                vars(os).pop("O_SEARCH", None)
            self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.read_text(), "original")
        self.assertEqual((self.repo / "apps").stat().st_mode & 0o777, 0o300)

    def test_directory_metadata_publish_does_not_follow_replaced_target(self):
        (self.base / "apps").chmod(0o755)
        (self.candidate / "apps").chmod(0o700)
        (self.repo / "apps").chmod(0o755)
        chmod = os.fchmod
        moved = False

        def move_during_chmod(fd, mode):
            nonlocal moved
            if not moved:
                moved = True
                (self.repo / "apps").rename(self.repo / "apps-moved")
                (self.repo / "apps").mkdir(mode=0o755)
            return chmod(fd, mode)

        with patch.object(os, "fchmod", move_during_chmod):
            self.assertNotEqual(self.publish(), 0)

        self.assertTrue(moved, "fixture did not replace the metadata target")
        self.assertEqual((self.repo / "apps").stat().st_mode & 0o777, 0o755)
        self.assertEqual((self.repo / "apps-moved").stat().st_mode & 0o777, 0o700)
        report = io.StringIO()
        with contextlib.redirect_stderr(report):
            self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertIn("concurrent directory preserved", report.getvalue())

    def test_directory_metadata_rollback_does_not_follow_replaced_target(self):
        (self.base / "apps").chmod(0o755)
        (self.candidate / "apps").chmod(0o700)
        (self.repo / "apps").chmod(0o755)
        self.assertEqual(self.publish(), 0)
        chmod = os.fchmod
        moved = False

        def move_during_chmod(fd, mode):
            nonlocal moved
            if not moved:
                moved = True
                (self.repo / "apps").rename(self.repo / "apps-moved")
                (self.repo / "apps").mkdir(mode=0o700)
            return chmod(fd, mode)

        with patch.object(os, "fchmod", move_during_chmod):
            self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)

        self.assertTrue(moved, "fixture did not replace the metadata target")
        self.assertEqual((self.repo / "apps").stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.repo / "apps-moved").stat().st_mode & 0o777, 0o755)
        self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)

    def test_competing_directory_created_during_restore_is_not_owned(self):
        retired = self.retire_directory(children=("note",))
        self.assertEqual(self.publish(), 0)
        original_restore = publisher.restore_entry_noreplace
        raced = False

        def competing_mkdir(source, destination, *args, **kwargs):
            nonlocal raced
            if not raced and Path(destination).resolve() == (self.repo / retired).resolve():
                raced = True
                Path(destination).mkdir(mode=0o700)
            return original_restore(source, destination, *args, **kwargs)

        with patch.object(publisher, "restore_entry_noreplace", competing_mkdir):
            self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)

        self.assertTrue(raced, "fixture did not race directory reconstruction")
        self.assertFalse((self.repo / retired / "note").exists())
        self.assertEqual((self.recovery / publisher.OBJECTS / retired / "note").read_text(), "keep")
        # A retry must not treat the competing directory's matching metadata
        # as proof that rollback created it and then restore children there.
        # Pre-fix journals could have recorded this very directory after losing
        # mkdir. A retry must also disregard that ambiguous ownership evidence.
        publisher.journal_append(self.recovery / "recreated-directories.jsonl", {
            "path": str(retired), "identity": publisher.identity(self.repo / retired),
        })
        self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertFalse((self.repo / retired / "note").exists())

    def test_retry_after_interruption_reconstructing_directory_keeps_ownership(self):
        retired = self.retire_directory(children=("sub/deep",))
        self.publish_while_directory_vanishes(retired)
        original_restore = publisher.restore_entry_noreplace
        interrupted = False

        def stop_after_directory_install(source, destination, *args, **kwargs):
            nonlocal interrupted
            result = original_restore(source, destination, *args, **kwargs)
            if not interrupted and Path(destination).resolve() == (self.repo / retired).resolve():
                interrupted = True
                # Simulate a process interruption after the filesystem
                # mutation, before rollback can append its old post-install
                # ownership marker.
                raise KeyboardInterrupt
            return result

        with patch.object(publisher, "restore_entry_noreplace", stop_after_directory_install):
            self.assertRaises(KeyboardInterrupt, publisher.rollback, self.repo, self.recovery)

        self.assertTrue(interrupted, "fixture did not reconstruct the missing original directory")
        self.assertTrue((self.repo / retired).is_dir())
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual((self.repo / retired / "sub/deep").read_text(), "keep")

    def test_eacces_for_one_rollback_record_does_not_abort_other_records(self):
        blocked = Path("apps/aretired")
        independent = Path("apps/zretired")
        for tree, content in ((self.base, "old"), (self.repo, "old"),
                              (self.candidate, "new")):
            for relative in (blocked, independent):
                (tree / relative).parent.mkdir(parents=True, exist_ok=True)
                (tree / relative).write_text(content)
        self.assertEqual(self.publish(), 0)

        real_path_exists = publisher.path_exists
        denied = publisher.claim_slot(
            self.recovery.resolve() / publisher.UNDO_CLAIMS, str(blocked)
        )

        def deny_one_record(path):
            if Path(path) == denied:
                raise PermissionError(13, "permission denied by test fixture", str(path))
            return real_path_exists(path)

        with patch.object(publisher, "path_exists", deny_one_record):
            try:
                status = publisher.rollback(self.repo, self.recovery)
            except PermissionError as error:
                self.fail(f"path_exists EACCES aborted independent rollback work: {error}")

        self.assertNotEqual(status, 0)
        self.assertEqual((self.repo / independent).read_text(), "old")

    def test_eacces_during_directory_fingerprint_is_isolated_to_that_record(self):
        blocked = Path("apps/aretired")
        independent = Path("apps/zretired")
        for tree, content in ((self.base, "old"), (self.repo, "old"),
                              (self.candidate, "new")):
            for relative in (blocked, independent):
                (tree / relative).parent.mkdir(parents=True, exist_ok=True)
                (tree / relative).write_text(content)
        self.assertEqual(self.publish(), 0)

        real_fingerprint = publisher.fingerprint
        denied = self.repo.resolve() / blocked

        def deny_one_fingerprint(path):
            if Path(path) == denied:
                raise PermissionError(13, "permission denied by test fixture", str(path))
            return real_fingerprint(path)

        with patch.object(publisher, "fingerprint", deny_one_fingerprint):
            try:
                status = publisher.rollback(self.repo, self.recovery)
            except PermissionError as error:
                self.fail(f"directory fingerprint EACCES aborted independent rollback work: {error}")

        self.assertNotEqual(status, 0)
        self.assertEqual((self.repo / independent).read_text(), "old")

    def test_retried_rollback_restores_into_directories_the_first_attempt_recreated(self):
        retired = self.retire_directory(children=("sub/deep",))
        self.assertEqual(self.publish(), 0)
        restore = publisher.restore_entry_noreplace

        def stop_at_the_file(source, destination, *args, **kwargs):
            if destination.name == "deep":
                raise KeyboardInterrupt
            return restore(source, destination, *args, **kwargs)

        with patch.object(publisher, "restore_entry_noreplace", stop_at_the_file):
            self.assertRaises(KeyboardInterrupt, publisher.rollback, self.repo, self.recovery)
        self.assertTrue((self.repo / retired / "sub").is_dir())
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual((self.repo / retired / "sub/deep").read_text(), "keep")

    def test_interrupted_claim_of_a_vanished_directory_returns_it_with_its_saved_mode(self):
        retired = self.retire_directory()
        self.publish_while_directory_vanishes(retired, crash_before_recording=True)
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual((self.repo / retired / "note").read_text(), "keep")
        self.assertEqual((self.repo / retired).stat().st_mode & 0o777, 0o700)

    def test_directory_another_writer_removed_is_not_recreated_empty(self):
        retired = self.retire_directory()
        # Its only child was edited, so nothing journaled lives under the directory.
        (self.repo / retired / "note").write_text("edited independently")
        self.publish_while_directory_vanishes(retired)
        report = io.StringIO()
        with contextlib.redirect_stderr(report):
            self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertFalse((self.repo / retired).exists())
        self.assertIn("apps/retired was removed by another writer", report.getvalue())

    def test_altered_saved_directory_metadata_is_not_used_to_recreate_it(self):
        retired = self.retire_directory()
        self.publish_while_directory_vanishes(retired)
        (self.recovery / publisher.DIRECTORY_METADATA / retired).chmod(0o755)
        self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)

    def test_writer_returning_during_restore_keeps_both_versions(self):
        self.publish_while_editor_wins_final_install("independent")
        self.live.unlink()

        def writer_returns(source, destination, *_):
            destination.write_text("back again")
            raise FileExistsError(destination)

        with patch.object(publisher, "restore_claim_noreplace", writer_returns):
            self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.read_text(), "back again")
        self.assertEqual(self.claim(self.relative).read_text(), "original")

    def test_original_back_in_place_is_settled_even_if_its_claim_remains(self):
        self.publish_while_editor_wins_final_install("independent")
        self.live.unlink()

        def unlink_fails(source, destination, *_):
            os.link(source, destination)
            raise PermissionError(source)

        with patch.object(publisher, "restore_claim_noreplace", unlink_fails):
            self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.read_text(), "original")

    def test_malformed_unresolved_records_need_manual_recovery(self):
        for before in ("", ', "before": "oops"'):
            with self.subTest(before=before):
                (self.recovery / "journal.jsonl").write_text(
                    '{"path": "apps/gone", "operation": "write", "state": "unresolved"' + before + "}\n")
                self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)

    def test_file_where_a_new_directory_belongs_does_not_stop_other_paths(self):
        (self.candidate / "apps/added").mkdir()
        (self.candidate / "apps/added/child").write_text("captured")
        (self.repo / "apps/added").write_text("independent")
        self.assertNotEqual(self.publish(), 0)
        self.assertEqual((self.repo / "apps/added").read_text(), "independent")
        self.assertEqual(self.live.read_text(), "captured")

    def test_parent_directory_another_writer_removed_is_not_recreated_with_default_mode(self):
        kept = Path("apps/kept")
        for tree in (self.base, self.candidate, self.repo):
            (tree / kept).mkdir()
            (tree / kept).chmod(0o700)
        for tree in (self.base, self.repo):
            (tree / kept / "note").write_text("keep")
        self.assertEqual(self.publish(), 0)
        (self.repo / kept).rmdir()
        report = io.StringIO()
        with contextlib.redirect_stderr(report):
            self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertFalse((self.repo / kept).exists())
        self.assertIn("parent directory was removed by another writer", report.getvalue())
        self.assertEqual(self.live.read_text(), "original")
        # A directory made at that path later is not the one the file left.
        (self.repo / kept).mkdir(mode=0o700)
        report = io.StringIO()
        with contextlib.redirect_stderr(report):
            self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertIn("parent directory was replaced by another writer", report.getvalue())
        self.assertFalse((self.repo / kept / "note").exists())
        self.assertEqual((self.recovery / publisher.OBJECTS / kept / "note").read_text(), "keep")

    def test_root_level_file_returns_through_a_symlinked_checkout(self):
        for tree, content in ((self.base, "original"), (self.candidate, "captured"), (self.repo, "original")):
            (tree / "Brewfile").write_text(content)
        linked = self.repo.with_name("repo-link")
        linked.symlink_to(self.repo)
        publisher.record_directories(self.base, linked, ["Brewfile"])
        self.assertEqual(publisher.publish(self.base, self.candidate, linked, self.recovery, ["Brewfile"]), 0)
        self.assertEqual((self.repo / "Brewfile").read_text(), "captured")
        self.assertEqual(publisher.rollback(linked, self.recovery), 0)
        self.assertEqual((self.repo / "Brewfile").read_text(), "original")

    def test_interrupted_install_with_another_writers_file_stays_unsettled(self):
        append = publisher.journal_append

        def stop_before_recording(path, record):
            if record["state"] == "unresolved":
                raise KeyboardInterrupt
            return append(path, record)

        self.editor.write_text("independent")
        link = os.link

        def editor_wins(src, dst, *args, **kwargs):
            if self.is_destination(dst, kwargs, self.live):
                os.replace(self.editor, self.live)
            return link(src, dst, *args, **kwargs)

        with patch.object(os, "link", editor_wins), patch.object(publisher, "journal_append", stop_before_recording):
            self.assertRaises(KeyboardInterrupt, self.publish)
        self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.read_text(), "independent")
        self.assertEqual(self.claim(self.relative).read_text(), "original")

    def test_failed_restore_after_an_interrupted_claim_is_reported_then_retried(self):
        link = os.link

        def stop_at_install(src, dst, *args, **kwargs):
            if self.is_destination(dst, kwargs, self.live):
                raise KeyboardInterrupt
            return link(src, dst, *args, **kwargs)

        with patch.object(os, "link", stop_at_install):
            self.assertRaises(KeyboardInterrupt, self.publish)
        self.assertFalse(self.live.exists())

        def cannot_restore(source, destination, *_):
            raise PermissionError(destination)

        with patch.object(publisher, "restore_claim_noreplace", cannot_restore):
            self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertFalse(self.live.exists())
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.read_text(), "original")

    def test_file_at_a_saved_directory_path_is_never_adopted(self):
        retired = self.retire_directory()
        saved = self.recovery / publisher.DIRECTORY_METADATA / retired
        saved.parent.mkdir(parents=True)
        saved.write_text("not this run's directory")
        self.assertRaises(RuntimeError, self.publish)
        self.assertEqual(saved.read_text(), "not this run's directory")

    def test_original_returns_once_the_conflicting_writer_leaves(self):
        self.publish_while_editor_wins_final_install("independent")
        self.live.unlink()
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.read_text(), "original")
        # A retry must not report the restored original as still in conflict.
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.read_text(), "original")

    def test_unapplied_candidate_never_owns_an_equal_editor_save(self):
        self.assert_final_install_preserves_editor("captured")

    def test_legacy_journal_requires_manual_recovery(self):
        # A recovery directory left by the previous publisher has no ownership witness.
        (self.recovery / "journal.jsonl").write_text(
            '{"path": "apps/settings", "before": null, "after": {"kind": "file"}}\n'
        )
        self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.read_text(), "original")

    def test_directory_mode_round_trip_keeps_independent_children(self):
        for tree in (self.base, self.candidate, self.repo):
            (tree / "apps").chmod(0o755)
        (self.candidate / "apps").chmod(0o700)
        extra = self.repo / "apps/editor-only"
        extra.write_text("keep")

        self.assertEqual(self.publish(), 0)
        self.assertEqual((self.repo / "apps").stat().st_mode & 0o777, 0o700)
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual((self.repo / "apps").stat().st_mode & 0o777, 0o755)
        self.assertEqual(extra.read_text(), "keep")

    def test_rollback_refuses_damaged_directory_metadata_until_repaired(self):
        for tree, mode in ((self.base, 0o700), (self.repo, 0o700), (self.candidate, 0o750)):
            (tree / "apps").chmod(mode)
        self.assertEqual(self.publish(), 0)
        saved = self.recovery / publisher.DIRECTORY_METADATA / "apps"
        saved.chmod(0o755)
        directory = self.live.parent
        (directory / "note").write_text("keep")
        for attempt in range(2):
            with self.subTest(attempt=attempt):
                self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
                self.assertEqual(directory.stat().st_mode & 0o777, 0o750)
                self.assertEqual(self.live.read_text(), "original")
        saved.chmod(0o700)
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(directory.stat().st_mode & 0o777, 0o700)
        self.assertEqual((directory / "note").read_text(), "keep")

    def test_directory_rollback_applies_the_verified_metadata_and_checks_the_result(self):
        directory = self.live.parent
        for tree, mode in ((self.base, 0o700), (self.repo, 0o700), (self.candidate, 0o750)):
            (tree / "apps").chmod(mode)
        self.assertEqual(self.publish(), 0)
        with patch.object(publisher, "apply_directory_metadata_fd", return_value=None):
            self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(directory.stat().st_mode & 0o777, 0o750)

        saved = self.recovery / publisher.DIRECTORY_METADATA / "apps"
        apply_metadata = publisher.apply_directory_metadata_fd
        def change_saved_copy_during_apply(source, directory_fd, *, apply_step):
            saved.chmod(0o755)
            apply_metadata(source, directory_fd, apply_step=apply_step)

        with patch.object(publisher, "apply_directory_metadata_fd", change_saved_copy_during_apply):
            self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(directory.stat().st_mode & 0o777, 0o700)
        self.assertEqual(saved.stat().st_mode & 0o777, 0o755)

    def interrupt_metadata_step(self, field, *, attribute=None, after_write=False):
        real_apply = publisher.apply_directory_metadata_fd

        def apply(source, destination_fd, *, apply_step):
            def interrupt(write, name, value, key=None):
                if (name, key) == (field, attribute):
                    def interrupted():
                        if after_write:
                            write()
                        raise OSError(errno.EINTR, "fixture interrupted a directory metadata syscall")
                    apply_step(interrupted, name, value, key)
                else:
                    apply_step(write, name, value, key)
            real_apply(source, destination_fd, apply_step=interrupt)

        return patch.object(publisher, "apply_directory_metadata_fd", apply)

    def prepare_directory_metadata(self):
        saved = {"com.example.old": "saved only", "com.example.shared": "saved"}
        captured = {"com.example.new": "captured only", "com.example.shared": "captured"}
        for tree, mode, attributes in ((self.base, 0o700, saved), (self.repo, 0o700, saved),
                                      (self.candidate, 0o755, captured)):
            directory = tree / "apps"
            directory.chmod(mode)
            for name, value in attributes.items():
                subprocess.run(["/usr/bin/xattr", "-w", name, value, directory], check=True)
        subprocess.run(["/bin/chmod", "+a", "everyone allow readattr", self.candidate / "apps"], check=True)

    @unittest.skipUnless(sys.platform == "darwin", "requires macOS metadata")
    def test_retry_resumes_between_xattr_mode_and_acl_writes(self):
        self.prepare_directory_metadata()
        original = publisher.fingerprint(self.live.parent)
        self.assertEqual(self.publish(), 0)
        # Interrupt after removing an attribute, then again before chmod, then
        # after the ACL syscall (before that last step can be checked).
        with self.interrupt_metadata_step("xattrs", attribute="com.example.new", after_write=True):
            self.assertEqual(publisher.rollback(self.repo, self.recovery), 1)
        with self.interrupt_metadata_step("mode"):
            self.assertEqual(publisher.rollback(self.repo, self.recovery), 1)
        current = publisher.fingerprint(self.live.parent)
        self.assertEqual(current["xattrs"], original["xattrs"])
        self.assertEqual(current["mode"], 0o755)
        self.assertEqual(self.live.read_text(), "original")
        with self.interrupt_metadata_step("acl", after_write=True):
            self.assertEqual(publisher.rollback(self.repo, self.recovery), 1)
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(publisher.fingerprint(self.live.parent), original)

    @unittest.skipUnless(sys.platform == "darwin", "requires macOS metadata")
    def test_partial_publish_metadata_can_be_undone_without_adopting_later_edits(self):
        self.prepare_directory_metadata()
        original = publisher.fingerprint(self.live.parent)
        with self.interrupt_metadata_step("mode"):
            with self.assertRaisesRegex(OSError, "fixture interrupted"):
                self.publish()
        self.assertNotEqual(publisher.fingerprint(self.live.parent), original)
        # Another writer changes an independent field during the interruption.
        self.live.parent.chmod(0o750)
        self.live.write_text("independent editor save")
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 1)
        self.assertEqual(self.live.parent.stat().st_mode & 0o777, 0o750)
        self.live.parent.chmod(original["mode"])
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(publisher.fingerprint(self.live.parent), original)
        self.assertEqual(self.live.read_text(), "independent editor save")

    def test_metadata_changed_by_another_writer_before_the_syscall_survives(self):
        for tree, mode in ((self.base, 0o700), (self.repo, 0o700), (self.candidate, 0o755)):
            (tree / "apps").chmod(mode)
        append = publisher.journal_append
        raced = False

        def apply_concurrent_mode(journal, record):
            nonlocal raced
            append(journal, record)
            if record.get("metadata_step") and not raced:
                raced = True
                self.live.parent.chmod(0o755)

        with patch.object(publisher, "journal_append", apply_concurrent_mode):
            with self.assertRaisesRegex(RuntimeError, "directory metadata changed"):
                self.publish()
        self.assertTrue(raced)
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 1)
        self.assertEqual(self.live.parent.stat().st_mode & 0o777, 0o755)

    @unittest.skipUnless(sys.platform == "darwin", "requires macOS extended attributes")
    def test_attribute_only_change_publishes_and_rolls_back(self):
        attribute = "com.example.backup-fixture"
        (self.candidate / self.relative).write_text("original")
        for root, value in ((self.base, "old"), (self.repo, "old"), (self.candidate, "new")):
            subprocess.run(["/usr/bin/xattr", "-w", attribute, value, root / self.relative], check=True)

        def live_attribute():
            return subprocess.check_output(["/usr/bin/xattr", "-p", attribute, self.live], text=True).strip()

        self.assertEqual(self.publish(), 0)
        self.assertEqual(live_attribute(), "new")
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(live_attribute(), "old")

    def test_editor_arriving_during_rollback_keeps_its_file_and_the_original(self):
        self.assertEqual(self.publish(), 0)
        self.editor.write_text("newer save")
        identity = self.editor.stat().st_ino
        link = os.link
        live_parent = self.live.parent.stat()

        def save_before_restore(src, dst, *args, **kwargs):
            parent_fd = kwargs.get("dst_dir_fd")
            pinned_parent = os.fstat(parent_fd) if parent_fd is not None else None
            if (dst == self.live.name and pinned_parent is not None
                    and (pinned_parent.st_dev, pinned_parent.st_ino) == (live_parent.st_dev, live_parent.st_ino)
                    and self.editor.exists()):
                os.replace(self.editor, self.live)
            return link(src, dst, *args, **kwargs)

        with patch.object(os, "link", save_before_restore):
            self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.stat().st_ino, identity)
        self.assertEqual(self.live.read_text(), "newer save")
        self.assertEqual((self.recovery / "originals" / self.relative).read_text(), "original")

    def test_deleting_nested_directory_can_be_rolled_back(self):
        for tree in (self.base, self.repo):
            folder = tree / "apps/retired"
            folder.mkdir(mode=0o700)
            (folder / "last").write_text("old snapshot")

        self.assertEqual(self.publish(), 0)
        folder = self.repo / "apps/retired"
        self.assertFalse(folder.exists())
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual((folder / "last").read_text(), "old snapshot")
        self.assertEqual(folder.stat().st_mode & 0o777, 0o700)
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual((folder / "last").read_text(), "old snapshot")

    def test_editor_save_after_link_is_not_recorded_as_the_publishers_inode(self):
        link = os.link
        self.editor.write_text("captured")
        identity = self.editor.stat().st_ino

        def edit_after_link(src, dst, *args, **kwargs):
            result = link(src, dst, *args, **kwargs)
            if self.is_destination(dst, kwargs, self.live):
                os.replace(self.editor, self.live)
            return result

        with patch.object(os, "link", edit_after_link):
            self.publish()
        self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.stat().st_ino, identity)
        self.assertEqual((self.recovery / "originals" / self.relative).read_text(), "original")

    def test_deleted_path_uses_verified_claim_when_saved_copy_is_corrupt(self):
        (self.candidate / self.relative).unlink()
        self.assertEqual(self.publish(), 0)
        original = self.recovery / publisher.OBJECTS / self.relative
        original.write_text("corrupt")
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.read_text(), "original")

    def test_replaced_files_use_verified_claims_on_rollback_retry(self):
        missing = Path("apps/missing-copy")
        for tree, value in ((self.base, "old"), (self.repo, "old"), (self.candidate, "new")):
            (tree / missing).write_text(value)
        self.assertEqual(self.publish(), 0)
        with patch.object(publisher, "restore_entry_noreplace", side_effect=OSError("restore interrupted")):
            self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        (self.recovery / publisher.OBJECTS / self.relative).write_text("damaged copy")
        (self.recovery / publisher.OBJECTS / missing).unlink()
        for attempt in range(2):
            with self.subTest(attempt=attempt):
                self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
                self.assertEqual(self.live.read_text(), "original")
                self.assertEqual((self.repo / missing).read_text(), "old")

    def test_replaced_file_waits_for_a_verified_original_before_vacating_it(self):
        self.assertEqual(self.publish(), 0)
        (self.recovery / publisher.OBJECTS / self.relative).write_text("damaged copy")
        claim = self.claim(self.relative)
        claim.write_text("editor save")
        self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.read_text(), "captured")
        self.assertEqual(claim.read_text(), "editor save")
        claim.rename(self.editor)
        (self.recovery / publisher.OBJECTS / self.relative).write_text("original")
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.editor.read_text(), "editor save")
        self.assertEqual(self.live.read_text(), "original")

    def test_deleted_path_fails_closed_when_both_original_copies_are_corrupt(self):
        (self.candidate / self.relative).unlink()
        self.assertEqual(self.publish(), 0)
        (self.recovery / publisher.OBJECTS / self.relative).write_text("corrupt")
        self.claim(self.relative).write_text("also corrupt")
        self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertFalse(self.live.exists())

    def test_retry_after_restore_failure_uses_owned_undo_claim(self):
        self.assertEqual(self.publish(), 0)
        with patch.object(publisher, "restore_entry_noreplace", side_effect=OSError("restore failed")):
            self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertFalse(self.live.exists())
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.read_text(), "original")
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)

    def test_retry_preserves_editor_save_after_restore_failure(self):
        self.assertEqual(self.publish(), 0)
        with patch.object(publisher, "restore_entry_noreplace", side_effect=OSError("restore failed")):
            self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.live.write_text("editor save")
        self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.read_text(), "editor save")
        self.assertEqual((self.recovery / publisher.OBJECTS / self.relative).read_text(), "original")

    def test_retry_keeps_unverified_undo_claim_for_inspection(self):
        self.assertEqual(self.publish(), 0)
        with patch.object(publisher, "restore_entry_noreplace", side_effect=OSError("restore failed")):
            self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        claimed = publisher.claim_slot(self.recovery / publisher.UNDO_CLAIMS, str(self.relative))
        self.editor.write_text("captured")
        os.replace(self.editor, claimed)
        self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertFalse(self.live.exists())
        self.assertEqual(claimed.read_text(), "captured")
        self.assertEqual((self.recovery / publisher.OBJECTS / self.relative).read_text(), "original")

    def test_torn_rollback_progress_record_stops_until_retry(self):
        next_path = Path("apps/second")
        for tree, content in ((self.base, "old"), (self.repo, "old"), (self.candidate, "new")):
            (tree / next_path).write_text(content)
        self.assertEqual(self.publish(), 0)
        append = publisher.journal_append
        interrupted = False

        def tear_progress_record(journal, record):
            nonlocal interrupted
            if not interrupted and record.get("state") == "cancelled":
                interrupted = True
                with journal.open("ab") as stream:
                    stream.write(b'{"path":"apps/second","state":')
                raise OSError("fixture interrupted rollback journal")
            append(journal, record)

        with patch.object(publisher, "journal_append", tear_progress_record):
            self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertTrue(interrupted)
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.read_text(), "original")
        self.assertEqual((self.repo / next_path).read_text(), "old")

    def test_torn_applied_record_recovers_this_and_previous_writes(self):
        next_path = Path("apps/second")
        for tree, content in ((self.base, "old"), (self.repo, "old"), (self.candidate, "new")):
            (tree / next_path).write_text(content)
        append = publisher.journal_append

        def tear_final_record(journal, record):
            if record["path"] == str(self.relative) and record["state"] == "applied":
                with journal.open("ab") as stream:
                    stream.write(b'{"path":"apps/settings","state":')
                raise OSError("short journal write")
            append(journal, record)

        with patch.object(publisher, "journal_append", tear_final_record):
            with self.assertRaisesRegex(OSError, "short journal write"):
                self.publish()
        self.assertEqual(self.live.read_text(), "captured")
        self.assertEqual((self.repo / next_path).read_text(), "new")
        with patch.object(publisher, "restore_entry_noreplace", side_effect=OSError("restore failed")):
            self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.read_text(), "original")
        self.assertEqual((self.repo / next_path).read_text(), "old")
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)

    def test_in_place_save_on_displaced_inode_survives_publication_and_rollback(self):
        link = os.link
        with self.live.open("r+b") as editor:
            def finish_save(src, dst, **options):
                if self.is_destination(dst, options, self.live):
                    editor.write(b"independent edit")
                    editor.truncate()
                    editor.flush()
                return link(src, dst, **options)
            with patch.object(os, "link", finish_save):
                self.assertNotEqual(self.publish(), 0)
        self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        claimed = publisher.claim_slot(self.recovery / publisher.CLAIMS, str(self.relative))
        self.assertEqual(claimed.read_bytes(), b"independent edit")
        self.assertEqual(self.live.read_text(), "original")

    def test_open_editor_saves_to_undone_installs_survive_rollback_and_retry(self):
        new = Path("apps/zz-new")
        first = Path("apps/first")
        (self.candidate / new).write_text("new file")
        for tree, value in ((self.base, "old"), (self.repo, "old"), (self.candidate, "new")):
            (tree / first).write_text(value)
        self.assertEqual(self.publish(), 0)

        append = publisher.journal_append
        paths = (new, self.relative)
        with contextlib.ExitStack() as stack:
            editors = {path: stack.enter_context((self.repo / path).open("r+b", buffering=0)) for path in paths}

            def save_after_undo(journal, record):
                append(journal, record)
                path = Path(record["path"])
                if record["state"] == "cancelled" and path in editors:
                    self.assertEqual((self.repo / first).read_text(), "new")
                    editors[path].write(f"editor save for {path}".encode())
                    editors[path].truncate()

            report = io.StringIO()
            with patch.object(publisher, "journal_append", save_after_undo), contextlib.redirect_stderr(report):
                self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.read_text(), "original")
        self.assertFalse((self.repo / new).exists())
        self.assertEqual((self.repo / first).read_text(), "old")
        retry = io.StringIO()
        with contextlib.redirect_stderr(retry):
            self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        for path in paths:
            retained = self.recovery / publisher.STAGED / path
            self.assertIn(str(retained), report.getvalue())
            self.assertIn(str(retained), retry.getvalue())
            self.assertEqual(retained.read_text(), f"editor save for {path}")
            retained.rename(self.editor.with_name(path.name))
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)

    def test_interrupted_new_directory_install_rolls_back(self):
        folder = Path("apps/new")
        (self.candidate / folder).mkdir()
        append = publisher.journal_append
        def interrupt(journal, record):
            if record["operation"] == "directory-create" and record["state"] == "applied":
                raise OSError("interrupted after install")
            append(journal, record)
        with patch.object(publisher, "journal_append", interrupt):
            with self.assertRaisesRegex(OSError, "interrupted after install"):
                self.publish()
        self.assertTrue((self.repo / folder).is_dir())
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertFalse((self.repo / folder).exists())

    def test_interrupted_install_restores_claimed_original(self):
        inode = self.live.stat().st_ino
        with patch.object(os, "link", side_effect=OSError("install failed")):
            with self.assertRaisesRegex(OSError, "install failed"):
                self.publish()
        self.assertFalse(self.live.exists())
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.stat().st_ino, inode)
        self.assertEqual(self.live.read_text(), "original")

    def test_interrupted_delete_restores_claimed_original(self):
        (self.candidate / self.relative).unlink()
        inode = self.live.stat().st_ino
        append = publisher.journal_append

        def fail_applied(journal, record):
            if record["state"] == "applied":
                raise OSError("journal failed")
            append(journal, record)

        with patch.object(publisher, "journal_append", fail_applied):
            with self.assertRaisesRegex(OSError, "journal failed"):
                self.publish()
        self.assertFalse(self.live.exists())
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.stat().st_ino, inode)
        self.assertEqual(self.live.read_text(), "original")

    def test_process_exit_after_install_can_restore_original(self):
        publisher.record_directories(self.base, self.repo, ["apps"])
        # Terminate without running Python cleanup, immediately after the OS
        # installs the name and before the publisher can write another record.
        program = """
import os, runpy, sys
from pathlib import Path
script, base, candidate, repo, recovery = map(Path, sys.argv[1:])
sys.path.insert(0, str(script.parent))
publish = runpy.run_path(str(script))['publish']
link = os.link
def interrupt(src, dst, *args, **kwargs):
    result = link(src, dst, *args, **kwargs)
    parent_fd = kwargs.get('dst_dir_fd')
    same_parent = False
    if parent_fd is not None:
        info = os.fstat(parent_fd)
        expected = (repo / 'apps').stat()
        same_parent = (info.st_dev, info.st_ino) == (expected.st_dev, expected.st_ino)
    if same_parent and Path(dst) == Path('settings'):
        os._exit(42)
    return result
os.link = interrupt
sys.exit(publish(base, candidate, repo, recovery, ['apps']))
"""
        child = subprocess.run(
            [sys.executable, "-B", "-c", program, SCRIPTS / "publish-app-backup.py",
             self.base, self.candidate, self.repo, self.recovery],
            capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(child.returncode, 42, child.stderr)
        self.assertEqual(self.live.read_text(), "captured")
        self.assertEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.read_text(), "original")

    def test_rollback_preserves_atomic_editor_save_even_if_bytes_match_publication(self):
        self.assertEqual(self.publish(), 0)
        self.editor.write_text("captured")
        identity = self.editor.stat().st_ino
        os.replace(self.editor, self.live)

        self.assertNotEqual(publisher.rollback(self.repo, self.recovery), 0)
        self.assertEqual(self.live.stat().st_ino, identity)
        self.assertEqual(self.live.read_text(), "captured")
        self.assertEqual((self.recovery / "originals" / self.relative).read_text(), "original")


if __name__ == "__main__":
    unittest.main()
