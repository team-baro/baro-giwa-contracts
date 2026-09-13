import importlib.util
import json
import unittest
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

if __name__ == '__main__': unittest.main()
