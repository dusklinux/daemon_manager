import contextlib
import io
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / 'DaemonApp/NativeOverrides.swift').read_text().split('#"""', 1)[1].split('"""#', 1)[0]


class OverrideFailureTests(unittest.TestCase):
    def run_case(self, action_result, state_output, action='disable'):
        namespace = {}
        exec(compile(SCRIPT, 'NativeOverrides', 'exec'), namespace)

        def run(args):
            if args[1] == 'print-disabled':
                return subprocess.CompletedProcess(args, 0, state_output, '')
            if isinstance(action_result, Exception):
                raise action_result
            return subprocess.CompletedProcess(args, action_result, '', 'Operation not permitted' if action_result else '')

        namespace['run'] = run
        namespace['repair_metadata'] = lambda: None
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = namespace['apply']([['com.apple.example', action, 'system']])
        return code, output.getvalue()

    def test_success_requires_matching_disabled_override(self):
        self.assertEqual(self.run_case(0, '"com.apple.example" => disabled')[0], 0)
        self.assertEqual(self.run_case(0, '"com.apple.example" => enabled')[0], 1)

    def test_denied_command_is_not_reported_as_success(self):
        code, output = self.run_case(1, '"com.apple.example" => disabled')
        self.assertEqual(code, 1)
        self.assertIn('[error]', output)
        self.assertNotIn('Overrides verified.', output)

    def test_timeout_is_reported(self):
        code, output = self.run_case(subprocess.TimeoutExpired('launchctl', 30), '')
        self.assertEqual(code, 1)
        self.assertIn('timed out', output)

    def test_enabled_and_absent_override_are_accepted_for_enable(self):
        self.assertEqual(self.run_case(0, '"com.apple.example" => enabled', 'enable')[0], 0)
        self.assertEqual(self.run_case(0, '', 'enable')[0], 0)
