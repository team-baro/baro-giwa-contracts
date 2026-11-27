import importlib.util
import json
import unittest
import subprocess
import sys
import tempfile
from pathlib import Path

spec = importlib.util.spec_from_file_location('prepare_index', Path(__file__).parents[2] / 'tools/prepare_index.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class PrepareTest(unittest.TestCase):
    def payload(self, count=3):
        return {'day': 20000, 'fearGreed': 50, 'projects': [
            {'projectId': '0x'+f'{i+1:064x}', 'mindshareBps': 1000, 'gapBps': -100}
            for i in range(count)]}

    def test_roundtrip_all_proofs_including_odd_leaf(self):
        raw = json.dumps(self.payload()).encode()
        result = m.prepare(raw)
        for row in result['projects']:
            current = row['leaf']
            for sibling in row['proof']:
                current = m.keccak('0x'+''.join(sorted([current[2:], sibling[2:]])))
            self.assertEqual(current, result['projectRoot'])
        self.assertEqual(result['sourceHash'], m.keccak('0x'+raw.hex()))
        self.assertEqual(result, m.prepare(raw))

    def test_invalid_values(self):
        for key, value in [('day', True), ('day', -1), ('fearGreed', 101)]:
            data = self.payload(); data[key] = value
            with self.assertRaises(ValueError): m.prepare(json.dumps(data).encode())
        for key, value in [('projectId', '0x'+'0'*64), ('mindshareBps', 10001), ('gapBps', -10001)]:
            data = self.payload(); data['projects'][0][key] = value
            with self.assertRaises(ValueError): m.prepare(json.dumps(data).encode())

    def test_rejects_empty_duplicate_and_excess_total(self):
        data = self.payload(0)
        with self.assertRaises(ValueError): m.prepare(json.dumps(data).encode())
        data = self.payload(2); data['projects'][1] = data['projects'][0]
        with self.assertRaises(ValueError): m.prepare(json.dumps(data).encode())
        data = self.payload(2)
        for row in data['projects']: row['mindshareBps'] = 6000
        with self.assertRaises(ValueError): m.prepare(json.dumps(data).encode())


    def test_proofs_for_single_even_and_unbalanced_trees(self):
        for count in (1, 2, 4, 5, 8, 9):
            with self.subTest(count=count):
                result = m.prepare(json.dumps(self.payload(count)).encode())
                for row in result['projects']:
                    current = row['leaf']
                    for sibling in row['proof']:
                        current = m.keccak('0x' + ''.join(sorted([current[2:], sibling[2:]])))
                    self.assertEqual(current, result['projectRoot'])
                if count == 1:
                    self.assertEqual(result['projects'][0]['proof'], [])

    def test_source_bytes_are_committed_independently_of_merkle_values(self):
        data = self.payload()
        compact = m.prepare(json.dumps(data, separators=(',', ':')).encode())
        spaced = m.prepare(json.dumps(data, indent=2).encode())
        self.assertEqual(compact['projectRoot'], spaced['projectRoot'])
        self.assertNotEqual(compact['sourceHash'], spaced['sourceHash'])

    def test_rejects_wrong_json_shapes_without_running_cast(self):
        values = [[], None, {}, {'day': 1, 'fearGreed': 50, 'projects': {}},
                  {'day': 1, 'fearGreed': 50, 'projects': [None]},
                  {'day': 1, 'fearGreed': 50, 'projects': [{}]},
                  {'day': 1, 'fearGreed': 50, 'projects': [{'projectId': 42, 'mindshareBps': 1, 'gapBps': 0}]}]
        for value in values:
            with self.subTest(value=value), self.assertRaises(ValueError):
                m.prepare(json.dumps(value).encode())

    def test_cli_writes_usable_calldata(self):
        script = Path(__file__).parents[2] / 'tools/prepare_index.py'
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'source.json'
            source.write_text(json.dumps(self.payload(1)))
            run = subprocess.run([sys.executable, str(script), str(source)], text=True, capture_output=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            result = json.loads(run.stdout)
            self.assertEqual(result['calldata'], m.cast('calldata', 'publish(uint256,uint8,bytes32,bytes32)',
                              result['day'], result['fearGreed'], result['projectRoot'], result['sourceHash']))

    def test_cli_reports_bad_input_without_traceback(self):
        script = Path(__file__).parents[2] / 'tools/prepare_index.py'
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'bad.json'
            for content in ('{', '[]', '{}'):
                source.write_text(content)
                run = subprocess.run([sys.executable, str(script), str(source)], text=True, capture_output=True)
                self.assertEqual(run.returncode, 2)
                self.assertIn('error:', run.stderr)
                self.assertNotIn('Traceback', run.stderr)
                self.assertEqual(run.stdout, '')

if __name__ == '__main__': unittest.main()
