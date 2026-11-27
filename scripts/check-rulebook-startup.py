#!/usr/bin/env python3
"""Verify startup delivery, a bound checkpoint, and read-before-work ordering."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import sys

ADAPTER = Path(__file__).with_name("claude-rulebook.py").resolve()
spec = importlib.util.spec_from_file_location("rulebook_adapter", ADAPTER)
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)


def grade(trace, book, project, expected=(), forbidden=(), owner=None, state_dir=None):
    book = book.resolve()
    state_dir = (state_dir or Path.home() / ".claude/state/rulebook").resolve()
    groups, base = adapter.inventory(book)
    events = [json.loads(raw) for raw in trace.read_text().splitlines()]
    tools = {}
    finished = False
    cwd = sid = None
    loader_body = re.sub(r"^---\n.*?\n---\n", "", (book / "skills/init-rulebook/SKILL.md").read_text(), count=1, flags=re.S).strip()
    bodies = []
    for order, event in enumerate(events):
        if event.get("type") == "system" and event.get("subtype") == "init":
            cwd, sid = event.get("cwd"), event.get("session_id")
        if event.get("type") == "result":
            finished = event.get("subtype") == "success" and not event.get("is_error")
        if event.get("type") == "assistant":
            for block in event.get("message", {}).get("content", []):
                if block.get("type") == "tool_use":
                    tools[block["id"]] = {"name": block["name"], "input": block.get("input", {}), "start": order}
        if event.get("type") == "user":
            blocks = event.get("message", {}).get("content", [])
            if any(b.get("type") == "text" and loader_body in b.get("text", "") for b in blocks):
                bodies.append(order)
            results = [b for b in blocks if b.get("type") == "tool_result"]
            for result in results:
                tool = tools.get(result.get("tool_use_id"))
                if tool is not None:
                    response = event.get("tool_use_result", {}) if len(results) == 1 else {}
                    # Batched results have no single event-level Read response.
                    # Preserve each result's own numbered text for byte checking.
                    if len(results) > 1:
                        response = {"read_text": result.get("content")}
                    tool.update(end=order, error=bool(result.get("is_error")), response=response if isinstance(response, dict) else {})
    success = [t for t in tools.values() if "end" in t and not t["error"]]

    def control(tool):
        command = tool["input"].get("command", "")
        if tool["name"] != "Bash" or not isinstance(command, str) or any(c in command for c in adapter.SHELL_OPERATORS):
            return None
        try:
            words = shlex.split(command)
            interpreter = Path(words[0]) if words else Path()
            if (len(words) >= 12 and interpreter.is_absolute() and interpreter.is_file()
                    and os.access(interpreter, os.X_OK) and re.fullmatch(r"python(?:\d+(?:\.\d+)*)?", interpreter.name)
                    and Path(words[1]).resolve() == ADAPTER and words[2] == "--rulebook"
                    and Path(words[3]).resolve() == book and words[4] == "--state-dir"
                    and Path(words[5]).resolve() == state_dir
                    and words[6:8] == ["complete", "--session"] and words[8] == sid
                    and words[9] == "--generation" and words[11] == "--rules"
                    and all(not w.startswith("-") for w in words[12:])):
                return words
        except ValueError:
            pass
        return None

    def bootstrap(tool):
        name, value = tool["name"], tool["input"]
        if name == "Skill":
            return value.get("skill") == "init-rulebook"
        if name == "Read":
            path = adapter.relative(book, value.get("file_path"))
            if path in ("AGENTS.md", "skills/init-rulebook/SKILL.md"):
                return True
            if path and path.startswith("rules/"):
                top = Path(path).parts[1]
                return not groups.get(top, "").startswith("Action-gated") and top not in adapter.ACTION_REFERENCE_DIRS
        if name == "Glob":
            return adapter.relative(book, value.get("path")) == "rules" and value.get("pattern") in ("*", "*.md")
        return control(tool) is not None

    work = [t for t in success if not bootstrap(t)]
    first = min((t["start"] for t in work), default=len(events))
    full = {}
    reads = set()
    for tool in success:
        if tool["name"] != "Read":
            continue
        path = adapter.relative(book, tool["input"].get("file_path"))
        if path:
            reads.add(path)
        file = tool["response"].get("file", {})
        if (path and isinstance(file, dict) and file.get("startLine") == 1
                and type(file.get("totalLines")) is int and file["totalLines"] > 0
                and file.get("numLines") == file["totalLines"] and isinstance(file.get("content"), str)
                and file["content"].rstrip("\n") == (book / path).read_text().rstrip("\n")):
            full[path] = min(full.get(path, tool["end"]), tool["end"])
        elif path and (book / path).is_file():
            text = tool["response"].get("read_text")
            if isinstance(text, list):
                text = "\n".join(b.get("text", "") for b in text if b.get("type") == "text")
            if isinstance(text, str):
                rows = [re.fullmatch(r"\s*(\d+)(?:\t|→)(.*)", line) for line in text.rstrip("\n").splitlines()]
                numbered = [(int(m[1]), m[2]) for m in rows if m]
                lines = (book / path).read_text().splitlines()
                wanted = list(enumerate(lines, 1))
                # Read can include the final empty line after a terminal newline.
                if rows and all(rows) and numbered in (wanted, wanted + [(len(lines) + 1, "")]):
                    full[path] = min(full.get(path, tool["end"]), tool["end"])
    bodies += [full["skills/init-rulebook/SKILL.md"]] if "skills/init-rulebook/SKILL.md" in full else []
    checkpoints = []
    for tool in success:
        words = control(tool)
        # Claude can stream the next tool request before emitting this Bash
        # result. Require the checkpoint request first and all read deliveries
        # before that request; the adapter seals state before admitting work.
        # Its successful bound receipt is still mandatory, never invocation only.
        if words is None or tool["start"] >= first:
            continue
        try:
            receipt = json.loads(tool["response"].get("stdout", ""))
            selected = receipt["selected"]
            needed = adapter.required(book, selected, groups, base)
            evidence = receipt["evidence"]
            valid = (receipt.get("rulebook_ready") is True and receipt.get("rulebook") == str(book)
                     and Path(receipt.get("python", sys.executable)).resolve() == Path(words[0]).resolve()
                     and receipt.get("session") == sid and receipt.get("generation") == words[10]
                     and words[12:] == selected and receipt.get("required") == needed
                     and set(evidence) == set(needed) and any(i < tool["start"] for i in bodies)
                     and receipt.get("loader_sha256") == adapter.digest(book / "skills/init-rulebook/SKILL.md"))
            for path in needed:
                proof = evidence[path]
                valid = valid and proof.get("sha256") == adapter.digest(book / path)
                if proof.get("source") == "Read":
                    valid = valid and full.get(path, first) < tool["start"]
                else:
                    # Native delivery certificates are emitted by the exact
                    # adapter command only after InstructionsLoaded evidence.
                    valid = valid and path in base and proof.get("source") == "InstructionsLoaded"
            if valid:
                checkpoints.append(receipt)
        except (ValueError, KeyError, TypeError, AttributeError):
            continue
    selected = set(checkpoints[-1]["selected"]) if checkpoints else set()
    missing = sorted(path for path in expected if full.get(path, first) >= first)
    undeclared = sorted(set(expected) - selected)
    unwanted = sorted(set(forbidden) & reads)
    has_owner = not owner or any(t["name"] == "Skill" and t["input"].get("skill") == owner for t in success)
    project_matches = cwd is not None and Path(cwd).resolve() == project.resolve()
    result = {"completed": finished, "project_matches": project_matches,
              "loader_body_before_work": any(i < first for i in bodies), "checkpoint_before_work": bool(checkpoints),
              "missing_full_reads_before_work": missing, "undeclared_required": undeclared,
              "forbidden_reads": unwanted, "owner_used": has_owner}
    result["pass"] = finished and project_matches and bool(checkpoints) and not missing and not undeclared and not unwanted and has_owner
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--rulebook", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--require", nargs="*", default=[])
    parser.add_argument("--forbid", nargs="*", default=[])
    parser.add_argument("--owner")
    parser.add_argument("--state-dir", type=Path)
    args = parser.parse_args()
    result = grade(args.trace, args.rulebook, args.project, args.require, args.forbid, args.owner, args.state_dir)
    print(json.dumps(result, indent=2))
    return 0 if result["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
