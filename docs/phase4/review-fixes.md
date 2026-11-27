# Review fixes and commit date correction

Actual work date: 2026-11-28 (Asia/Seoul). Public deployment is not part of this change.

## Reputation gas exhaustion

The previous unbounded optional SBT call could exhaust gas and prevent catch from recording a pending update.
At a 400,000-gas claim budget, the reproduction rolled back both payment and pending bookkeeping.

The optional call is now capped at 200,000 gas. Its boundary requires a further 50,000 gas reserve
for pending storage, claim events and guard cleanup. A lower supplied budget reverts explicitly with
InsufficientReputationGas, preserving all balances and nonce/claim slots for retry. This also prevents
gas estimation from finding a cheap successful path that silently skips healthy SBT updates.

Regression tests demonstrate payment despite a gas-burning SBT, successful deferred retry after repair,
rollback and retry for underfunded calls, and normal first-mint reputation credit at a 400,000-gas claim budget.

## Malformed credential ABI

Dependency return-data decoding happened in the adapter caller frame and escaped try/catch.
Malformed isVerified, current UID and EAS record responses each reverted instead of returning false.

isEligible now wraps all dependency reads and decoding in an external self-call. The helper is self-only;
external callers cannot use it directly. All three reproductions now return false. Tests also cover a
noncanonical ABI bool, fuzzed short EAS responses and direct-helper rejection. Credential issuer,
schema, recipient, time, expiry, revocation and payload checks remain enforced.

## Commit date display

For the 56 allocation commits, CommitterDate is aligned to the existing AuthorDate. GitHub can therefore
group them by the agreed 2026-08-10 through 2026-11-28 allocation dates. Later QA/dependency/fix commits
remain on 2026-11-28. File trees, messages and authors are preserved during the metadata-only rewrite.
Actual creation timestamps before alignment are archived in [history-date-provenance.json](history-date-provenance.json).
The repository still explicitly states that implementation actually occurred on 2026-11-28.

## Verification

- Full Solidity rebuild with the pinned GIWA fork: 123 passed, 0 failed, 0 skipped.
- Python tooling: 8 passed.
- Mixed-asset invariant: 128 runs, 8,192 calls, 0 reverts.
- Production line coverage: 96.24% (409/425); branch coverage: 77.97% (92/118).
- Slither 0.11.5: 0 High, 0 Medium; existing 7 Low timestamp and 5 naming notes remain.
- Formatting, lint exit status, contract sizes and generated ABI drift checks passed.
- Four previously failing reproduction tests now pass, along with healthy-path and underfunded-call regressions.

Reproduce with the commands in master-review.md. The public-chain positive Upbit credential case remains
untested; positive credential cases use fixtures and the fork checks rejection of an unverified wallet.
