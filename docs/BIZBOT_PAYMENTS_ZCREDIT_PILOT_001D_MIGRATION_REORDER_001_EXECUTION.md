# BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-MIGRATION-REORDER-001 — execution packet: the final local P1 candidate on current `main` — the 001D migration re-version, the D-061 / D-065 fold, the l10n and D1 unions and the bounded migration apply (GR-37)

Work ID: `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-MIGRATION-REORDER-001`, a local composition task of the 001D row of
[BIZBOT-PAYMENTS-ZCREDIT-PILOT-001](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001.md). It builds one fresh, minimal-history P1
candidate on the current `main`: the accepted 001D content of #370, the narrow review route **D-061** and the owner
decision **D-065**, folded together, with the current-`main` adaptations this packet lists and nothing else.

The packet contains no credential, terminal number, password, TPN, PIN-pad identifier, KEY, device serial, card datum,
provider payload, e-mail address, database URL, access token or real production UUID.

## 1. Request and boundary

- **The request.** The command-room authorization of 2026-11-04, "COMMAND-ROOM AUTHORIZATION — FINAL LOCAL P1
  CURRENT-MAIN COMPOSITION, 001D MIGRATION RE-VERSION, D-061/D-065 FOLD AND BOUNDED APPLY PROOF". It is kept outside
  Git with a SHA-256 sidecar (`fb37020d62cd96548130520ee119fef14ebce231ca30d6af802d778aafea7c17`). Its verdict accepts
  the D-065 owner-decision delta package locally: head `e005eaba97d1f43a8ba858bb6fd59f4072fa9fed`, tree
  `4b02fb4b29ca46e44a670d3155ddc7f36d06e612`, package SHA-256
  `4f749b91c24e155d0f8059f71dc3dc94099de7d8d06c480a21e244c92d0682dc`.
- **The statuses it keeps.** Q047_STATUS: CLOSED. Q049_STATUS: CLOSED_FOR_PHASE1_TEST. E2B_STATUS: OPEN.
  LOOKUP_LONG_TERM_RETENTION_STATUS: OPEN_FOR_LIVE. The deployment gates LG-08 and LG-09 stay held.
- **The candidate contains:** the accepted #370 ledger and database implementation (its single migration, re-versioned
  under M-A); the accepted Dashboard audit registry and the l10n portion of #370; the accepted seven pgTAP lanes and the
  concurrency runner; the accepted CI step; **D-061** and **D-065**, folded; the current-`main` l10n union; the
  current-`main` D1 union; the re-version's reference updates; the bounded migration-apply mechanism, its tests and its
  documentation; this packet.
- **The candidate does not contain:** the G1 / **D-062** migration; any 001E, W1, **D-063** or **D-064** source; the
  provider profile; any 001C, 001F or 001G source; any 001H runtime tool; secrets, mappings or provider configuration.
  `supabase/functions/pos-card-charge` (the 001E Edge function and its `providerProfile`) is absent from the
  candidate, so `providerProfile` cannot be set by it; on every accepted 001E-or-later head it stays `null`.
- **Not authorized and not done:** a push, PR, merge or PR edit; closing #370 or #371; hosted SQL; applying a migration
  to hosted; an Edge deploy; installing a secret or configuration; a provider call; terminal or card use; an APK or
  printer action. Every flag stays OFF. No Codex review is requested; one focused fresh-context Claude review runs
  (§10).
- **Preservation.** #370, #371, #314, #315 and every earlier payment branch, commit, package and evidence folder stay
  unchanged; no amend, rebase, reset, deletion or history rewrite.

## 2. Preflight (read-only, 2026-11-04T10:56Z)

Recorded outside Git by the evidence folder's flight tool (`preflight/PREFLIGHT.txt`).

- **Current `main`.** `git ls-remote` gives `be579180d43958f716872dac22daf24ba7cc8c26`, the authorization's value, so
  there is no drift to re-derive. The main checkout has no tracked-file change.
- **The named heads**, unchanged: #370 `54b19ab58ce72a2fa9a43860e31181a08222b254` (OPEN, draft; tree
  `2bbbb1f694c9157f77535bec4d5fb16d0397e7ea`, five commits on its base `d20798203052bfcfcdd58cd009bdc6babf5df12c`);
  #371 `53d6a6adc38f308b7ed6b0dd62177e6edd5ad5ce` (OPEN, draft, one commit on #370 changing only
  `docs/DECISIONS.md`); #314 `54346b37b35679c21248a64e40dcb3b0ca894673` and #315
  `4e8c81f6bd7249f3a44d1089c6253ad84df7f413` (OPEN). The D-065 head `e005eaba` has the #370 head as an ancestor and not
  the #371 head. All 25 accepted payment heads and their worktrees are unchanged and clean, and all 21 accepted
  packages still verify.
- **Migrations on `main`:** 183, the latest `20261102015942_bizbot_storefront_seo_discovery_001.sql`. Ten were added
  after the #370 base (`20261026144133` to `20261102015942`); all ten sort after the 001D version `20261023225657`, so
  the M-A re-version is required. None of them re-creates a function the 001D migration creates or re-creates.
- **The #370 paths.** #370 changes 34 paths; `main` changed 8 of them after the #370 base: the three ARB files, the
  four generated l10n files and the D1 file `supabase/tests/public_surface_acl_remediation_001_test.sql`. The other 26
  are unchanged on `main` since the #370 base.
- **The l10n union.** `main` has 2,887 messages per locale (200 `activityLog*`); #370 adds 73 `activityLog*` messages
  (and their 73 English metadata entries); `main` added 17 messages after the #370 base; no key is removed or added by
  both sides, and #370 changes no value of an existing key. The union has 2,960 messages per locale with ar / he / en
  parity and 273 `activityLog*` messages.
- **The D1 surface.** On `main` test 15's expected set has 18 entries: the six-entry anon allowlist (four storefront
  menu readers and the two SEO readers) and the twelve service-only web-request / notification wrappers. #370 appends
  the six service-only card-attempt wrappers, so the derived P1 set has 24 entries.
- **CI.** One workflow, `.github/workflows/ci.yml` (unchanged on `main` since the #370 base), triggered by every
  `pull_request` and by `push` to `main` only; jobs `validate` (30 min) and `db-tests` (25 min, Supabase CLI 2.107.0).
  Branch protection on `main`: strict, the only required check `validate`, admins not enforced, no required review.
  The repository is public.
- **Vercel.** Four projects link the repository, all with production branch `main`: `resto-flow` (root
  `vercel.json` ignore command: the `product` selector of `tools/vercel/ignore-build.mjs`), `bizbot-site` (`site/`, the
  `marketing` selector), `bizbot-storefront` (`storefront/`, the `storefront` selector) and `bizbot-pos-alert-cron`
  (`services/pos-alert-cron`, no ignore step: it builds a Preview on every push and redeploys production on every
  merge).
- **Ownership.** Five PRs are open: #370, #371, #314, #315 and the draft #379
  (`fix/BIZBOT-STOREFRONT-CINEMATIC-001B-source-rebuild`, updated 2026-11-04T09:57Z). #379 also changes the D1 file and
  adds the migration `20261102140930_bizbot_storefront_cinematic_001b_appearance.sql`, which sorts after `main`'s latest
  and before any version created today. #315 changes one l10n test file this candidate does not touch.
- **Decision IDs.** Across 451 distinct heads (every register read): **D-061** is allocated on three local route
  branches (one of them #371's head); **D-062**, **D-063** and **D-064** on the stacked local 001E-and-later branches;
  **D-065** only on `e005eaba`; nothing allocates **D-066** or later. `main`'s highest decision is **D-058**.

*(2026-11-04, after the first composition: at 13:20Z #379 re-versioned its migration to `20261104131256` and, per its own release
record, applied it to hosted; at 13:46:43Z it merged into `main` as `0df86dcb`, which then held 184 migrations and a
19-entry D1 set. The facts above are the 10:56Z preflight; §12.2 records the drift and the recomposition.)*

## 3. Composition method

- **A fresh branch on current `main`.** `feat/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-FINAL-P1-current-main` starts at
  `be579180`. Nothing of the old local stack is merged, rebased or cherry-picked, and none of its 116 commits is
  reachable from the candidate. *(2026-11-04: recomposed as R2 on `0df86dcb`, branch
  `feat/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-FINAL-P1-current-main-r2`; the first composition, on `be579180`, is kept
  locally and superseded — §12.1, §12.2.)*
- **Path by path.** Each accepted #370 path is taken from the #370 head as its exact blob, or derived as §4 to §8
  describe. A path whose content differs from the #370 blob differs only for a permitted reason:
  1. the migration filename re-version (§4);
  2. a reference to the migration filename (§4);
  3. the current-`main` l10n union and its deterministic generated output (§7);
  4. the current-`main` D1 union (§8);
  5. the **D-061** re-pin and fold wording (§6);
  6. the **D-065** fold wording (§6);
  7. the bounded-apply tooling, documentation and tests (§5);
  8. this packet's facts and hashes.
- **The proof.** A composition manifest outside Git lists, for every changed path, the accepted source blob (or the
  accepted generated-source origin), the current-`main` base blob, the final blob and the reason for any difference.
  Every other path of the candidate equals `main`.
- **The commit plan** (each commit message ends with the Work ID):
  1. `docs(payments)`: this packet's plan (§1 to §11), before any implementation;
  2. `docs(payments)`: the accepted 001D documents, the reference updates of §4 and the **D-061** / **D-065** fold;
  3. `feat(db)`: the 001D migration under its new version, body byte-identical;
  4. `feat(dashboard)`: the audit registry, its labels, the l10n union and the regenerated output;
  5. `test(db)`: the seven lanes, the concurrency runner and the D1 union;
  6. `infra(ci)`: the accepted `db-tests` step for the 001D runner;
  7. `feat(db)`: the bounded migration-apply wrapper, its tests and its documentation;
  8. `docs(payments)`: this packet's results.

  Review fixes, if any, follow as separate commits before the results commit. *(2026-11-04: R2 adds a base re-pin (8) and
  review fixes (9 to 14) before these results (15) — §12.1.)*

## 4. The 001D migration: M-A re-version

- **The old file.** `supabase/migrations/20261023225657_bizbot_zcredit_001d_server_ledger.sql` (#370 blob
  `b94a34176d6eefb8d1a53c7907d1b4272de7dcfd`, content SHA-256
  `468768f89029a0fb131869f754d5374127930b8bf05b48cd8de19d645546352e`). It was never applied to hosted.
- **The new version** is generated by the installed Supabase CLI (2.107.0), `supabase migration new
  bizbot_zcredit_001d_server_ledger`, only after the check of §2; it must sort after every migration on `main`
  (`20261102015942`). The CLI's empty file then receives the exact #370 blob: the body bytes are unchanged and only the
  filename changes. The old filename is removed from the candidate. *(2026-11-04: first `20261104111118`; after #379's merge,
  `20261104141959`, again generated by `supabase migration new` after checking `main` — §12.4.)*
- **References.** Every source, test or document reference that tracks the active filename is updated. Historical prose
  that deliberately names the old reviewed filename keeps it and is marked historical.
- **Not used:** `--include-all`, `migration repair` and any edit of a hosted migration ledger.
- **G1.** The G1 / **D-062** migration (`20261027211023`) is not imported. Its later re-version must be newer than this
  candidate's 001D version.
- **#379.** Its `20261102140930` sorts before this candidate's version. If #379 lands first, the order is still valid.
  If this candidate lands first, #379 needs its own re-version under its own Work ID before it can be applied.
  *(Superseded on 2026-11-04: #379 carries `20261104131256`, applied to hosted and merged before this candidate;
  §12.2.)*

## 5. The bounded migration apply (GR-37)

GR-37 (a hard gate recorded by the 001H readiness corrections of 2026-11-01): the exact apply transaction of any hosted
migration must use a tested, bounded `lock_timeout` and `statement_timeout`. The frozen migration body is not changed to
add them, and nothing assumes that the Supabase CLI propagates a setting.

- **Investigation order.**
  1. Test whether a reviewed `PGOPTIONS`-based wrapper propagates both settings to every connection the installed CLI
     opens, on its local target and on a `--db-url` target. The proof is read on the server side: a login event trigger
     records each new session's settings, and a `ddl_command_start` event trigger records the settings each DDL
     statement of the migration runs with. Both probes live only in the disposable rehearsal database.
  2. If propagation is not proven, stop and propose the smallest alternative.
  3. Never a manual writer of the migration ledger, and never a mechanism that depends on `migration repair`.
- **The mechanism**, if step 1 holds: a Node wrapper in `tools/supabase/` around `supabase db push`, fail-closed. It
  refuses to run unless the CLI is the proven version; the target is a proven one; both timeouts are given as finite
  integers inside fixed ranges; the expected migration file exists with the expected SHA-256 of its raw bytes; that
  file is the newest migration; and the CLI's dry run lists exactly that one pending migration. It never retries,
  never passes `--include-all`, never calls `migration repair`, and never prints a password, database URL or access
  token: its own output names no secret, and the CLI's output is redacted before it is shown.
- **Values.** The proposed values for the 001D apply are a `lock_timeout` of 5 s and a `statement_timeout` of 60 s.
  The 001D statements create new, empty tables and functions, so no statement scans existing rows; a wait for a lock on
  one of the seven live tables its foreign keys reference is bounded by the `lock_timeout`, and every statement is
  bounded by the `statement_timeout`.
- **The local proof** runs on a disposable stack whose database holds `main`'s 183 migrations, with the 001D
  migration pending:
  1. the normal apply through the wrapper succeeds;
  2. every connection the CLI opens, and every DDL statement of the migration, sees exactly the given values;
  3. a conflicting lock on a referenced table makes the apply fail within the bound;
  4. after that failure no partial schema and no history row remain (the schema dump equals the one taken before);
  5. after the lock is released, the retry succeeds;
  6. a statement-timeout failure (rehearsal values: `statement_timeout` shorter than `lock_timeout`, behind a held
     lock) also leaves a clean, retryable ledger;
  7. no migration other than the intended one is applied, and the applied schema equals the schema of a normal full
     reset.
- **Not run against hosted.** The hosted route (a direct connection or the pooler) is not proven by a local run; the
  hosted apply stays held under its own approval, and the wrapper records what a hosted run must prove first.

*(2026-11-04: step 1 found that the CLI 2.107.0 does not read `PGOPTIONS`; the run stopped at step 2, and the command room
approved the modified route `APPROVE_MODIFIED_GR37_DB_URL_OPTIONS_ROUTE`: the settings in the `options` parameter of a
passwordless `--db-url`, the password only from an owner-private `PGPASSFILE`, `PGSSLMODE=require`, the direct host only.
Item 6 was replaced by the continuation's rehearsal C, a temporary event trigger that delays the migration's DDL beyond
60 s. The local proof ran on `main`'s 184 migrations after the recomposition — §12.5.)*

## 6. The D-061 and D-065 fold

- **D-061** (the narrow owner-directed review route, the process record of #371). It is re-pinned to this candidate.
  Only the wording that folding requires changes: the Status line (identity, provenance, the fold), item 1
  (applicability: the final P1 head the command room source-reviews, which contains this record), item 2 (the reviews
  that rest on this candidate's package), item 4 (the record merges together with the implementation, never ahead of
  it), the Alternatives line (recording the route inside the implementation branch is now the command room's decision C
  of 2026-11-01) and the changelog. The narrow review exception is kept; **D-016** and
  [AGENT_WORKFLOW](AGENT_WORKFLOW.md) are not amended. #371 becomes superseded only after a future accepted P1 PR
  contains the exact final record.
- **D-065** (the owner decision). Its accepted substance is kept: Q047_STATUS CLOSED; Q049_STATUS
  CLOSED_FOR_PHASE1_TEST; E2B_STATUS OPEN; LOOKUP_LONG_TERM_RETENTION_STATUS OPEN_FOR_LIVE; the formatter exactly
  `alpha16-l32-v1` with `[a-p]`; the provider's acceptance of `[a-p]` NOT_YET_PROVEN; LG-08 and LG-09 held. Its dated
  notes on **D-051** point 7, **D-052** point 2 and **D-058** point 2, the three quick-index rows and the new D-065 row,
  and the four dated notes of [OPEN_QUESTIONS](OPEN_QUESTIONS.md) are folded as accepted. The fold wording only:
  appends a dated fold note to its Status line; turns the two links to packets that this candidate does not contain
  (the closure assessment and the owner-decision packets) into plain references by identity; names the
  owner-decision packet where the record says "the execution packet"; and adapts its changelog entry's live-range
  sentence. The closure packet's §8.4 note is not folded, because that packet is not in the candidate.
- **IDs.** No decision or question ID is allocated. In this candidate the live range is **D-001..D-029,
  D-031..D-061, D-065** (**D-030** reserved; **D-062** to **D-064** are allocated on unpublished local branches that
  this candidate does not contain, and are never reused); the next free decision ID is **D-066** and the next free
  question ID **Q-058**. A new changelog entry records the fold.

## 7. The l10n union

- **The derivation.** For each ARB file, the three-way union of the #370 base, `main` and #370: every `main` key
  with `main`'s value, plus #370's 73 `activityLog*` keys (and the English metadata) with #370's values. No key is
  lost or duplicated, and no value conflicts. The proof compares keys and values, never printing a value.
- **Generation.** The four generated files are regenerated with the repository-pinned Flutter 3.44.2 (`flutter
  gen-l10n` in `packages/l10n`, its `generate` flag set to `true` only for the run and then restored byte for byte).
  Generated Dart is never hand-merged. A second generation must produce no diff.
- **The snapshot.** `_activityLogKeyCountSnapshot` in `packages/l10n/test/order_edit_labels_test.dart` follows the
  actual union (273). That equals #370's value, so the file is #370's blob unchanged.
- **Not imported:** 001F's `posCard*` keys.

## 8. The D1 union

- Test 15 of `supabase/tests/public_surface_acl_remediation_001_test.sql` is re-derived from `main`'s file: its
  anon allowlist and every newer public surface are kept, and the six service-only card-attempt wrappers are appended
  with #370's description. The derived set has 24 entries; the guard is not weakened and the plan count is unchanged.
  *(R2: 25 entries — #379 added `storefront_menu_v5(text)` to the anon allowlist; §12.8.)*
- **The proof.** After a fresh reset of the composed candidate, the live set of `public` functions that
  `authenticated` cannot execute equals the expected set exactly.

## 9. Local validation (planned)

On disposable, task-specific local stacks only, never a linked or remote target:

- **The validation stack** (the project id and port that the frozen 001D runner accepts):
  1. a fresh reset with `main`'s 183 migrations, and the PRE record (definitions, hashes, owners and ACLs of every
     function the migration re-creates, `app.record_payment`, the card tables, the callers of `app.record_payment`);
  2. the re-versioned migration applied through the normal local path (`supabase migration up --local`), and the
     POST record;
  3. a fresh reset of the whole candidate; the 001D concurrency runner twice; the full pgTAP suite; the seven 001D
     lanes one by one; D1 and its live-set proof.
- **A fixture container** in the namespace that the 353 and acceptance-ETA runners accept locally, holding the
  composed schema: the 353 runner and the acceptance-ETA runner.
- **The rehearsal stack**: the bounded-apply proof of §5.
- **The worktree at the tested head:** the Dashboard suite, the l10n structural check and the l10n tests, format,
  analyze and the guards (no floating-point money, secrets, hard-coded strings).
- **Honesty rules.** A CI-only guard is never bypassed locally: the two committed-fixture storefront concurrency
  files refuse to run outside GitHub Actions, so a local full run ends `Result: FAIL` with them and is reported as such.
  *(Corrected 2026-11-04: a plain local full run refuses six guarded files; the four with a dedicated-database mode and
  the content-contract suite, whose guard names a dedicated local marker, ran locally in those modes; only the
  featured-items suite is CI-only — §12.9. After the recomposition the validation stack held `main`'s 184 migrations.)*
  Every result names its command, its head and its log.

## 10. Review (planned)

One focused fresh-context Claude review of: current-`main` source equality; the migration re-version; the timeout
mechanism; the **D-061** / **D-065** fold; the l10n union; the D1 union; the test evidence. Confirmed implementation or
evidence defects are fixed; wording notes do not start another round.

**Record (2026-11-04).** The review ran as one workflow of eight fresh-context Claude agents on the first composition's head
`b6a14a4f` (on `be579180`): six lenses (composition, migration re-version, the GR-37 wrapper, the fold, the l10n and D1
unions, the evidence) and two skeptics. A transcript audit found no write, Git mutation or network command by any agent.
41 findings remained after the skeptic pass, which confirmed all nine it received and re-rated four MINOR: 3 BLOCKER, 5
MAJOR, 16 MINOR, 17 NOTE. The three BLOCKERs share one cause — #379 merged with a migration that sorts after the first
re-version — and led to the recomposition (§12.2). A read-only verification of the recomposed candidate and its fixes
followed (three verifiers; 15 findings, no BLOCKER or MAJOR). Every finding of both passes is dispositioned in the
evidence folder (`review/REVIEW_AND_DISPOSITIONS.md`): fixed in commits 9 to 14 or in this results commit, recorded in the
evidence, or held for the command room (§12.6, §12.12). These are Claude reviews, not Codex reviews.

## 11. Publication preparation (planned, not executed)

Prepared locally only: the branch name, a Draft PR title and body, the exact changed-path allowlist, the commit plan,
the expected Vercel Preview and merge fan-out, the held migration-apply statement, and the closure plan for #370 and
#371 after a replacement PR is accepted. Nothing is pushed, no PR is created or edited, and #370 and #371 stay open.

## 12. Results (2026-11-04)

Recorded after the work. Sections 1 to 11 are the plan as first committed, with dated notes added. Every local run used
a disposable, task-specific target, never a linked or remote one. The records named below are outside Git: in this
task's evidence folder and its local source and review package (§12.11).

### 12.1 Identity: two compositions, one candidate

**The candidate (R2).** Branch `feat/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-FINAL-P1-current-main-r2`, linear on `main`
`0df86dcb1e5978164dcc346a40b18345e3036075` (the #379 merge), not pushed. Each commit message ends with the Work ID.

| # | Commit | Content |
|---|---|---|
| 1 | `bd5625c6` | `docs(payments)`: this packet's plan (§1 to §11), unchanged from the first composition |
| 2 | `f8a800a6` | `docs(payments)`: the accepted 001D documents, the §4 reference updates, the **D-061** / **D-065** fold |
| 3 | `0b4effb5` | `feat(db)`: the 001D migration as `20261104141959`, body unchanged |
| 4 | `21a44a62` | `feat(dashboard)`: the audit registry and labels, the l10n union, the regenerated output |
| 5 | `0c18ca10` | `test(db)`: the seven lanes, the concurrency runner, the D1 union |
| 6 | `b26a9a9d` | `infra(ci)`: the accepted `db-tests` step for the 001D runner |
| 7 | `6c90c6c9` | `feat(db)`: the GR-37 wrapper, its tests, [DEPLOYMENT](DEPLOYMENT.md) §18.2b |
| 8 | `05427a58` | `docs(payments)`: the fold and the 001D re-version notes re-pinned to the R2 base |
| 9 | `54ed8aa8` | `fix(db)`: review fixes to the wrapper and its tests |
| 10 | `513f9bae` | `docs(deployment)`: review fixes to §18.2 and §18.2b |
| 11 | `9812921c` | `docs(payments)`: review fixes to the fold records and the 001D packet's historical notes |
| 12 | `0b062a78` | `fix(db)`: verification fixes to the wrapper (debug gate, canonical paths, STOP lines, error lines) |
| 13 | `890f6ece` | `docs(deployment)`: every wrapper verdict listed; the 18.2a note |
| 14 | `eb2dc064` | `docs(payments)`: the provenance of decision C and the drift rule stated exactly |
| 15 | this commit | `docs(payments)`: these results |

The code head is `eb2dc064`. This results commit changes only this packet.

**The first composition (R1), superseded and kept.** Branch
`feat/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-FINAL-P1-current-main`, head `b6a14a4f`: eight commits on `be579180`, with the
migration as `20261104111118`. The focused review of §10 ran on it. It is not published, and nothing in R2 descends
from it.

**No old history.** None of `b6a14a4f`, #370's head, #371's head or the D-065 head is an ancestor of the R2 head.

### 12.2 The #379 drift and the recomposition

**What happened.**
- At 13:20Z, #379 re-versioned its migration from `20261102140930` to
  `20261104131256_bizbot_storefront_cinematic_001b_appearance.sql` (commit `8b5cfbb6`).
- Its own release record states that the migration was applied to hosted under that version. This task never contacted
  hosted and cannot confirm it.
- At 13:46:43Z, #379 merged into `main` as `0df86dcb`. Its first parent is `be579180`, so #379 is the only change on
  `main`.

**Why the first composition could not stand.** `20261104111118` sorts before `20261104131256`.
- With #379 merged, the wrapper refuses a 001D file that is not the newest, and the CLI would need the forbidden
  `--include-all`.
- Against the hosted ledger #379 describes, the dry run fails on a remote version that the local folder lacks
  (rehearsal D, §12.5).

**The rule followed.** The continuation's section 7: if #379 merged, stop before packaging, recompose from the new
`main`, re-evaluate the migration version, re-derive D1 and rerun the complete validation. The review reported the merge
in the same pass (§10).

**Overlap.**
- Of #379's 218 paths, only the D1 test file is also a candidate path.
- #379 changed no l10n path, no register and no `ci.yml`, and no function that 001D creates: its migration creates ten
  storefront functions, 001D's creates 62, and none is shared.
- It added the workflow `.github/workflows/cinematic-integration.yml`, which runs on every pull request.
- It changed the Vercel ignore engine.

**The recomposition** (`r2/R2_DERIVATION.txt`, `r2/R2_DELTA_PROOF.txt`). Commits 1 to 7 carry the reviewed blobs, with
three adaptations only:
1. The migration moves to `20261104141959`, generated by `supabase migration new` at 14:19:57Z after checking `main`.
   It is the same blob.
2. Nine references follow the version, in six files: the 001D packet (2), `DECISIONS.md` (1), the regression lane (1),
   `DEPLOYMENT.md` (2), the wrapper (1) and its test (2).
3. The D1 file is a clean three-way merge of the new `main`'s file and the reviewed change.

R2 commit 7 also carries the reviewed fix of the wrapper test's synthetic token (R1 commit 8). The literal that R1
commit 7 held is therefore never in R2's history.

30 of the 38 paths are byte-identical to the reviewed head. Commit 8 re-pins the base facts that the fold text and the
001D notes state: `main` `0df86dcb`, the R2 branch name, eleven later migrations.

### 12.3 Composition

`logs/COMPOSITION_MANIFEST_R2_FINAL_HEAD.txt`, PASS.

**38 paths differ from `main`** (14 added, 24 modified):
- **22** equal #370's blobs, the re-versioned migration included.
- **13** differ for a permitted reason:
  - the 001D packet and the regression lane: re-version references and dated historical notes;
  - `docs/DECISIONS.md`: the fold;
  - `docs/OPEN_QUESTIONS.md`: `main`'s blob plus the four accepted **D-065** notes, which is the accepted blob
    `ab86b547`;
  - the three ARB files and the four generated files: the l10n union;
  - the D1 file: the D1 union;
  - `docs/DEPLOYMENT.md`: the GR-37 documentation.
- **3** are new: this packet, `tools/supabase/bounded-db-push.mjs` and its test.

**All 34 #370 paths are accounted for.** Neither earlier migration filename is present.

**Nothing else differs from `main`.** These keep `main`'s trees: `supabase/functions` (so `pos-card-charge` and
`providerProfile` stay absent), `apps/pos`, `apps/kds`, `apps/kiosk`, `apps/admin`, `packages/feature_admin`,
`services`, `site`, `storefront` and `e2e`.

**Excluded content is absent:**
- the G1 / **D-062** migration;
- any 001E, W1, **D-063** or **D-064** source;
- any 001C, 001F or 001G source;
- any 001H tool;
- any `posCard*` key.

### 12.4 The migration re-version (M-A)

- **The final file.** `supabase/migrations/20261104141959_bizbot_zcredit_001d_server_ledger.sql` is #370's blob
  `b94a34176d6e…` unchanged: 382,717 bytes, no CR byte, SHA-256
  `468768f89029a0fb131869f754d5374127930b8bf05b48cd8de19d645546352e`.
- **What sorts after the reviewed version.** Eleven later `main` migrations sort after `20261023225657`:
  `20261026144133` to `20261104131256`, the last being #379's.
- **The intermediate version** `20261104111118`, the first composition's, was applied only on this task's disposable
  local stacks.
- **References.** The active references follow the final version. Prose that deliberately names `20261023225657` or
  the first composition keeps it and is marked historical.
- **Not used:** `--include-all`, `migration repair`, any edit of a hosted ledger.
- **G1** (`20261027211023`) must be re-versioned after `20261104141959`.

### 12.5 GR-37: the bounded migration apply

**Investigation and approval.** Step 1 found that the CLI 2.107.0 does not read `PGOPTIONS`: no session and no DDL
statement saw the values. The libpq `options` parameter of `--db-url` does reach the session. The run stopped at step
2, and the command room approved the modified route (`APPROVE_MODIFIED_GR37_DB_URL_OPTIONS_ROUTE`):
- the settings in the `options` parameter of a passwordless `--db-url`;
- the password only from an owner-private `PGPASSFILE`;
- `PGSSLMODE=require`;
- the direct host only.

**The mechanism** is [DEPLOYMENT](DEPLOYMENT.md) §18.2b. `tools/supabase/bounded-db-push.mjs` at the code head has
SHA-256 `fafac6d0fcb6c098ce94240ad1297e363268d26d8c1d2bd9111b8522bb11da6b`. Its 20 unit tests pass on Node 22.14.0 and
24.22.1.

**What the review and the verification changed** (commits 9 and 12):
- **STOP lines.** Every failure after the CLI starts ends in a STOP line: `DRY_RUN_FAILED` (exit 3), `PUSH_FAILED`
  (exit 3) or `POSTCHECK_MISMATCH` (exit 4). A refusal prints `REFUSED <code>` (exit 2) and pushes nothing.
- **CLI advice.** The CLI's advice to repair, pull, reset or pass `--include-all` is never relayed. A line the CLI flags
  as an error is always kept.
- **The passfile.** It is read as the CLI's reader (pgpassfile v1.0.0) reads it, and an ambiguous line refuses. Its
  location is compared in canonical long form, so a `..`-prefixed folder, an 8.3 short name or a device-path spelling
  cannot escape the gate.
- **Debug.** A non-empty `NODE_OPTIONS`, an inspector or preload flag, or an active inspector refuses. Node 24's
  configuration-only `--inspect-port` default does not.

**The CLI pin.**
- `supabase.exe`: `bb59c6b769f6fa8817b0a7ee98cf791ad29d65268dd0c76df6ced6d22a8a2933`.
- `supabase-go.exe`: `4fb853b875b1e44c886e5e298b8b84be1399e23f1db629d2e8e6936c5e454125`.

These are the members of the official 2.107.0 Windows x64 archive; its pinned asset hash `2d909c0cae7c…` was
re-verified. `supabase.exe` runs the `supabase-go.exe` beside it, so both are checked.

**The URL shape**, with private values as placeholders:
`postgresql://<user>@<direct-host>:5432/<database>?options=-c%20lock_timeout%3D5s%20-c%20statement_timeout%3D60s%20-c%20application_name%3Dbizbot_gr37_001d_v1`.

**The final proofs** are in `gr37/r2_final/`. They are for this exact wrapper, and each tool is copied there with its
SHA-256.

*The password-required transport target.* A disposable PostgreSQL 17 that requires `scram-sha-256` on every TCP
connection and serves TLS. Its random password existed only in memory, in the private passfiles and in the container,
and is not kept.

- **The CLI alone: 19 of 19.**
  - The correct passfile connects over TLS with `scram-sha-256`.
  - A wrong or an absent passfile fails, with no session.
  - With neither a passfile nor a password variable the CLI also fails. Whether it tried a default password is not
    established.
  - `PGSSLMODE=require` refuses a server without TLS, and the `disable` control proves that the variable is read.
- **The TLS matrix: 9 of 9, each row asserted.**
  - Without server TLS, only `disable` connects, in plaintext.
  - With server TLS, every mode connects: over TLS, except `disable`.
  - So the CLI refuses a server without TLS whether `PGSSLMODE` is unset, `prefer` or `require`; `require` is an
    explicit second guard.
- **The wrapper: 17 of 17.** The correct passfile works. Each of these fails with nothing pushed:
  - a wrong passfile (with `RESULT: DRY_RUN_FAILED` and no CLI advice);
  - an absent passfile;
  - a password-bearing URL;
  - an inherited ACL;
  - a passfile inside the evidence folder;
  - a debug variable;
  - `NODE_OPTIONS`;
  - an ambiguous passfile line;
  - two pending migrations;
  - a server without TLS.

*Process arguments.* Process tables were sampled during the wrapper's dry run and during rehearsal B's blocked push.
Both executables' `db push` command lines were observed, none empty. No command line holds a password, a passfile path
or a password-bearing URL; only the passwordless URL with the fixed options appears.

*Timeout propagation.* The same authenticated session (`scram-sha-256`, TLS) showed `lock_timeout=5s`,
`statement_timeout=1min` and `application_name=bizbot_gr37_001d_v1`, set by the client. In the rehearsals, every one of
the migration's 145 DDL statements ran with them.

*Composed-schema rehearsals: 22 of 22.* The disposable stack held `main`'s 184 migrations (`0df86dcb`) with only the
001D file pending. The `postgres` role had a random password, so the passfile was the only way in.
- **B, lock timeout.** With `ACCESS EXCLUSIVE` held on `public.orders`:
  - the push failed by `lock_timeout` (SQLSTATE 55P03) after 8,097 ms;
  - the server saw the session wait on the lock for about 4.7 s (4.0 to 5.6 s required);
  - 8,097 ms is within 5 s plus A's unobstructed apply (2,705 ms) plus 2 s;
  - the ledger, the schema fingerprint and the card objects equalled PRE;
  - after the release, one retry applied 001D and added exactly its history row.
- **C, statement timeout.** A temporary event trigger in the disposable database delayed the migration's first DDL by
  65 s:
  - the push failed by `statement_timeout` (SQLSTATE 57014) after 62,806 ms;
  - the rollback was complete;
  - the trigger was removed;
  - one retry applied 001D.
- **A, normal.** The dry run listed exactly 001D. The bounded apply added exactly one history row. Its schema
  fingerprint (`b49e3d13…`) and its history rows equal those of the CLI's normal local path
  (`supabase migration up --local`).
- **The fingerprint** is a schema-only dump of `app`, `public` and `supabase_migrations`, plus the card-object counts and
  the ledger. That is adequate here: the migration creates objects only in `app` and `public`.

*Rehearsal D, a hosted ledger ahead of the candidate: 12 of 12 (additional).* A stand-in version newer than 001D
(`20261104235959`) was recorded by the CLI's normal local path and is absent from the local folder. The wrapper refused
before any push, in check mode and with `--apply`, with `RESULT: DRY_RUN_FAILED`. It relayed the remote-ahead error and
none of the CLI's repair, pull, reset or `--include-all` advice. The ledger and the schema were unchanged.

*Migration history PRE / POST.*
- Before each rehearsal: 184 rows, the last `20261104131256`.
- After a timeout failure: 184 rows, with the same list digest.
- After each retry and after A: 185 rows, the last `20261104141959`.

*The password-bearing URL route was not used.* The wrapper refuses such a URL. The transport proofs and the rehearsals
used only the passwordless URL and the passfile, and the process tables show no password. Only the investigation before
the stop passed the local stack's documented default credential inside a local `--db-url`; this is recorded in the stop
report. No real or hosted password was used.

**Earlier runs, kept and disclosed:**
- `gr37/`: the first composition's proofs, for its wrapper `d0345ed7…`.
- `gr37/r2/`: the proofs for R2's first code head, wrapper `d6ed2f8a…`. They include a wrapper-phase run of 16 of 17,
  whose new W2 check mistook the wrapper's own "no `--include-all`" STOP line for relayed advice.
- A transport run whose TLS control wrongly assumed that `prefer` allows plaintext.
- A rehearsal run whose state capture waited behind the held lock.
- Wrapper runs from before the URL-shape and summary fixes.

**The hosted PRE gate stays held** ([DEPLOYMENT](DEPLOYMENT.md) §18.2b):
1. The direct host is reachable; otherwise STOP, never a pooler.
2. TLS is active on the session.
3. The project, database and user are the expected ones.
4. The passfile entry matches exactly that endpoint.
5. There is no pooler fallback.
6. The settings are observed or source-pinned.
7. The hosted ledger lists exactly `main`'s versions (`0df86dcb`: 184), so the dry run shows only 001D.

### 12.6 The D-061 / D-065 fold

**The registers.**
- `docs/DECISIONS.md` is #370's blob plus insertions.
- `docs/OPEN_QUESTIONS.md` is the accepted D-065 blob `ab86b547`.
- No decision or question ID is allocated; the next free IDs are **D-066** and **Q-058**.
- **D-016** and [AGENT_WORKFLOW](AGENT_WORKFLOW.md) are unchanged.

**D-061: every passage changed from #371's record.**

| Passage | Change |
|---|---|
| Status line | re-pin and fold; the R2 base and branch; decision C (recorded in §11 of the 001H readiness packet at `a7af6bc8`) folds the record into the final 001D head, and the authorization of 2026-11-04 applied it to the P1 candidate |
| item 1 | the P1 head and branch |
| item 2 | the focused review of the P1 candidate added to leg (a) |
| item 4 | the record merges only inside the P1 merge |
| Alternatives | decision C and the authorization of 2026-11-04 |
| Consequences | "001D merge" becomes "P1 merge"; the exception's boundary is the command room's source-matched review |
| Related | **D-065** and this packet |
| Changelog note | the fold; the entry's applicability, live range and next ID marked historical |

Decision C enumerated the Status line, item 1, item 4, the Alternatives line and the changelog. Item 2, Consequences
and Related go beyond that list and are held for the command room: it accepts them, or they are reverted.

**D-065: every passage changed from the accepted record.**

| Passage | Change |
|---|---|
| Status line | a dated fold note: the R2 base; the local records and the identifiers they define, by identity; the Edge `KEY_FORMATS` and `providerProfile` scoped to the 001E function, which the candidate lacks |
| item 2 | the owner-decision packet named |
| Related | the two packet links as references by identity, plus this packet |
| Changelog entry | "Recorded at `e005eaba` on a branch stacked on …"; the live-range sentence |

Its substance is unchanged:
- Q047 CLOSED;
- Q049 CLOSED_FOR_PHASE1_TEST;
- E2B OPEN;
- LOOKUP_LONG_TERM_RETENTION OPEN_FOR_LIVE;
- `alpha16-l32-v1` `[a-p]`, NOT_YET_PROVEN;
- LG-08 and LG-09 held.

The fold's changelog entry lists both.

**Held for the command room.** D-061's re-pinned route now covers the whole P1 head, but its item 3 ("approves nothing
else … 001H") and its Consequences predate the fold. Whether the route also covers the D-065 record and the GR-37
wrapper, or those keep the default review gate, is a scope decision. No text was changed for it.

### 12.7 The l10n union

- **Unchanged by #379,** which touched no l10n path.
- **The ARB files** are the three-way union of the #370 base, `main` and #370 (`git merge-file`, no conflict). Each
  locale has 2,960 unique messages, with ar / he / en parity, and 273 `activityLog*` messages. A duplicate
  `posShiftDemoNote` key is inherited from `main` and left unchanged.
- **The generated files** are the output of `flutter gen-l10n` (3.44.2) over the union. Two generations were identical,
  and each file's delta over `main` equals #370's (+438, +250, +250, +245).
- **The snapshot test** equals #370's blob (273).
- **No `posCard*` key.**

### 12.8 The D1 union

- **The expected set at the R2 head has 25 entries:**
  - the seven-entry anon allowlist, including #379's `storefront_menu_v5(text)`;
  - the twelve service-only web-request and notification wrappers;
  - the six card-attempt wrappers.
- **The guard is not weakened.** The plan count stays 62, and nothing of `main`'s guard is removed.
- **The live set** of `public` functions that `authenticated` cannot execute, after a fresh reset of the R2 candidate,
  equals it exactly: 25, none missing, none extra.

### 12.9 Validation

**Database** (`validation/r2_db_run1`, run at `9812921c`). Its `supabase/` tree `b12a5ac4…` is unchanged at the code
head, and the harness equals it (613 files, 0 differ).

| Step | Result |
|---|---|
| Drift check before the full reset | `main` `0df86dcb`; #379 merged |
| PRE: fresh reset with `main`'s 184 migrations | PASS; ledger 184, last `20261104131256` |
| 001D through `supabase migration up --local`, POST | PASS; ledger 185, last `20261104141959` |
| PRE / POST against the accepted W2–W6 captures | PASS: the re-created functions as accepted; `app.record_payment` unchanged and called only by `app.sync_push`; `public` functions 177 → 185, exactly the eight card wrappers |
| Fresh reset of the whole candidate | PASS (185) |
| 353 runner | PASS (3 race assertions) |
| Acceptance-ETA runner | PASS (106 assertions, 9 races) |
| 001D concurrency runner, twice | PASS, PASS (41 scenarios each) |
| Full pgTAP suite | `Files=335, Tests=13342, Result: FAIL`: 329 files pass; six guarded files refuse by their own guards and run no test |
| The four dedicated-database suites, in their dedicated mode | PASS: SEO discovery 205 and 33, SEO consent 35, online-order controls 26 |
| The content-contract suite, with its dedicated local marker | PASS (38) |
| The featured-items suite | not run locally: CI-only; its CI marker was never set |
| Seven 001D lanes | PASS: 139, 397, 273, 140, 244, 343, 177 (1,713) |
| D1 file; live set | PASS; 25 equal |

How the guarded and fixture-based suites ran:
- **The dedicated-database suites** ran on databases restored from the dump of the fresh candidate reset, each named
  and marked as its guard requires.
- **The content-contract suite** ran on the disposable stack's `postgres` database, with its marker on the session only.
  It ran last, because it writes rows.
- **The 353 and acceptance-ETA runners** ran on a task-owned fixture: the pinned image, one internal network without
  IPv6, no published port, the composed schema.

**Flutter, Node and guards** (`validation/r2_ui_run2`, at the code head `eb2dc064`): all pass: format (1,810 files, 0 changed), the l10n structure check, the l10n tests (95), the Dashboard suite (2,852 passed, 16 skipped), `melos analyze` (no issues), the wrapper's unit tests (20), the Vercel filter tests (170 passed, 2 skipped) and the three guardrails (no floating-point money, no committable secrets, no hard-coded strings); the worktree stayed clean.

The wrapper's unit tests also pass on Node 24.22.1 at `eb2dc064` (`validation/r2_node24`: 20 of 20).

**Earlier runs, kept and disclosed:**
- R2 first code head: `validation/r2_ui_run1`, at `9812921c`, all PASS.
- First composition: database runs 1 to 3, and the Flutter runs 1 and 2.
  - Database run 1 had tool path errors; run 2 had two harness defects, fixed outside Git.
  - Flutter run 1 found that the secret-leak guard reported the wrapper test's contiguous synthetic `sbp_` literal.

**Not run locally:**
- the other CI `validate` steps: packages, apps, the storefront, site and Edge-function suites, and the Android
  guardrails. The candidate's paths do not touch them beyond the l10n union, which `melos analyze` compiles in every
  package;
- #379's `cinematic-integration` workflow.

### 12.10 Review and verification

- **The focused review** (§10) ran on the first composition's head.
- **A read-only verification of R2 and its fixes followed:** three fresh-context verifiers, 15 findings, no BLOCKER or
  MAJOR.
  - Its five MINOR findings were all fixed: the gates' path spellings, the verdict lines, the stated provenance, and
    this packet's base facts and evidence record.
  - Its NOTEs were fixed or recorded.
- **Every finding of both passes is dispositioned** in the evidence folder (`review/REVIEW_AND_DISPOSITIONS.md`).

### 12.11 Publication preparation (not executed)

**Prepared**, outside Git and in the package (`publication/`):
- the R2 branch name;
- a Draft PR title and body, marked held;
- the exact allowlist of the 38 changed paths, with their blobs and SHA-256;
- the commit plan;
- the fan-out;
- the held migration-apply statement;
- the closure plan for #370 and #371: each is closed only after a replacement PR is accepted, with a pointer to it.

Nothing is pushed, no PR is created or edited, and #370 and #371 stay open.

**Expected fan-out**, from the repository's own ignore engine at the code head, run in a throwaway clone:
- **A push** would build Previews of `resto-flow` (nine product runtime paths: the Dashboard audit files and the l10n
  files) and of `bizbot-pos-alert-cron` (no ignore step). `bizbot-site` and `bizbot-storefront` would ignore it.
- **A merge** would redeploy `resto-flow` and `bizbot-pos-alert-cron` to production.
- **A pull request** also triggers `validate`, `db-tests` and #379's `cinematic-integration`.
- **No migration is applied** by any Vercel build step or CI step.

### 12.12 Preservation and holds

**Preserved.**
- #370 (`54b19ab5`), #371 (`53d6a6ad`), #314 (`54346b37`) and #315 (`4e8c81f6`) are unchanged and open.
- This task ran no hosted SQL and applied no migration to hosted.
- It deployed nothing, installed no secret or configuration, and called no provider.
- It used no terminal, card, printer or APK.
- Every flag stays OFF, and `providerProfile` stays `null`.

**Held.**
- Push, PR, merge and the hosted apply.
- The command room's decisions:
  - the pinned migration name: `20261104141959` replaces the continuation's `20261104111118` under its section 7;
  - the D-061 passages beyond decision C;
  - D-061's scope over the D-065 record and the GR-37 wrapper.
