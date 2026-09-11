#!/usr/bin/env python3
"""Build BaroIndexOracle calldata and sorted-pair proofs. Never broadcasts."""
import argparse
import json
import re
import subprocess
from pathlib import Path


def cast(*args):
    return subprocess.check_output(['cast', *map(str, args)], text=True).strip()


def keccak(data):
    return cast('keccak', data)


def integer(value, low, high):
    if type(value) is not int or not low <= value <= high:
        raise ValueError(f'integer must be in [{low}, {high}]')
    return value


def prepare(raw):
    data = json.loads(raw)
    day = integer(data['day'], 0, 2**256 - 1)
    fear = integer(data['fearGreed'], 0, 100)
    leaves = []
    projects = data['projects']
    if not projects:
        raise ValueError('projects cannot be empty')
    seen = set()
    for row in projects:
        project = row['projectId'].lower()
        if not re.fullmatch(r'0x[0-9a-f]{64}', project) or int(project, 16) == 0 or project in seen:
            raise ValueError('projectId must be unique nonzero bytes32')
        seen.add(project)
        share = integer(row['mindshareBps'], 0, 10_000)
        gap = integer(row['gapBps'], -10_000, 10_000)
        encoded = cast('abi-encode', 'f(uint256,bytes32,uint16,int32)', day, project, share, gap)
        leaves.append(keccak(keccak(encoded)))
    if sum(row['mindshareBps'] for row in projects) > 10_000:
        raise ValueError('aggregate mindshare exceeds 10000 bps')
    levels = [leaves]
    while len(levels[-1]) > 1:
        layer = levels[-1]
        levels.append([
            keccak('0x' + ''.join(sorted([layer[i][2:], layer[i+1][2:]])))
            if i+1 < len(layer) else layer[i]
            for i in range(0, len(layer), 2)
        ])
    root = levels[-1][0]
    results = []
    for i, row in enumerate(projects):
        proof = []
        idx = i
        for layer in levels[:-1]:
            sibling = idx ^ 1
            if sibling < len(layer):
                proof.append(layer[sibling])
            idx //= 2
        results.append({**row, 'leaf': leaves[i], 'proof': proof})
    source = keccak('0x' + raw.hex())
    return {
        'day': day, 'fearGreed': fear, 'projectRoot': root, 'sourceHash': source,
        'calldata': cast('calldata', 'publish(uint256,uint8,bytes32,bytes32)', day, fear, root, source),
        'projects': results,
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare(args.source.read_bytes()), indent=2))
