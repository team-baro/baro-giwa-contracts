# Security model

## Trust boundaries

- Project owners fund campaigns and may withdraw only after the configured end time.
- Baro operators verify offchain quest completion and sign reward vouchers.
- Users submit their own claims and pay the claim transaction gas.
- The default admin manages operator, escrow, and pause roles.

## Implemented controls

- EIP-712 signatures are bound to chain ID and verifying contract.
- Nonces are single-use per wallet.
- Each wallet can claim a given campaign quest only once, even with a different nonce.
- Campaign token, period, status, and remaining budget are checked onchain.
- Checks-effects-interactions and `ReentrancyGuard` protect payouts.
- `SafeERC20` handles ERC-20 transfers; fee-on-transfer funding is rejected.
- Claims and campaign creation can be paused without blocking matured withdrawals.
- Reputation tokens cannot be transferred or approved.

## Operational requirements

- Keep admin and operator keys separate. Use a multisig for the admin before mainnet.
- Never expose the operator signer key to the web client or repository.
- Issue voucher deadlines no later than the campaign end time.
- Monitor role changes, campaign status changes, claims, and withdrawals.
- Complete an independent audit before any mainnet deployment or real-value reward campaign.
