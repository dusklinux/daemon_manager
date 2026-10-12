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


class LiveFeatureTests(unittest.TestCase):
    def run_case(self, action, present, command_error=0, print_error=0):
        namespace = {}
        exec(compile(SCRIPT, 'NativeOverrides', 'exec'), namespace)
        state = {'present': present, 'disabled': False}
        calls = []
        def run(args):
            calls.append(args)
            cmd = args[1]
            code = 0
            output = ''
            if cmd in ('enable', 'disable'):
                state['disabled'] = cmd == 'disable'
            elif cmd == 'print-disabled':
                output = '"com.apple.feature" => ' + ('disabled' if state['disabled'] else 'enabled')
            elif cmd == 'print':
                code = print_error or (0 if state['present'] else 113)
            elif cmd in ('bootstrap', 'bootout'):
                code = command_error
                if not code: state['present'] = cmd == 'bootstrap'
            return subprocess.CompletedProcess(args, code, output, 'denied' if code not in (0, 113) else '')
        namespace['run'] = run
        namespace['repair_metadata'] = lambda: None
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = namespace['apply_live']([['com.apple.feature', action, 'user/501', '/feature.plist']])
        return code, calls, output.getvalue()

    def test_disable_removes_loaded_job(self):
        code, calls, _ = self.run_case('disable', True)
        self.assertEqual(code, 0)
        self.assertIn(['launchctl', 'bootout', 'user/501/com.apple.feature'], calls)

    def test_enable_bootstraps_only_when_unloaded(self):
        code, calls, _ = self.run_case('enable', False)
        self.assertEqual(code, 0)
        self.assertIn(['launchctl', 'bootstrap', 'user/501', '/feature.plist'], calls)
        self.assertFalse(any(c[1] == 'bootstrap' for c in self.run_case('enable', True)[1]))

    def test_failed_live_command_is_not_success(self):
        code, _, output = self.run_case('disable', True, command_error=1)
        self.assertEqual(code, 1)
        self.assertNotIn('Feature overrides and loaded job states verified.', output)

    def test_unreadable_job_is_not_treated_as_unloaded(self):
        code, calls, _ = self.run_case('enable', True, print_error=1)
        self.assertEqual(code, 1)
        self.assertFalse(any(c[1] == 'bootstrap' for c in calls))
