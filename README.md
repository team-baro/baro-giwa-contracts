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

- `BaroCampaignEscrow`: campaign funding, EIP-712 reward claims, withdrawals, and pause controls.
- `BaroReputationSBT`: one non-transferable reputation token per wallet with quest and campaign counters.

Quest activity is verified offchain by Baro. An authorized operator signs a short-lived claim
voucher, and the user submits it onchain. Successful reward delivery and reputation updates are
atomic.

## Development

Requirements: [Foundry](https://book.getfoundry.sh/getting-started/installation).

```bash
forge install
forge fmt --check
forge build --sizes
forge test -vvv
```

See [claim voucher](docs/claim-voucher.md), [security model](docs/security-model.md), and
[deployment guide](docs/deployment.md) for integration details.

## Status

GIWA Sepolia development. The contracts have not been audited and must not be used with
real-value assets.

## License

MIT

