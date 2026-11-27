"""Regression tests for secrets restore input validation using disposable data."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
RESTORE = Path(os.environ.get("SECRETS_RESTORE_SCRIPT", ROOT / "scripts/secrets-restore.sh"))
STAMP = "20261020-123456"


@unittest.skipIf(os.name == "nt", "secrets restore requires the POSIX shell fixture")
class SecretsRestoreValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="secrets-restore-validation-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.target = self.home / ".secrets"
        self.target.mkdir()
        (self.target / "existing").write_text("preserve\n")
        self.source = self.root / "vault"
        self.snapshot = self.source / STAMP
        self.snapshot.mkdir(parents=True)

    def run_restore(
        self,
        mode: str,
        *,
        source: Path | None = None,
        payload: Path | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = {
            **os.environ,
            "HOME": str(self.home),
            "DOTFILES_RESTORE_SOURCE": str(source or self.source),
            "DOTFILES_SECRETS_DIR": str(self.target),
        }
        if payload is not None:
            env["DOTFILES_RESTORE_SECRETS_SOURCE"] = str(payload)
        else:
            env.pop("DOTFILES_RESTORE_SECRETS_SOURCE", None)
        return subprocess.run(
            ["bash", str(RESTORE), mode, STAMP],
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def assert_rejected_without_mutation(self, *, payload: Path | None = None) -> None:
        for mode in ("--check", "--apply"):
            with self.subTest(mode=mode):
                result = self.run_restore(mode, payload=payload)
                try:
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    existing = self.target / "existing"
                    self.assertEqual(
                        existing.read_text() if existing.is_file() else None,
                        "preserve\n",
                    )
                    self.assertFalse((self.target / "restored").exists())
                    self.assertEqual(list(self.home.glob(".*.restore-stage.*")), [])
                    self.assertEqual(list(self.home.glob(".*.restore-rollback.*")), [])
                finally:
                    # Keep each mode independent even when a vulnerable script
                    # unexpectedly applies to the disposable target.
                    if self.target.is_symlink() or self.target.is_file():
                        self.target.unlink()
                    elif self.target.exists():
                        shutil.rmtree(self.target)
                    self.target.mkdir()
                    (self.target / "existing").write_text("preserve\n")

    def test_rejects_symlink_child_in_legacy_payload(self) -> None:
        payload = self.snapshot / "Users/old-user/.secrets"
        payload.mkdir(parents=True)
        (payload / "restored").write_text("fixture\n")
        outside = self.root / "outside"
        outside.write_text("fixture only\n")
        (payload / "linked").symlink_to(outside)
        self.assert_rejected_without_mutation()

    def test_rejects_symlinked_payload_ancestor(self) -> None:
        external = self.root / "external"
        (external / "secrets").mkdir(parents=True)
        (external / "secrets/restored").write_text("fixture\n")
        (self.snapshot / "payload").symlink_to(external, target_is_directory=True)
        self.assert_rejected_without_mutation()

    def test_rejects_symlinked_selected_payload_root(self) -> None:
        external = self.root / "external"
        external.mkdir()
        (external / "restored").write_text("fixture\n")
        payload_parent = self.snapshot / "payload"
        payload_parent.mkdir()
        (payload_parent / "secrets").symlink_to(external, target_is_directory=True)
        self.assert_rejected_without_mutation()

    def test_rejects_symlinked_snapshot_root_with_or_without_receipt(self) -> None:
        for receipt in (False, True):
            with self.subTest(receipt=receipt):
                actual = self.root / f"actual-{receipt}"
                payload = actual / "payload/secrets"
                payload.mkdir(parents=True)
                (payload / "restored").write_text("fixture\n")
                if receipt:
                    entries = {
                        "payload": None,
                        "payload/secrets": None,
                        "payload/secrets/restored": hashlib.sha256(
                            b"fixture\n"
                        ).hexdigest(),
                    }
                    (actual / ".dotfiles-snapshot.json").write_text(
                        json.dumps({"schema": 1, "entries": entries})
                    )
                (self.source / STAMP).rmdir()
                (self.source / STAMP).symlink_to(actual, target_is_directory=True)
                self.assert_rejected_without_mutation()
                (self.source / STAMP).unlink()
                (self.source / STAMP).mkdir()

    def test_rejects_special_file_in_explicit_source(self) -> None:
        payload = self.root / "custom-source"
        payload.mkdir()
        (payload / "restored").write_text("fixture\n")
        if not hasattr(os, "mkfifo"):
            self.skipTest("FIFO creation is unavailable")
        os.mkfifo(payload / "endpoint")
        self.assert_rejected_without_mutation(payload=payload)

    def test_rejects_symlink_child_in_explicit_source_outside_snapshot(self) -> None:
        payload = self.root / "custom-source"
        payload.mkdir()
        (payload / "restored").write_text("fixture\n")
        outside = self.root / "outside"
        outside.write_text("fixture only\n")
        (payload / "linked").symlink_to(outside)
        self.assert_rejected_without_mutation(payload=payload)

    def test_rejects_dot_segment_path_that_changes_meaning_after_symlink(self) -> None:
        canonical = self.snapshot / "payload/secrets"
        canonical.mkdir(parents=True)
        (canonical / "restored").write_text("canonical fixture\n")

        redirected = self.root / "redirected/a"
        (redirected / "b").mkdir(parents=True)
        redirected_payload = redirected / "payload/secrets"
        redirected_payload.mkdir(parents=True)
        (redirected_payload / "restored").write_text("redirected fixture\n")
        (self.snapshot / "alias").symlink_to(redirected / "b", target_is_directory=True)

        # Lexical abspath collapses alias/.. into snapshot/payload, but the OS
        # follows alias first and then resolves .. to redirected/a.
        selected = self.snapshot / "alias/../payload/secrets"
        self.assert_rejected_without_mutation(payload=selected)

    def test_accepts_regular_legacy_and_explicit_payloads(self) -> None:
        legacy = self.snapshot / "Users/old-user/.secrets"
        legacy.mkdir(parents=True)
        (legacy / "restored").write_text("legacy fixture\n")
        checked = self.run_restore("--check")
        self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
        applied = self.run_restore("--apply")
        self.assertEqual(applied.returncode, 0, applied.stdout + applied.stderr)
        self.assertEqual((self.target / "restored").read_text(), "legacy fixture\n")

        # Preserve the existing explicit-source override, including a custom
        # path outside the snapshot, when it contains only ordinary files.
        custom = self.root / "custom-source"
        custom.mkdir()
        (custom / "restored").write_text("explicit fixture\n")
        checked = self.run_restore("--check", payload=custom)
        self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
        applied = self.run_restore("--apply", payload=custom)
        self.assertEqual(applied.returncode, 0, applied.stdout + applied.stderr)
        self.assertEqual((self.target / "restored").read_text(), "explicit fixture\n")

    def test_rejects_windows_before_mutating_disposable_target(self) -> None:
        result = subprocess.run(
            ["bash", str(RESTORE), "--apply", STAMP],
            env={
                **os.environ,
                "OS": "Windows_NT",
                "HOME": str(self.home),
                "DOTFILES_RESTORE_SOURCE": str(self.source),
                "DOTFILES_SECRETS_DIR": str(self.target),
            },
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("This is a macOS workflow", result.stderr)
        self.assertEqual((self.target / "existing").read_text(), "preserve\n")
        self.assertFalse((self.target / "restored").exists())
        self.assertEqual(list(self.home.glob(".*.restore-stage.*")), [])
        self.assertEqual(list(self.home.glob(".*.restore-rollback.*")), [])


if __name__ == "__main__":
    unittest.main()
