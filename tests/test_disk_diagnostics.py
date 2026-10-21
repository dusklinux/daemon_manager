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

    def test_extended_storage_and_boot_counters(self):
        data = (b'hostWrites: 1000\nnandWrites: 1300\nhostReads: 5000\nnandReads: 5200\n'
                b'validLbas: 5400\nboots: 3300\nshutdowns: 2900\nuncleanBoots: 400\n')
        res = self.ns['parse_snapshot'](data)
        self.assertEqual(res['hostWrites'], 1000)
        self.assertEqual(res['nandWrites'], 1300)
        self.assertEqual(res['hostReads'], 5000)
        self.assertEqual(res['nandReads'], 5200)
        self.assertEqual(res['validLbas'], 5400)
        self.assertEqual(res['boots'], 3300)
        self.assertEqual(res['shutdowns'], 2900)
        self.assertEqual(res['uncleanBoots'], 400)

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


if __name__ == '__main__':
    unittest.main()
