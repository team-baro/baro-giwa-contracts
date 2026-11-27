# Phase 4 operations runbook

## Deployment preparation

Use Foundry 1.5.1 and Solidity 0.8.28. Run `make check` and `make test-fork` first.
Provide nonzero BARO_DEPLOYER_ADDRESS, BARO_ADMIN_ADDRESS, BARO_ORGANIZER_ADDRESS,
BARO_PUBLISHER_ADDRESS, BARO_VERIFIER_ADDRESS and GIWA_SEPOLIA_RPC_URL locally.
Use a multisig for admin and separate service keys for publishing, attendance approvals and performance verification.
No private key belongs in an environment file, source tree, generated artifact or frontend bundle.

DeployPhase4 defaults to the documented GIWA Sepolia EAS, DojangScroll, Upbit Korea issuer and Verified Address schema.
Optional overrides: BARO_EAS_ADDRESS, BARO_DOJANG_SCROLL, BARO_DOJANG_ISSUER, BARO_VERIFIED_ADDRESS_SCHEMA.
Recheck governance and current official addresses before overriding. The script checks chain ID, dependency code,
Dojang schema shape and actor configuration before creating anything. It reuses or registers the zero-resolver,
irrevocable attendance schema, then deploys the four modules. No creator role is granted implicitly.

Run `make simulate-phase4` without broadcasting. The deployment script emits a deployment struct in simulation output.
Review dependencies, roles, schema, gas and source commit. Live broadcasting is a separate operator action using an
approved encrypted keystore; this repository's implementation work did not broadcast or deploy to GIWA.
After any real deployment, verify source on the explorer and record chain ID, block/hash, contract addresses,
schema UID, constructor arguments, transaction hashes and source commit in a new deployment manifest.
Only successful confirmed receipts and read-back state establish a deployed result.

For creator/token setup, provide BARO_PERFORMANCE_ESCROW, BARO_CAMPAIGN_CREATOR and optional BARO_REWARD_TOKEN
(default native ETH), then simulate `forge script script/ConfigurePhase4.s.sol --rpc-url giwa_sepolia`.
That step requires the configured admin; use the admin multisig transaction process when it is a smart wallet.
Allowlist only reviewed standard ERC-20 tokens. Keep real-value assets outside the unaudited pilot.

## Keys and permissions

Admin: one-day delayed two-step transfer through AccessControlDefaultAdminRules. No unattended admin key in web services.
Publisher: grant replacement PUBLISHER_ROLE, confirm it can simulate publication, then revoke the old key.
Organizer: revoke ORGANIZER_ROLE to invalidate outstanding approvals. Sessions bind their original organizer permanently;
create a replacement session if it must move to another signer. Existing EAS attestations remain valid.
Performance verifier: revoke VERIFIER_ROLE to invalidate outstanding receipts. Campaign verifier addresses are immutable;
old campaigns must reach their end and refund before replacement campaigns are funded.
Credential verifier: configuration is immutable. Deploy a reviewed new adapter and new consumers for changed trust settings.
Never bypass credential checks because an RPC, Scroll or EAS read fails.

## Daily publication incident

Use index-operations.md. Retry the same payload on the same UTC day. A mismatch aborts for human review.
A missed UTC day stays missing; never backfill and never rewrite an existing snapshot.
Rotate a compromised publisher immediately. A bad published value remains onchain; publish an offchain correction
notice linked to the original source hash, and do not present the immutable record as corrected.

## Attendance incident

Pause new claims through admin if approvals are being abused. Confirm session, recipient, signature domain,
organizer authority, credential state and EAS schema before retrying. An EAS failure rolls back the claim slot.
Retries must still occur inside the session window. Do not backdate sessions or mint after the end.
Attestations are irrevocable: incorrect issuance requires an explicit offchain correction policy, not silent deletion.

## Settlement incident

Pause payouts and new campaign creation if the verifier key or token behavior is compromised.
Refunds remain available to project owners once campaigns end. No admin or verifier can sweep campaign budget.
A failed payout must leave remainingBudget, totalLiability, rewardedUsers and usedEvidence unchanged.
For native ETH, check that the channel accepts ETH. For tokens, check balance deltas and approved token behavior.
Monitor totalLiability against actual balances per token; unexpected deficits require pausing and investigation.
Do not rely on accidental donations or forced ETH as campaign funding; no recovery method exists for that excess.

## Product integration still required

A hosted daily scheduler, public source archive, confirmed event indexer, organizer approval service,
performance evidence verifier and client UI are separate deployments. Use integration/typed-data.json and ABI exports.
Validate signatures against independent vectors, handle chain reorganization and confirmation status,
and avoid counting pending/failed transactions as attendance or paid performance.
A successful verified-wallet test fixture is not evidence of successful verification of a real Upbit user.
