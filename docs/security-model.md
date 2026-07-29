# Security model

## Trust boundaries

- Project owners fund campaigns and may withdraw only after the configured end time.
- Only operator-approved project wallets can create campaigns.
- Baro operators verify offchain quest completion and sign reward vouchers.
- Users submit their own claims and pay the claim transaction gas.
- The default admin manages operator, escrow, pause, and metadata roles.

## Implemented controls

- EIP-712 signatures are bound to chain ID and verifying contract.
- Nonces are single-use per wallet.
- Each wallet can claim a given campaign quest only once, even with a different nonce.
- Campaign token allowlist, period, status, remaining budget, and aggregate token liability are
  checked onchain.
- Every campaign sets onchain maximum rewards per claim and per user.
- Checks-effects-interactions and `ReentrancyGuard` protect payouts.
- `SafeERC20` handles ERC-20 transfers; fee-on-transfer funding is rejected.
- Claims and campaign creation can be paused without blocking matured withdrawals.
- Reputation failures are queued for retry and cannot block a valid reward payout.
- Campaign owners can permanently cancel their campaigns but cannot withdraw before the configured
  end. An operator pause is reversible; an owner cancellation is not.
- Matured withdrawals require explicit campaign deactivation.
- Only balances above recorded campaign liabilities can be recovered by the admin.
- Reputation uses one aggregate, non-transferable token per wallet. Each completion adds ten points
  and emits the campaign ID, quest ID, counters, and completion time.
- Channel verification can be updated or revoked when ownership changes.
- Smart contract wallets do not need to implement `IERC721Receiver` to receive reputation.
- Default-admin transfers use OpenZeppelin's delayed two-step process.
- The hot operator role cannot rewrite reputation metadata; `METADATA_ROLE` is granted to the admin.

## Operational requirements

- Keep admin and operator keys separate. Use a multisig for the admin before mainnet.
- Never expose the operator signer key to the web client or repository.
- Issue voucher deadlines no later than the campaign end time.
- Monitor role changes, campaign status changes, claims, and withdrawals.
- Use an RPC provider with an operational SLA for the application; GIWA's public endpoint is for
  development and is rate-limited.
- Complete an independent audit before any mainnet deployment or real-value reward campaign.
- Update OpenZeppelin and forge-std only to reviewed release commits; do not automatically follow
  an upstream submodule's development branch.

An operator can approve campaign creators and sign claims up to the per-claim and per-user maximums.
A compromised operator can still distribute the funded budget across multiple wallets, so these
caps reduce concentration but do not replace monitoring, rapid role revocation, or a multisig/ERC-1271
operator for higher-value deployments.
