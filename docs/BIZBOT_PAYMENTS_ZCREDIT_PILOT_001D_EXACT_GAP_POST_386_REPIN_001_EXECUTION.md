# BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-POST-386-REPIN-001 — execution packet: the one-time exact-gap mode re-pinned to current `main` and the current hosted shape after #386

Work ID: `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-POST-386-REPIN-001`, on the fresh branch
`fix/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-POST-386-REPIN-001` from `main`
`28c41911fa3ae1ace9bcee1b793f810a3ac3990f` (the #386 merge; tree `025f55dbffb6196084416ebad165ec012c29f0d4`; parents
`ae2d35d7ad84f684f1f7efd0561e841badaa4e7b` and `3d05e3ff144eadedc824361b3259a70637f91c34`). It re-pins the merged
one-time exact-gap mode of `tools/supabase/bounded-db-push.mjs` (**DECISION D-066**, as amended by **DECISION D-067**)
to the shape that #386 left — 189 local migrations and, on hosted, 188 versions with the one gap `20261104141959` — and
adds #386's history row and its named database surface to the mode's PRE and POST gates (**DECISION D-068**, allocated
by this task).

The packet contains no credential, password, terminal number, TPN, PIN-pad identifier, KEY, device serial, card datum,
provider payload, e-mail address, database URL, access token or real production UUID.

## 1. Request and boundary

- **The request.** The command-room authorization of 2026-11-08 "REPIN THE ONE-TIME EXACT-GAP MODE TO CURRENT MAIN AND
  CURRENT HOSTED SHAPE AFTER PR #386". Its verdict: the APPLY-002 attempt remains permanently stopped
  (`HOSTED_001D_EXACT_GAP_APPLY_STOPPED_BEFORE_PUSH_MAIN_MOVED_PR_386_MERGED` / `NO_APPLY_NO_RETRY`) and is not reused;
  this task is local source work, proof, independent review and packaging only; no hosted query, check or apply; no push
  and no PR yet. It is kept outside Git with its SHA-256 (`d8791bcd4acd0888e1b0ef50f65fb74d0389d2a5592458c2a53471f9b0321cc9`).
- **The hosted facts it states** (the command room's read-only observation; this task never contacts hosted):
  - 188 migration versions, the latest `20261108085442`, recorded under the name `bizbot_pos_long_shift_alerts_001` with
    one stored statement whose SHA-256 is `7bd3b8946cde2979519a4e302c6c5ecef25399725234072df617359168b4a865` (the SHA-256
    of the migration file at `main`, so the official operation stored the whole file as one statement, as for the four
    earlier later-hosted versions);
  - no `20261104141959` row, no 001D table and no 001D function;
  - the exact local / hosted difference is `{20261104141959}`.
- **The accepted sources, referenced by hash and never modified.**
  - The merged wrapper at `main`: SHA-256 `33edff7c241bcba655a266550c7a507ce50367ae0aded05cfac50155934aecde` (the D-067
    wrapper, merged as #387); its pins hold 188 / 187.
  - The REPIN-001 package (`66fbd25c5dc6d54956c67b8db5375d1421db4dadd0a35a0fdecabdf78025f0ee`) and the
    HOSTED-PRE-COMPAT-001 package (`a4770762658caf5873dc50f9f1e353a706c4e6f95a8cd0d111dc47e8058349d2`), whose harness tools this task adapts.
  - The read-only hosted check of 2026-11-07 (EXACT-GAP-CHECK-002, seal `b1bda0d7dbaea0e28207fb063d202d6c94d214b46e603e07a291fdeea3dfe04c`)
    and the stopped apply attempt of 2026-11-08 (HOSTED-APPLY-002, seal `b9aa02d1c40f370f543647360f6eb03af0d688b6d02a9d8a7fb0e5dd2c911c90`).
    APPLY-002's outside-Git runner is permanently retired and is not reused.
- **What moved.** #386 (`BIZBOT-POS-EDIT-AND-IDLE-RECOVERY-001`, "Add opt-in long-shift pickup alerts to eligible POS
  devices") merged on 2026-11-08 at 11:31:36Z as `28c41911`. It adds `20261108085442_bizbot_pos_long_shift_alerts_001.sql`
  (SHA-256 `7bd3b894…`; its own record states that the reviewed source was formerly named
  `20261106180840_bizbot_pos_long_shift_alerts_001.sql` and that the official Supabase operation recorded version
  `20261108085442` on hosted), so `main` holds 189 migrations. It changes none of this task's eight paths and not
  `supabase/config.toml` (SHA-256 `447beeba30b17a739beede822807a9f0b19590e9e31abd4605b0ffc06a9a6bd7`, the pin the mode
  already holds).
- **Scope: exactly eight tracked paths may differ from `28c41911`.**
  - `tools/supabase/bounded-db-push.mjs`;
  - `tools/supabase/bounded-db-push.test.mjs`;
  - `docs/DECISIONS.md`;
  - `docs/DEPLOYMENT.md`;
  - `docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001D_EXACT_GAP_APPLY_001_EXECUTION.md`;
  - `docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001D_EXACT_GAP_APPLY_001_REPIN_001_EXECUTION.md`;
  - `docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001D_EXACT_GAP_HOSTED_PRE_COMPAT_001_EXECUTION.md`;
  - this packet.
- **Not changed:** every migration (001D, #380's two, #382's and #386's among them), the `.github` workflows,
  `supabase/config.toml`, D1, the cinematic contract and runner files, payment SQL, Edge, POS, Dashboard and l10n, and
  the substance of **D-061**, **D-065**, **D-066** and **D-067**.
- **No hosted, remote, provider or device action.** No hosted SQL, query, check or apply, no `--include-all` against
  hosted, no migration repair or manual ledger write, no push, no PR, no Edge deploy, no secret installation, no
  `providerProfile` wiring, no Z-Credit call, no terminal or card action, no APK or printer action.

## 2. Precheck (read-only, 2026-11-08; `pre/PREFLIGHT.txt` in the evidence folder)

- `origin/main` (read with `git ls-remote`, the fetched remote-tracking ref and the GitHub API) is `28c41911`, tree
  `025f55db…`, parents `ae2d35d7…` and `3d05e3ff…`; #386's merge commit is `28c41911`.
- `main` holds 189 migrations; the newest is `20261108085442_bizbot_pos_long_shift_alerts_001.sql`; no version sorts
  after it; no file carries the former version `20261106180840`; the #386 file's raw SHA-256 equals the hosted stored
  statement's (`7bd3b894…`); the 001D file is present once under its exact name with SHA-256 `468768f8…`.
- The merged wrapper is the D-067 wrapper (`33edff7c…`): it carries the `legacyCrlfBefore` map with its six legacy CRLF
  pins, the `recreatedBodyForm` export, `localCount: 188` and `remoteCountBefore: 187`; `supabase/config.toml` is
  `447beeba…`.
- **D-068 is free.** `main`'s `DECISIONS.md` has 63 decision headings, the highest D-067; its two mentions of D-068 are
  D-067's next-free statements (the changelog line and D-067's point 7). The two open PRs (#314, #315; last updated
  2026-10-10) carry registers whose highest heading is D-044. Of 872 local and `origin/*` refs, none holds a D-068
  heading.
- No remote branch names the Work ID; no PR exists from its branch; #314 and #315 are untouched.
- `providerProfile` appears in no non-docs path; no `pos-card-charge` function directory exists; no line outside
  `supabase/tests/` turns a card-payment flag on (the one match is a test fixture).
- The accepted packages and seals verify unchanged (REPIN-001, HOSTED-PRE-COMPAT-001, CHECK-002, APPLY-002).
- **Local environment facts.** The worktree had to be written as LF explicitly: Git's system configuration on this
  machine sets `core.autocrlf=true` (the REPIN-001 worktree is still LF), so the tracked files were removed and restored
  with `core.autocrlf=false`; every tracked text file then equals its blob (the wrapper `33edff7c…`, the tests, the #386
  file and `config.toml` included). The disposable stack runs on port 56522 because 56422 lies in a Windows (WinNAT)
  excluded port range on this machine at the time of the task; its image is PostgreSQL 17.6 (`server_version_num`
  170006, `TimeZone` UTC, no database-level time zone).
- No hosted contact.

## 3. The repin contract

### 3.1 The local and remote sets

| Pin | REPIN-001 / D-067 (`main` before #386) | This repin (`28c41911`) |
|---|---|---|
| Local migrations | 188 | **189** |
| Remote versions before the apply | 187 | **188** |
| The one missing version | `20261104141959` | `20261104141959` |
| Local tail | `…131256`, `…141959`, `…025413`, `…025604`, `…141815` | `…131256`, `…141959`, `…025413`, `…025604`, `…141815`, **`…085442`** |
| Remote tail | `…131256`, `…025413`, `…025604`, `…141815` | `…131256`, `…025413`, `…025604`, `…141815`, **`…085442`** |
| Later hosted migrations (present on both sides) | `…025413`, `…025604`, `…141815` | `…025413`, `…025604`, `…141815`, **`…085442`** |
| Stored statements (one each, the whole file) | four | **five** |
| `config.toml` | `447beeba…` | `447beeba…` (unchanged by #386) |

- The local symmetric difference with the remote set must be exactly `{20261104141959}`.
- All 189 local names and raw LF bytes are pinned (two digests over the sorted set, regenerated from the `28c41911`
  blobs: names `756219a502df025420b5a129887b9802b1cc410a0254b4e10a69634c45c5b78d`, bytes
  `0fae2d5a0a5a53e5cba1215c07fdf52faaca6940755cea1429056943d41f8358`).
- Still refused: a second missing migration, a remote-only migration, a changed #386 name or stored statement, any
  migration after `20261108085442` (local or remote), a linked workdir, a dotenv file other than `.env.example`, a
  changed file name or migration byte, a caller's `--include-all`, migration repair and any automatic retry.
- The mode's flag value stays `--exact-gap BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001`: it names the
  one-time D-066 route, not the Work ID that pins it.

### 3.2 The #386 history row

PRE requires the `20261108085442` row with the name `bizbot_pos_long_shift_alerts_001` and one stored statement whose
SHA-256 is `7bd3b8946cde2979519a4e302c6c5ecef25399725234072df617359168b4a865`, as the fifth later-hosted version; a
changed name (`stored_name`), another statement count or digest (`stored_statement`), its absence (`later_missing`,
with `remote_tail`, `remote_count` and `gap_mismatch`) and a remote version after it (`remote_only`, `remote_tail`) are
refused. POST requires every earlier row, this one included, unchanged.

### 3.3 The #386 named surface (additive)

- **The surface,** derived from the #386 migration's bytes (`pins/GEN_PINS_28c41911.*` in the evidence folder): the
  three relations it creates (`app.pos_shift_alert_policies`, `app.pos_shift_alert_approvals`,
  `app.pos_shift_alert_consents`) and the relation it alters (`app.pos_order_alert_registrations`: one column and one
  unique index added); its 28 functions — 23 it creates or replaces (22 `CREATE FUNCTION`, among them seven `public`
  wrappers, and `CREATE OR REPLACE FUNCTION app.pos_order_alert_authority`) and the five it renames to `*_core`
  (`app.pos_register_order_alert_core`, `app.pos_order_alert_status_core`, `app.pos_disable_order_alert_core`,
  `app.pos_refresh_order_alert_token_core`, `app.pos_claim_order_alert_deliveries_core`), whose bodies are the latest
  earlier definitions of the original names (a rename keeps `prosrc`); its twelve indexes; its twelve triggers (all on
  other tables: `public.shifts`, `memberships`, `employee_profiles`, `pin_sessions`, `devices`, `device_sessions`,
  `device_pairings`, `app.online_order_settings`, `public.app_users`, `branches`, `restaurants`, `organizations`); and
  its policies (none: the three new tables have row level security enabled and forced with no policy, and every
  privilege revoked from `public`, `anon`, `authenticated` and `service_role`).
- **PRE** requires, as observed on the current-`main` sequential reference database (PostgreSQL 17.6):
  - each of the 28 functions, exactly once under its name: its identity arguments, body (`prosrc` SHA-256), security
    definer or invoker state, `search_path` setting, volatility, language, whole definition (the SHA-256 of
    `pg_get_functiondef`), owner and exact access (every grantee, privilege, grant option and grantor); the EXECUTE
    group of each function is the file's own GRANT / REVOKE set — `none` (owner only), `authenticated` or `service_role`
    — and for the one `CREATE OR REPLACE`, which the file neither grants nor revokes, the exact entries the reference
    shows;
  - each of the four relations: kind, RLS and forced-RLS state, owner, exact access, column grants, policies and the
    SHA-256 of its catalog line (columns, constraints, policies as their JSON list with roles by name, triggers and
    indexes, as the other-relation digest renders them; the section 11 reviews replaced the policy roles' instance-local
    OIDs by names and then the whole joined policy line by the policies' JSON text, one unambiguous serialization, so the
    digest no longer embeds an instance-local role OID and no two policy sets share a line; its other renderings
    still follow the database's settings, as the review noted for a later re-pin);
  - each of the twelve triggers: present on its table, enabled, with the SHA-256 of its definition
    (`pg_get_triggerdef`).
- **POST** requires the whole #386 answer identical to PRE: no #386 function, relation, trigger or grant can be added,
  removed or changed without POST naming it.
- **Line endings (D-067).** Every #386 function joins the selected functions that PRE and POST accept in canonical LF
  only (`selected_function_eol`, `post_function_eol`).
- **Refusal codes.** `surface386_unreadable`, `surface386_function`, `surface386_access`, `surface386_relation` and
  `surface386_trigger` (PRE); `post_surface386` (POST).
- The existing broad digests of every other `app` / `public` function and relation and of every default privilege stay
  required; the #379 / #380 / #382 surface counts and #382's exact surface are unchanged.

### 3.4 D-067 preserved exactly

Unchanged: the six exact legacy CRLF alternatives, the LF-only `app.audit_category`, the LF-only rule for every other
selected function, the raw and normalized hashes and counts, the PRE session checks, the per-run Default ACL baseline,
the canonical-LF-only POST and the exact final-object access. The proof: the eleven D-067 tests are retained and pass
(nine unchanged in text; two widened for the #386 block: the D-067 state-SQL test expects the line-ending facts
fragment twice, and the D-067 fingerprint test also covers the #386 surface); the retained D-066 / D-067 mutant sets
are re-run from their sealed evidence folders at the proof head named in §10 (`proof/RETAINED_*`), and every mutant
whose anchor D-068 moved is reported NOT APPLIED by the retained tool and is either superseded by D-068's own mutant
at the new value (REPIN-001's six count and digest pins, in `p3_mutants.mjs`) or re-anchored with the same intent in
`p3_readapted_mutants.mjs` (the #386 code repeats the #382 patterns; the LF-only loop and the tails now end with
#386; the storage.objects policies digest now reads the policies' JSON text), where each is killed; the entries
earlier tasks had already re-anchored keep their re-anchored forms; the
D-067 exports (`recreatedBodyForm`, `legacyCrlfBefore`, `recreatedBefore`, the line-ending facts of the state query)
are byte-identical apart from the new pins; and the default-route preservation check passes against `28c41911`.

### 3.5 D-068

**DECISION D-068** records that #386 merged and added `20261108085442` to `main`; that this migration was applied to
hosted before 001D; that `main` has 189 migrations and hosted 188 with the exact difference `{20261104141959}`; that the
one-time D-066 route remains applicable after this reviewed re-pin; that D-067's exact line-ending compatibility is
unchanged; that generic `--include-all`, migration repair and manual ledger writes remain forbidden; that the APPLY-002
authorization is expired and cannot be reused; that a future apply needs a new Work ID and a fresh quiet-window
confirmation; and that D-068 itself authorizes no hosted query or apply. The next free decision ID becomes **D-069**.

### 3.6 Unchanged

CR-EG-01 (the one-entry passfile), CR-EG-02 (the exact access of the seven re-created functions at PRE and of every
001D object at POST), the runtime gate (170006 / UTC), the #382 surface pins, the default GR-37 route and the one
exact-gap CI step (`node --test tools/supabase/bounded-db-push.test.mjs`, which runs every final test).

## 4. Local proof (design)

Every database is disposable and local: this task's own stack (project `BIZBOTZCREDIT001D`, PostgreSQL 17.6), never a
linked or remote target.

- **Harness folders** (outside the repository and the evidence), each from `git archive` of `28c41911` with
  `core.autocrlf=false`: the whole 189-file tree (`C:/tmp/p3v`), the 183-file prefix (`p3p`), the prefix plus
  `20261104131256` and `20261104141959` (`p3q`), and a pristine wrapper workdir with `main`'s own `config.toml` (`p3w`).
- **The two final databases** share the route of every version and differ only in order:
  - **A (sequential):** the prefix by the CLI's normal local path; `20261104131256` by the emulation of the official
    operation; `20261104141959` by the CLI; `20261105025413`, `20261105025604`, `20261105141815` and `20261108085442` by
    the emulation (189 versions);
  - **B (hosted shape):** the prefix; the same five versions by the emulation (188 versions; 001D absent; #386's
    surface present); then the exact-gap wrapper's check mode and its one apply (189 versions; a normal dry run up to
    date).
- **Compared, A against B:** the whole schema-only dump, every catalog category of the earlier proofs, the D-067
  line-ending and access facts, the Default ACL behaviour, the #379 / #380 / #382 surfaces, the complete #386 named
  manifest (a new independent capture category), the 001D schema and access manifest, D1, `record_payment` and its
  callers, and the migration versions, names and stored-statement digests. Ignored only: pg_dump's random `\restrict`
  sentinel pair and the state answer's session block.
- **Negative states,** each built and refused: the earlier set (no gap, two gaps, a missing #380 migration, a
  remote-only version, a changed #380 statement, a partial 001D, drifted re-created functions, a fifth role on a
  re-created function, default privileges that grant a fifth role on new objects, a missing #382 migration, a changed
  #382 statement, a #382 surface drift, a non-UTC `TimeZone`, a #382 function no longer STRICT), the later remote-only
  version moved after #386, and the #386 states: a missing #386 migration, a changed #386 statement, a changed #386
  name, a #386 function access drift, a #386 relation drift (forced RLS removed), a #386 trigger drift (disabled) and a
  #386 function definition drift (SECURITY DEFINER removed); plus, in the live set, a #386 change between PRE 1 and
  PRE 2 (refused before any push) and between PRE 2 and POST (a POST mismatch).
- **Tests on both final databases:** the full pgTAP aggregate (reported honestly: the known local guarded files), the
  dedicated guarded lanes, the seven 001D lanes, the 001D concurrency runner twice, the 353 and acceptance-ETA runners,
  D1, the #380 and #382 database tests, #386's long-shift database test, the cinematic contract tests and the wrapper
  tests. The committed 001D runner allowlists the container name together with port 56422; on this machine that port
  is in a Windows excluded range, so its lane runs from a scratch copy that differs only in that port constant, with
  the copy's hash and diff recorded (a disclosed deviation; the committed runner's refusal is recorded too).
- **Wrapper unit tests** on Windows (Node 22) and Linux (Node 24), the default-route preservation check, and mutation
  checks for every new pin and gate, for the retained D-066 / D-067 sets as shipped (their NOT APPLIED entries
  disclosed) and for the re-anchored intents of the mutants D-068 moved (`p3_readapted_mutants.mjs`).

## 5. The future apply runner (outside Git; design)

A new outside-Git runner for a future hosted apply, under this Work ID, in the evidence folder: it starts every Node
script through `process.execPath` (the APPLY-002 runner handed the watchdog a `.mjs` path as the program, which Windows
refuses with `spawn EFTYPE`); it refuses the retired Work ID and token and requires a new owner confirmation record and
token; it takes a single-start lock and an exclusive apply lock, so at most one write attempt is possible and no retry
exists; it requires the exact current-`main` and wrapper identity from a pins file; every command runs under the proven
process-tree watchdog; the command inventory is recorded sanitized, and no credential appears in argv, output or
evidence. Rehearsed without hosted contact: a stubbed state matrix, a real harmless child spawn through
`process.execPath` (the real watchdog starting the real wrapper and the real final read with the private environment
removed, so each refuses locally with its own line), a timeout with the process tree killed, a successful check followed
by a blocked apply, a failed check that never reaches the apply, and a second start that never reaches a push.

## 6. CI

No workflow changes. The one existing `db-tests` step `node --test tools/supabase/bounded-db-push.test.mjs` runs every
final test (the new tests live in the same file).

## 7. Review

One focused fresh-context Claude delta review and one focused independent Codex review of the final wrapper and test
delta, both limited to: the 189 / 188 set pinning, the #386 history and surface pins, the preservation of D-067, the
confinement of `--include-all`, the PRE / POST behaviour, the outside-Git runner's `process.execPath` fix, and the
secret and redaction behaviour. Only confirmed defects are fixed. If the Codex review is unavailable, the task stops at
that gate and reports it.

## 8. Drift rule

Before the package is sealed, `origin/main` is read again. A change that touches a migration, `supabase/config.toml`,
one of the eight paths, D1, the cinematic migration contract or runner, or the database-test baseline is a STOP. A
change elsewhere is recorded; the package is still finished against `28c41911`, without a rebase, and push and PR stay
held. The task never re-pins to another head on its own.

## 9. Package

One sanitized source and review package outside Git: base, head, tree and parents; the eight-path allowlist with blobs
and hashes; D-068 as committed; the exact 189 / 188 contract; the #386 migration and surface manifest; the A/B
equivalence; the tests and mutation checks; the Claude and Codex reviews; the future apply-runner evidence; the Draft PR
plan; and a complete SHA-256 manifest. The earlier packages are referenced by hash and never modified.

## 10. Results

Recorded on 2026-11-08 by the task's record commit; every file named below is in the task's evidence folder
(`evidence/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-POST-386-REPIN-001-20261108/`, outside Git) or in the
sanitized package. Nothing was pushed, no PR was opened, no hosted or remote target was contacted.

### 10.1 Heads, commits and digests

- Base `main` `28c41911` (tree `025f55db`), 189 migrations. The branch's commits, in order: `aba21d64` (this packet,
  before any source edit); `67cfa6b2` (the re-pin to 189 / 188 and #386's named surface, D-068); `39ce7027` (D-068,
  the DEPLOYMENT amendment, the earlier packets' notes); `9d02bac7` (three assertions that kill the D-068 mutation
  check's survivors); `0e2663d6` (policy roles rendered by name in the relation catalog line, review finding L2-1);
  `fcbbdd45` (a relation's policies carried as their JSON text in the catalog line, review finding R2-01: the proof
  head); `ce686f6f` (the policy-line properties stated exactly, review finding LENS1-1); and the record commit that
  carries this section and the review wording corrections of §3.3, §3.4, §4 and D-068.
- The wrapper `tools/supabase/bounded-db-push.mjs` at the final head: SHA-256 `04246a36655e34a79892fead7a1b145fbc64dbb2f6459820e9157f6e07ebc67a`
  (unchanged since `fcbbdd45`); the tests: SHA-256 `26deaaac503ac59fcfbe030ce6903b7286a96bf4c9354048c46b8c37309d0fa3`;
  the state query the wrapper sends: SHA-256 `d46bd6997dea978a806f02c74ce9950b22c00bfb96f6bebd07c316ad14e45cb4`
  (pinned in the tests); the catalog-rendered #386 pins: digest `234dc90703b0c95129792c063f097da17f45dc63bc8a4661955f37fe2c76ea87`.
- The registrations relation's definition digest moved twice under the reviews (`3eda8120…` → `92362ca0…` →
  `e31be14384c9740c458449709ae92199dfe094c841e246905a57540909eaf8a2`), each time re-derived from a rebuilt sequential
  reference by the identically corrected explorer; every other #386 pin (27 functions, the five renamed `*_core`
  bodies, 12 triggers, 3 relations) is identical across the three readings (`explore/A0_*`, `A1_*`, `A2_*`).
- Exactly the eight authorized paths differ from the base; no migration, workflow, `config.toml`, D1, cinematic,
  payment SQL, Edge, POS, Dashboard or l10n file changed; every tracked file of the task is LF.

### 10.2 Precheck (§2)

`pre/PREFLIGHT.txt`: 45 checks, 0 failures — `main` `28c41911`, tree `025f55db`, 189 migrations, #386's file SHA-256
`7bd3b894…`, 001D's `468768f8…`, the hosted shape as the accepted CHECK-002 record states it, D-068 free, the
worktree created on the exact commit with LF bytes equal to the blobs.

### 10.3 The local proof (§4): run5 at the proof head `fcbbdd45`

The wrapper at the proof head is byte-identical to the final head's; the later commits touch the tests and the
documents only.

- The disposable stack: PostgreSQL 17.6 (`server_version_num` 170006), TimeZone UTC, the task's own project on a free
  port, never a linked or remote target; the harness tools' SHA-256 are in `run5/HARNESS_SHA256.txt`.
- **A** (sequential, 189 versions; 001D applied by the CLI, the five later files by the official-route emulation that
  stores one statement per file) built and captured; **N1** (no gap) refused `remote_count, no_gap`; every test lane
  PASS on A (`run5/A_validate`).
- The negative states, each built and refused with exactly the expected codes (`run5/N*`): N2A two gaps
  (`remote_count, gap_mismatch`); N2B a #380 file missing (`remote_count, remote_tail, gap_mismatch, later_missing`);
  N3 a remote-only version (`remote_count, remote_only`); N4 a changed #380 statement (`stored_statement`); N5 a
  partial 001D (`partial_001d`); N6 drifted re-created functions (`recreated_access, recreated_drift`); N7 the
  fifth-role PRE set PASS; N8 a default-privilege change applied between PRE and POST, a `POSTCHECK_MISMATCH` as
  expected, with its access snapshot; N9 #382 missing (`remote_count, remote_tail, gap_mismatch, later_missing,
  surfaces_missing, surface382_function, surface382_relation, surface382_policy`); N10 a changed #382 statement
  (`stored_statement`); N11 a #382 access drift (`surface382_access`); N12 a database TimeZone (`runtime_timezone`);
  N13 a later remote-only version after #386 (`remote_count, remote_tail, remote_only`); N14 #382's function no longer
  STRICT (`surface382_function`); N15 #386 missing (`remote_count, remote_tail, gap_mismatch, later_missing,
  surface386_function, surface386_relation, surface386_trigger`); N16 a changed #386 statement (`stored_statement`);
  N17 the same bytes under another name (`stored_name, remote_name`); N18 a #386 access drift (`surface386_access`);
  N19 a #386 relation without forced RLS (`surface386_relation`); N20 a disabled #386 trigger (`surface386_trigger`);
  N21 a #386 function without SECURITY DEFINER (`surface386_function`).
- **B** (the hosted shape, 188 versions): the live gap set PASS (`run5/B_gap_live`): a caller `--include-all` and a
  repair refused before any CLI process; a CRLF copy of 001D, a CRLF `config.toml`, a dotenv file, a linked workdir
  and a passfile with an extra entry refused before any CLI process; a wrong CA, a host name the certificate does not
  cover and a wrong password refused with no session; check mode `CHECKED_EXACT_GAP` with a dry run listing exactly
  001D and the database unchanged; the one apply `APPLIED_EXACT_GAP` (POST: 189 versions, 62 functions, 6 relations,
  12 indexes, 11 triggers, the exact pinned access; the pg-delta post-step stayed off). The B shape before and after
  the apply PASS; B captured; every test lane PASS on B (`run5/B_validate`).
- **B2** (B rebuilt): the live D-067 / #386 set PASS (`run5/B2_live386`): the six legacy CRLF forms accepted in check
  mode and `app.audit_category` kept canonical; a Default ACL change and a #386 access change between PRE 1 and PRE 2
  refused on both routes with nothing pushed; a disabled #386 trigger refused by name; a #386 access change between PRE
  2 and POST a `POSTCHECK_MISMATCH`; every hooked state restored to the reference fingerprint.
- **A/B**: EQUIVALENT in all 23 captured categories (`surface_386_exact` among them), the whole schema dump and the
  state answer (`run5/COMPARISON_A_B.txt`); every runtime, access, #382 and #386 pin equals the live sequential
  reference and the live gap database before and after the apply (`run5/PIN_CHECK.txt`).
- Earlier runs, kept whole under `superseded/` with a note each: run1 (head `9d02bac7`, PASS end to end, superseded by
  the wrapper corrections); run2 (`0e2663d6`, stopped when R2-01 was found); run3 (`fcbbdd45`, stopped: the CLI starts
  the database container once more a few seconds after `db reset` has returned, so a scenario that began right after a
  build found it not running — the build script now waits until the container is settled); run4 (`fcbbdd45`,
  discarded: stopping run3's background shell had not ended its driver, which kept running against the same database
  and collided with run4 — the driver now holds an exclusive run lock and stops the run on a failed build).

### 10.4 Tests and mutation checks at the final head `ce686f6f`

- Unit tests: Windows (Node 22) 73 tests, 73 pass, 0 fail, 0 skipped (`proof/UNIT_TESTS_WINDOWS_NODE22_ce686f6f.txt`); Linux (Node 24, the worktree mounted read-only, `--network none`) 73 tests, 64 pass, 0 fail, 9 skipped
  at `/repo` and 73 tests, 65 pass, 0 fail, 8 skipped two levels down (the skips are by design: the Git-backed pin tests without `git` in the
  image, and the default-wiring passfile test at `/repo`). Default-route preservation against `28c41911` (text, AST,
  behaviour, sensitivity probes): PASS (`proof/DEFAULT_ROUTE_PRESERVATION_ce686f6f.txt`).
- The D-068 mutation check (48 mutants over the count and digest pins, the #386 history row, the #386 surface pins,
  the PRE gates, the POST identity, the line-ending rule and the state SQL block): 48 of 48 killed, none not applied, none survived (`proof/D068_MUTANTS_ce686f6f.txt`). The re-anchored retained
  intents (`p3_readapted_mutants.mjs`, 13 mutants): 13 of 13 killed (`proof/D067_READAPTED_MUTANTS_ce686f6f.txt`); the battery's own verdict is `RESULT: PASS` (`proof/FINAL_CHECKS_ce686f6f.console.txt`).
- The retained D-066 / D-067 sets, run unchanged from their sealed evidence folders (`proof/RETAINED_*_ce686f6f.txt`):
  seven records, no survivor, no invalid and no not-counted entry; 26 NOT APPLIED entries, each one an anchor D-068 or its reviews moved (REPIN-001: C01..C06, L01, L02, G04, G05, G09, G10, G11, G12, D01, D02; CORRECTIONS-001: A16; the fix round: M04, M05, M12, M13, M19; the adapted set: A16b, M19; D-067: S02, Z03); killed: REPIN-001 31 of 47, CORRECTIONS-001 33 of 34, the fix round 13 of 18, the review set 19 of 19, the adapted set 1 of 3, D-067 54 of 56, D-067 re-anchored 7 of 7 (`proof/RETAINED_MUTANTS_ce686f6f.console.txt`). Every entry they report NOT APPLIED is either superseded by D-068's own mutant at the new value
  (REPIN-001's C01..C06) or re-anchored with the same intent and killed (S02r, Z03r, Z03b, G04r, G05r, G10r, G11r,
  G12r, G09r, A16br, A16cr, L01r, L02r); D01, D02, M04, M05, M12, M13, M19 and A16a keep the forms the earlier tasks
  re-anchored, which still apply.

### 10.5 The future apply runner (§5; outside Git, `tools/runner/` of the evidence folder)

Every Node child starts through `process.execPath` under the proven watchdog (the APPLY-002 defect); the local recheck
runs through Git Bash at its fixed place, validated before any lock, under the same bound and in a clean environment;
every pinned value comes from a pins file whose shape is validated (the project reference required; rehearsal pins
partitioned on every axis: the synthetic reference, a local origin only, no passfile and no CA for the children; real
pins must not carry the synthetic reference and must name the GitHub repository as origin); the retired token and Work
IDs are refused by name; a single-start lock and an exclusive apply lock; the accepted Default ACL baseline from the
pins; the private values (the URL, the host, the reference, the passfile and CA paths in both spellings, the workdir,
the CLI, the Node program, the scratch and evidence folders) scrubbed from every stored console and inventory and
counted in every console, including the independent read's. Rehearsals (`rehearsal/`): r0 the stub matrix 121 scenarios, all pass (`rehearsal/R0_CORE_SCENARIOS.txt`); r1
the real watchdog starting the real wrapper and the real final read through `process.execPath` with the private
environment removed (each refused by its own first line, no spawn error); r2 the watchdog's process-tree kill; r3 the
dress rehearsal of the real runner against a scratch clone with a configured stand-in wrapper: PASS in every scenario (`rehearsal/REHEARSAL_STATUS.txt`, `rehearsal/R3_*`): a passing check, the recheck, the one apply attempt and the final read refusing `GATE_REFUSED passfile_missing` (apply steps called 1); a failed check that never reaches the apply; a passing check whose recheck blocks the apply; a lock planted after a passing check that refuses the apply before any command; a second start refused on the run lock before any step; and the retired token, a missing owner record and a half-filled pins file refused before any contact. The runner's own local gates at the head: 39 PASS (`rehearsal/LOCAL_GATES_worktree_ce686f6f.txt`).

### 10.6 Reviews (§7)

- Round 1 (a fresh-context Claude review of `9d02bac7`, seven lenses, every finding adversarially verified): nine
  MINOR, no MAJOR — L2-1 (the relation catalog line rendered policy roles as instance-local OIDs, and D-068 was the first
  to pin a relation digest with a policy), D067-1 (an unevidenced "passes unchanged"), runner-1..5, L7-1, L7-2; all
  corrected.
- Round 2 (`0e2663d6`): the independent Codex review — R2-01 MAJOR (names joined with `+` could collide), R2-02 MAJOR
  (rehearsal-shaped pins could still reach a real database), R2-03 MINOR and two NOTEs; the fresh-context Claude review
  — L3-1..L3-4 and D067W-1..3 MINOR; all corrected. The first Codex invocation never started (it waited on standard
  input in a background shell) and is recorded under `superseded/`.
- Round 3 (`fcbbdd45`, the final wrapper and test delta): Codex — four MINOR, all in the runner and harness tools (the
  wrapper lenses had no finding; R2-01, R2-04 and R2-05 resolved, R2-02 and R2-03 completed by this round's
  corrections); Claude — five MINOR (LENS1-1 the test assertions, REH-1..3 the rehearsal partition, L4-1 a retained
  mutant whose anchor the R2-01 correction moved) and one finding refuted as already corrected; a focused round 3b over
  the corrections confirmed HC-1 (the proof-run collision, MAJOR for the proof's validity, not for the wrapper), HC-2,
  HC-3 and REH4-1 MINOR; all corrected, and the proof was re-run as run5. NOTEs accepted without a code change, with
  the reviewers' reasons: SET-01 (no CI signal when `main` moves), L2-2, L2-3 / PREPOST-1, PREPOST-2, L2-1-2
  (session-dependent renderings in the catalog line, pre-existing, for the next re-pin), L2S-2 (the wrapper's own
  temporary query folder in its redaction lists, pre-existing). The structured results and the Codex messages are in
  `review/`.

### 10.7 Package (§9)

The sanitized source and review package
`BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-POST-386-REPIN-001-local-source-review-package.zip` is built after this
record commit from the final head (so its SHA-256 and member count are in the task report and in the evidence folder's
seal `SHA256SUMS.txt`, not here): the heads and trees, the eight-path patch and the files at head (the two registers by
patch and blob hash only), D-068 as committed, the set pins and #386's surface as the wrapper exports them, the live
proof run5 and the earlier runs under `superseded/`, the exploration and the generated pins, the tests, the
preservation proof and every mutation record, the rehearsals, the three review rounds, the authorization, the
preflight, the harness tools and their superseded versions, the postflight and the session-log records, and a complete
member manifest. Its builder masks the local user-profile prefix and the hosted project reference in the runner's
copies and the session-log records, leaves the copied earlier tools out (by digest manifest), and aborts on any
private value; the earlier packages and seals are referenced by SHA-256 and were not modified.

### 10.8 Postflight and the drift rule (§8)

`origin/main` read again before this record commit: `28c41911`, unchanged (the GitHub API agreed at the preflight; the postflight reads both again). The read-only postflight runs at the final head
after this commit and its record stays in the evidence folder (`postflight/POSTFLIGHT.txt`): `origin/main` and the
GitHub API still at `28c41911`, no remote branch and no PR for this Work ID, the two long-open PRs untouched, the
earlier packages and seals unchanged, the disposable stack's containers gone with its volumes kept, and no owner
variable set in the shell. No push, no PR, no remote branch; no hosted query, check or apply; no provider, terminal,
device, Edge, secret or payment-flag action; no private environment variable was set, read or printed by this task.

Status: `LOCAL_001D_EXACT_GAP_POST_386_REPIN_READY_FOR_COMMAND_ROOM_REVIEW` / `PUSH_PR_HOSTED_CHECK_AND_APPLY_HELD`.
