# Performance verification and settlement

BaroPerformanceEscrow is separate from the existing user quest reward escrow.
A CREATOR_ROLE project funds immutable Terms: channel, token, verifier, eligibility adapter (or zero),
budget, unitReward, [start,end), and conditionHash. The selected verifier must currently hold VERIFIER_ROLE.
The conditionHash commits to public action qualification and channel attribution rules fixed before funding.

After independently checking a confirmed chain event and its attribution, that verifier signs:
ActionReceipt(uint256 campaignId,address user,address channel,bytes32 evidenceHash,uint64 actionAt,uint256 deadline).
Domain: BaroPerformanceEscrow / 1 / chainId / verifyingContract. The unit reward is fixed by campaign terms.
Use evidenceHash = keccak256(abi.encode(chainId,transactionHash,logIndex,conditionHash)).
Bind a single user's qualifying event to one receipt. Batch events require an unambiguous per-user event index.
Never sign the same evidence for another campaign. Check canonical block hash and finality before approval.

Any relayer may submit. The contract checks the active window, claimed action time, approval expiry,
verifier role/signature, recipient binding and optional live wallet eligibility. It pays only the fixed channel.
Only one reward per user per campaign and one reward per evidence hash across this escrow deployment.
A failed transfer or verifier call cannot consume the reward slot or reduce the outstanding liability.

The contract verifies the approval, not transaction receipts from an arbitrary chain. A malicious authorized
verifier can approve false evidence. Do not describe this as trustless action verification.
Signing infrastructure must protect keys, deduplicate evidence, persist issuance logs and wait for confirmations.

Only the owner can refund the remaining budget at/after end. Refunds remain available while payouts are paused.
There is no owner cancellation, arbitrary operator withdrawal, admin sweep or early refund path.
Forced donations and unsupported accidental token transfers have no recovery path; they are never counted as budget.
Allowlist only reviewed standard tokens. Rebasing and fee-on-transfer tokens are unsupported.
Removing token support blocks new funding; it does not confiscate existing campaigns' refunds or payouts.
