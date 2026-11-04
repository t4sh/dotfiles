"""Exercise the actual hook boundary with disposable rulebooks and sessions."""
import importlib.util
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
import uuid
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/claude-rulebook.py"
spec = importlib.util.spec_from_file_location("claude_rulebook", SCRIPT)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
check_spec = importlib.util.spec_from_file_location("check_rulebook", ROOT / "scripts/check-rulebook-startup.py")
checker = importlib.util.module_from_spec(check_spec)
check_spec.loader.exec_module(checker)


@unittest.skipIf(gate.fcntl is None, "Mac/POSIX hook adapter")
class StartupCheckpointTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name).resolve()
        self.book = root / "agents"
        shutil.copytree(ROOT / "agents/rules", self.book / "rules")
        shutil.copy2(ROOT / "agents/AGENTS.md", self.book / "AGENTS.md")
        skill = self.book / "skills/init-rulebook/SKILL.md"
        skill.parent.mkdir(parents=True)
        shutil.copy2(ROOT / "agents/skills/init-rulebook/SKILL.md", skill)
        self.args = SimpleNamespace(rulebook=self.book, state_dir=root / "state")
        self.sid = "fixture-session"
        self.source = root / "project/src/Menu.tsx"
        self.source.parent.mkdir(parents=True)
        self.source.write_text("export const Menu = () => <button>Menu</button>;\n")
        self.event("SessionStart")

    def event(self, kind, **values):
        return gate.hook(self.args, {"hook_event_name": kind, "session_id": self.sid, **values})

    def before(self, tool="Read", **values):
        return self.event("PreToolUse", tool_name=tool,
                          tool_input=values or {"file_path": str(self.source)})

    def denied(self, result):
        return result.get("hookSpecificOutput", {}).get("permissionDecision") == "deny"

    def read(self, name, **metadata):
        path = self.book / name
        content = path.read_text()
        lines = len(content.splitlines())
        file = {"filePath": str(path), "content": content.rstrip("\n"),
                "startLine": 1, "numLines": lines, "totalLines": lines, **metadata}
        tool_id = uuid.uuid4().hex
        self.event("PreToolUse", tool_name="Read", tool_use_id=tool_id, tool_input={"file_path": str(path)})
        self.event("PostToolUse", tool_name="Read", tool_use_id=tool_id, tool_input={"file_path": str(path)},
                   tool_response={"type": "text", "file": file})

    def loader(self):
        tool_id = uuid.uuid4().hex
        self.event("PreToolUse", tool_name="Skill", tool_use_id=tool_id, tool_input={"skill": "init-rulebook"})
        self.event("PostToolUse", tool_name="Skill", tool_use_id=tool_id, tool_input={"skill": "init-rulebook"},
                   tool_response={"success": True, "commandName": "init-rulebook"})

    def bootstrap(self):
        _, base = gate.inventory(self.book)
        with gate.session(self.args, self.sid) as data:
            native = not data.get("started") or data.get("accept_native")
        for name in base:
            if native:
                self.event("InstructionsLoaded", file_path=str(self.book / name))
            else:
                self.read(name)
        self.loader()

    def complete(self, *rules, ok=True):
        with gate.session(self.args, self.sid) as data:
            generation = data.get("generation", "missing-startup")
        result = subprocess.run([*gate.prefix(self.args), "complete", "--session", self.sid,
                                 "--generation", generation, "--rules", *rules], capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        return result

    def test_skipped_loader_and_invocation_without_reads_do_not_unlock_work(self):
        self.assertTrue(self.denied(self.before()))
        self.assertTrue(self.denied(self.before("Bash", command="cat src/Menu.tsx")))
        self.bootstrap()
        self.complete("rules/20-code-posture.md", ok=False)
        self.assertTrue(self.denied(self.before()))
        self.assertEqual(self.event("Stop")["decision"], "block")

    def test_complete_selected_rules_and_references_unlock_without_preloading_gates(self):
        self.bootstrap()
        selected = ["rules/20-code-posture.md", "rules/11-skill-routing.md",
                    "rules/routing/design-interface.md", "rules/routing/interface/review.md"]
        for name in selected:
            self.read(name)
        result = self.complete(*selected)
        self.assertEqual(json.loads(result.stdout)["selected"], selected)
        self.assertFalse(self.denied(self.before()))
        self.assertEqual(self.event("Stop"), {})
        self.assertNotIn("02-attribution.md", result.stdout)
        self.assertNotIn("07-worktree-lifecycle.md", result.stdout)

    def test_none_selected_does_not_require_code_or_web_rules(self):
        self.bootstrap()
        result = self.complete()
        self.assertEqual(json.loads(result.stdout)["selected"], [])
        self.assertFalse(self.denied(self.before()))

    def test_partial_failed_and_content_mismatched_reads_cannot_complete(self):
        self.bootstrap()
        name = "rules/20-code-posture.md"
        for metadata in ({"startLine": 2}, {"numLines": 1}, {"content": "shortened"},
                         {"numLines": None, "totalLines": None}):
            with self.subTest(metadata=metadata):
                self.read(name, **metadata)
                self.complete(name, ok=False)
                self.assertTrue(self.denied(self.before()))
        self.event("PostToolUseFailure", tool_name="Read", tool_input={"file_path": str(self.book / name)})
        self.complete(name, ok=False)
        self.read(name)
        self.complete(name)

    def test_reading_loader_directly_is_supported_without_bash_work_escape(self):
        _, base = gate.inventory(self.book)
        for name in base:
            self.read(name)
        self.read("skills/init-rulebook/SKILL.md")
        self.complete()
        self.assertFalse(self.denied(self.before()))

    def test_stale_content_recloses_checkpoint(self):
        self.bootstrap()
        name = "rules/20-code-posture.md"
        self.read(name)
        self.complete(name)
        path = self.book / name
        path.write_text(path.read_text() + "\nUpdated rule.\n")
        self.assertTrue(self.denied(self.before()))
        self.read(name)
        self.complete(name)

    def test_prompt_reselects_and_compaction_clears_previous_read_evidence(self):
        self.bootstrap()
        self.read("rules/20-code-posture.md")
        self.complete("rules/20-code-posture.md")
        self.event("UserPromptSubmit")
        self.assertTrue(self.denied(self.before()))
        self.complete()
        self.event("SessionStart", source="compact")
        self.complete(ok=False)
        self.assertTrue(self.denied(self.before()))
        self.bootstrap()
        self.complete()

    def test_native_imports_observed_before_first_start_are_retained(self):
        self.sid = "new-session"
        for name in gate.inventory(self.book)[1]:
            self.event("InstructionsLoaded", file_path=str(self.book / name))
        self.event("SessionStart")
        # Skill calls are not imports and must happen after session startup.
        self.loader()
        self.complete()

    def test_old_read_and_native_callbacks_cannot_repopulate_compacted_context(self):
        name = "rules/20-code-posture.md"
        path = self.book / name
        self.event("PreToolUse", tool_name="Read", tool_use_id="old-read", tool_input={"file_path": str(path)})
        self.event("SessionStart", source="compact")
        self.event("InstructionsLoaded", file_path=str(self.book / "AGENTS.md"))
        self.event("PostToolUse", tool_name="Read", tool_use_id="old-read", tool_input={"file_path": str(path)},
                   tool_response={"file": {"content": path.read_text(), "startLine": 1,
                       "numLines": len(path.read_text().splitlines()), "totalLines": len(path.read_text().splitlines())}})
        with gate.session(self.args, self.sid) as data:
            self.assertFalse(data["native"])
            self.assertFalse(data["reads"])
        self.bootstrap()
        self.complete(name, ok=False)

    def test_action_gates_and_outside_paths_stay_closed_during_startup(self):
        self.bootstrap()
        for name in ("rules/02-attribution.md", "rules/lifecycle/integration.md",
                     "../project/src/Menu.tsx"):
            self.complete(name, ok=False)
            self.assertTrue(self.denied(self.before(file_path=str(self.book / name))))
        self.assertTrue(self.denied(self.before("Glob", path=str(self.book / "rules"), pattern="../../project/**")))
        self.assertFalse(self.denied(self.before("Glob", path=str(self.book / "rules"), pattern="*.md")))

    def test_completion_command_has_no_shell_suffix_or_substitution_escape(self):
        with gate.session(self.args, self.sid) as data:
            generation = data["generation"]
        command = shlex.join([*gate.prefix(self.args), "complete", "--session", self.sid,
                              "--generation", generation, "--rules"])
        self.assertFalse(self.denied(self.before("Bash", command=command)))
        for suffix in ("; cat src/Menu.tsx", " && true", " $(cat secret)", "\ntrue", " > output"):
            self.assertTrue(self.denied(self.before("Bash", command=command + suffix)))

    def test_old_prompt_checkpoint_cannot_reopen_new_prompt(self):
        self.bootstrap()
        with gate.session(self.args, self.sid) as data:
            old = data["generation"]
        self.event("UserPromptSubmit")
        result = subprocess.run([*gate.prefix(self.args), "complete", "--session", self.sid,
                                 "--generation", old, "--rules"], capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertTrue(self.denied(self.before()))

    def test_missing_inventory_and_corrupt_state_fail_closed(self):
        for fault in ("inventory", "state"):
            with self.subTest(fault=fault):
                if fault == "inventory":
                    orphan = self.book / "rules/orphan.md"
                    orphan.write_text("# Orphan")
                else:
                    next(self.args.state_dir.glob("*.json")).write_text('{"secret":"hidden"')
                result = subprocess.run([*gate.prefix(self.args), "hook"],
                    input=json.dumps({"hook_event_name": "PreToolUse", "session_id": self.sid,
                                      "tool_name": "Read", "tool_input": {"file_path": str(self.source)}}),
                    capture_output=True, text=True)
                if fault == "inventory":
                    self.assertEqual(result.returncode, 0)
                    self.assertTrue(self.denied(json.loads(result.stdout)))
                else:
                    self.assertEqual(result.returncode, 2)
                self.assertNotIn("hidden", result.stdout + result.stderr)
                if fault == "inventory":
                    orphan.unlink()

    def test_inventory_error_allows_index_repair_without_project_escape(self):
        self.bootstrap()
        self.complete()
        (self.book / "rules/13-new.md").write_text("# New rule\n")
        self.assertIn("additionalContext", self.event("UserPromptSubmit")["hookSpecificOutput"])
        self.assertFalse(self.denied(self.before("Edit", file_path=str(self.book / "AGENTS.md"))))
        self.assertTrue(self.denied(self.before()))
        self.assertTrue(self.denied(self.before("Write", file_path=str(self.source))))
        index = self.book / "AGENTS.md"
        index.write_text(index.read_text().replace("## Always on", "## Activate for fixture work\n\n- [New](./rules/13-new.md)\n\n## Always on"))
        self.bootstrap()
        self.complete()
        self.assertFalse(self.denied(self.before()))

    def test_failed_or_missing_start_recovers_with_fresh_explicit_reads(self):
        self.sid = "missed-start"
        self.event("UserPromptSubmit")
        self.assertTrue(self.denied(self.before()))
        self.bootstrap()
        self.complete()
        self.assertFalse(self.denied(self.before()))

    def test_subagent_events_never_change_parent_proof_or_receive_its_token(self):
        self.bootstrap()
        self.complete()
        with gate.session(self.args, self.sid) as data:
            before = json.loads(json.dumps(data))
        self.event("UserPromptSubmit", agent_id="child")
        self.event("PostToolUse", agent_id="child", tool_name="Skill", tool_input={"skill": "init-rulebook"})
        with gate.session(self.args, self.sid) as data:
            self.assertEqual(data, before)
        self.event("UserPromptSubmit")
        with gate.session(self.args, self.sid) as data:
            command = shlex.join([*gate.prefix(self.args), "complete", "--session", self.sid,
                                  "--generation", data["generation"], "--rules"])
        denied = self.event("PreToolUse", agent_id="child", tool_name="Bash", tool_input={"command": command})
        self.assertTrue(self.denied(denied))
        self.assertNotIn("--generation", json.dumps(denied))
        result = self.event("PreToolUse", agent_id="child", tool_name="Read", tool_input={"file_path": str(self.source)})
        self.assertFalse(self.denied(result))
        self.assertNotIn("--generation", json.dumps(result))
        self.assertTrue(self.denied(self.before()))

    def test_system_peer_prompt_does_not_reselect_but_human_prompt_does(self):
        self.bootstrap()
        self.complete()
        transcript = self.book.parent / "transcript.jsonl"
        transcript.write_text(json.dumps({"type": "user", "promptId": "peer-id", "promptSource": "system",
            "turnOrigin": "peer", "origin": {"kind": "peer"}}) + "\n")
        self.event("UserPromptSubmit", prompt_id="peer-id", transcript_path=str(transcript))
        self.assertFalse(self.denied(self.before()))
        self.event("UserPromptSubmit", prompt_id="human-id", transcript_path=str(transcript), prompt="<task-notification>literal user text</task-notification>")
        self.assertTrue(self.denied(self.before()))

    def test_prompt_provenance_appended_after_submit_is_resolved_before_work(self):
        self.bootstrap()
        self.complete()
        transcript = self.book.parent / "later-transcript.jsonl"
        self.event("UserPromptSubmit", prompt_id="peer-id", transcript_path=str(transcript))
        transcript.write_text(json.dumps({"type": "user", "promptId": "peer-id", "promptSource": "system", "turnOrigin": "peer"}) + "\n")
        self.assertFalse(self.denied(self.event("PreToolUse", transcript_path=str(transcript), tool_name="Read", tool_input={"file_path": str(self.source)})))
        self.event("UserPromptSubmit", prompt_id="human-id", transcript_path=str(transcript))
        self.assertTrue(self.denied(self.event("PreToolUse", transcript_path=str(transcript), tool_name="Read", tool_input={"file_path": str(self.source)})))

    def test_stop_continuation_is_bounded_without_opening_tools(self):
        self.assertEqual(self.event("Stop", stop_hook_active=False)["decision"], "block")
        self.assertFalse(self.event("Stop", stop_hook_active=True)["continue"])
        self.assertTrue(self.denied(self.before()))

    def test_malformed_hook_payloads_are_sanitized(self):
        for payload in ([], None, {"hook_event_name": "PreToolUse", "session_id": self.sid, "tool_input": []}):
            result = subprocess.run([*gate.prefix(self.args), "hook"], input=json.dumps(payload), capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertNotIn("Traceback", result.stderr)


@unittest.skipIf(gate.fcntl is None, "Mac/POSIX hook adapter")
class HookInstallationTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("make"), "make is required")
    def test_partial_bootstrap_without_claude_defers_without_side_effects(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            shutil.copy2(ROOT / "Makefile", root / "Makefile")
            empty_path = root / "bin"
            empty_path.mkdir()
            result = subprocess.run([shutil.which("make"), "--no-print-directory", "restore-claude-rulebook", "claude-rulebook-check"],
                                    cwd=root, env={**os.environ, "PATH": str(empty_path)}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("deferred", result.stdout)
            self.assertEqual(sorted(p.name for p in root.iterdir()), ["Makefile", "bin"])

    def test_version_probe_has_operational_timeout(self):
        args = SimpleNamespace(claude="claude", action="check")
        def hung(*args, **kwargs):
            self.assertGreater(kwargs.get("timeout", 0), 0)
            raise subprocess.TimeoutExpired(args[0], kwargs["timeout"])
        with mock.patch.object(gate.subprocess, "check_output", side_effect=hung):
            with self.assertRaises(subprocess.TimeoutExpired):
                gate.configure(args)

    def test_bootstrap_report_distinguishes_setup_from_deferral(self):
        source = (ROOT / "install.sh").read_text()
        report = source.split("COMPLETED_STAGES=()", 1)[1].split("prompt_yes_no()", 1)[0]
        stage = source.split("CURRENT_STAGE='Claude rulebook checkpoint'", 1)[1].split('echo ""', 1)[0]
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            make = root / "make"
            make.write_text("#!/bin/sh\nexit 0\n")
            make.chmod(0o755)
            script = ('set -euo pipefail\nBOOTSTRAP_SMOKE=0\nAPP_GROUPS=all\nDOTFILES=.\nCOMPLETED_STAGES=()'
                      + report + "CURRENT_STAGE='Claude rulebook checkpoint'" + stage)
            for present in (False, True):
                if present:
                    cli = root / "claude"
                    cli.write_text("#!/bin/sh\nexit 0\n")
                    cli.chmod(0o755)
                result = subprocess.run(["/bin/bash", "-c", script], env={**os.environ, "PATH": str(root)},
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual("DONE     Claude rulebook checkpoint setup" in result.stdout, present)
                self.assertEqual("DEFERRED Claude rulebook checkpoint" in result.stdout, not present)

    def test_merge_preserves_rtk_permissions_and_unrelated_hooks(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            settings = root / "settings.json"
            fake = root / "claude"
            fake.write_text('#!/bin/sh\nprintf "2.1.311 (Claude Code)\\n"\n')
            fake.chmod(0o755)
            rtk = {"matcher": "Bash", "hooks": [{"type": "command", "command": "rtk hook claude"}]}
            original = {"theme": "dark", "permissions": {"allow": ["Read"]},
                        "hooks": {"PreToolUse": [rtk], "Notification": [{"hooks": []}]}}
            settings.write_text(json.dumps(original))
            command = [sys.executable, str(SCRIPT), "restore", "--settings", str(settings), "--claude", str(fake)]
            subprocess.run(command, check=True, capture_output=True)
            current = json.loads(settings.read_text())
            self.assertEqual(current["permissions"], original["permissions"])
            self.assertEqual(current["hooks"]["PreToolUse"][0], rtk)
            self.assertEqual(current["hooks"]["Notification"], original["hooks"]["Notification"])
            gate_hook = current["hooks"]["PreToolUse"][1]["hooks"][0]
            self.assertEqual(gate_hook["onFailure"], "block")
            stamp = settings.stat().st_mtime_ns
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(settings.stat().st_mtime_ns, stamp)
            subprocess.run([sys.executable, str(SCRIPT), "check", "--settings", str(settings),
                            "--claude", str(fake)], check=True, capture_output=True)
            fake.write_text('#!/bin/sh\nprintf "2.1.200\\n"\n')
            result = subprocess.run(command, capture_output=True)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(settings.stat().st_mtime_ns, stamp)


class StartupTraceTests(unittest.TestCase):
    def test_eventual_or_fabricated_evidence_cannot_pass(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td).resolve()
            book = root / "agents"
            shutil.copytree(ROOT / "agents/rules", book / "rules")
            shutil.copy2(ROOT / "agents/AGENTS.md", book / "AGENTS.md")
            skill = book / "skills/init-rulebook/SKILL.md"
            skill.parent.mkdir(parents=True)
            shutil.copy2(ROOT / "agents/skills/init-rulebook/SKILL.md", skill)
            name = "rules/20-code-posture.md"
            path = book / name
            source = root / "src/Menu.tsx"
            generation = "fixture-generation"
            command = shlex.join([sys.executable, str(SCRIPT), "--rulebook", str(book), "--state-dir", str(root / "state"),
                                  "complete", "--session", "s", "--generation", generation, "--rules", name])
            def pair(id, tool, args, response, error=False):
                return [{"type": "assistant", "message": {"content": [{"type": "tool_use", "id": id, "name": tool, "input": args}]}},
                        {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": id, "is_error": error}]}, "tool_use_result": response}]
            init = [{"type": "system", "subtype": "init", "cwd": str(root), "session_id": "s"}]
            loader_call = pair("init", "Skill", {"skill": "init-rulebook"}, {"success": True})
            loader = loader_call + [{"type": "user", "message": {"content": [{"type": "text", "text": skill.read_text()}]}}]
            def file_read(id, relative):
                file = book / relative
                total = len(file.read_text().splitlines())
                return pair(id, "Read", {"file_path": str(file)}, {"file": {
                    "filePath": str(file), "content": file.read_text(), "startLine": 1, "numLines": total, "totalLines": total}})
            read = file_read("read", name)
            _, base = gate.inventory(book)
            needed = base + [name]
            receipt = {"rulebook_ready": True, "rulebook": str(book), "session": "s", "generation": generation,
                       "selected": [name], "required": needed, "loader_sha256": gate.digest(skill),
                       "evidence": {n: {"sha256": gate.digest(book / n), "source": "Read" if n == name else "InstructionsLoaded"} for n in needed}}
            checkpoint = pair("checkpoint", "Bash", {"command": command}, {"stdout": json.dumps(receipt)})
            work = pair("work", "Read", {"file_path": str(source)}, {})
            end = [{"type": "result", "subtype": "success", "is_error": False}]
            trace = root / "trace.jsonl"
            def grade(events):
                trace.write_text("\n".join(json.dumps(e) for e in events) + "\n")
                return checker.grade(trace, book, root, [name], state_dir=root / "state")
            def clone(value):
                return json.loads(json.dumps(value))
            self.assertTrue(grade(init + loader + read + checkpoint + work + end)["pass"])
            late = file_read("late", name)
            self.assertTrue(grade(init + loader + read + checkpoint + work + late + end)["pass"], "a later reread must not erase earlier proof")
            second = file_read("second", "AGENTS.md")
            batched = clone(read[1])
            batched.pop("tool_use_result")
            batched["message"]["content"] += second[1]["message"]["content"]
            for block, relative in zip(batched["message"]["content"], [name, "AGENTS.md"]):
                block["content"] = "\n".join(f"{i}\t{line}" for i, line in enumerate((book / relative).read_text().splitlines(), 1))
            self.assertTrue(grade(init + loader + read[:1] + second[:1] + [batched] + checkpoint + work + end)["pass"], "batched complete Read results")
            for text in ("1\ttruncated", batched["message"]["content"][0]["content"].replace("1\t", "2\t", 1)):
                bad = clone(batched)
                bad["message"]["content"][0]["content"] = text
                self.assertFalse(grade(init + loader + read[:1] + second[:1] + [bad] + checkpoint + work + end)["pass"])
            other_python = root / "python3.99"
            other_python.symlink_to(sys.executable)
            other = clone(checkpoint)
            other[0]["message"]["content"][0]["input"]["command"] = command.replace(shlex.quote(sys.executable), shlex.quote(str(other_python)), 1)
            other_receipt = clone(receipt)
            other_receipt["python"] = str(other_python)
            other[1]["tool_use_result"]["stdout"] = json.dumps(other_receipt)
            # Simulate grading from another Python installation (not a symlink).
            with mock.patch.object(checker.sys, "executable", "/different/python3"):
                self.assertTrue(grade(init + loader + read + other + work + end)["pass"])
            # Stream-json may interleave next-tool requests with prior results.
            # Reads still must finish before the checkpoint is requested.
            self.assertTrue(grade(init + loader + read + checkpoint[:1] + work[:1]
                                  + checkpoint[1:] + work[1:] + end)["pass"])
            self.assertFalse(grade(init + loader + work + read + checkpoint + end)["pass"])
            self.assertFalse(grade(init + loader_call + read + checkpoint + work + end)["pass"])
            for mutation in ("partial", "content"):
                bad = clone(read)
                if mutation == "partial":
                    bad[1]["tool_use_result"]["file"]["numLines"] = 1
                else:
                    bad[1]["tool_use_result"]["file"]["content"] = "wrong bytes"
                self.assertFalse(grade(init + loader + bad + checkpoint + work + end)["pass"])
            for mutation in ("base", "hash", "python", "failed", "shell", "unrelated", "state-dir"):
                bad = clone(checkpoint)
                if mutation in ("base", "hash", "python"):
                    body = clone(receipt)
                    if mutation == "base":
                        del body["evidence"][base[0]]
                    elif mutation == "hash":
                        body["evidence"][base[0]]["sha256"] = "wrong"
                    else:
                        body["python"] = "/wrong/python3"
                    bad[1]["tool_use_result"]["stdout"] = json.dumps(body)
                elif mutation == "failed":
                    bad[1]["message"]["content"][0]["is_error"] = True
                elif mutation == "shell":
                    bad[0]["message"]["content"][0]["input"]["command"] += "; echo forged"
                elif mutation == "state-dir":
                    bad[0]["message"]["content"][0]["input"]["command"] = command.replace(str(root / "state"), str(root / "other-state"))
                else:
                    bad[0]["message"]["content"][0]["input"]["command"] = shlex.join([sys.executable, str(SCRIPT), "--help", "complete"])
                self.assertFalse(grade(init + loader + read + bad + work + end)["pass"], mutation)
            early_gate = file_read("gate", "rules/02-attribution.md")
            self.assertFalse(grade(init + loader + early_gate + read + checkpoint + work + end)["pass"])
            blocked = pair("blocked", "Read", {"file_path": str(source)}, {}, error=True)
            self.assertTrue(grade(init + loader + blocked + read + checkpoint + work + end)["pass"])


if __name__ == "__main__":
    unittest.main()
