# Initial Phase 4 implementation and validation

> Historical snapshot at commit `65a5365`, before the master review.
> See [master-review.md](master-review.md) for the later fixes and full pre-push results.

Actual implementation and verification date: 2026-11-28 (Asia/Seoul).
Branch: `phase4/contracts`. Baseline: `fa0143e3909c0967bbf0fa43ab6655729eccaac3`.
The work is 56 local commits with the agreed retrospective author dates from 2026-08-10 to 2026-11-28.
Author-date gaps are 1 day (14), 2 days (28), and 3 days (14), including the gap from the baseline.
Committer timestamps retain actual creation time. Dates are allocation metadata, not proof of historical activity.
Existing history is preserved. Nothing was pushed and no public contract was deployed.

## Implemented

| Module | Behavior |
| --- | --- |
| BaroIndexOracle | Immutable current-UTC-day snapshot, once per day; fear/greed value, project data root and public source commitment; project proof verification |
| BaroAttendance | Immutable talk/quest sessions, organizer EIP-712/ERC-1271 approvals, wallet-bound EAS issuance in the active window, one claim per session per wallet, optional live eligibility |
| DojangEligibility | Current Upbit Korea UID through Scroll, configured EAS schema/issuer/recipient checks, canonical true payload, creation/expiry/revocation checks, failure closes eligibility |
| BaroPerformanceEscrow | Fixed channel/condition/unit reward, funded ETH/ERC-20 budget, signed action receipts, one reward per user per campaign, unique evidence, owner-only matured refunds |

Integration ABI and typed-data exports, source-data/proof preparation, idempotent daily publication,
deployment/configuration scripts, CI checks and operations documentation are included.
Existing quest escrow, reputation SBT and BQT source files were not changed; their original 35 tests still pass.

## Verification results

Foundry/cast 1.5.1-stable, Solidity 0.8.28, Slither 0.11.5.

| Check | Result |
| --- | --- |
| Solidity tests, including pinned GIWA fork | 104 passed, 0 failed, 0 skipped across 14 suites |
| Python source/proof tooling tests | 3 passed |
| Fuzz tests | 512 runs per fuzz test |
| Stateful budget conservation | 128 runs, 8,192 handler calls, 0 reverts |
| Production source line coverage | 95.52% (384/402) |
| Production source branch coverage | 75.22% (85/113) |
| New four modules only | 203/203 lines and 56/56 measured branches covered |
| Slither | 0 High, 0 Medium; 7 Low timestamp findings and 5 informational naming findings retained |
| Formatting, lint exit status, ABI drift, whitespace | Passed; lint retains naming notes |
| Runtime code size | All four modules below the EIP-170 limit |

Coverage gate now counts `src/` only, excluding mock contracts. It keeps the repository's 80% line / 40% branch thresholds.
Slither timestamp findings correspond to specified session, expiry, daily publication and refund boundaries;
these are time gates, not randomness. A targeted reentrancy-benign suppression documents the returned UID write
inside nonReentrant attendance issuance. Regression tests exercise a callback and rollback on failed issuance.
These checks are not an independent security audit.

Independent compatibility checks verify cast-generated EIP-712 signatures against the Solidity digest,
and Python/cast-generated Merkle data against the Solidity verifier. Test fixture private keys are synthetic.

| New module | Runtime bytecode bytes |
| --- | ---: |
| BaroIndexOracle | 4,993 |
| BaroAttendance | 8,501 |
| DojangEligibility | 1,944 |
| BaroPerformanceEscrow | 12,040 |

Machine-readable results: [validation-results.json](validation-results.json).

## Real GIWA code on a local fork

Pinned GIWA Sepolia block: 42,453,800. Chain ID: 91,342.
The fork executed the deployment script, registered/reused the attendance schema, deployed local module instances,
and issued an attestation through the actual EAS predeploy code. Read-back checked UID, schema, attester,
recipient, payload and irrevocable/non-expiring settings. The synthetic unverified wallet was rejected by the
Dojang-gated session and did not consume a claim slot.

All writes occurred in Foundry's local VM. No public transaction hash, deployment address, real issued attendance,
real recorded index day or real channel payout is claimed. No real Upbit-verified wallet's positive flow was tested.
Positive credential scenarios use explicit test fixtures, including issuer/schema/ownership/expiry/revocation failures.

## Reproduce

```bash
make check
BARO_FORK_BLOCK=42453800 make test-fork
BARO_RUN_FORK_TESTS=true BARO_FORK_BLOCK=42453800 forge test --force --summary
uv tool run --from slither-analyzer==0.11.5 slither . \
  --exclude-dependencies --filter-paths 'lib|test|script' --fail-medium
```

The full test command uses `--force` to rebuild all suites instead of depending on selective incremental artifacts.
The fork test needs RPC access. The normal offline suite intentionally skips that opt-in test.
GitHub CI configuration was updated locally; no remote workflow run was triggered.

## Remaining integration work

Live deployment, explorer verification, a real verified-wallet positive test, production source archives,
a hosted daily scheduler, client UI, signing services, confirmed action verification and real campaign operation
remain outside this local delivery. See [operations.md](operations.md).
The performance verifier remains trusted to approve genuine events and correct channel attribution.
Credential verification does not prove that one person controls only one wallet.
