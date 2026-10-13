import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('sample_resources', ROOT / 'tools/sample_resources.py')
resources = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resources)


class ResourceSamplingTests(unittest.TestCase):
    def test_mach_ticks_are_converted_to_one_core_percent(self):
        before = {'monotonic': 1, 'processes': {10: {'started': 100, 'ticks': 0}}}
        after = {'monotonic': 11, 'processes': {
            10: {'started': 100, 'ticks': 24000000, 'name': 'fixture', 'footprint_bytes': 1024}}}
        row = resources.deltas(before, after, 125, 3)[0]
        self.assertEqual(row['cpu_seconds'], 1)
        self.assertEqual(row['one_core_percent'], 10)

    def test_reused_new_and_disappeared_pids_are_not_compared(self):
        before = {'monotonic': 1, 'processes': {10: {'started': 100, 'ticks': 100},
                                               11: {'started': 100, 'ticks': 100}}}
        after = {'monotonic': 11, 'processes': {10: {'started': 200, 'ticks': 1000},
                                               12: {'started': 200, 'ticks': 1000}}}
        self.assertEqual(resources.deltas(before, after, 125, 3), [])
