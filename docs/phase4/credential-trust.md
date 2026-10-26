# Credential trust and configuration

DojangEligibility reads the current UPBIT KOREA credential UID through DojangScroll and validates
its EAS payload. EAS/Scroll read errors return false. Both consumers and operators must treat false
as ineligible, not as a reason to bypass verification. A new adapter deployment is required to change trust settings.

GIWA documentation reviewed 2026-11-28 lists the following GIWA Sepolia configuration:

| Field | Documented value |
| --- | --- |
| EAS | 0x4200000000000000000000000000000000000021 |
| Schema registry | 0x4200000000000000000000000000000000000020 |
| DojangScroll | 0xd5077b67dcb56caC8b270C7788FC3E6ee03F17B9 |
| Upbit Korea issuer | 0x09B170CA2A006081042992bCE7379B85a02149C6 |
| Verified Address schema UID | 0x072d75e18b2be4f89a13a7147240477481c4b526d5795802acba59046b426e08 |

Recheck current chain ID, code, Scroll configuration and EAS schema before deploying. Documentation is not runtime proof.
Sources: https://docs.giwa.io/giwa-chain/en/giwa-ecosystem/dojang/contracts and
https://docs.giwa.io/giwa-chain/en/giwa-ecosystem/dojang/verified-address.

The adapter verifies a credential issued to a wallet. It does not obtain an Upbit account identifier,
prove one person owns only one wallet, or expose personal KYC data. Do not describe it as complete Sybil resistance.
A verified session snapshots the adapter address through its attendance deployment; its requirement cannot be weakened later.
Test fixtures can inject arbitrary credentials and must never be configured as a production verifier.
