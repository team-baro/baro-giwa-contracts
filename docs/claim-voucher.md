# Claim voucher

Baro verifies quest completion offchain and signs an EIP-712 `QuestClaim`. The user submits
the voucher and signature to `claimReward` on GIWA Sepolia.

## Domain

- `name`: `BaroCampaignEscrow`
- `version`: `1`
- `chainId`: the connected chain ID
- `verifyingContract`: the deployed escrow address

## Message

| Field | Solidity type | Purpose |
| --- | --- | --- |
| `user` | `address` | Only this wallet can claim |
| `campaignId` | `uint256` | Onchain campaign identifier |
| `questId` | `uint256` | Offchain quest identifier |
| `rewardToken` | `address` | Must match campaign configuration; zero means native ETH |
| `amount` | `uint256` | Reward amount in base units |
| `nonce` | `uint256` | Single-use value scoped to the user |
| `deadline` | `uint256` | Last valid Unix timestamp, bounded by campaign end |

The contract additionally binds every signature to the chain and escrow address through the
EIP-712 domain. The amount cannot exceed the campaign's `maxRewardPerClaim`, and a wallet's
cumulative campaign rewards cannot exceed `maxRewardPerUser`. Revoking an operator role invalidates
that operator's outstanding vouchers. Operators may be EOAs or ERC-1271 smart-contract wallets.

Successful reward payment marks the claim as final. If the reputation contract is unavailable, the
escrow records a pending reputation update that anyone can retry after service is restored.

The optional SBT call is limited to REPUTATION_UPDATE_GAS_LIMIT (200,000 gas). The escrow also
requires 50,000 gas of post-call reserve at that boundary. Use transaction gas estimation;
InsufficientReputationGas means the entire claim rolled back and can be retried with more gas.
A gas-exhausting SBT does not consume the reserved bookkeeping gas; reward payment finalizes
and the reputation update can be retried separately with its own gas budget.
