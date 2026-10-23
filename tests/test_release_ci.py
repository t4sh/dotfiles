"""Final release markers select native checks and keep documented defaults."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def evaluate(expression, event, message='', full=False):
    expression = expression.strip()
    if expression.startswith('${{'):
        expression = expression[3:-2].strip()
    expression = expression.replace('github.event.head_commit.message', 'message')
    expression = expression.replace('github.event_name', 'event')
    expression = expression.replace('inputs.full', 'full')
    expression = expression.replace('&&', ' and ').replace('||', ' or ')
    expression = re.sub(r'!(?!=)', ' not ', expression)
    return eval(expression.strip(), {'__builtins__': {}},
                dict(event=event, message=message, full=full, contains=lambda a, b: b in a))


class ReleaseWorkflowTests(unittest.TestCase):
    def test_windows_release_runs_for_dispatch_or_marked_main_push(self):
        text = (ROOT / '.github/workflows/windows-verify.yml').read_text()
        self.assertRegex(text, r'push:\s+branches: \[main\]')
        expression = re.search(r'^    if: (.+)$', text, re.M).group(1)
        self.assertTrue(evaluate(expression, 'push', 'release [full ci]'))
        self.assertTrue(evaluate(expression, 'workflow_dispatch'))
        self.assertFalse(evaluate(expression, 'push', 'ordinary maintenance'))
        self.assertNotIn('[skip ci]', text)

    def test_mac_release_uses_full_fixtures_and_preserves_smoke_default(self):
        text = (ROOT / '.github/workflows/macos-verify.yml').read_text()
        if '[full ci]' not in text:
            # Public Mac validation already runs its complete fixture target on every push.
            self.assertIn('make test-public', text)
            return
        push_scope = text.split('  push:', 1)[1].split('  pull_request:', 1)[0]
        self.assertNotIn("'public-projection/**'", push_scope,
                         'Receipt-only final pushes must reach the release gate')
        timeout = re.search(r'^    timeout-minutes: (.+)$', text, re.M).group(1)
        cases = [('push', 'ordinary maintenance', False, 5),
                 ('push', 'release [full ci]', False, 20),
                 ('workflow_dispatch', '', True, 20),
                 ('workflow_dispatch', '', False, 5),
                 ('pull_request', 'release [full ci]', False, 5)]
        conditions = re.findall(r'^        if: (.+)$', text, re.M)
        self.assertEqual(len(conditions), 3)
        for event, message, full, expected_timeout in cases:
            with self.subTest(event=event, message=message, full=full):
                self.assertEqual(evaluate(timeout, event, message, full), expected_timeout)
                expected_full = expected_timeout == 20
                self.assertEqual(bool(evaluate(conditions[0], event, message, full)), not expected_full)
                for condition in conditions[1:]:
                    self.assertEqual(bool(evaluate(condition, event, message, full)), expected_full)


if __name__ == '__main__':
    unittest.main()
