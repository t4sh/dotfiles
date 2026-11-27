"""Metadata preservation fixtures for the app backup publisher."""

import ctypes
import errno
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import backup_metadata


def set_fixture_xattr(path: Path, name: str, value: bytes, *, symlink: bool = False) -> None:
    if sys.platform == "darwin":
        lib = ctypes.CDLL(None, use_errno=True)
        setxattr = lib.setxattr
        setxattr.argtypes = [
            ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t,
            ctypes.c_uint32, ctypes.c_int,
        ]
        setxattr.restype = ctypes.c_int
        payload = ctypes.create_string_buffer(value)
        options = 0x0001 if symlink else 0
        if setxattr(os.fsencode(path), name.encode(), payload, len(value), 0, options) == 0:
            return
        error = ctypes.get_errno()
        if error in (errno.ENOTSUP, errno.EOPNOTSUPP, errno.EPERM):
            raise unittest.SkipTest(f"filesystem does not support fixture xattrs: {os.strerror(error)}")
        raise OSError(error, os.strerror(error), str(path))
    try:
        os.setxattr(path, name, value, follow_symlinks=not symlink)
    except (AttributeError, NotImplementedError):
        raise unittest.SkipTest("Python or filesystem does not support fixture xattrs")
    except OSError as error:
        if error.errno in (errno.ENOTSUP, errno.EOPNOTSUPP, errno.EPERM):
            raise unittest.SkipTest(f"filesystem does not support fixture xattrs: {error}")
        raise


class BackupMetadataTests(unittest.TestCase):
    def test_copy_file_preserves_content_mode_and_extended_attributes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.write_bytes(b"fixture bytes\x00")
            source.chmod(0o640)
            set_fixture_xattr(source, "com.example.backup-fixture", b"fixture\x00value")

            backup_metadata.copy_entry(source, destination)

            self.assertEqual(destination.read_bytes(), source.read_bytes())
            self.assertEqual(destination.stat().st_mode & 0o7777, 0o640)
            self.assertEqual(backup_metadata.fingerprint(destination), backup_metadata.fingerprint(source))

    def test_copy_symlink_preserves_target_and_extended_attributes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source-link"
            destination = root / "destination-link"
            target = root / "target"
            target.write_text("target data must remain unchanged")
            os.symlink(target.name, source)
            if hasattr(os, "lchmod"):
                os.lchmod(source, 0o755)
            set_fixture_xattr(source, "com.example.backup-link-fixture", b"link-data", symlink=True)

            backup_metadata.copy_entry(source, destination)

            self.assertTrue(destination.is_symlink())
            self.assertEqual(os.readlink(destination), target.name)
            self.assertEqual(
                destination.lstat().st_mode & 0o7777,
                source.lstat().st_mode & 0o7777,
            )
            self.assertEqual(backup_metadata.fingerprint(destination), backup_metadata.fingerprint(source))
            self.assertEqual(target.read_text(), "target data must remain unchanged")

    @unittest.skipUnless(sys.platform == "darwin", "macOS cp symlink metadata")
    def test_copy_symlink_preserves_attributes_when_cp_omits_them(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, destination = root / "source-link", root / "destination-link"
            source.symlink_to("missing-target")
            set_fixture_xattr(source, "com.example.backup-link-fixture", b"link-data", symlink=True)
            run = subprocess.run

            def copy_without_attributes(args, **kwargs):
                return run([args[0], "-X", *args[1:]], **kwargs)

            with patch.object(subprocess, "run", side_effect=copy_without_attributes):
                backup_metadata.copy_entry(source, destination)

            self.assertEqual(backup_metadata.fingerprint(destination), backup_metadata.fingerprint(source))

    def test_apply_directory_metadata_updates_only_directory_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir(mode=0o700)
            destination.mkdir(mode=0o755)
            source.chmod(0o700)
            destination.chmod(0o755)
            source_child = source / "child"
            source_child.write_text("source\n")
            destination_child = destination / "child"
            destination_child.write_text("destination\n")
            set_fixture_xattr(source, "com.example.backup-directory-fixture", b"source")
            set_fixture_xattr(destination, "com.example.backup-directory-fixture", b"stale")
            set_fixture_xattr(destination, "com.example.backup-extra-fixture", b"remove me")

            backup_metadata.apply_directory_metadata(source, destination)

            self.assertEqual(destination.stat().st_mode & 0o7777, 0o700)
            self.assertEqual(backup_metadata.fingerprint(destination)["xattrs"],
                             backup_metadata.fingerprint(source)["xattrs"])
            self.assertEqual(destination_child.read_text(), "destination\n")

    def test_apply_directory_metadata_fd_updates_an_open_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir(mode=0o700)
            destination.mkdir(mode=0o700)
            source.chmod(0o700)
            destination.chmod(0o700)
            set_fixture_xattr(source, "com.example.backup-directory-fd", b"source")

            descriptor = os.open(destination, os.O_RDONLY | os.O_DIRECTORY)
            try:
                backup_metadata.apply_directory_metadata_fd(source, descriptor)
            finally:
                os.close(descriptor)

            self.assertEqual(destination.stat().st_mode & 0o7777, 0o700)
            self.assertEqual(backup_metadata.fingerprint(destination)["xattrs"],
                             backup_metadata.fingerprint(source)["xattrs"])

    @unittest.skipUnless(sys.platform == "darwin", "macOS search-only xattr access")
    def test_fd_metadata_fails_closed_when_target_xattrs_cannot_be_enumerated(self):
        if os.geteuid() == 0:
            self.skipTest("root can enumerate owner-restricted xattrs")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            destination.chmod(0o300)
            set_fixture_xattr(source, "com.example.backup-directory-fd", b"source")
            descriptor = os.open(destination, backup_metadata.directory_search_flag() | os.O_DIRECTORY)
            try:
                with self.assertRaises(PermissionError):
                    backup_metadata.apply_directory_metadata_fd(source, descriptor)
            finally:
                os.close(descriptor)
                destination.chmod(0o700)

    def test_copy_directory_metadata_without_copying_children(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir(mode=0o711)
            source.chmod(0o711)
            set_fixture_xattr(source, "com.example.backup-empty-directory", b"yes")
            (source / "child").write_text("metadata-only source tree")

            backup_metadata.copy_entry(source, destination)

            self.assertTrue(destination.is_dir())
            self.assertFalse((destination / "child").exists())
            self.assertEqual(backup_metadata.fingerprint(destination), backup_metadata.fingerprint(source))

    @unittest.skipUnless(sys.platform == "darwin", "macOS quarantine metadata")
    def test_capture_retains_original_quarantine_record(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "document.wflow"
            copy = Path(temporary) / "captured"
            source.write_text("Automator fixture")
            record = b"0083;12345678;fixture;00000000-0000-0000-0000-000000000001"
            set_fixture_xattr(source, "com.apple.quarantine", record)

            backup_metadata.copy_entry(source, copy)

            self.assertEqual(backup_metadata.fingerprint(source), backup_metadata.fingerprint(copy))
            self.assertEqual(dict(backup_metadata._iter_xattrs(copy))["com.apple.quarantine"], record)

    def test_fingerprint_detects_mode_and_xattr_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "entry"
            path.write_text("same content")
            initial = backup_metadata.fingerprint(path)
            path.chmod(0o600)
            changed_mode = backup_metadata.fingerprint(path)
            self.assertNotEqual(initial, changed_mode)
            set_fixture_xattr(path, "com.example.backup-fingerprint", b"changed")
            self.assertNotEqual(changed_mode, backup_metadata.fingerprint(path))

    @unittest.skipUnless(sys.platform == "darwin", "macOS ACLs use the native copyfile API")
    def test_copy_file_preserves_extended_acl(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.write_text("fixture")
            result = shutil.which("chmod")
            self.assertIsNotNone(result)
            subprocess.run(
                [result, "+a", "everyone allow read", str(source)],
                check=True, capture_output=True, text=True,
            )

            source_fingerprint = backup_metadata.fingerprint(source)
            self.assertTrue(source_fingerprint.get("acl"))
            backup_metadata.copy_entry(source, destination)
            self.assertEqual(backup_metadata.fingerprint(destination), source_fingerprint)

    @unittest.skipUnless(sys.platform == "darwin", "macOS ACLs use native metadata APIs")
    def test_apply_directory_metadata_fd_copies_extended_acl(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            subprocess.run(
                [shutil.which("chmod"), "+a", "everyone allow read", str(source)],
                check=True, capture_output=True, text=True,
            )
            descriptor = os.open(destination, backup_metadata.directory_search_flag() | os.O_DIRECTORY)
            try:
                backup_metadata.apply_directory_metadata_fd(source, descriptor)
            finally:
                os.close(descriptor)

            self.assertEqual(backup_metadata.fingerprint(destination)["acl"],
                             backup_metadata.fingerprint(source)["acl"])


if __name__ == "__main__":
    unittest.main()
