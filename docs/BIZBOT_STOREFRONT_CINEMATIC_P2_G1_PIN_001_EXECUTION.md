# BIZBOT-STOREFRONT-CINEMATIC-P2-G1-PIN-001 — execution note

**Scope.** Extend the Cinematic real-service migration-sequence pin (`BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-CINEMATIC-PROOF-001`) so that the
P2 publication candidate of the Z-Credit pilot stack (`BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-P2-INTEGRATION-001`, which adds the 190th
migration G1) passes the Cinematic workflow's harness check. The change is carried on the P2 branch as its own, separately reviewed
commits under this Work ID, on top of the delivered P2 head `6998c817` (base `main` `46612618`). The six delivered P2 commits and their 54
file blobs are untouched.

**Why.** `supabase/tests/support/cinematic_001b_migration_contract.mjs` proves the exact migration sequence before any Cinematic phase
runs: the 183-name prefix, the `#379` target, 001D, the three visual follow-ups and, until this change, exactly one later migration (the
`#386` POS duty migration). G1 is a sixth migration after the target, so the contract refused the P2 candidate
(`Unexpected migration sequence after the #379 target`; 7 of the 20 unit tests failed at the P2 head, 20 / 20 passed at `main`). The
pin is deliberately exact and is extended only by a reviewed change of these files.

## What changed

| File | Change |
|---|---|
| `supabase/tests/support/cinematic_001b_migration_contract.mjs` | The singular `posDutySuccessor` pin is replaced by the fixed, ordered, frozen list `excludedSuccessors` (two entries, below). `proveMigrationSequence` requires the exact sequence `[001D, product, scene, background clarity, POS duty, G1]` after the target, pins each successor's raw-byte SHA-256 (`Unreviewed <label> successor bytes`), refuses reviewed successor bytes under any other name (`Reviewed <label> bytes may appear only under their pinned name`), and ends the historical plans right before the first pinned successor (an internal assertion checks that the successors are the final migrations). The receipt summary carries `excluded_successors` (both pinned objects) instead of the singular `excluded_successor`. Comments describe the historical `#379` / PR380 fixture as historical (001D has since been applied on hosted). |
| `supabase/tests/support/cinematic_001b_migration_wrapper.test.mjs` | The expected receipt (with the two pin objects written out literally) and the sequence expectations cover both successors; six existing tests are updated (8, 9, 12, 15, 19 and the former POS-successor test 20) and three added (coverage below). 20 → 23 tests. |
| `supabase/tests/support/run_cinematic_001b_migration_atomicity.mjs` | Comments only: the header names the two successors and their treatment; the comment above the historical visual-release phase describes the fixture as the historical `#379` / PR380 regression fixture rather than hosted's current state. The executable flow, the phase identifier `prove_scoped_visual_release_without_pending_payment`, the receipt keys (`pending_payment_omitted`, `pending_payment_schema_absent`), the absence assertions and the migration selection are unchanged. |
| `docs/BIZBOT_STOREFRONT_CINEMATIC_P2_G1_PIN_001_EXECUTION.md` | This note. |

Nothing else changes: no workflow, branch protection, job requirement, timeout, retry, Playwright assertion, payment source, migration
SQL, provider configuration or the exact-gap wrapper. A pre-existing comment in the contract (above `proveFinalMigration`) still calls the
`#379` target "still-unapplied"; it is not a 001D statement and is left outside this change's scope.

## The two pinned successors (fixed order)

| Successor | File | SHA-256 of the committed bytes |
|---|---|---|
| `#386` POS duty | `20261108085442_bizbot_pos_long_shift_alerts_001.sql` | `7bd3b8946cde2979519a4e302c6c5ecef25399725234072df617359168b4a865` |
| G1 (P2, D-062 drop-field evidence) | `20261109143313_bizbot_zcredit_001e_drop_evidence_001.sql` | `1ac9a99048c0755a982d197099a7aed27d802a67ea02b38254b79453b92bad95` (23,409 bytes, Git blob `0e7b9c1a3be5b5ac56cb2b4e2e647571c81ec1a8`, equal to the accepted DROP-EVIDENCE package bytes) |

Both successors are applied whenever the complete migration directory is applied: by `supabase db reset` in the `db-tests` job and in
every local harness, and by the Cinematic job's own stack start before the atomicity runner resets the stack. The historical exclusions
are confined to the Cinematic regression plans.

## Plan boundaries

| Plan | Count |
|---|---:|
| Complete P2 checkout (`summary.migrations`) | 190 |
| `target_prefix`, ending at `#379` | 184 |
| Historical atomicity / follow-up plan (`historical_names`: prefix + 001D + three visual follow-ups) | 188 |
| Historical visual-release plan (`visualReleaseSources`: additionally omitting 001D) | 187 |

Both historical plans exclude `#386` and G1. Evaluated on the same migration bytes, the previous contract (on the 189-file listing
without G1) and this contract (on the complete 190-file listing) produce identical plans, name by name and byte by byte: the 184-name
target prefix, the 188-name historical plan and the 187-name visual-release plan (names-and-bytes digests `61c65dd6…`, `fe389ae9…`,
`710fb97f…`; the proof script and its output are in the Work ID's evidence folder, kept outside Git). The previous contract refuses the
190-file listing and this contract refuses the 189-file listing, each with `Unexpected migration sequence after the #379 target`.

## Receipt and consumers

The runner passes `sequence.summary` into its receipt as `migration_sequence`; that object now carries `excluded_successors` (an array of
the two frozen pin objects `{ label, name, sha256 }`) and no singular field. Consumer search over the whole tree: `excluded_successor` and
`posDutySuccessor` appear nowhere outside the contract and its unit test; no file outside the contract, its unit test and the atomicity
runner reads or validates any field of the sequence summary or of the receipt; `e2e/cinematic/ci-runtime.mjs` and
`e2e/cinematic/live-transport-preload.mjs` import only `requireEphemeralCi`, and the `sanitize` step of the Cinematic job parses the
receipt generically (JSON validity and a credential-shaped-content check) without validating field names; the runner uses
`historical_names`, `target_prefix`, `visual_followups`, `targetPrefixSources` and `visualReleaseSources`, all with unchanged shapes, and
passes `summary` through untouched. Historical sealed receipts (earlier CI evidence) are not modified.

## Verification (local)

- `node --test supabase/tests/support/cinematic_001b_migration_wrapper.test.mjs`: **23 / 23** on Node 22.14.0 and on Node 24.22.1
  (0 skipped). Coverage of the two-successor contract: the exact 190-file sequence and both successor hashes (the expected receipt is
  compared in full, pin objects written out literally); the 184 / 188 / 187 boundaries; both successors absent from both historical
  plans and from the target prefix; each successor missing; each successor's bytes modified, CRLF-converted, BOM-prefixed or changed at
  end of file; renamed (same version, next version) or copied (into the prefix, as an extra later file, under an unknown name between
  the visual follow-ups and `#386`) successor bytes; duplicate successor versions and reordered input; swapped successor order and
  swapped successor bytes; an unknown migration between the visual follow-ups and `#386`, between `#386` and G1, and after G1; the
  historical plan builders (`targetPrefixSources`, `visualReleaseSources`) rejecting invalid complete inputs before producing any subset.
  Every refusal input of the earlier 20 tests is still exercised (the POS-duty cases of the former test 20 now run for both successors);
  no case was removed or skipped.
- The two e2e consumers of `requireEphemeralCi` pass a syntax check (`node --check`); that export and their import are unchanged.
- The real-service atomicity job is not run locally (its `requireEphemeralCi` guard is not bypassed and no GitHub Actions marker is
  spoofed). Removing the known harness failure does not predict the outcome of the exact-head CI cycle; the complete database suite and
  the race runners are established by that cycle after publication is separately authorized.

## Status kept from the P2 candidate

Local full pgTAP on the P2 head: `Result: FAIL`, exit 1, because six files refuse to run outside their own fixture database or the CI
database: `storefront_seo_discovery_001_test`, `zz_dashboard_online_order_controls_001_concurrency_test`,
`zz_storefront_content_contract_001_concurrency_test`, `zz_storefront_featured_items_001_concurrency_test`,
`zz_storefront_seo_consent_001_concurrency_test`, `zz_storefront_seo_discovery_001_concurrency_test` (the P2 evidence record
`db/PGTAP_FULL.txt`, kept outside Git). The three CI race runners did not run locally: the 001D runner requires a stack publishing host
port 56422, inside a Windows NAT excluded range on the build host; the platform-353 and acceptance-ETA runners accept only their own
fixture container or the CI database (`db/RUNNERS_LOCAL_STATUS.txt` in the same evidence folder). Deno / edge-runtime validation of
`pos-card-charge` (GR-30) is NOT VALIDATED (no Deno on the host). None of these becomes a pass through this change.

## Review route

D-069 (recorded in `docs/DECISIONS.md` as **RECORDED — NOT YET APPROVED**; it approves no head) names the route for the P2–P6 units; the
command room's decision of 2026-11-10 applies it to this extension: (a) one fresh-context Claude review of this extension and its
interaction with the P2 candidate, (b) the command room's source / package review of the exact head, (c) the owner's exact-head
decision. Publication and merge are held until (b) and (c) are recorded. No push, PR, merge, CI dispatch, hosted contact, deployment or
secret is part of this change; payment flags stay OFF and `providerProfile` stays `null`.
