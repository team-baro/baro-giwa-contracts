# Performance payout model

A project funds a campaign with immutable token, channel recipient, condition hash, fixed unit reward,
start/end window and optional wallet eligibility verifier. The channel cannot be selected by the operator later.
A campaign-scoped verifier signs EIP-712 receipts binding campaignId, user, channel, evidenceHash,
action timestamp and expiry. Settlement requires one receipt per user per campaign and globally unused evidence.
Evidence must identify a confirmed chain action (chainId, transaction hash, log index and condition context),
not a bare wallet or arbitrary reusable screenshot. Verification of that action remains an offchain trust assumption.
Anyone may relay a receipt; payout goes only to the fixed channel. No operator withdrawal or arbitrary admin sweep.
Only the project owner can refund unspent budget after end; pause blocks payouts, not matured refunds.
Native ETH and allowlisted standard ERC-20 are supported. Reject fee-on-transfer funding; do not allow rebasing tokens.
