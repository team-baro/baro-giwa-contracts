# Index publication operations

1. Produce a public aggregate JSON file: day (UTC epoch day), fearGreed, projects[].
   Each project supplies a unique bytes32 projectId, mindshareBps and signed gapBps.
2. Run `python3 tools/prepare_index.py source.json > prepared.json`.
   Archive the exact source bytes, output and proofs. The source hash changes with whitespace.
3. Independently review source quality and the leaf values. A Merkle proof is not a truth oracle.
4. Configure BARO_INDEX_ORACLE, BARO_PUBLISHER_ADDRESS, BARO_INDEX_DAY, BARO_FEAR_GREED,
   BARO_PROJECT_ROOT, BARO_SOURCE_HASH and GIWA_SEPOLIA_RPC_URL.
5. Simulate `forge script script/PublishIndex.s.sol --rpc-url giwa_sepolia`.
   Broadcast only under the operator's normal signing process; no private key is stored in this repo.
6. Confirm receipt status, SnapshotPublished event and onchain values before marking a day published.

Publish near the end of the current UTC observation day, with time for retries before midnight.
Identical same-day retries are no-ops. Conflicting retries abort. Past days cannot be filled later.
A scheduler is not deployed here. It must invoke this process daily, monitor failures and record missing days.
Missing days must appear as missing in consumers, never as carried-forward or invented observations.
