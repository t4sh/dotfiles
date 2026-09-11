"""Compact Windows skills CLI output; retain full diagnostics in the supplied log."""
import sys


def summarize(status, log, arguments):
    source = arguments[2] if len(arguments) > 2 else "skills"
    if status:
        print(f"  Failed to update skills from {source} (exit {status}); log: {log}")


if __name__ == "__main__":
    summarize(int(sys.argv[1]), sys.argv[2], sys.argv[3:])
