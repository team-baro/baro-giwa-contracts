# Daily index format v1

A snapshot contains UTC day number (Unix seconds / 86400), fear/greed (0..100), project Merkle root and source hash.
Each project leaf contains projectId (nonzero bytes32), Korean mindshare (0..10000 basis points),
and kimchi mindshare gap (-10000..10000 signed basis points).
Leaves use double keccak256 of ABI-encoded (day, projectId, mindshareBps, gapBps); sorted pairs form the tree.
The source hash commits to the exact UTF-8 source document bytes, not a URL or private messages.
Archive the public aggregate dataset and proofs offchain. No personal data belongs in a snapshot.
