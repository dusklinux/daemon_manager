import contextlib
import io
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
def script(name):
    return (ROOT / 'DaemonApp' / name).read_text().split('#"""', 1)[1].split('"""#', 1)[0]

class AirDropRestorationTests(unittest.TestCase):
    def run_case(self, disabled=True, present=False, helper_code=0, timeout=False, restore_error=False):
        namespace = {}
        exec(compile(script('NativeOverrides.swift') + '\n' + script('AirDropControl.swift'), 'AirDropControl', 'exec'), namespace)
        state = {'disabled': disabled, 'present': present}
        calls = []
        def run(args):
            calls.append(args)
            cmd = args[1] if args[0] == 'launchctl' else 'helper'
            code = 0
            output = ''
            if cmd == 'print-disabled':
                output = '"com.apple.managedconfiguration.profiled" => ' + ('disabled' if state['disabled'] else 'enabled')
            elif cmd == 'print': code = 0 if state['present'] else 113
            elif cmd in ('enable', 'disable'): state['disabled'] = cmd == 'disable'
            elif cmd in ('bootstrap', 'bootout'):
                if cmd == 'bootout' and restore_error: code = 1
                else: state['present'] = cmd == 'bootstrap'
            elif cmd == 'helper':
                if timeout: raise subprocess.TimeoutExpired(args, 30)
                code = helper_code
                output = 'airdrop_allowed=0\n'
            return subprocess.CompletedProcess(args, code, output, 'failed' if code else '')
        namespace['run'] = run
        namespace['repair_metadata'] = lambda: None
        with contextlib.redirect_stdout(io.StringIO()) as output:
            code = namespace['air_drop']('/helper', 'off')
        return code, state, calls, output.getvalue()

    def test_success_restores_original_disabled_and_unloaded_state(self):
        code, state, _, output = self.run_case()
        self.assertEqual(code, 0)
        self.assertEqual(state, {'disabled': True, 'present': False})
        self.assertIn('airdrop_allowed=0', output)

    def test_helper_failure_and_timeout_restore_state_without_publishing_value(self):
        for kwargs in ({'helper_code': 1}, {'timeout': True}):
            code, state, _, output = self.run_case(**kwargs)
            self.assertEqual(code, 1)
            self.assertEqual(state, {'disabled': True, 'present': False})
            self.assertNotIn('\nairdrop_allowed=0', output)

    def test_enabled_running_service_is_left_untouched(self):
        code, state, calls, _ = self.run_case(disabled=False, present=True)
        self.assertEqual(code, 0)
        self.assertEqual(state, {'disabled': False, 'present': True})
        self.assertFalse(any(c[0] == 'launchctl' and c[1] in ('enable', 'disable', 'bootstrap', 'bootout') for c in calls))

    def test_restore_failure_fails_the_whole_action(self):
        self.assertEqual(self.run_case(restore_error=True)[0], 1)
