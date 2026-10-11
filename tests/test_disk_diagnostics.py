import contextlib
import io
import pathlib
import plistlib
import tarfile
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


def script_namespace(filename):
    script = (ROOT / 'DaemonApp' / filename).read_text().split('#"""', 1)[1].split('"""#', 1)[0]
    namespace = {}
    exec(compile(script, filename, 'exec'), namespace)
    return namespace


class DiskDiagnosticsTests(unittest.TestCase):
    def setUp(self):
        self.ns = script_namespace('DiskDiagnostics.swift')

    def test_exact_fields_and_nul_padded_latest_values(self):
        data = b'fwUpdatesPercentUsed: 167\npercentUsed: 9\nhostWrites: 123\npercentUsed: 10\n'.replace(b'', b'\0')
        self.assertEqual(self.ns['parse_snapshot'](data), {'percentUsed': 10, 'hostWrites': 123})

    def test_missing_fields_are_not_zeroes(self):
        self.assertEqual(self.ns['parse_snapshot'](b'percentUsed: 0\n'), {'percentUsed': 0})
        with self.assertRaises(RuntimeError):
            self.ns['parse_snapshot'](b'fwUpdatesPercentUsed: 167\n')

    def test_archive_reads_only_expected_snapshot(self):
        with tempfile.TemporaryDirectory() as temp:
            archive_path = pathlib.Path(temp) / 'report.tar.gz'
            with tarfile.open(archive_path, 'w:gz') as archive:
                data = b'percentUsed: 9\n'
                member = tarfile.TarInfo('sysdiagnose/ASPSnapshots/asptool_snapshot.log')
                member.size = len(data)
                archive.addfile(member, io.BytesIO(data))
            self.assertEqual(self.ns['read_report'](str(archive_path))['values'], {'percentUsed': 9})

    def test_collection_failure_restores_originally_disabled_job(self):
        with tempfile.TemporaryDirectory() as temp:
            override_path = pathlib.Path(temp) / 'disabled.plist'
            with override_path.open('wb') as handle:
                plistlib.dump({'com.apple.sysdiagnose': True}, handle)
            self.ns['OVERRIDES_PATH'] = str(override_path)
            calls = []
            def launchctl(*args):
                calls.append(args)
                return (1, 'mock denied') if args[0] == 'bootstrap' else ((1, '') if args[0] == 'print' else (0, ''))
            self.ns['launchctl'] = launchctl
            with self.assertRaises(RuntimeError):
                self.ns['collect']()
            self.assertIn(('disable', 'system/com.apple.sysdiagnose'), calls)
            self.assertIn(('bootout', 'system/com.apple.sysdiagnose'), calls)
            self.assertNotIn(('disable', 'system/com.apple.sysdiagnose_helper'), calls)


class AnimationControlTests(unittest.TestCase):
    def test_filter_toggle_round_trip_preserves_bytes(self):
        ns = script_namespace('AnimationControl.swift')
        with tempfile.TemporaryDirectory() as temp, contextlib.redirect_stdout(io.StringIO()):
            base = pathlib.Path(temp) / 'NoAnimationsX'
            ns['BASE'] = str(base)
            base.with_suffix('.dylib').touch()
            active = base.with_suffix('.plist')
            data = plistlib.dumps({'Filter': {'Bundles': ['com.apple.springboard']}}, fmt=plistlib.FMT_BINARY)
            active.write_bytes(data)
            ns['run'](False)
            self.assertFalse(active.exists())
            ns['run'](True)
            self.assertEqual(active.read_bytes(), data)

    def test_custom_filter_is_not_changed(self):
        ns = script_namespace('AnimationControl.swift')
        with tempfile.TemporaryDirectory() as temp, contextlib.redirect_stdout(io.StringIO()):
            base = pathlib.Path(temp) / 'NoAnimationsX'
            ns['BASE'] = str(base)
            base.with_suffix('.dylib').touch()
            active = base.with_suffix('.plist')
            data = plistlib.dumps({'Filter': {'Bundles': ['different.app']}})
            active.write_bytes(data)
            with self.assertRaises(SystemExit):
                ns['run'](False)
            self.assertEqual(active.read_bytes(), data)


if __name__ == '__main__':
    unittest.main()
