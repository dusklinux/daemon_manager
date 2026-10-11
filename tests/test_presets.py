import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class PresetTests(unittest.TestCase):
    def test_config_matches_builtin_targets(self):
        source = (ROOT / 'DaemonApp/DefaultPresets.swift').read_text()
        block = source.split('static let builtinDefaults: [String: Bool] = [', 1)[1].split('\n    ]', 1)[0]
        pairs = re.findall(r'"([^\"]+)": (true|false)', block)
        self.assertEqual(len(pairs), len(dict(pairs)), 'Duplicate builtin labels')
        builtin = {label: value == 'true' for label, value in pairs}
        config = {}
        for line in (ROOT / 'daemon.cfg').read_text().splitlines():
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            label, action = line.split()
            self.assertIn(action, ('yes', 'no'))
            self.assertNotIn(label, config)
            config[label] = action == 'yes'
        self.assertEqual(config, builtin)
        critical = source.split('static let criticalServices: [String: String] = [', 1)[1].split('\n    ]', 1)[0]
        labels = re.findall(r'"([^\"]+)":', critical)
        self.assertFalse([label for label in labels if builtin.get(label) is True])
        for label in ('searchd', 'biomed', 'syncdefaultsd', 'mobile.lockdown'):
            self.assertIs(builtin['com.apple.' + label], False)
