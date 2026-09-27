#!/usr/bin/env python3
"""Run dotfiles Python operations inside Hermes's selected dependency generation.

The installation launcher selects Python; Hermes bootstrap owns dependencies.
Only the Python argument forms used by the dotfiles integration are supported.
"""
import runpy
import sys
import os


def main():
    root, *args = sys.argv[1:]
    for name in ("PYTHONHOME", "PYTHONPATH", "VIRTUAL_ENV"):
        os.environ.pop(name, None)
    sys.path.insert(0, root)
    import hermes_bootstrap  # noqa: F401 -- selects and leases dependencies
    while args and args[0] in ("-B", "-u"):
        if args.pop(0) == "-B":
            sys.dont_write_bytecode = True
        else:
            for stream in (sys.stdout, sys.stderr):
                if hasattr(stream, "reconfigure"):
                    stream.reconfigure(write_through=True)
    if not args:
        raise SystemExit("A script, -c command, or -m module is required")
    if args[0] in ("-c", "-m"):
        if len(args) < 2:
            raise SystemExit("Missing Python command or module")
        kind, target, *rest = args
        sys.argv = ["-c" if kind == "-c" else target, *rest]
        if kind == "-c":
            exec(target, {"__name__": "__main__"})
        else:
            runpy.run_module(target, run_name="__main__", alter_sys=True)
    else:
        if args[0].startswith("-"):
            raise SystemExit("Unsupported Python option: " + args[0])
        sys.argv = args
        runpy.run_path(args[0], run_name="__main__")


if __name__ == "__main__":
    main()
