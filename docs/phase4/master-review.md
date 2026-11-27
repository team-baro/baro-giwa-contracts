# Master pre-push review

> Historical QA snapshot before the later date correction and review fixes.
> Current follow-up: [review-fixes.md](review-fixes.md).

Date: 2026-11-28 (Asia/Seoul). Target: direct `origin/master`, authorized by the maintainer, no PR.
This record captures validation before that push. It does not assert a public contract deployment.
The original 56 allocation commits remain intact. Remote dependency update `2eaeee3` is preserved by a merge.
The QA fixes use actual current author and committer timestamps.

## Issue reproduced and fixed

A token can deliver the full requested amount while debiting an additional sender-paid fee.
Checking only the recipient balance, or using unchecked outgoing transfer accounting, could consume reserves
booked to another campaign. Five regression tests failed against the previous implementation.

Both escrows now require the escrow balance to decrease and the recipient balance to increase by exactly
the booked amount. A mismatch reverts the entire transfer and all claim/refund accounting.
The legacy quest escrow applies the same rule to rewards, matured withdrawals and excess recovery.
Recipient-deducted transfer fees are rejected too. Reviewed standard tokens remain the supported asset model.

## Requirement and regression coverage

| Area | Cases and asserted outcomes | Evidence |
| --- | --- | --- |
| Daily indices | Current UTC day only; no duplicates/backfill/overwrite; project bounds; wrong proof; publisher rotation preserves history | BaroIndexOracle.t.sol, IndexToolCompatibility.t.sol |
| Publication operations | Real run() environment inputs; correct publication; identical retry no-op; conflicting retry aborts; wrong chain and stale day rejected | PublishIndex.t.sol, Phase4ScriptEntryPoints.t.sol |
| Attendance | Correct recipient and EAS payload; session start/end; duplicate claim; wrong/expired/cross-chain/cross-contract signature; revoked organizer; ERC-1271 signer | BaroAttendance.t.sol |
| Attendance failures | EAS revert/zero UID preserves claim slot; callback cannot reenter; verifier failure preserves slot | BaroAttendance.t.sol, VerifiedAttendance.t.sol |
| Credential checks | Issuer, schema, recipient, creation time, expiry, revocation, canonical bool, UID mismatch, missing current UID, faucet credential exclusion, read failures | DojangEligibility.t.sol |
| Performance payouts | Fixed channel and unit reward; signature tampering; wrong action times; campaign binding; duplicate wallet/evidence; exhausted budget; ETH/ERC-20 success | BaroPerformanceEscrow.t.sol, PerformanceRegression.t.sol |
| Reserve protection | Sender-fee payout/refund cannot consume another campaign's budget; legacy excess recovery cannot consume liabilities; recipient-fee transfers revert; retry after token repair succeeds | TokenAccountingRegression.t.sol |
| Owner refunds | Only matured owner refunds; payout pause does not trap funds; rejecting receiver rolls back; callback cannot reenter; refund retry succeeds | BaroPerformanceEscrow.t.sol, PerformanceRegression.t.sol |
| Token de-listing | New funding rejected, existing funded campaign payout and refund still work | PerformanceRegression.t.sol |
| Script wiring | Deploy/configure/publish actual run() entry points; dependency checks; role assignment; zero creator/wrong admin/wrong chain errors | Phase4ScriptEntryPoints.t.sol, Phase4Integration.t.sol |
| Independent encoding | cast-generated EIP-712 signatures and Python/cast Merkle data match Solidity | TypedDataCompatibility.t.sol, IndexToolCompatibility.t.sol |
| Stateful accounting | Randomized creation, settlement, time advance, and refund across ETH and two ERC-20s; per-asset liabilities, balances and paid amounts reconcile | PerformanceInvariant.t.sol |
| Source tooling | Single/even/odd/unbalanced Merkle trees, raw source-byte commitments, input shape/range/duplicate validation, CLI success and readable failure | test/tooling/test_prepare_index.py |
| Existing pilot | Original quest escrow, reputation SBT and BQT regression suites still pass after the transfer fix | Original three test suites |

## Final local results

| Check | Result |
| --- | --- |
| Solidity full rebuild | 114 passed, 0 failed, 0 skipped in 18 suites |
| Python tooling | 8 passed |
| Fuzzing | 512 runs per fuzz test |
| Stateful mixed-asset invariant | 128 runs, 8,192 calls, 0 reverts |
| Production source line coverage | 96.16% (401/417) |
| Production source branch coverage | 77.19% (88/114) |
| Slither 0.11.5 | High 0, Medium 0; 7 intentional time-boundary Low results and 5 naming notes retained |
| Formatting, lint exit status, ABI export drift, whitespace | Passed; lint retains naming and test environment cheatcode notes |
| Runtime size | Quest escrow 15,192 bytes; performance escrow 12,301 bytes; all deployable modules below EIP-170 limit |

Machine-readable evidence: [master-review-results.json](master-review-results.json).
The coverage denominator excludes test/mocks and other non-production sources.

## GIWA fork verification

GIWA Sepolia chain ID 91342, pinned block 42453800. All writes remain in the local Foundry VM.
The test uses actual GIWA EAS/SchemaRegistry/Scroll code and verifies:

1. Deployment script wiring and attendance schema registration/reuse.
2. Actual EAS issuance and read-back for an EOA recipient and a contract recipient without NFT receiver hooks.
3. Rejection of an unverified wallet by a verified session, without consuming the claim slot.
4. Current-day index publication and project inclusion proof verification.
5. Native ETH and BQT campaign funding, verifier-signed channel payout, and matured owner refund.
6. Zero remaining liabilities after both campaign refunds.

The action receipts and aggregate data are explicitly synthetic test inputs. No real upstream transaction
verification or actual attendance is claimed. A real Upbit-verified user's positive flow remains untested;
positive credential combinations are tested with fixtures. Frontend/backend integration and public deployment
remain separate from this contract repository review. These tests and static checks are not an external audit.

## Reproduce

```bash
forge fmt --check
forge lint
forge build --sizes
BARO_RUN_FORK_TESTS=true BARO_FORK_BLOCK=42453800 forge test --force --summary
scripts/check-coverage.sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s test/tooling -v
python3 tools/export_integration.py --check
uv tool run --from slither-analyzer==0.11.5 slither . \
  --exclude-dependencies --filter-paths 'lib|test|script' --fail-medium
```
