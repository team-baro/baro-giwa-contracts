# Verified wallet model

Use DojangScroll's current verified-address UID for the UPBIT KOREA attester ID,
then read the EAS record and check schema, configured issuer, recipient, creation time,
expiration, revocation and ABI-encoded bool isVerified=true. Reject missing or malformed records.
Fail closed on external read errors. Do not substitute the testnet faucet credential for Upbit Korea.
Configuration is immutable per verifier deployment. Verification does not prove one natural person per wallet.
Sources (reviewed 2026-11-28):
- https://docs.giwa.io/giwa-chain/en/giwa-ecosystem/dojang/verified-address
- https://docs.giwa.io/giwa-chain/en/giwa-ecosystem/dojang/contracts
- https://github.com/ethereum-attestation-service/eas-contracts/blob/master/contracts/IEAS.sol
