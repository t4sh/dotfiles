#!/usr/bin/env python3
"""Group Mac TCP listeners without connecting to or stopping their processes."""

import argparse
from pathlib import Path
import re
import subprocess
import sys


def listeners(text):
    rows = []
    pid, name = None, "unknown"
    for line in text.splitlines():
        if line.startswith("p") and line[1:].isdigit():
            pid, name = int(line[1:]), "unknown"
        elif line.startswith("c"):
            name = line[1:]
        elif line.startswith("n") and pid is not None:
            address = line[1:]
            port = address.rsplit(":", 1)[-1]
            if port.isdigit():
                row = (int(port), pid, name, address)
                if row not in rows:
                    rows.append(row)
    return sorted(rows)


def process_column(pids, column):
    result = subprocess.run(
        ["ps", "-ww", "-p", pids, "-o", "pid=," + column + "="],
        capture_output=True, text=True,
    )
    values = {}
    for line in result.stdout.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[0].isdigit():
            values[int(parts[0])] = parts[1]
    return values


def working_directories(text):
    values, pid = {}, None
    for line in text.splitlines():
        if line.startswith("p") and line[1:].isdigit():
            pid = int(line[1:])
        elif line.startswith("n") and pid is not None:
            values[pid] = line[1:]
    return values


def category(executable, arguments):
    # Match server commands, not arbitrary Node/Python processes or familiar ports.
    previews = (
        r"(?:^|[ /])(?:vite|astro|nuxt|nuxi|eleventy|webpack-dev-server|http-server)(?:[ /]|\.\w|$)",
        r"(?:^|[ /])next(?:\.js)?\s+(?:dev|start)(?:\s|$)",
        r"^next-server(?:\s|$)",
        r"^(?:\S*/)?(?:serve|live-server)(?:\s|$)",
        r"/(?:serve|live-server)/(?:build|bin)/\S+",
        r"/node_modules/\.bin/(?:serve|live-server)(?:\s|$)",
        r"(?:^|[ /])python[\d.]*(?:\s+\S+)*\s+-m\s+http\.server(?:\s|$)",
        r"(?:^|[ /])manage\.py\s+runserver(?:\s|$)",
        r"(?:^|[ /])flask\s+run(?:\s|$)",
        r"(?:^|[ /])(?:hugo|jekyll)\s+serve(?:r)?(?:\s|$)",
    )
    if any(re.search(pattern, arguments) for pattern in previews):
        return "Dev / preview servers (likely)"
    if executable.startswith(("/System/Library/", "/usr/libexec/", "/usr/sbin/")):
        return "macOS services"
    return "Other apps / unknown"


def display(value):
    # Never let process-controlled text emit terminal control sequences.
    return re.sub(r"[\x00-\x1f\x7f-\x9f]", "?", value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ports", nargs="*", type=int, metavar="PORT",
                        help="show only these ports (default: all TCP listeners)")
    args = parser.parse_args()
    if any(port < 1 or port > 65535 for port in args.ports):
        parser.error("ports must be between 1 and 65535")
    try:
        # Authenticate before capturing output so a password prompt stays visible.
        if subprocess.run(["sudo", "-v"]).returncode:
            return 1
        result = subprocess.run(
            ["sudo", "-n", "lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"],
            capture_output=True, text=True,
        )
        # lsof returns 1 with no diagnostics when nothing matches.
        if result.returncode and not (result.returncode == 1 and not result.stdout and not result.stderr):
            print("Could not inspect listeners: " + result.stderr.strip(), file=sys.stderr)
            return 1
        rows = [row for row in listeners(result.stdout) if not args.ports or row[0] in args.ports]
        if not rows:
            print("No matching TCP listeners.")
            return 0
        pids = ",".join(str(pid) for pid in sorted({row[1] for row in rows}))
        executables = process_column(pids, "comm")
        arguments = process_column(pids, "args")
        cwd_result = subprocess.run(
            ["sudo", "-n", "lsof", "-a", "-p", pids, "-d", "cwd", "-Fpn"],
            capture_output=True, text=True,
        )
        directories = working_directories(cwd_result.stdout)
        groups = {}
        for port, pid, name, address in rows:
            group = category(executables.get(pid, ""), arguments.get(pid, ""))
            groups.setdefault(group, []).append((port, pid, name, address))
        home = str(Path.home())
        for group in ("Dev / preview servers (likely)", "macOS services", "Other apps / unknown"):
            if group not in groups:
                continue
            print(group + ":")
            for port, pid, name, address in groups[group]:
                cwd = directories.get(pid, "unavailable (process exited or access denied)")
                if cwd == home or cwd.startswith(home + "/"):
                    cwd = "~" + cwd[len(home):]
                print(f"  PORT {port:<5}  {display(name)}  (PID {pid})  {display(address)}")
                print(f"              {display(cwd)}")
            print()
        print("Preview labels are inferred from process commands; other listeners may also be development tools.")
        return 0
    except OSError as error:
        print("Could not inspect listeners: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
