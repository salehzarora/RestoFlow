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
    SHA-256 of its catalog line (columns, constraints, policies, triggers and indexes, as the other-relation digest
    renders them);
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
the canonical-LF-only POST and the exact final-object access. The proof: the D-067 tests and mutation set are retained
and pass unchanged; the D-067 exports (`recreatedBodyForm`, `legacyCrlfBefore`, `recreatedBefore`, the line-ending facts
of the state query) are byte-identical apart from the new pins; and the default-route preservation check passes
against `28c41911`.

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
  checks for every new pin and gate and for the retained D-066 / D-067 sets.

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

Filled by this task's record commits once the implementation, proof, tests, reviews and package are complete; until
then this section states only that the packet was committed before any source edit (§1 of the authorization).
