# GIWA Sepolia deployment

GIWA Sepolia uses chain ID `91342` (`0x164ce`).

1. Import the deployer into Foundry's encrypted keystore with
   `cast wallet import baro-giwa-deployer`.
2. Copy `.env.example` to `.env` and set the deployer address, account alias, admin, operator, and
   metadata URI locally. Do not place a private key in the environment file.
3. Fund the deployer with test ETH from the GIWA faucet.
4. Run the deployment simulation without `--broadcast`.
5. Broadcast only after reviewing the simulation output and entering the keystore password.
6. Verify both contracts on GIWA Explorer through its Blockscout API.
7. Record addresses, deployment block, and source commit in `deploy/giwa-sepolia.json`.
8. Allowlist the test ERC-20, grant the approved project wallet `CAMPAIGN_CREATOR_ROLE`, and run
   native-reward and ERC-20 campaigns end to end.

```bash
make simulate-giwa
make deploy-giwa
```

Deployment keys and environment files must never be committed.

After deployment, the operator grants `CAMPAIGN_CREATOR_ROLE` to each approved project wallet and
the token manager allowlists each accepted ERC-20. The default admin should be a multisig; changing
it uses a one-day delayed two-step transfer. The script refuses any chain other than GIWA Sepolia
(`91342`) and verifies the configured roles after construction.
