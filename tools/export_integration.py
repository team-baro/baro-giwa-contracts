#!/usr/bin/env python3
"""Export ABI and EIP-712 contract bindings; --check detects artifact drift."""
import argparse
import json
import subprocess
from pathlib import Path

CONTRACTS = ('BaroIndexOracle', 'BaroAttendance', 'DojangEligibility', 'BaroPerformanceEscrow')

def artifacts():
    for name in CONTRACTS:
        abi = json.loads(subprocess.check_output(['forge','inspect', name, 'abi', '--json'], text=True))
        yield Path(f'integration/abi/{name}.json'), json.dumps(abi, indent=2)+'\n'
    common = {'name': 'BaroAttendance', 'version': '1', 'chainId': 91342,
              'verifyingContract': 'REPLACE_WITH_DEPLOYED_ATTENDANCE_ADDRESS'}
    receipt = dict(common, name='BaroPerformanceEscrow', verifyingContract='REPLACE_WITH_DEPLOYED_PERFORMANCE_ADDRESS')
    bindings = {
        'notice': 'Replace domain addresses with verified deployments. Sign only after offchain verification.',
        'attendance': {'domain': common, 'primaryType': 'AttendanceClaim', 'types': {'AttendanceClaim': [
            {'name':'sessionId','type':'uint256'}, {'name':'user','type':'address'}, {'name':'deadline','type':'uint256'}]}},
        'performance': {'domain': receipt, 'primaryType': 'ActionReceipt', 'types': {'ActionReceipt': [
            {'name':'campaignId','type':'uint256'}, {'name':'user','type':'address'}, {'name':'channel','type':'address'},
            {'name':'evidenceHash','type':'bytes32'}, {'name':'actionAt','type':'uint64'}, {'name':'deadline','type':'uint256'}]}},
    }
    yield Path('integration/typed-data.json'), json.dumps(bindings, indent=2)+'\n'

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check', action='store_true');args=parser.parse_args()
    drift=[]
    for path,content in artifacts():
        if args.check:
            if not path.exists() or path.read_text()!=content: drift.append(str(path))
        else:
            path.parent.mkdir(parents=True,exist_ok=True);path.write_text(content)
    if drift: parser.exit(1,'Integration artifact drift: '+', '.join(drift)+'\n')
