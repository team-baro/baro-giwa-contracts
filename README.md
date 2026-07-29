# Baro GIWA Contracts

Open-source smart contracts for Baro quest rewards and reputation on GIWA.

## Network

| Item | Value |
| --- | --- |
| Network | GIWA Sepolia |
| Chain ID | `91342` (`0x164ce`) |
| RPC | `https://sepolia-rpc.giwa.io/` |
| Explorer | `https://sepolia-explorer.giwa.io` |

## Contracts

- `BaroCampaignEscrow`: allowlisted campaign funding, EIP-712 claims with per-claim and per-user caps,
  liability accounting, recoverable reputation updates, withdrawals, and pause controls.
- `BaroReputationSBT`: one non-transferable aggregate reputation token per wallet with quest points,
  quest count, campaign count, and revocable channel verification.

Quest activity is verified offchain by Baro. An authorized operator signs a short-lived claim
voucher, and the user submits it onchain. Reward delivery remains available during a reputation
outage; failed reputation updates are queued for retry.

## Development

Requirements: [Foundry](https://book.getfoundry.sh/getting-started/installation).

```bash
forge install
forge fmt --check
forge lint
forge build --sizes
forge test -vvv
scripts/check-coverage.sh
```

Run `make simulate-giwa` before `make deploy-giwa`. The deployment target broadcasts both
contracts and verifies them through the GIWA Blockscout API.

See [claim voucher](docs/claim-voucher.md), [security model](docs/security-model.md), and
[deployment guide](docs/deployment.md) for integration details.

## Status

GIWA Sepolia development. The contracts have not been audited and must not be used with
real-value assets.

## Security

See [SECURITY.md](SECURITY.md) to report a vulnerability privately. Do not disclose an unpatched
vulnerability in a public issue.

## License

MIT
