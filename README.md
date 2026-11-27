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
- `BaroQuestTestToken`: fixed-supply `BQT` reward token used only for the GIWA Sepolia pilot. It has
  no mint function and represents no real-world value.

Quest activity is verified offchain by Baro. An authorized operator signs a short-lived claim
voucher, and the user submits it onchain. Reward delivery remains available during a reputation
outage; failed reputation updates are queued for retry.

## Phase 4 modules

- `BaroIndexOracle`: current-UTC-day-only immutable fear/greed observations and verifiable project mindshare/gap commitments.
- `BaroAttendance`: organizer-approved wallet-bound EAS attendance, session windows and optional live credential gating.
- `DojangEligibility`: fail-closed Upbit Korea verified-address checks through DojangScroll and EAS.
- `BaroPerformanceEscrow`: fixed channel payouts per approved user action, duplicate protection and owner-only matured refunds.

These modules are locally implemented and tested. No public deployment is claimed.
Attendance uses EAS UIDs, with no separate NFT. Performance receipts trust the configured offchain verifier.
See [operations](docs/phase4/operations.md), [integration bindings](integration/README.md),
and [work allocation history](docs/phase4/development-log.md).

## Development

Requirements: Python 3 and [Foundry](https://book.getfoundry.sh/getting-started/installation).

```bash
forge install
forge fmt --check
forge lint
forge build --sizes
forge test -vvv
scripts/check-coverage.sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s test/tooling -v
python3 tools/export_integration.py --check
make test-fork
```

The fork test reads actual GIWA contract code but writes only to the local VM. It needs network access.
Use `BARO_FORK_BLOCK=<block> make test-fork` to pin a block. `make simulate-phase4` prepares the new stack
without broadcasting; see the operations runbook for required actors and dependency configuration.

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
