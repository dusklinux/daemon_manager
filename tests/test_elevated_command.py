import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'DaemonApp/ElevatedCommand.swift').read_text()
SCRIPT = re.search(r'static let suScript = #"""\n(.*?)\n"""#', SOURCE, re.S)[1]


class ElevationTests(unittest.TestCase):
    def test_pty_forwards_literal_password_and_command(self):
        with tempfile.TemporaryDirectory() as directory:
            helper = pathlib.Path(directory) / 'fake-su.py'
            helper.write_text('''import sys, termios
settings = termios.tcgetattr(0)
settings[3] &= ~termios.ECHO
termios.tcsetattr(0, termios.TCSANOW, settings)
print("Password:", flush=True)
password = sys.stdin.readline().rstrip("\\n")
if password != "literal $dollar `backtick` 'apostrophe'":
    sys.exit(7)
if sys.argv[-1] != "printf '%s' 'literal $data'":
    sys.exit(8)
print("fixture-authenticated", flush=True)
''')
            result = subprocess.run([sys.executable, '-c', SCRIPT, sys.executable, str(helper),
                                     "printf '%s' 'literal $data'"],
                                    input="literal $dollar `backtick` 'apostrophe'\n",
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('fixture-authenticated', result.stdout)
            self.assertNotIn('literal $dollar', result.stdout)

    def test_signalled_child_is_failure(self):
        result = subprocess.run([sys.executable, '-c', SCRIPT, sys.executable, '-c',
                                 'import os,signal; os.kill(os.getpid(),signal.SIGTERM)'],
                                input='fixture\n', capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 143)
