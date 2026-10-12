import contextlib
import io
import json
import os
import pathlib
import plistlib
import re
import subprocess
import tempfile
import types
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]


class SpringBoardUIControlTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = pathlib.Path(self.temporary.name) / 'mobile'
        self.folder = pathlib.Path(self.temporary.name) / 'tweaks'
        self.folder.mkdir()
        (self.home / 'Library/Preferences').mkdir(parents=True)
        (self.home / 'Library/Caches').mkdir()
        source = (ROOT / 'DaemonApp/SpringBoardUIControl.swift').read_text()
        script = re.search(r'static let script = #"""\n(.*?)\n"""#', source, re.S)[1]
        self.namespace = {}
        exec(script, self.namespace)
        original_path = pathlib.Path
        paths = {'/var/jb/Library/MobileSubstrate/DynamicLibraries': self.folder, '/var/mobile': self.home}
        self.namespace['pathlib'] = types.SimpleNamespace(Path=lambda p: paths.get(str(p), original_path(p)))
        self.mobile = types.SimpleNamespace(pw_dir=str(self.home / 'bootstrap-home'), pw_uid=os.getuid(), pw_gid=os.getgid())
        self.config = self.home / 'Library/Preferences/com.dusklinux.DaemonManagerUI.plist'

    def call(self, action, values=None, asset='missing-file'):
        output = io.StringIO()
        result = subprocess.CompletedProcess([], 0, '\tpid = 12345\n', '')
        with mock.patch.object(self.namespace['pwd'], 'getpwnam', return_value=self.mobile), \
             mock.patch.object(self.namespace['subprocess'], 'run', return_value=result), \
             contextlib.redirect_stdout(output):
            self.namespace['ui_control'](asset, action, values or {})
        return json.loads(next(line[9:] for line in output.getvalue().splitlines() if line.startswith('ui_state=')))

    def test_old_runtime_pid_is_not_reported_as_applied(self):
        report = self.home / 'Library/Caches/daemon-manager-ui-runtime.json'
        report.write_text(json.dumps({'pid': 9876, 'version': 1, 'supported': {}, 'disabled': {}}))
        self.assertIsNone(self.call('read')['runtime'])
        report.write_text(json.dumps({'pid': 12345, 'version': 1, 'supported': {}, 'disabled': {}}))
        self.assertEqual(self.call('read')['runtime']['pid'], 12345)

    def test_missing_asset_preserves_existing_choices(self):
        original = plistlib.dumps({'controlCenter': True, 'dock': False})
        self.config.write_bytes(original)
        with self.assertRaises(FileNotFoundError):
            self.call('set', {'dock': True}, asset=str(self.home / 'missing.dylib'))
        self.assertEqual(self.config.read_bytes(), original)
        self.assertEqual(list(self.folder.iterdir()), [])

    def test_settings_use_native_home_when_bootstrap_home_differs(self):
        asset = self.home / 'companion.dylib'
        asset.write_bytes(b'fixture companion')
        with mock.patch.object(self.namespace['os'], 'chown'):
            state = self.call('set', {'controlCenter': True, 'dock': True}, asset=str(asset))
        self.assertTrue(state['saved']['controlCenter'])
        self.assertTrue(plistlib.loads(self.config.read_bytes())['dock'])
        self.assertFalse(pathlib.Path(self.mobile.pw_dir).exists())
