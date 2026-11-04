# BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-CINEMATIC-PROOF-001 — execution packet: the bounded cinematic migration-sequence proof for PR #381

Work ID: `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-CINEMATIC-PROOF-001`, a follow-up of
[BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-MIGRATION-REORDER-001](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001D_MIGRATION_REORDER_001_EXECUTION.md)
on the existing Draft PR #381 branch `feat/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-FINAL-P1-current-main-r2`. It replaces
the cinematic migration-atomicity proof's newest-migration guard with an exact, pinned migration sequence: the #379
target, then exactly one reviewed follow-up, the 001D migration.

The packet contains no credential, terminal number, password, TPN, PIN-pad identifier, KEY, device serial, card datum,
provider payload, e-mail address, database URL, access token or real production UUID.

## 1. Request and boundary

- **The request.** The command-room authorization of 2026-11-04, "COMMAND-ROOM AUTHORIZATION — BOUNDED CINEMATIC
  MIGRATION-SEQUENCE FOLLOW-UP PROOF FOR PR #381". It is kept outside Git with a SHA-256 sidecar
  (`e657c80f46130fd1672912e97a4750d299518af7a54a0d26e08bb48115fad125`).
- **The facts it accepts.** PR #381 at head `517d41ac3ae63e86f14f3b29a1064c946c915a8d` (tree
  `e3e7fc98d4ca2aee06b52416ea87043b4c4891f4`) on `main` `0df86dcb1e5978164dcc346a40b18345e3036075`. Its CI:
  `validate` SUCCESS; `db-tests` SUCCESS (335 files, 13,704 assertions); the cinematic downstream guards SUCCESS; the
  cinematic real Auth / Storage / Dashboard job FAILURE at the migration-atomicity runner's deliberate newest-migration
  guard, with the steps after it skipped. **The failure is not waived**: this Work ID corrects the proof, and fresh CI
  must pass.
- **The merge order it selects.** PR #381 first; PR #380 second, after it is recomposed on the future `main` that
  contains #381 (§7).
- **Scope: exactly four tracked paths.** This packet;
  `supabase/tests/support/cinematic_001b_migration_contract.mjs`;
  `supabase/tests/support/cinematic_001b_migration_wrapper.test.mjs`;
  `supabase/tests/support/run_cinematic_001b_migration_atomicity.mjs`.
- **Not changed:** `.github/workflows/cinematic-integration.yml`; the 001D migration and every other migration; payment
  SQL, Edge, POS or Dashboard source; the D1 test; l10n; **D-061** and **D-065**; the GR-37 wrapper; anything of
  PR #380.
- **History.** One additive commit on the existing branch, pushed normally (no force, no tag, no other branch). No
  amend, rebase, reset or history rewrite.
- **Not authorized and not done:** a merge; marking #381 ready for review; auto-merge; an admin bypass; closing #370 or
  #371; changing #314, #315 or #380; hosted SQL; applying a migration to hosted; an Edge deploy; installing a secret;
  a provider call; terminal or card use; an APK. D-061 leg (c) is NOT GIVEN. E2-B, LG-08 and LG-09 stay held. No Codex
  review is requested; one focused fresh-context Claude delta review runs (§8).

## 2. Resume point (read-only, 2026-11-04T20:44Z)

Recorded outside Git (`preflight/PREFLIGHT.txt`); every check passed.

- `origin/main` is `0df86dcb`. The local branch, the remote branch and `refs/pull/381/head` are `517d41ac`, tree
  `e3e7fc98`. The worktree is clean and the local branch has no upstream.
- PR #381 is OPEN and a Draft, auto-merge is off and no review is requested.
- #370 (`54b19ab5`), #371 (`53d6a6ad`), #314 (`54346b37`) and #315 (`4e8c81f6`) are at the heads recorded at the #381
  publication, with unchanged last-update times.
- PR #380 is OPEN, a Draft and unmerged; its author is still pushing to it (head `e006ee2f` at 20:44Z). It is not
  touched.
- `providerProfile` stays `null`: the head has no `supabase/functions/pos-card-charge`, and no path outside `docs/`
  names `providerProfile`.

## 3. The failure being corrected

- **Where.** Step 10 of `Cinematic · real Auth / Storage / Dashboard` runs
  `run_cinematic_001b_migration_atomicity.mjs`. In its `preflight` phase the runner asserted that the newest migration
  is #379's `20261104131256_bizbot_storefront_cinematic_001b_appearance.sql`, failing with "This narrow proof must be
  reviewed if later migrations are introduced". #381 adds `20261104141959_bizbot_zcredit_001d_server_ledger.sql`
  after it, so the guard fired, and steps 11–15 (the Edge function, the fixtures, the Dashboard and Storefront builds,
  the acceptance run and the cross-restaurant rejection) were skipped.
- **Why the guard alone cannot simply be relaxed.** The runner copied the whole migration directory into its
  late-failure workdir and finished with a plain `supabase migration up --local`, which applies every pending
  migration. With a later migration present, the target phase would also have applied 001D, so the target-only
  evidence would no longer be target-only.

## 4. The pinned sequence

The contract proves the exact directory listing, in the order the Supabase CLI applies it (byte-wise file-name order):

| Position | Migration | Pinned by |
|---|---|---|
| 1–183 | the 183 migrations of `main` before the #379 target, `20260619155649_rf014_multitenant_core_rls.sql` … | their count and the SHA-256 of their names joined by `\n`: `6ee60a7fc86607ebbcd69492f551f673622336c4476823ee8a2c014106f15643` |
| 183 | the #379 predecessor `20261102015942_bizbot_storefront_seo_discovery_001.sql` | its name, directly before the target |
| 184 | the #379 target `20261104131256_bizbot_storefront_cinematic_001b_appearance.sql` | #379's own SHA-256 `a276aef4fdd30b35272939e51d649bff3dfeb70b6c806ecb7c2edee94ceb263b`; no top-level transaction control; no legacy reader re-created |
| 185 | the reviewed follow-up `20261104141959_bizbot_zcredit_001d_server_ledger.sql` | the SHA-256 of its exact LF bytes `468768f89029a0fb131869f754d5374127930b8bf05b48cd8de19d645546352e`; no top-level transaction control |

The proof is exact, not a generic "accept every later migration" mechanism. It refuses:

- a file name that is not a 14-digit version followed by a lower-case snake-case name and `.sql`, and any directory
  entry that is not a regular file;
- a duplicate version, and versions that are not strictly ascending in the given order;
- a missing target, a missing predecessor, or a migration between them;
- an added, removed or renamed migration anywhere in the 183-migration prefix (the prefix is pinned by name; its bytes
  are not, see §10);
- a missing follow-up; an unknown migration after the target; a migration between the target and the follow-up; and a
  second migration after the follow-up;
- changed, CRLF-converted or otherwise different follow-up bytes, and top-level transaction control in it (`BEGIN`,
  `START TRANSACTION`, `COMMIT`, `END`, `ROLLBACK`, `ABORT`, `SAVEPOINT`, `RELEASE`, `PREPARE TRANSACTION`), checked
  with #379's lexical statement scanner so that PL/pgSQL `BEGIN … END` inside dollar quotes is not mistaken for it;
- the pinned target or follow-up bytes under any other name (a renamed or copied migration with the same contents).

Any future migration therefore fails this proof until a reviewed change extends the pinned sequence.

## 5. The runner

The runner keeps every #379 safeguard unchanged: the ephemeral-CI check before any subprocess, no arguments, the
pinned CLI 2.107.0, the runner-local Docker daemon and container checks, the fresh-stack check, the historical
wrapper-only proof, the final-migration proof, fixed assertion messages only, and the artifact location rules. Its
`preflight` phase now reads the migration directory's raw bytes and applies the contract in place of the
newest-migration guard. Then:

- **A. Reset to the predecessor.** `supabase db reset --local --version 20261102015942 --no-seed --yes`. The target's
  readiness surfaces are absent, and the migration history holds exactly the 183 prefix versions. The schema, history
  and legacy-reader snapshots are taken.
- **B. The intentional late failure, in a disposable prefix workdir.** The workdir holds `config.toml`, the 183 prefix
  migrations (the tracked bytes) and the target with the appended late-failure block, and nothing else; its listing is
  verified before use. `supabase migration up --local --workdir <dir>` must fail with `BIZBOT_CINEMATIC_LATE_FAILURE`
  and SQLSTATE `P0001`. The readiness surfaces stay absent, the schema snapshot and the whole migration history are
  byte-identical to phase A, and the tracked target migration is unchanged.
- **C. The correct target alone.** A second disposable workdir holds the same prefix and the exact tracked target.
  `supabase migration up --local --workdir <dir>` applies the target alone: the readiness surfaces are present with
  exactly one target history row, and the history is exactly the prefix plus the target. The legacy readers'
  definitions, ACLs and owners are byte-identical to phase A. The target-only evidence is captured: the schema and
  history SHA-256, and a catalog snapshot of the target's surfaces (the ten functions it creates or replaces, with
  their definitions, ACLs, owners and comments; the `appearance` column; the table's constraints).
- **D. The reviewed follow-up.** `supabase migration up --local` in the repository then has exactly one pending
  migration, 001D. The history is exactly the prefix, the target and the follow-up: one 001D row and no other
  migration later than #379. Every history row through the target is byte-identical to phase C, the readiness
  surfaces are unchanged, the legacy readers are byte-identical to phase A, and the target-surface snapshot is
  byte-identical to phase C. Finally every tracked migration source is byte-identical to the preflight read (the same
  names, the same bytes).

The runner does not test 001D's behavior; its 41 runner scenarios and seven pgTAP lanes stay in `db-tests`. The
receipt (`migration-atomicity.json`) gains the sequence summary, the follow-up proof and each phase's SHA-256 values
(its former `after_schema_sha256` and `after_history_sha256` become the `target_only_*` and `follow_up_*` pairs); it
carries no credential and no raw command output.

## 6. Unit tests

`cinematic_001b_migration_wrapper.test.mjs` keeps #379's seven tests and adds tests that prove:

- the current #381 sequence passes, and the target prefix ends at #379 and excludes 001D, which is applied only as the
  reviewed follow-up;
- unknown later, interleaved (between the predecessor and the target, deep in the prefix, and between the target and
  the follow-up) and second later migrations fail;
- a missing target, predecessor or follow-up fails;
- reordered input and a duplicate version fail, and so does the follow-up moved before the target by version;
- changed follow-up bytes fail (also when only the end of the file changes), and so do CRLF-converted and renamed
  follow-up bytes and the pinned bytes copied under another name;
- each listed form of top-level transaction control fails with the structural refusal, whether it is appended,
  prepended or placed between two statements, and also with line breaks or tabs between its words, while
  dollar-quoted PL/pgSQL bodies do not;
- non-conforming names, an empty listing and sources that are not raw bytes fail (refusing a directory entry that is
  not a regular file is the runner's own check);
- the #379 and 001D hashes, the predecessor and the prefix fingerprint are pinned to the reviewed values, and the
  target's function list matches the reviewed target SQL.

**Checkout forms.** The tests read the working tree. Only when Git reports a file as `i/lf w/crlf` (a Windows checkout
with `core.autocrlf`) do they convert its CRLF to LF before calling the contract. The contract and the runner always
hash the raw bytes, so a committed CRLF, or a CRLF in the Linux CI checkout, is refused at run time.

## 7. The #380 forward rule (record only)

- #381 is selected to merge first. After it merges, #380 must be recomposed on the new `main`.
- #380's future reviewed sequence must become:

  | Version | Migration |
  |---|---|
  | `20261104131256` | the #379 target |
  | `20261104141959` | #381 / 001D |
  | `20261104154000` | #380 product media |
  | `20261104155000` | #380 scene |

- #380 must then extend this pinned sequence, re-derive D1 and keep both of its `docs/API_CONTRACT.md` changes, and it
  needs its own fresh CI and review.
- This record authorizes no merge of #381 or #380. Nothing of #380 is imported, merged or modified here.

## 8. Local validation and review (planned)

- The wrapper unit tests in two checkout forms: a Windows `core.autocrlf=true` checkout and an LF checkout. Locally
  that is Node 22.14.0; CI's step 8 runs the same file on Node 24.
- `node --check` on the three modules, and a format check of the four paths (ASCII only, no tab, no trailing
  whitespace, a final newline, LF in the index).
- Mutation testing of every new contract condition, in a scratch clone, never in the worktree; every mutant must be
  killed. Negative checks of the refusal messages.
- `git diff --check`, and `tools/check_secrets.sh`, `tools/check_no_float_money.sh` and
  `tools/check_no_hardcoded_strings.sh`.
- The runner is not run locally: its ephemeral-CI guard is not bypassed. Fresh GitHub CI proves it after the push.
- One focused fresh-context Claude delta review of exactly the four-path change; only confirmed proof or test defects
  are fixed.

## 9. Commit, push and CI (planned)

- One commit with this Work ID, pushed normally to the PR #381 branch. The remote head and the PR merge ref are read
  back at once.
- The PR #381 body is updated only to remove the statement that the cinematic failure is expected, to record this
  Work ID and the new head, to state that the bounded proof accepts exactly the pinned 001D follow-up, to keep the
  #381-before-#380 order, and to keep merge, hosted apply, E2-B, LG-08 and LG-09 held. No tracked file changes for
  the body.
- Fresh CI must give `validate`, `db-tests`, the cinematic downstream guards and the cinematic real Auth / Storage /
  Dashboard job SUCCESS, with steps 11–15 executed, and every Vercel check success or ignored-success. A failure is
  reported as it is: no automatic rerun and no second correction without a new authorization.

## 10. Results (local, 2026-11-04)

Recorded outside Git. Each result belongs to one source state: the scripts record the tracked-diff and packet hashes
before and after every run. The commit, the push and the fresh CI are recorded outside Git and in the PR.

- **Unit tests.** `cinematic_001b_migration_wrapper.test.mjs` has 17 tests (#379's seven and ten new); all 17 pass in
  three checkout forms: this worktree (`core.autocrlf=true`; 184 migrations `i/lf w/crlf`, one `i/lf w/lf`), a fresh
  `core.autocrlf=true` clone (185 `i/lf w/crlf`) and an LF clone (185 `i/lf w/lf`, the Linux CI form). Node 22.14.0
  locally; CI's step 8 runs the same file on Node 24.
- **Mutation testing.** 50 single-point mutants of the contract's new conditions, constants and prefix plan, in a
  scratch LF clone. Each is syntax-checked first and counts as killed only when the whole test file runs and fails:
  all 50 are killed. They include the review's five surviving mutants (below), which a control run shows surviving the
  reviewed tests.
- **Checkout negatives.** A CRLF working tree over an LF index is accepted by the unit tests as a checkout form, while
  the runner's raw-byte path refuses the same bytes ("Unreviewed 001D follow-up bytes"). A CRLF committed to the index
  fails the unit tests.
- **SQL.** The runner's three new catalog queries (their exact text, taken from the runner) ran against a throwaway
  PostgreSQL 10.7 cluster in the session scratchpad, with synthetic fixtures: they are valid and deterministic, and a
  changed comment or ACL changes the target-surface snapshot. This is not the runner: nothing touched Supabase, Docker
  or an existing database, and the runner was not run locally.
- **Static checks.** `node --check` passes for the three modules. The four paths have no tab, trailing whitespace or
  missing final newline, the modules are ASCII-only, and the index will hold LF. `git diff --check` is clean.
  `tools/check_secrets.sh` passes (the two Dart guards do not scan these file types), and the evidence scanner finds
  nothing in the four paths.
- **Fixed during local validation, before the review.**
  - The tests identify a refusal by the first line of its message, because strict assert appends a diff to a custom
    message.
  - Buffer and large-string comparisons use `assert.ok(a === b)`, so a failure cannot trigger an enormous diff; one
    mutant had crashed the test runner that way.
  - Two synthetic 13- and 15-digit versions in a test happened to be Luhn-valid card shapes and were changed.
  - Whole-word and string-in-the-prefix test cases were added after the mutation plan showed them untested.
- **Review.** One focused fresh-context Claude review round of exactly this four-path change, with three lenses
  (authorization conformance, the runner in CI, the tests and checkout forms), each followed by one adversarial
  verifier. All six agents were read-only; a transcript audit shows writes only in their scratch directories. Seven
  findings, none BLOCKER or MAJOR:
  - **Confirmed and fixed.** T-1: the transaction-control test placed each control only first or last and with single
    spaces, so a first-and-last-only scan or a literal-space pattern survived; the test now also inserts controls
    between two statements and with line breaks or tabs between the words. T-2: no test changed only the end of the
    file, so a contract that trims the end before hashing survived; an extra final LF, CRLF or spaces, a removed final
    LF and a final LF turned into CRLF are now refused. T-3 (also noted as PROOF-3): §6 claimed that the unit tests
    prove the refusal of non-file directory entries, which is the runner's own check; §6 is corrected.
  - **Refuted, kept as disclosed residuals.** PROOF-1: only the names of the 183-migration prefix are pinned, not
    their bytes. The authorization pins bytes only for the #379 target and 001D, so an in-place edit of an
    already-merged migration is outside this proof. PROOF-2: the structural transaction-control check does not
    recognize START or PREPARE separated from TRANSACTION by a comment; for the pinned 001D any such change is refused
    by its hash, and the 001D contains no transaction control in any spelling. A future extension of the pin (§7)
    should strip comments before matching. RUNNER-CI-1: phase C's "constraints exist" clause is a non-vacuity check
    of the snapshot, not a check of #379's own constraint, which the pinned bytes add in the same ALTER TABLE as the
    column.
