"""Check the installer's account-shell decision without changing an account."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import shutil

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipIf(os.name == "nt", "POSIX shell fixture; no native Windows changes")
class AccountShellSetup(unittest.TestCase):
    @unittest.skipUnless(shutil.which("zsh"), "Zsh unavailable")
    def test_highlighting_loads_after_local_editor_widgets(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            lib = home / ".dotfiles/zsh/lib"
            lib.mkdir(parents=True)
            for name in ("20-plugins.zsh", "99-syntax-highlighting.zsh"):
                shutil.copy2(ROOT / "zsh/lib" / name, lib / name)
            (lib / "99-local.zsh").write_text(
                'fixture_widget() { :; }\nzle -N fixture-local-widget fixture_widget\n'
                'fixture_order+=(local)\n'
            )
            prefix = home / "brew"
            suggestions = prefix / "share/zsh-autosuggestions"
            highlighting = prefix / "share/zsh-syntax-highlighting"
            suggestions.mkdir(parents=True)
            highlighting.mkdir(parents=True)
            (suggestions / "zsh-autosuggestions.zsh").write_text(
                'fixture_order+=(suggestions)\n'
            )
            (highlighting / "zsh-syntax-highlighting.zsh").write_text(
                'typeset -gA ZSH_HIGHLIGHT_STYLES\n'
                'fixture_order+=(highlighting)\n'
                'fixture_widget_seen="${widgets[fixture-local-widget]-missing}"\n'
            )
            env = {**os.environ, "HOME": str(home), "ZDOTDIR": str(home),
                   "HOMEBREW_PREFIX": str(prefix), "FIXTURE_SOURCE": str(ROOT)}
            result = subprocess.run(
                ["zsh", "-dfc", 'typeset -a fixture_order; '
                 'source "$FIXTURE_SOURCE/zsh/zshrc"; '
                 'print -r -- "${(j: :)fixture_order}|$fixture_widget_seen"'],
                env=env, text=True, capture_output=True, timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(),
                             "suggestions local highlighting|user:fixture_widget")

    @unittest.skipUnless(shutil.which("zsh") and shutil.which("zoxide"), "Zsh/zoxide unavailable")
    def test_interactive_completion_registers_zoxide_before_any_late_reset(self):
        import pty
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            lib = home / ".dotfiles/zsh/lib"
            lib.mkdir(parents=True)
            for name in ("15-completion.zsh", "90-zoxide.zsh"):
                shutil.copy2(ROOT / "zsh/lib" / name, lib / name)
            env = {**os.environ, "HOME": str(home), "ZDOTDIR": str(home),
                   "FIXTURE_SOURCE": str(ROOT)}
            master, slave = pty.openpty()
            try:
                result = subprocess.run(
                    ["zsh", "-f", "-i", "-c",
                     'source "$FIXTURE_SOURCE/zsh/zshrc"; print -r -- "${_comps[cd]-missing}"'],
                    stdin=slave, env=env, text=True, capture_output=True, timeout=15,
                )
            finally:
                os.close(master)
                os.close(slave)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "__zoxide_z_complete")

    def test_account_state_overrides_inherited_shell_and_lookup_fails_closed(self):
        source = (ROOT / "install.sh").read_text()
        block = source.split("# 5. Default shell\n", 1)[1].split("# 6.", 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = root / "bin"
            scripts.mkdir()
            query = scripts / "dscacheutil"
            query.write_text(
                '#!/bin/sh\n: > "$FIXTURE_QUERY"\n'
                '[ "$FIXTURE_LOOKUP_FAIL" = 0 ] || exit 1\n'
                'printf "shell: %s\\n" "$FIXTURE_ACCOUNT_SHELL"\n'
            )
            change = scripts / "chsh"
            change.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$FIXTURE_CHSH"\n')
            query.chmod(0o755)
            change.chmod(0o755)
            env = {key: value for key, value in os.environ.items()
                   if key not in ("BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS")}
            env.update(PATH=str(scripts) + os.pathsep + os.defpath,
                       FIXTURE_QUERY=str(root / "queried"),
                       FIXTURE_CHSH=str(root / "changed"))
            cases = [
                ("/bin/zsh", "/bin/bash", "0", "0", 0, True),
                ("/bin/bash", "/bin/zsh", "0", "0", 0, False),
                ("/bin/zsh", "", "0", "0", 1, False),
                ("/bin/zsh", "/bin/bash", "1", "0", 1, False),
                ("/bin/bash", "/bin/bash", "1", "1", 0, False),
            ]
            for number, (inherited, account, failure, smoke, code, changes) in enumerate(cases):
                with self.subTest(case=number):
                    # Each case gets independent markers; no process may reach real chsh.
                    env.update(SHELL=inherited, FIXTURE_ACCOUNT_SHELL=account,
                               FIXTURE_LOOKUP_FAIL=failure,
                               FIXTURE_QUERY=str(root / f"query-{number}"),
                               FIXTURE_CHSH=str(root / f"change-{number}"))
                    result = subprocess.run(
                        ["/bin/bash", "-c", "set -euo pipefail\nBOOTSTRAP_SMOKE=" + smoke + "\n" + block],
                        env=env, text=True, capture_output=True, timeout=10,
                    )
                    self.assertEqual(result.returncode, code, result.stdout + result.stderr)
                    marker = Path(env["FIXTURE_CHSH"])
                    self.assertEqual(marker.exists(), changes)
                    if changes:
                        self.assertEqual(marker.read_text(), "-s /bin/zsh\n")
                    self.assertEqual(Path(env["FIXTURE_QUERY"]).exists(), smoke == "0")

    def test_installer_prompt_skips_cleanly_without_a_terminal(self):
        source = (ROOT / "install.sh").read_text()
        helper = source.split("prompt_yes_no() {", 1)[1].split("\n}\n", 1)[0]
        script = "prompt_yes_no() {" + helper + "\n}\n"
        script += 'if prompt_yes_no "fixture?"; then exit 9; else exit 0; fi\n'
        result = subprocess.run(
            ["/bin/bash", "-c", script], input="", text=True,
            capture_output=True, timeout=5,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("no interactive terminal; skipped: fixture?", result.stderr)


if __name__ == "__main__":
    unittest.main()
