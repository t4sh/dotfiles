"""Keep or ignore Brewfile dump declarations during backup."""
from io import StringIO
from pathlib import Path
import importlib.util
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load_module():
    path = ROOT / 'scripts/brewfile-review.py'
    spec = importlib.util.spec_from_file_location('brewfile_review', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


REVIEW = load_module()


class BrewfileReviewTests(unittest.TestCase):
    def test_keep_addition_inserts_after_last_matching_kind(self):
        saved = 'tap "one"\nbrew "git"\ncask "arc"\nmas "Pages", id: 1\n'
        candidate = saved + 'cask "homebrew-app"\n'
        answers = StringIO('y\n')
        result, kept, ignored = REVIEW.review(
            saved, candidate, interactive=True, stdin=answers, stdout=StringIO()
        )
        self.assertEqual(kept, 1)
        self.assertEqual(ignored, 0)
        self.assertEqual(
            result,
            'tap "one"\nbrew "git"\ncask "arc"\ncask "homebrew-app"\nmas "Pages", id: 1\n',
        )

    def test_ignore_addition_retains_saved_file(self):
        saved = 'brew "git"\n# keep this comment\ncask "arc"\n'
        candidate = 'brew "git"\ncask "arc"\ncask "homebrew-app"\n'
        answers = StringIO('n\n')
        result, kept, ignored = REVIEW.review(
            saved, candidate, interactive=True, stdin=answers, stdout=StringIO()
        )
        self.assertEqual((kept, ignored), (0, 1))
        self.assertEqual(result, saved)

    def test_comment_only_dump_retains_saved_file(self):
        saved = '# curated\nbrew "git"\n'
        candidate = '# dumped rewrite\nbrew "git"\n'
        result, kept, ignored = REVIEW.review(saved, candidate, override=False, interactive=False)
        self.assertEqual((kept, ignored), (0, 0))
        self.assertEqual(result, saved)

    def test_override_keeps_dump_including_new_cask(self):
        saved = 'cask "arc"\n'
        candidate = 'cask "arc"\ncask "homebrew-app"\n'
        result, kept, ignored = REVIEW.review(saved, candidate, override=True)
        self.assertEqual(result, candidate)
        self.assertEqual((kept, ignored), (1, 0))

    def test_noninteractive_drift_fails_closed(self):
        with self.assertRaises(ValueError) as raised:
            REVIEW.review('brew "git"\n', 'brew "git"\ncask "homebrew-app"\n')
        self.assertIn('OVERRIDE=1', str(raised.exception))

    def test_keep_line_change_and_ignore_addition(self):
        saved = 'cask "deskflow/tap/deskflow"\ncask "arc"\n'
        candidate = 'cask "deskflow/tap/deskflow", trusted: true\ncask "arc"\ncask "homebrew-app"\n'
        answers = StringIO('y\nn\n')
        stdout = StringIO()
        result, kept, ignored = REVIEW.review(
            saved, candidate, interactive=True, stdin=answers, stdout=stdout
        )
        self.assertEqual((kept, ignored), (1, 1))
        self.assertEqual(result, 'cask "deskflow/tap/deskflow", trusted: true\ncask "arc"\n')
        self.assertIn('Keep this change? [y/N]:', stdout.getvalue())
        self.assertNotIn('cask "homebrew-app"', result)

    def test_cli_override_writes_candidate(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            saved = root / 'saved'
            candidate = root / 'candidate'
            saved.write_text('cask "arc"\n')
            candidate.write_text('cask "arc"\ncask "homebrew-app"\n')
            env = {**os.environ, 'OVERRIDE': '1'}
            result = subprocess.run(
                [
                    'python3',
                    str(ROOT / 'scripts/brewfile-review.py'),
                    '--saved',
                    str(saved),
                    '--candidate',
                    str(candidate),
                ],
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('cask "homebrew-app"', candidate.read_text())

    def test_cli_without_tty_fails_on_new_cask(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            saved = root / 'saved'
            candidate = root / 'candidate'
            saved.write_text('cask "arc"\n')
            candidate.write_text('cask "arc"\ncask "homebrew-app"\n')
            result = subprocess.run(
                [
                    'python3',
                    str(ROOT / 'scripts/brewfile-review.py'),
                    '--saved',
                    str(saved),
                    '--candidate',
                    str(candidate),
                ],
                env={**os.environ, 'OVERRIDE': '0'},
                capture_output=True,
                text=True,
                stdin=subprocess.DEVNULL,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Brewfile review failed', result.stderr)
            self.assertEqual(candidate.read_text(), 'cask "arc"\ncask "homebrew-app"\n')


class BackupAppsReviewWiringTests(unittest.TestCase):
    def test_backup_dumps_then_reviews_with_override(self):
        makefile = (ROOT / 'Makefile').read_text()
        backup = makefile.split('\nbackup:', 1)[1].split('\n\n', 1)[0]
        self.assertIn('OVERRIDE="$(OVERRIDE)" bash scripts/backup-apps.sh', backup)
        apps = (ROOT / 'scripts/backup-apps.sh').read_text()
        self.assertIn('scripts/brewfile-review.py', apps)
        self.assertIn('--saved "$SOURCE_DOTFILES/Brewfile"', apps)
        self.assertIn('--candidate "$STAGE/Brewfile"', apps)


if __name__ == '__main__':
    unittest.main()
