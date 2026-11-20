"""Exercise the managed Browse installation without a network or browser profile."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def config_for(manifest, source_prefix, destination):
    rows = (ROOT / manifest).read_text().splitlines()
    source, = [row.split("\t")[0] for row in rows if row.endswith("\t" + destination)]
    if not source.startswith(source_prefix):
        raise ValueError(source)
    path = ROOT / source[len(source_prefix):]
    # These managed JSONC files use full-line comments.
    return path, json.loads("\n".join(line for line in path.read_text().splitlines()
                                      if not line.lstrip().startswith("//")))


class BrowseTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="browse fixture ")
        self.addCleanup(temp.cleanup)
        self.home = Path(temp.name)
        self.bin = self.home / ".local/bin"
        self.bin.mkdir(parents=True)
        self.live = self.home / ".config/opencode/opencode.jsonc"
        self.live.parent.mkdir(parents=True)
        self.source, self.mac = config_for("symlinks.tsv", "$DOTFILES/",
                                           "$HOME/.config/opencode/opencode.jsonc")
        self.live.symlink_to(self.source)
        self.env = dict(os.environ, HOME=str(self.home), PATH=f"{self.bin}:/usr/bin:/bin",
                        XDG_BIN_HOME=str(self.home / "elsewhere"),
                        OPENCODE_BROWSER_HOME=str(self.home / "other-runtime"))

    def tool(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/sh\nset -eu\n" + body + "\n")
        path.chmod(0o755)

    def target(self, name, success=True):
        result = subprocess.run(["make", name], cwd=ROOT, env=self.env,
                                capture_output=True, text=True, timeout=25)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)

    def test_platform_manifests_restore_permissions_and_mac_command(self):
        _, windows = config_for("config/windows-links.tsv", "${DOTFILES}/",
                                "${HOME}/.config/opencode/opencode.jsonc")
        self.assertEqual(self.mac["permissions"], windows["permissions"])
        self.assertNotIn("browse", windows.get("mcp", {}).get("servers", {}))
        server = self.mac["mcp"]["servers"]["browse"]
        command = [arg.replace("{env:HOME}", str(self.home)) for arg in server["command"]]
        self.assertEqual(command, [str(self.bin / "browse"), "mcp"])
        self.assertEqual(server["cwd"].replace("{env:HOME}", str(self.home)), str(self.home))

    def test_clean_install_and_repeat_leave_config_to_linker(self):
        installer = self.home / "installer"
        installer.write_text("""set -eu
test "$#" = 1 && test "$1" = --no-setup || exit 1
test -z "${OPENCODE_BROWSER_HOME:-}"
test "$XDG_BIN_HOME" = "$HOME/.local/bin"
printf '%s\\n' '#!/bin/sh' 'test "$1" = version' > "$XDG_BIN_HOME/browse"
chmod +x "$XDG_BIN_HOME/browse"
""")
        self.tool("curl", 'while [ "$1" != --output ]; do shift; done\ncp "$HOME/installer" "$2"')
        self.target("browse-install")
        self.tool("curl", "exit 99")
        self.target("browse-install")
        self.assertTrue(self.live.is_symlink())

    def test_failed_download_never_runs_partial_installer(self):
        self.tool("curl", """while [ "$1" != --output ]; do shift; done
echo 'touch "$HOME/partial-ran"' > "$2"
exit 18""")
        self.target("browse-install", success=False)
        self.assertFalse((self.home / "partial-ran").exists())
        self.assertFalse((self.bin / "browse").exists())

    def test_check_requires_managed_link_and_browse_connection(self):
        self.tool("browse", "exit 0")
        self.tool("opencode", "printf '%s\\n' '✓ other  connected' '✗ browse  failed'")
        self.target("browse-check", success=False)
        self.tool("opencode", """test "$*" = 'mcp list'
echo '✓ browse  connected'""")
        self.target("browse-check")
        self.live.unlink()
        self.live.write_bytes(self.source.read_bytes())
        self.target("browse-check", success=False)


if __name__ == "__main__":
    unittest.main()
