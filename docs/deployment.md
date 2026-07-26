# GIWA Sepolia deployment

GIWA Sepolia uses chain ID `91342` (`0x164ce`).

1. Copy `.env.example` to `.env` and set the three deployment values locally.
2. Fund the deployer with test ETH from the GIWA faucet.
3. Run the deployment simulation without `--broadcast`.
4. Broadcast only after reviewing the simulation output.
5. Verify both contracts on GIWA Explorer through its Blockscout API.
6. Record addresses, deployment block, and source commit in `deploy/giwa-sepolia.json`.
7. Run a native-reward and ERC-20 test campaign end to end.

```bash
make simulate-giwa
make deploy-giwa
```

Deployment keys and environment files must never be committed.

After deployment, the operator grants `CAMPAIGN_CREATOR_ROLE` to each approved project wallet.
The default admin should be a multisig; changing it uses a one-day delayed two-step transfer.
