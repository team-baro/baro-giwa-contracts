# Attendance lifecycle

An authorized organizer creates an immutable session before its start, with nonzero ID, metadata hash,
kind (talk or quest), start and exclusive end. The session organizer signs EIP-712 wallet-bound approvals.
Only that recipient submits a claim; contract wallets are supported. Claim only during [start,end).
One attestation per session per wallet. Revoked organizer authority invalidates outstanding approvals.
EAS is the issuance format; no second ERC-721 is minted. KPI means successful EAS UIDs, not NFT balances.
Schema: uint256 sessionId,uint8 kind,bytes32 metadataHash. Attestations are non-expiring and irrevocable.
Only a zero-fee schema with no resolver is supported. Register a fresh schema before deployment.
