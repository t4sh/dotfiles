#!/usr/bin/env python3
"""Restore the macOS gateway startup fallback after a Hermes runtime update."""
import argparse
import fcntl
from pathlib import Path
import subprocess


PATCH = Path(__file__).resolve().parents[1] / "apps/hermes/integration/macos-gateway.patch"
RUNTIME = "hermes_cli/gateway_launchd_runtime.py"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="report whether the fix is present")
    parser.add_argument("--hermes-root", type=Path, default=Path.home() / ".hermes/hermes-agent")
    args = parser.parse_args()
    root = args.hermes_root.resolve()

    def git(*argv):
        return subprocess.run(["git", "-C", str(root), *argv], capture_output=True, text=True)

    top = git("rev-parse", "--show-toplevel")
    if top.returncode or Path(top.stdout.strip()) != root:
        raise SystemExit(f"Expected a Hermes Git checkout at {root}")
    if git("ls-files", "--error-unmatch", "--", RUNTIME).returncode:
        raise SystemExit(f"Hermes no longer tracks {RUNTIME}. Review the gateway fix for this release.")

    def applied():
        return git("apply", "--reverse", "--check", str(PATCH)).returncode == 0

    if args.check:
        if not applied():
            raise SystemExit("Hermes gateway startup fix is missing or upstream changed.")
        print("Hermes gateway startup fix is present.")
        return

    # Share the native updater's checkout lock, including across linked worktrees.
    common = git("rev-parse", "--git-common-dir")
    common.check_returncode()
    with (root / common.stdout.strip() / "hermes-update.lock").open("a+b") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit("A Hermes update is running. Retry after it finishes.") from None
        conflicts = git("ls-files", "--unmerged")
        conflicts.check_returncode()
        if conflicts.stdout:
            raise SystemExit("Resolve the Hermes checkout's Git conflicts before repairing the gateway.")
        if applied():
            print("Hermes gateway startup fix is present.")
            return
        if git("diff", "--quiet", "HEAD", "--", RUNTIME).returncode:
            raise SystemExit(f"Local edits in {RUNTIME}. Review them before applying the gateway fix.")
        result = git("apply", str(PATCH))
        if result.returncode:
            raise SystemExit(f"Review the gateway patch against this Hermes release.\n{result.stderr.strip()}")
        if not applied():
            raise SystemExit("Could not verify the Hermes gateway patch after applying it.")
    print("Restored the Hermes gateway startup fix.")


if __name__ == "__main__":
    main()
