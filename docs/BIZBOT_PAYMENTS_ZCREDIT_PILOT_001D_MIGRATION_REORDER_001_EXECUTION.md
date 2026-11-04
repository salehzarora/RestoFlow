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

## 3. Composition method

- **A fresh branch on current `main`.** `feat/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-FINAL-P1-current-main` starts at
  `be579180`. Nothing of the old local stack is merged, rebased or cherry-picked, and none of its 116 commits is
  reachable from the candidate.
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

  Review fixes, if any, follow as separate commits before the results commit.

## 4. The 001D migration: M-A re-version

- **The old file.** `supabase/migrations/20261023225657_bizbot_zcredit_001d_server_ledger.sql` (#370 blob
  `b94a34176d6eefb8d1a53c7907d1b4272de7dcfd`, content SHA-256
  `468768f89029a0fb131869f754d5374127930b8bf05b48cd8de19d645546352e`). It was never applied to hosted.
- **The new version** is generated by the installed Supabase CLI (2.107.0), `supabase migration new
  bizbot_zcredit_001d_server_ledger`, only after the check of §2; it must sort after every migration on `main`
  (`20261102015942`). The CLI's empty file then receives the exact #370 blob: the body bytes are unchanged and only the
  filename changes. The old filename is removed from the candidate.
- **References.** Every source, test or document reference that tracks the active filename is updated. Historical prose
  that deliberately names the old reviewed filename keeps it and is marked historical.
- **Not used:** `--include-all`, `migration repair` and any edit of a hosted migration ledger.
- **G1.** The G1 / **D-062** migration (`20261027211023`) is not imported. Its later re-version must be newer than this
  candidate's 001D version.
- **#379.** Its `20261102140930` sorts before this candidate's version. If #379 lands first, the order is still valid.
  If this candidate lands first, #379 needs its own re-version under its own Work ID before it can be applied.

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
  Every result names its command, its head and its log.

## 10. Review (planned)

One focused fresh-context Claude review of: current-`main` source equality; the migration re-version; the timeout
mechanism; the **D-061** / **D-065** fold; the l10n union; the D1 union; the test evidence. Confirmed implementation or
evidence defects are fixed; wording notes do not start another round.

## 11. Publication preparation (planned, not executed)

Prepared locally only: the branch name, a Draft PR title and body, the exact changed-path allowlist, the commit plan,
the expected Vercel Preview and merge fan-out, the held migration-apply statement, and the closure plan for #370 and
#371 after a replacement PR is accepted. Nothing is pushed, no PR is created or edited, and #370 and #371 stay open.
