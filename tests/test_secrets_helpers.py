"""Exercise vault helpers with fake Keychain and clipboard implementations only."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipIf(os.name == "nt", "Mac terminal and clipboard helper fixtures")
class SecretsHelperTests(unittest.TestCase):
    def test_import_uses_native_prompt_without_secret_arguments(self):
        import pty
        import select
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            security = root / "security"
            security.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$ARG_LOG"\nexit "$FIXTURE_STATUS"\n')
            security.chmod(0o755)
            env = {**os.environ, "PATH": f"{root}:{os.defpath}", "USER": "fixture",
                   "ARG_LOG": str(root / "args")}
            for code in ("0", "17"):
                master, slave = pty.openpty()
                try:
                    proc = subprocess.Popen(
                        ["bash", str(ROOT / "scripts/secrets-pass-import.sh")], stdin=slave,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                        env={**env, "FIXTURE_STATUS": code},
                    )
                    # Bash's old hidden read flushes pre-prompt terminal input.
                    # Wait for prompt/output (or EOF) before feeding the fixture.
                    ready, _, _ = select.select([proc.stdout, proc.stderr], [], [], 2)
                    prefixes = {proc.stdout: b"", proc.stderr: b""}
                    for stream in ready:
                        prefixes[stream] = os.read(stream.fileno(), 4096)
                    os.write(master, b"fixture-only-password\n")
                    stdout, stderr = proc.communicate(timeout=5)
                    stdout = prefixes[proc.stdout] + stdout
                    stderr = prefixes[proc.stderr] + stderr
                    self.assertEqual(proc.returncode, int(code), stdout + stderr)
                finally:
                    os.close(master)
                    os.close(slave)
                args = (root / "args").read_text().splitlines()
                self.assertEqual(args[-2:], ["-U", "-w"])
                self.assertNotIn("fixture-only-password", args)
                self.assertIn("DotfilesSecretsVault", args)
            (root / "args").unlink()
            result = subprocess.run(["bash", str(ROOT / "scripts/secrets-pass-import.sh")],
                                    env=env, input="", text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / "args").exists())

    def test_copy_passes_secret_only_on_stdin_and_schedules_token_expiry(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, body in {
                "security": '#!/bin/sh\nprintf "%s" "$FIXTURE_PASSWORD"\nexit "$FIXTURE_STATUS"\n',
                "pbcopy": '#!/bin/sh\ncat > "$COPY_LOG"\n',
                "osascript": '''#!/bin/sh
if [ "$4" = copy ]; then
  cat > "$COPY_LOG"
  printf '41\n'
else
  printf '%s\n' "$@" > "$EXPIRY_LOG"
  exit "${FIXTURE_EXPIRY_STATUS:-0}"
fi
''',
            }.items():
                path = root / name
                path.write_text(body)
                path.chmod(0o755)
            env = {**os.environ, "PATH": f"{root}:{os.defpath}", "USER": "fixture",
                   "COPY_LOG": str(root / "copied"), "EXPIRY_LOG": str(root / "expiry"),
                   "FIXTURE_STATUS": "0", "FIXTURE_PASSWORD": "fixture-only-password"}
            result = subprocess.run(["bash", str(ROOT / "scripts/secrets-pass.sh")],
                                    env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual((root / "copied").read_text(), env["FIXTURE_PASSWORD"])
            deadline = time.monotonic() + 2
            while not (root / "expiry").exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue((root / "expiry").exists(), "Copied password needs an expiry job")
            args = (root / "expiry").read_text().splitlines()
            self.assertEqual(args[-2:], ["expire", "41"])
            self.assertNotIn(env["FIXTURE_PASSWORD"], args)
            self.assertNotIn(env["FIXTURE_PASSWORD"], result.stdout + result.stderr)
            failed_expiry = subprocess.run(
                ["bash", str(ROOT / "scripts/secrets-pass.sh")],
                env={**env, "FIXTURE_EXPIRY_STATUS": "17"},
                capture_output=True, text=True, timeout=5,
            )
            self.assertIn("best-effort", failed_expiry.stdout)
            self.assertIn("expiry failed; clear the clipboard manually", failed_expiry.stderr)
            for password, status in [("", "0"), ("fixture-only-password", "9")]:
                (root / "copied").unlink()
                result = subprocess.run(["bash", str(ROOT / "scripts/secrets-pass.sh")],
                                        env={**env, "FIXTURE_PASSWORD": password, "FIXTURE_STATUS": status},
                                        capture_output=True, text=True, timeout=5)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((root / "copied").exists())
                # The failing attempt never created a new copy file.
                (root / "copied").touch()

    def test_clipboard_expiry_preserves_newer_generations(self):
        node = Path.home() / ".local/bin/node-stable"
        if not node.exists():
            found = shutil.which("node")
            if not found:
                self.skipTest("Node unavailable for the JavaScript bridge fixture")
            node = Path(found)
        harness = r'''
const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
let count = 10, clears = 0, copied, waits = [], input = 'fixture-only-password';
const board = {
  get clearContents() { clears++; return ++count; },
  setStringForType(text) { copied = text; count++; return true; },
  get changeCount() { return count; }
};
function $(value) { return value; }
Object.assign($, {
  NSPasteboard: { generalPasteboard: board }, NSPasteboardTypeString: 'text',
  NSFileHandle: { fileHandleWithStandardInput: { get readDataToEndOfFile() { return input; } } },
  NSString: { alloc: { initWithDataEncoding(bytes) { return bytes; } } },
  NSUTF8StringEncoding: 4, NSThread: { sleepForTimeInterval(n) { waits.push(n); } }
});
const context = { $, ObjC: { import() {}, unwrap(value) { return value; } } };
vm.createContext(context); vm.runInContext(fs.readFileSync(process.argv[1], 'utf8'), context);
const token = context.run(['copy']); assert.equal(token, '12'); assert.equal(copied, input);
context.run(['expire', token]); assert.equal(clears, 2); assert.deepEqual(waits, [30]);
const newer = context.run(['copy']); const before = clears; count++; // user copied again
context.run(['expire', newer]); assert.equal(clears, before);
assert.throws(() => context.run(['expire', 'invalid']));
input = ''; assert.throws(() => context.run(['copy'])); assert.equal(clears, before);
'''
        result = subprocess.run([str(node), "-e", harness, str(ROOT / "scripts/secret-clipboard.js")],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
