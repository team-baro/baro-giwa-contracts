# Phase 4 development allocation

Actual implementation started on 2026-11-28 (Asia/Seoul).
Author dates below are retrospective work allocation dates requested by the maintainer,
not evidence that development, tests, deployments, or user activity occurred then.
AuthorDate and CommitterDate now both use the retrospective allocation dates so GitHub groups
commits by the agreed schedule. The original creation timestamps are preserved in
[history-date-provenance.json](history-date-provenance.json). Actual implementation dates remain in this table.
The baseline before this allocation period is unchanged.
No deployment or push is implied by this log.

| Step | Allocated author date | Actual work date (KST) | Change |
| --- | --- | --- | --- |
| 1 | 2026-08-10 | 2026-11-28 | docs: define phase four contract scope |
| 2 | 2026-08-11 | 2026-11-28 | docs: define index snapshot format |
| 3 | 2026-08-12 | 2026-11-28 | docs: define daily publication rules |
| 4 | 2026-08-15 | 2026-11-28 | docs: define attendance attestation lifecycle |
| 5 | 2026-08-16 | 2026-11-28 | docs: define verified wallet eligibility |
| 6 | 2026-08-17 | 2026-11-28 | docs: define performance payout model |
| 7 | 2026-08-18 | 2026-11-28 | feat: add index oracle storage |
| 8 | 2026-08-19 | 2026-11-28 | feat: add index publisher authorization |
| 9 | 2026-08-22 | 2026-11-28 | feat: publish daily index snapshots |
| 10 | 2026-08-24 | 2026-11-28 | feat: enforce current day publication |
| 11 | 2026-08-27 | 2026-11-28 | feat: reject duplicate daily snapshots |
| 12 | 2026-08-28 | 2026-11-28 | feat: validate index values and commitments |
| 13 | 2026-08-30 | 2026-11-28 | feat: add index history queries |
| 14 | 2026-09-01 | 2026-11-28 | feat: verify project index proofs |
| 15 | 2026-09-03 | 2026-11-28 | test: cover daily publication boundaries |
| 16 | 2026-09-05 | 2026-11-28 | test: fuzz index snapshot validation |
| 17 | 2026-09-08 | 2026-11-28 | test: enforce snapshot immutability |
| 18 | 2026-09-11 | 2026-11-28 | feat: add index publication tooling |
| 19 | 2026-09-13 | 2026-11-28 | test: cover publisher retry behavior |
| 20 | 2026-09-15 | 2026-11-28 | docs: document index publication operations |
| 21 | 2026-09-18 | 2026-11-28 | feat: add attendance session registry |
| 22 | 2026-09-19 | 2026-11-28 | feat: configure attendance session windows |
| 23 | 2026-09-20 | 2026-11-28 | feat: add EAS attestation adapter |
| 24 | 2026-09-22 | 2026-11-28 | feat: verify attendance claim signatures |
| 25 | 2026-09-24 | 2026-11-28 | feat: enforce attendance claim windows |
| 26 | 2026-09-27 | 2026-11-28 | feat: prevent duplicate attendance claims |
| 27 | 2026-09-30 | 2026-11-28 | feat: issue attendance attestations |
| 28 | 2026-10-02 | 2026-11-28 | feat: expose attendance attestation references |
| 29 | 2026-10-03 | 2026-11-28 | test: reject invalid attendance claims |
| 30 | 2026-10-06 | 2026-11-28 | test: cover EAS failure rollback |
| 31 | 2026-10-08 | 2026-11-28 | test: cover attendance time boundaries |
| 32 | 2026-10-10 | 2026-11-28 | docs: document attendance integration |
| 33 | 2026-10-12 | 2026-11-28 | feat: add wallet eligibility interface |
| 34 | 2026-10-14 | 2026-11-28 | feat: validate credential issuers and schemas |
| 35 | 2026-10-16 | 2026-11-28 | feat: validate credential ownership |
| 36 | 2026-10-18 | 2026-11-28 | feat: reject expired and revoked credentials |
| 37 | 2026-10-20 | 2026-11-28 | feat: gate verified attendance sessions |
| 38 | 2026-10-22 | 2026-11-28 | test: cover verified wallet eligibility |
| 39 | 2026-10-23 | 2026-11-28 | test: cover credential verifier failures |
| 40 | 2026-10-26 | 2026-11-28 | docs: document credential trust assumptions |
| 41 | 2026-10-28 | 2026-11-28 | feat: add performance campaign escrow |
| 42 | 2026-10-31 | 2026-11-28 | feat: configure campaign payout terms |
| 43 | 2026-11-02 | 2026-11-28 | feat: fund performance campaign budgets |
| 44 | 2026-11-04 | 2026-11-28 | feat: verify qualified action receipts |
| 45 | 2026-11-07 | 2026-11-28 | feat: bind qualified actions to channels |
| 46 | 2026-11-09 | 2026-11-28 | feat: prevent duplicate action rewards |
| 47 | 2026-11-11 | 2026-11-28 | feat: settle qualified channel payouts |
| 48 | 2026-11-13 | 2026-11-28 | feat: refund expired campaign balances |
| 49 | 2026-11-16 | 2026-11-28 | test: enforce performance escrow invariants |
| 50 | 2026-11-19 | 2026-11-28 | docs: document performance verification model |
| 51 | 2026-11-21 | 2026-11-28 | feat: export phase four integration artifacts |
| 52 | 2026-11-22 | 2026-11-28 | feat: add phase four deployment scripts |
| 53 | 2026-11-24 | 2026-11-28 | test: add phase four integration scenarios |
| 54 | 2026-11-25 | 2026-11-28 | ci: add phase four contract checks |
| 55 | 2026-11-27 | 2026-11-28 | docs: add phase four operations runbook |
| 56 | 2026-11-28 | 2026-11-28 | docs: record phase four validation status |

## Master review on 2026-11-28

The maintainer authorized a direct master push with no PR, after additional validation.
The original 56 allocation commits were preserved. Remote master dependency update `2eaeee3` was merged without replacement.
Subsequent QA changes use their actual author/committer timestamps and are not added to the retrospective schedule.
A sender-fee ERC-20 regression was reproduced with five failing tests, then fixed in both escrows.
Additional coverage includes recipient fees, failure rollback, cross-campaign signatures, token de-listing,
script entry points, mixed-asset stateful accounting and expanded real-code fork integration.
Full results: [master-review.md](master-review.md).

## Date display correction and review fixes on 2026-11-28

GitHub displayed the initial allocation commits under their current-day CommitterDate.
The maintainer requested matching CommitterDate to AuthorDate, preserving trees, messages,
authors and baseline history. These dates are scheduling metadata, not evidence of historical work.
The later QA, dependency update and review fixes remain on their actual current day.

The two independently reproduced review bugs were fixed and covered by regression tests:
optional reputation calls now have a bounded gas budget with a post-call reserve, and malformed
Dojang ABI responses are decoded within a catchable external boundary.
See [review-fixes.md](review-fixes.md) for the verification results.
