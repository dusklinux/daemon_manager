import contextlib
import io
import pathlib
import unittest

SOURCE = pathlib.Path(__file__).resolve().parents[1] / 'DaemonApp/FeatureBatchControl.swift'
SCRIPT = SOURCE.read_text().split('#"""', 1)[1].split('"""#', 1)[0]


class FeatureBatchTests(unittest.TestCase):
    def run_batch(self, service_code=0, policy_code=0, interface_error=False, live=False):
        calls = []
        def services(operations):
            calls.append(('services', operations))
            return service_code
        def policy(*args):
            calls.append(('policy', args))
            return policy_code
        def interfaces(*args):
            calls.append(('interfaces', args))
            if interface_error:
                raise RuntimeError('cannot verify interface state')
        namespace = {'apply': services, 'apply_live': services, 'air_drop': policy, 'ui_control': interfaces}
        exec(compile(SCRIPT, 'FeatureBatchControl', 'exec'), namespace)
        with contextlib.redirect_stdout(io.StringIO()):
            code = namespace['apply_feature_batch']([], live, ['/helper', False], ['/companion', True])
        return code, calls

    def test_controls_follow_successful_service_batch_once(self):
        code, calls = self.run_batch()
        self.assertEqual(code, 0)
        self.assertEqual([x[0] for x in calls], ['services', 'policy', 'interfaces'])
        self.assertEqual(calls[1][1], ('/helper', 'off'))
        self.assertEqual(calls[2][1], ('/companion', 'set', {'controlCenter': True, 'appLibrary': True}))

    def test_service_failure_skips_both_feature_controls(self):
        code, calls = self.run_batch(service_code=1)
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 1)

    def test_policy_failure_skips_interfaces_and_is_not_success(self):
        code, calls = self.run_batch(policy_code=1)
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 2)

    def test_interface_failure_propagates(self):
        with self.assertRaisesRegex(RuntimeError, 'cannot verify'):
            self.run_batch(interface_error=True)

    def test_native_only_batch_does_not_require_feature_helpers(self):
        namespace = {'apply': lambda operations: 0, 'apply_live': lambda operations: 7}
        exec(compile(SCRIPT, 'FeatureBatchControl', 'exec'), namespace)
        self.assertEqual(namespace['apply_feature_batch']([], False, None, None), 0)
        self.assertEqual(namespace['apply_feature_batch']([], True, None, None), 7)
