#!/usr/bin/env python3
"""Claude Code load checkpoint; applicability remains owned by the rulebook/model.

Mac adapter. Session state contains paths/hashes, never prompts or tool contents.
"""
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import uuid

try:
    import fcntl
except ImportError:
    fcntl = None

SCRIPT = Path(__file__).resolve()
EVENTS = ("SessionStart", "UserPromptSubmit", "InstructionsLoaded", "PreToolUse", "PostToolUse", "Stop")
ACTION_REFERENCE_DIRS = ("attribution", "lifecycle")
SHELL_OPERATORS = "`$;&|<>\n\r"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory(root):
    index = root / "AGENTS.md"
    groups = {}
    for heading, body in re.findall(r"^## ([^\n]+)\n(.*?)(?=^## |\Z)", index.read_text(), re.M | re.S):
        for name in re.findall(r"\(\./rules/([^/)]+\.md)\)", body):
            if name in groups:
                raise ValueError("duplicate indexed rule")
            groups[name] = heading
    disk = {p.name for p in (root / "rules").glob("*.md") if p.is_file()}
    if not groups or disk != set(groups):
        raise ValueError("canonical rule inventory differs from index")
    always = ["rules/" + n for n, h in groups.items() if h == "Always on"]
    if not always or any(not (h == "Always on" or h.startswith(("Activate", "Action-gated"))) for h in groups.values()):
        raise ValueError("unclassified canonical rule")
    return groups, ["AGENTS.md", *always]


def write(path, data):
    content = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    if path.exists() and path.read_text() == content:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as f:
            temporary = Path(f.name)
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


@contextlib.contextmanager
def session(args, session_id):
    if fcntl is None:
        raise ValueError("this hook adapter requires POSIX file locking")
    if not isinstance(session_id, str) or not session_id:
        raise ValueError("missing session identity")
    args.state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    name = hashlib.sha256(session_id.encode()).hexdigest()
    path = args.state_dir / (name + ".json")
    with (args.state_dir / (name + ".lock")).open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        data = json.loads(path.read_text()) if path.exists() else {}
        if not isinstance(data, dict):
            raise ValueError("invalid checkpoint state; start a fresh session")
        try:
            yield data
        finally:
            write(path, data)


def relative(root, value):
    try:
        return str(Path(value).expanduser().resolve().relative_to(root))
    except (ValueError, TypeError):
        return None


def prefix(args):
    return [sys.executable, str(SCRIPT), "--rulebook", str(args.rulebook), "--state-dir", str(args.state_dir)]


def guidance(args, session_id, generation):
    command = shlex.join([*prefix(args), "complete", "--session", session_id,
                          "--generation", generation, "--rules"])
    return (
        "Rulebook checkpoint is closed. Invoke init-rulebook, or read its full loader at "
        + str(args.rulebook / "skills/init-rulebook/SKILL.md")
        + " if the skill is unavailable. Read the canonical index at " + str(args.rulebook / "AGENTS.md")
        + "; inventory with Glob path=" + str(args.rulebook / "rules") + " pattern=*.md. Use the index to choose "
        "only currently applicable rules and necessary references. Read them completely before project access. "
        "Native always-on imports count when observed; action gates remain just-in-time. "
        "After loading, run this Bash command followed by the selected rulebook-relative paths "
        "(for example rules/20-code-posture.md); use no paths when none apply: " + command
    )


def required(root, selected, groups, base):
    if not isinstance(selected, list) or not all(isinstance(n, str) for n in selected):
        raise ValueError("declare selected paths with complete --rules")
    for name in selected:
        path = root / name
        if (not name.startswith("rules/") or path.suffix != ".md" or relative(root, path) != name
                or any(part.startswith(".") for part in Path(name).parts) or not path.is_file()):
            raise ValueError("selected rule/reference must stay in canonical rules")
        top = Path(name).parts[1]
        if groups.get(top, "").startswith("Action-gated") or top in ACTION_REFERENCE_DIRS:
            raise ValueError("action gates cannot be preloaded by the startup checkpoint")
    return list(dict.fromkeys([*base, *selected]))


def pending(args, data, groups, base):
    if not data.get("started") or data.get("root") != str(args.rulebook):
        return ["fresh SessionStart initialization"]
    needed = required(args.rulebook, data.get("selected"), groups, base)
    missing = []
    loader = args.rulebook / "skills/init-rulebook/SKILL.md"
    if data.get("loader") != digest(loader):
        missing.append("init-rulebook")
    for name in needed:
        current = digest(args.rulebook / name)
        if current not in (data.get("reads", {}).get(name), data.get("native", {}).get(name)):
            missing.append(name)
    return missing


def is_completion(args, command, session_id, generation):
    # Only this literal control command may run before the checkpoint. Never
    # accept command substitution, redirection, pipelines or a shell suffix.
    if not isinstance(command, str) or any(c in command for c in SHELL_OPERATORS):
        return False
    try:
        words = shlex.split(command)
        expected = [*prefix(args), "complete", "--session", session_id,
                    "--generation", generation, "--rules"]
        return words[:len(expected)] == expected and all(not w.startswith("-") for w in words[len(expected):])
    except ValueError:
        return False


def full_read(args, event):
    response = event.get("tool_response", {})
    file = response.get("file", {}) if isinstance(response, dict) else {}
    name = relative(args.rulebook, event.get("tool_input", {}).get("file_path"))
    if (not name or not isinstance(file, dict) or file.get("startLine") != 1
            or type(file.get("totalLines")) is not int or file["totalLines"] < 1
            or file.get("numLines") != file["totalLines"]):
        return None
    path = args.rulebook / name
    if not path.is_file() or not isinstance(file.get("content"), str):
        return None
    # Read strips the final newline; compare the actual returned text, not just
    # its requested limit or a successful tool status.
    if file["content"].rstrip("\n") != path.read_text().rstrip("\n"):
        return None
    return name, digest(path)


def reset(data, root, source, native=None):
    data.clear()
    data.update(started=True, root=str(root), source=source, native=native or {}, reads={},
                selected=None, sealed=False, generation=uuid.uuid4().hex, inflight={},
                accept_native=source == "startup")


def system_prompt(event, prompt_id):
    """Use host transcript provenance, never the submitted message's wording.

    The message is not yet appended at UserPromptSubmit on some clients. Resolve
    again at the next main-agent tool/Stop, when delivery has been recorded.
    """
    path = event.get("transcript_path")
    if not prompt_id or not isinstance(path, str):
        return False
    try:
        with Path(path).open() as transcript:
            for line in transcript:
                entry = json.loads(line)
                if (entry.get("type") == "user" and entry.get("promptId") == prompt_id
                        and entry.get("promptSource") == "system"
                        and entry.get("turnOrigin") in ("peer", "task_notification")):
                    return True
    except (OSError, ValueError, AttributeError):
        pass
    return False


def stop_failure(event, message):
    if event.get("stop_hook_active"):
        return {"continue": False, "stopReason": message + " Project tools remain closed; repair the rulebook or hook setup."}
    return {"decision": "block", "reason": message}


def hook(args, event):
    if not isinstance(event, dict) or not isinstance(event.get("tool_input", {}), dict):
        raise ValueError("invalid hook payload")
    kind = event.get("hook_event_name")
    sid = event.get("session_id")
    # This adapter enforces the main session only. Child callbacks must neither
    # mutate parent proof nor receive a command that seals the parent's prompt.
    if event.get("agent_id"):
        if kind == "PreToolUse" and event.get("tool_name") == "Bash":
            command = event.get("tool_input", {}).get("command", "")
            if isinstance(command, str) and str(SCRIPT) in command and "complete" in command:
                return {"hookSpecificOutput": {"hookEventName": kind, "permissionDecision": "deny",
                    "permissionDecisionReason": "The main-agent checkpoint cannot be completed by a subagent."}}
        return {}
    with session(args, sid) as data:
        if kind == "SessionStart":
            # Native imports may be observed before the first SessionStart.
            native = (data.get("native", {}) if not data.get("started")
                      and event.get("source", "startup") == "startup" else {})
            reset(data, args.rulebook, event.get("source", "startup"), native)
        elif kind != "InstructionsLoaded" and (not data.get("started") or data.get("root") != str(args.rulebook)):
            # A failed/timed-out SessionStart is recoverable without /clear.
            # Do not certify old imports or reads in this recovery context.
            reset(data, args.rulebook, "recovery")
        if kind in ("PreToolUse", "Stop") and data.get("submitted_prompt"):
            submitted = data.pop("submitted_prompt")
            if not system_prompt(event, submitted["id"]):
                data.update(selected=None, sealed=False, generation=submitted["generation"], inflight={})
        if kind == "UserPromptSubmit":
            prompt_id = event.get("prompt_id")
            if system_prompt(event, prompt_id):
                return {}
            generation = uuid.uuid4().hex
            if isinstance(prompt_id, str) and prompt_id:
                data["submitted_prompt"] = {"id": prompt_id, "generation": generation}
            else:
                data.update(selected=None, sealed=False, generation=generation, inflight={})
            return {"hookSpecificOutput": {"hookEventName": kind, "additionalContext":
                "For a new user request, reselect applicable rules. System/peer reports do not open a new request. "
                + guidance(args, sid, generation)}}
        try:
            groups, base = inventory(args.rulebook)
        except (OSError, ValueError):
            message = "Canonical inventory is invalid. Read and repair the canonical AGENTS.md index before project work."
            if kind == "Stop":
                return stop_failure(event, message)
            if kind == "PreToolUse":
                value = event.get("tool_input", {})
                if (event.get("tool_name") in ("Read", "Edit", "Write")
                        and relative(args.rulebook, value.get("file_path")) == "AGENTS.md"):
                    return {}
                return {"hookSpecificOutput": {"hookEventName": kind, "permissionDecision": "deny", "permissionDecisionReason": message}}
            return {"hookSpecificOutput": {"hookEventName": kind, "additionalContext": message}} if kind == "SessionStart" else {}
        if kind == "SessionStart":
            return {"hookSpecificOutput": {"hookEventName": kind, "additionalContext": guidance(args, sid, data["generation"])}}
        if kind == "InstructionsLoaded":
            name = relative(args.rulebook, event.get("file_path"))
            if name in base and (not data.get("started") or data.get("accept_native")):
                data.setdefault("native", {})[name] = digest(args.rulebook / name)
            return {}
        if kind == "PostToolUse":
            observed = data.get("inflight", {}).pop(event.get("tool_use_id"), None)
            if observed is None or observed != data.get("generation"):
                return {}
            tool = event.get("tool_name")
            response = event.get("tool_response", {})
            if (tool == "Skill" and event.get("tool_input", {}).get("skill") == "init-rulebook"
                    and isinstance(response, dict) and response.get("success") is True
                    and response.get("commandName") == "init-rulebook"):
                data["loader"] = digest(args.rulebook / "skills/init-rulebook/SKILL.md")
            elif tool == "Read":
                proof = full_read(args, event)
                if proof:
                    name, value = proof
                    if name == "skills/init-rulebook/SKILL.md":
                        data["loader"] = value
                    elif name == "AGENTS.md" or name.startswith("rules/"):
                        data.setdefault("reads", {})[name] = value
            return {}
        try:
            missing = pending(args, data, groups, base)
        except ValueError:
            missing = ["selection declaration"]
        ready = data.get("sealed") and not missing
        instructions = guidance(args, sid, data.get("generation", "missing-startup"))
        if kind == "Stop":
            return {} if ready else stop_failure(event, instructions)
        if kind != "PreToolUse":
            return {}
        tool = event.get("tool_name")
        value = event.get("tool_input", {})
        name = relative(args.rulebook, value.get("file_path")) if tool == "Read" else None
        def observe():
            tool_id = event.get("tool_use_id")
            if isinstance(tool_id, str) and tool_id and data.get("generation"):
                data.setdefault("inflight", {})[tool_id] = data["generation"]
            return {}
        if ready:
            if name or (tool == "Skill" and value.get("skill") == "init-rulebook"):
                return observe()
            return {}
        if tool == "Read" and name:
            if name == "AGENTS.md" or name == "skills/init-rulebook/SKILL.md":
                return observe()
            if (name.startswith("rules/") and Path(name).suffix == ".md"
                    and not any(part.startswith(".") for part in Path(name).parts)):
                top = Path(name).parts[1]
                if not groups.get(top, "").startswith("Action-gated") and top not in ACTION_REFERENCE_DIRS:
                    return observe()
        if (tool == "Glob" and relative(args.rulebook, value.get("path")) == "rules"
                and value.get("pattern") in ("*", "*.md")):
            return {}
        if tool == "Skill" and value.get("skill") == "init-rulebook":
            return observe()
        if tool == "Bash" and is_completion(args, value.get("command"), sid, data.get("generation", "missing-startup")):
            return {}
        reason = instructions + " Pending: " + ", ".join(missing)
        return {"hookSpecificOutput": {"hookEventName": kind, "permissionDecision": "deny", "permissionDecisionReason": reason}}


def definition(args):
    command = shlex.join([*prefix(args), "hook"])
    result = {}
    for event in EVENTS:
        entry = {"type": "command", "command": command, "timeout": 10}
        if event == "PreToolUse":
            entry["onFailure"] = "block"
        group = {"hooks": [entry]}
        if event in ("PreToolUse", "Stop", "InstructionsLoaded"):
            group["matcher"] = "*"
        if event == "PostToolUse":
            group["matcher"] = "Read|Skill"
        result[event] = [group]
    return result


def owned(entry):
    try:
        words = shlex.split(entry.get("command", ""))
        return len(words) > 1 and Path(words[1]).name == SCRIPT.name and words[-1] == "hook"
    except (AttributeError, ValueError):
        return False


def configure(args):
    if fcntl is None:
        raise ValueError("this hook adapter is not installed on Windows")
    executable = args.claude or shutil.which("claude")
    if not executable:
        raise ValueError("Claude Code is required")
    version = subprocess.check_output([executable, "--version"], text=True, timeout=10)
    match = re.search(r"(\d+)\.(\d+)\.(\d+)", version)
    if not match or tuple(map(int, match.groups())) < (2, 1, 295):
        raise ValueError("Claude Code 2.1.295+ is required for fail-closed hook errors")
    path = args.settings.resolve()
    data = json.loads(path.read_text()) if path.exists() else {}
    if not isinstance(data, dict) or not isinstance(data.get("hooks", {}), dict):
        raise ValueError("settings/hooks must be objects")
    if data.get("disableAllHooks") is True or data.get("allowManagedHooksOnly") is True:
        raise ValueError("settings disable user hooks; preserve that setting and report the conflict")
    hooks = dict(data.get("hooks", {}))
    expected = definition(args)
    for event, groups in expected.items():
        existing = hooks.get(event, [])
        if not isinstance(existing, list) or any(not isinstance(g, dict) or not isinstance(g.get("hooks"), list) for g in existing):
            raise ValueError("invalid hook group")
        found = [{**g, "hooks": [h for h in g["hooks"] if owned(h)]} for g in existing if any(owned(h) for h in g["hooks"])]
        if args.action == "check" and found != groups:
            raise ValueError("startup hooks drifted; run make restore-claude-rulebook")
        kept = [{**g, "hooks": [h for h in g["hooks"] if not owned(h)]} for g in existing]
        hooks[event] = [g for g in kept if g["hooks"]] + groups
    if args.action == "restore":
        write(path, {**data, "hooks": hooks})
    print("Claude rulebook hooks: " + args.action + " OK")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("hook", "complete", "restore", "check"))
    parser.add_argument("--rulebook", type=Path, default=Path.home() / ".agents")
    parser.add_argument("--state-dir", type=Path, default=Path.home() / ".claude/state/rulebook")
    parser.add_argument("--settings", type=Path, default=Path.home() / ".claude/settings.json")
    parser.add_argument("--session")
    parser.add_argument("--generation")
    parser.add_argument("--rules", nargs="*", default=[])
    parser.add_argument("--claude")
    args = parser.parse_args()
    args.rulebook = args.rulebook.expanduser().resolve()
    args.state_dir = args.state_dir.expanduser().resolve()
    event = {}
    try:
        if args.action in ("restore", "check"):
            configure(args)
        elif args.action == "hook":
            event = json.load(sys.stdin)
            print(json.dumps(hook(args, event)))
        else:
            groups, base = inventory(args.rulebook)
            with session(args, args.session) as data:
                if not args.generation or args.generation != data.get("generation"):
                    print("Checkpoint belongs to a different prompt/context; use the current hook command.", file=sys.stderr)
                    return 2
                data.update(selected=args.rules, sealed=False)
                missing = pending(args, data, groups, base)
                if missing:
                    print("Complete reads still needed: " + ", ".join(missing), file=sys.stderr)
                    return 2
                data["sealed"] = True
                needed = required(args.rulebook, args.rules, groups, base)
                evidence = {name: {"sha256": digest(args.rulebook / name),
                    "source": "Read" if data.get("reads", {}).get(name) == digest(args.rulebook / name) else "InstructionsLoaded"}
                    for name in needed}
                print(json.dumps({"rulebook_ready": True, "rulebook": str(args.rulebook), "session": args.session,
                    "python": str(Path(sys.executable).resolve()),
                    "generation": args.generation, "selected": args.rules, "required": needed,
                    "loader_sha256": digest(args.rulebook / "skills/init-rulebook/SKILL.md"), "evidence": evidence}))
    except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError):
        # Settings/prompt/tool payloads may contain secrets. Do not echo parser
        # excerpts or arbitrary input in errors. PreToolUse fails closed.
        message = "Rulebook checkpoint failed; verify inventory, full reads and hook setup."
        if args.action == "hook" and isinstance(event, dict) and event.get("hook_event_name") == "Stop":
            print(json.dumps(stop_failure(event, message)))
            return 0
        print(message, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
