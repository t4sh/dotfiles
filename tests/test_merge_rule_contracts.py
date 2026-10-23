"""Public-owned isolated fixtures for merge rule contracts."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

def run(*args, **kwargs):
    kwargs.setdefault("stdin", subprocess.DEVNULL)
    return subprocess.run(args, text=True, capture_output=True, **kwargs)

class MergeRuleContracts(unittest.TestCase):
    @staticmethod
    def _copy_rulebook_contract_fixture(checkout: Path) -> Path:
        script = checkout / "scripts/audit-rules.sh"
        script.parent.mkdir(parents=True)
        shutil.copy2(ROOT / "scripts/audit-rules.sh", script)
        shutil.copy2(
            ROOT / "scripts/test-agent-terminal-integration.sh",
            script.parent / "test-agent-terminal-integration.sh",
        )
        agents = checkout / "agents"
        agents.mkdir()
        shutil.copy2(ROOT / "agents/AGENTS.md", agents / "AGENTS.md")
        shutil.copytree(ROOT / "agents/rules", agents / "rules")
        skills = agents / "skills"
        skills.mkdir()
        for source in (ROOT / "agents/skills").iterdir():
            if not (source / "SKILL.md").is_file():
                continue
            target = skills / source.name
            target.mkdir()
            (target / "SKILL.md").write_text("")
        init_skill = agents / "skills/init-rulebook/SKILL.md"
        shutil.copy2(ROOT / "agents/skills/init-rulebook/SKILL.md", init_skill)
        return script


    def test_rule_audit_rejects_missing_pr_title_contracts(self) -> None:
        cases = (
            ("agents/AGENTS.md", "creating a PR/MR or editing its title", "both action gates"),
            (
                "agents/rules/02-attribution.md",
                "commit message or PR/MR title",
                "dispatcher must route PR/MR titles",
            ),
            (
                "agents/rules/attribution/message.md",
                "commit subjects and pull/merge request (PR/MR) titles",
                "must share the emoji contract",
            ),
            (
                "agents/rules/attribution/message.md",
                "Before committing or creating/editing a PR/MR title",
                "validated before creation or edits",
            ),
            (
                "agents/rules/attribution/message.md",
                "including the custom mappings above",
                "must apply the custom emoji mappings",
            ),
            (
                "agents/rules/lifecycle/pr-title.md",
                "compare it exactly with the validated title",
                "compare the saved provider title",
            ),
            (
                "agents/rules/lifecycle/pr-title.md",
                "Correct any mismatch and repeat verification",
                "mismatches must be corrected and reverified",
            ),
            (
                "agents/rules/02-attribution.md",
                "PR/MR merge work loads message/emoji and identity/signing",
                "merges must load message and identity contracts",
            ),
            (
                "agents/rules/lifecycle/integration.md",
                "exactly one trailing ` (#NNN)` with the original PR/MR numeric ID",
                "integration subjects must end with the original request ID",
            ),
            (
                "agents/rules/lifecycle/integration.md",
                "read its actual subject",
                "must read the actual integration commit subject",
            ),
            (
                "agents/rules/lifecycle/integration.md",
                "compare the complete subject exactly with the validated subject",
                "must compare the complete integration subject",
            ),
            (
                "agents/rules/lifecycle/integration.md",
                "report the suffix check as not applicable",
                "must report suffix verification as not applicable",
            ),
            (
                "agents/rules/lifecycle/integration.md",
                "report incomplete merge-subject verification and stop before cleanup",
                "verification failures must block cleanup",
            ),
        )
        with tempfile.TemporaryDirectory() as td:
            checkout = Path(td) / "checkout"
            script = self._copy_rulebook_contract_fixture(checkout)
            env = {**os.environ, "DOTFILES": str(checkout)}
            baseline = run("bash", str(script), env=env)
            self.assertEqual(baseline.returncode, 0, baseline.stdout + baseline.stderr)
            for relative, clause, diagnostic in cases:
                with self.subTest(path=relative, clause=clause):
                    path = checkout / relative
                    original = path.read_text()
                    self.assertIn(clause, original)
                    path.write_text(original.replace(clause, "", 1))
                    result = run("bash", str(script), env=env)
                    path.write_text(original)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn(diagnostic, result.stderr)


    def test_rule_audit_requires_evidence_driven_merge_checks(self) -> None:
        # Preserve required gates and evidence-based recovery without imposing
        # task timers, retry quotas, or a renewed approval for routine repairs.
        lifecycle = "agents/rules/lifecycle/integration.md"
        cases = (
            (
                lifecycle,
                "Inspect the target repository's pipeline configuration at the target ref and candidate merge result",
                "discover CI/CD for the actual target and merge result",
            ),
            (
                lifecycle,
                "Resolve event, branch, path, and job conditions for this merge",
                "resolve pipeline applicability",
            ),
            (
                lifecycle,
                "A standalone script such as `verify:ci`, a documented `verify` alias, or a broad test target does not establish that CI/CD exists",
                "must not infer CI/CD from a verification script",
            ),
            (
                lifecycle,
                "Report the absence and use documented project validation or the smallest meaningful checks for the changed behavior",
                "absent CI must use relevant checks",
            ),
            (
                lifecycle,
                "never infer permission to bypass it",
                "preserving required gates",
            ),
            (
                lifecycle,
                "Local CI/CD emulation is permitted only for an applicable pipeline confirmed above",
                "require a confirmed applicable pipeline",
            ),
            (
                lifecycle,
                "Every selected check must have valid passing local or hosted evidence before integration",
                "selected checks must pass before integration",
            ),
            (
                lifecycle,
                "the applicable configured validation jobs, explicitly requested checks, or the relevant project validation selected above",
                "selected checks must pass before integration",
            ),
            (
                lifecycle,
                "Run selected checks that lack valid reusable evidence",
                "without reusable evidence must execute before integration",
            ),
            (
                lifecycle,
                "Failed, pending, skipped, or unavailable selected checks block integration",
                "unresolved selected checks must block integration",
            ),
            (
                lifecycle,
                "A local merge alone does not require another full run",
                "reuse valid evidence instead of unconditional reruns",
            ),
            (
                lifecycle,
                "diagnosis and safe repairs continue under the existing authorization",
                "failure recovery must preserve authorization",
            ),
            (
                lifecycle,
                "Stop repeating an unchanged failure",
                "require new evidence",
            ),
            (
                "agents/rules/23-verification.md",
                "Only apply time or attempt limits explicitly set by the user, or imposed by the actual tool or service",
                "limits must come from the user or execution constraints",
            ),
            (
                "agents/rules/23-verification.md",
                "Ordinary change verification does not authorize a full integration suite",
                "defer merge check selection to lifecycle policy",
            ),
        )
        with tempfile.TemporaryDirectory() as td:
            checkout = Path(td) / "checkout"
            script = self._copy_rulebook_contract_fixture(checkout)
            env = {**os.environ, "DOTFILES": str(checkout)}
            baseline = run("bash", str(script), env=env)
            self.assertEqual(baseline.returncode, 0, baseline.stdout + baseline.stderr)
            for relative, clause, diagnostic in cases:
                with self.subTest(path=relative, clause=clause):
                    path = checkout / relative
                    original = path.read_text()
                    self.assertIn(clause, original)
                    path.write_text(original.replace(clause, "", 1))
                    result = run("bash", str(script), env=env)
                    path.write_text(original)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn(diagnostic, result.stderr)

            # Reject reinstating either old mandate even alongside the new rules.
            path = checkout / lifecycle
            original = path.read_text()
            for legacy in (
                "Before integrating, run the repository-defined integration or CI-equivalent gate.",
                "After any local merge, rerun the same integration/CI-equivalent gate.",
            ):
                with self.subTest(legacy=legacy):
                    path.write_text(original + "\n" + legacy + "\n")
                    result = run("bash", str(script), env=env)
                    path.write_text(original)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn("must not restore unconditional full-suite gates", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
