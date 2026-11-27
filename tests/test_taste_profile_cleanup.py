"""A browser launch owns only the temporary profile it creates."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
STABLE_NODE = Path.home() / ".local/bin/node-stable"
NODE = str(STABLE_NODE) if STABLE_NODE.exists() else shutil.which("node")


@unittest.skipUnless(NODE and os.name == "posix", "Requires Node and a POSIX process fixture")
class TasteProfileCleanupTests(unittest.TestCase):
    def test_launch_preserves_an_older_open_profile_and_cleans_its_own(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake = root / "chrome"
            fake.write_text("#!/bin/sh\nprintf 'DevTools listening on ws://fixture\\n' >&2\nexec /usr/bin/tail -f /dev/null\n")
            fake.chmod(0o755)
            fixture = root / "probe.mjs"
            fixture.write_text('''
import * as fs from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const {Browser} = await import(pathToFileURL(process.argv[2]));
globalThis.WebSocket = class {
  constructor() { queueMicrotask(() => this.onopen?.()); }
  send(raw) { const {id} = JSON.parse(raw); queueMicrotask(() => this.onmessage?.({data: JSON.stringify({id, result:{}})})); }
  close() {}
};
const profile = join(process.env.TASTE_SKILL_TMP, 'ad-chrome-older-active');
fs.mkdirSync(profile);
const lock = fs.openSync(join(profile, 'lockfile'), 'w+');
fs.writeFileSync(join(profile, 'sentinel'), 'preserve');
fs.utimesSync(profile, new Date(Date.now()-240000), new Date(Date.now()-240000));
let browser;
try {
  browser = await Browser.launch();
  assert.equal(fs.existsSync(join(profile, 'sentinel')), true, 'another active profile was deleted');
} finally {
  if (browser) await browser.close();
  fs.closeSync(lock);
}
assert.equal(fs.existsSync(browser.dir), false, 'own profile was not cleaned');
''')
            module = Path(os.environ.get("TASTE_CDP_MODULE", ROOT / "agents/skills/design-taste-frontend/scripts/lib/cdp.mjs"))
            result = subprocess.run([NODE, str(fixture), str(module)],
                                    env={**os.environ, "CHROME_PATH": str(fake), "TASTE_SKILL_TMP": directory},
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
