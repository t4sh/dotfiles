"""Missing plist keys must terminate vault discovery despite stdout diagnostics."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipIf(os.name == "nt", "POSIX shell fixture")
class VaultPlutilTests(unittest.TestCase):
    def test_missing_key_diagnostic_is_discarded_and_discovery_terminates(self):
        source = (ROOT / "scripts/secrets-backup.sh").read_text()
        start = source.index("resolve_selected_vault_attachment() {")
        function = source[start:source.index("\n}\n", start) + 2]
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            plutil = root / "plutil"
            plutil.write_text("#!/bin/sh\nprintf 'missing key diagnostic\\n'\nexit 1\n")
            plutil.chmod(0o755)
            vault = root / "vault"
            vault.touch()
            function = function.replace("/usr/bin/plutil", shlex.quote(str(plutil)))
            program = ("set -eu\n"
                       "hdiutil() { printf '<plist/>'; }\n"
                       f"VAULT={shlex.quote(str(vault))}\nMOUNT={shlex.quote(str(root / 'mount'))}\n"
                       + function + "\nstatus=0\nresolve_selected_vault_attachment || status=$?\nprintf '%s' \"$status\"\n")
            result = subprocess.run(["bash", "-c", program], capture_output=True,
                                    text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(result.stdout, "1")


if __name__ == "__main__":
    unittest.main()
