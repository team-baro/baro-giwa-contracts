# Phase 4 integration bindings

`abi/` is generated with `python3 tools/export_integration.py`; CI checks it for drift.
`typed-data.json` defines the EIP-712 field order. Domain addresses are explicit placeholders,
not deployed addresses. Use the actual chain ID and verified deployment addresses at runtime.

Attendance: organizer signs after checking participation. User sends claim(sessionId,deadline,signature).
Performance: campaign verifier checks the condition and confirmed evidence, then signs a receipt.
Anyone can relay settle(receipt,signature); the campaign's fixed channel receives its fixed unit reward.
Do not sign a receipt merely because a client says an action occurred.

Read SnapshotPublished, AttendanceAttested, ChannelPaid and CampaignRefunded only from configured contracts.
Track transaction hash, log index, block hash and confirmation status. Reconcile reorganized logs before counting KPIs.
A failed or pending transaction is not a completed issuance or payout.
