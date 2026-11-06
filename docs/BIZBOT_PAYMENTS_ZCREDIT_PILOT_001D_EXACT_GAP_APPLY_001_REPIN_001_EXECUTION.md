# BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001-REPIN-001 — execution packet: the exact-gap mode recomposed on current `main` and re-pinned after #382

Work ID: `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001-REPIN-001`, on the fresh branch
`fix/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001-current-main-r2` from `main`
`0fe8ef803882467c40e653d22e176f6a0b56b5fd` (the #382 merge). It recomposes the accepted, corrected exact-gap source
(**DECISION D-066**; `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001` as corrected by its CORRECTIONS-001) onto
current `main` and re-pins the one-time exact-gap mode to the shape that #382 left: 188 local migrations and, on hosted,
187 versions with one gap.

The packet contains no credential, password, terminal number, TPN, PIN-pad identifier, KEY, device serial, card datum,
provider payload, e-mail address, database URL, access token or real production UUID.

## 1. Request and boundary

- **The request.** The command-room authorization of 2026-11-05 "CURRENT-MAIN RECOMPOSITION AND EXACT-GAP REPIN AFTER
  PR #382, LOCAL ONLY" (verdict: the CR-EG-01, CR-EG-02 and CR-EG-03 corrections are accepted as reported;
  `REPIN_TO_CURRENT_MAIN` is required; push, Draft PR and hosted apply stay held; no Codex review is requested). It is
  kept outside Git with its SHA-256 (`6dfa14165ea68d3b852404f80a646da1b0472e3de33a30eb8e5c5d6d03f4ece6`).
- **The accepted source, preserved unchanged.**
  - The corrected head `3e9e2316fba1a2dd5cd9b70829da781ffe074b81` (tree `36e84e8177bb3fc715756aa2e1f21bcaec7910c6`;
    final code `f7f3fb4b`) on its own branch, which this task does not rebase, merge, rewrite or modify.
  - The original exact-gap package (SHA-256 `23e2abaf28360f12bc048b68e2a9167dc4c1f6444ada8f64b30e641d6c19e0c5`) and the
    correction package (SHA-256 `76c0e074e9cdb7b12824188b24c9b6df5af8366c2309aab264f7aac28871e641`), referenced only.
- **What moved.** #382 (`BIZBOT-STOREFRONT-APPEARANCE-UX-002`) merged on 2026-11-05 at 14:51:22Z as `0fe8ef80`
  (tree `0b79beb647236cf28b57c18567abf611b6e72669`). It adds migration
  `20261105141815_bizbot_storefront_background_clarity_001_api.sql` (SHA-256
  `e5cf4b2840837facc5699cecb154689a7439383ac4d6650f13746d5e68bd8504`), so `main` holds 188 migrations. It changes none
  of this task's seven paths and not `supabase/config.toml`.
- **The hosted facts it states** (the command room's read-only observation; this task never contacts hosted):
  - 187 migration versions, the latest `20261105141815`;
  - no `20261104141959` row, no 001D private card table and no `card_attempt` function family;
  - `server_version` 17.6, `server_version_num` 170006, `TimeZone` UTC.
- **The stored-statement pins** (the authorization's §6): `a276aef4…ceb263b` (`20261104131256`), `a901a709…c77d5`
  (`20261105025413`), `7bfac52a…9b520` (`20261105025604`) and `e5cf4b28…8bd8504` (`20261105141815`); each equals
  its file's SHA-256 at `0fe8ef80`.
  - The #379 / #380 values were observed on hosted by the command room through an authorized read-only query on
    2026-11-05 (CORRECTIONS-001).
  - #382's value is pinned from the reviewed file; the authorization's hosted observation for this repin does not
    state it. The check-mode run reads that row read-only before any push.
- **Scope: exactly seven tracked paths may differ from `0fe8ef80`.**
  - `tools/supabase/bounded-db-push.mjs`;
  - `tools/supabase/bounded-db-push.test.mjs`;
  - `.github/workflows/ci.yml`;
  - `docs/DECISIONS.md`;
  - `docs/DEPLOYMENT.md`;
  - `docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001D_EXACT_GAP_APPLY_001_EXECUTION.md`;
  - this packet.
- **Not changed:** every migration (the 001D SQL, both #380 migrations and the #382 migration among them), D1, the
  cinematic contract and runner files, [API_CONTRACT](API_CONTRACT.md), Edge, POS, Dashboard and l10n, **D-061**,
  **D-065**, [AGENT_WORKFLOW](AGENT_WORKFLOW.md) and **D-016**.
- **No hosted, remote, provider or device action.** No hosted query or apply, no `--include-all` against hosted, no
  migration repair or manual ledger write, no Edge deploy, no secret installation, no `providerProfile` wiring, no
  provider call, no terminal or card action, no APK or printer action, no push and no PR.

## 2. Preflight (read-only, 2026-11-05T19:52Z)

- `origin/main` (read with `git ls-remote`) is `0fe8ef80`, parents `ad8c3caf` and `9e1c11ef`; it holds 188 migrations
  with the tail `20261104131256`, `20261104141959`, `20261105025413`, `20261105025604`, `20261105141815`, and the four
  stored-statement pins above equal the file SHA-256 values there.
- `supabase/config.toml` is unchanged by #382 (blob `810abd46`, SHA-256 `447beeba…`, the pin the mode already holds).
- The corrected branch is still at `3e9e2316`, its worktree clean, with no upstream.
- No remote branch and no PR exist for either branch name; #314 and #315 are open and untouched (last updated
  2026-10-10); no other PR is open.
- **D-066** is not allocated on `main`: its three mentions in `main`'s `DECISIONS.md` are next-free statements, and
  the MIGRATION-REORDER-001 packet mentions it only as unallocated or next free. It is allocated only on the
  unpublished corrected branch.
- Both accepted packages and both evidence seals verify unchanged.
- No hosted contact.

## 3. Source recomposition

- **One import commit.** The exact blobs of the six exact-gap paths are taken from `3e9e2316` into the fresh branch,
  before any repin edit. The recomposition is clean because the six paths are byte-identical on `ad8c3caf` (the
  corrected source's base) and on `0fe8ef80`: #382 touched none of them. The imported blobs are therefore exactly
  "current `main` plus the accepted exact-gap change".
- **The equality proof** (recorded before any repin edit): the wrapper and its tests equal the corrected head blob for
  blob; the D-066 amendment of [DEPLOYMENT](DEPLOYMENT.md) §18.2b equals the corrected head; the exact-gap packet
  equals the corrected head; `ci.yml` and `DECISIONS.md` equal their accepted exact-gap candidate forms.
- **Then only the repin adaptations** of the authorization: the current-`main` count pins, the #382 migration pins,
  the PostgreSQL 17.6 runtime pins, the #382 PRE / POST surface proof, the current facts and hashes in the documents
  and tests, and this packet.
- **The provenance table** (current-`main` blob → corrected-source blob → final blob → permitted reason) is in §10.1.

## 4. The repin contract

### 4.1 The local and remote sets

| Pin | Corrected source (`ad8c3caf`) | This repin (`0fe8ef80`) |
|---|---|---|
| Local migrations | 187 | **188** |
| Remote versions before the apply | 186 | **187** |
| The one missing version | `20261104141959` | `20261104141959` |
| Local tail | `…131256`, `…141959`, `…025413`, `…025604` | `…131256`, `…141959`, `…025413`, `…025604`, **`…141815`** |
| Remote tail | `…131256`, `…025413`, `…025604` | `…131256`, `…025413`, `…025604`, **`…141815`** |
| Later hosted migrations (present on both sides) | `…025413`, `…025604` | `…025413`, `…025604`, **`…141815`** |
| Stored statements (one each, the whole file) | three | **four** |
| `config.toml` | `447beeba…` | `447beeba…` (unchanged by #382) |

- The local symmetric difference with the remote set must be exactly `{20261104141959}`.
- All 188 local names and raw LF bytes are pinned (two digests over the sorted set).
- Still refused: a linked workdir, a dotenv file other than `.env.example`, a changed file name or migration byte, a
  remote-only migration, a second missing migration, an unexpected later migration, a caller's `--include-all`,
  migration repair and any automatic retry.

### 4.2 The PostgreSQL runtime hard gate

- The access manifest of CR-EG-02 was derived on PostgreSQL 17.6 (a table owner holds MAINTAIN).
- The state answer gains a `runtime` object, `server_version_num` and `TimeZone`, outside its session block, so the
  state fingerprint covers both values.
- PRE refuses unless `server_version_num` is exactly `170006` (`runtime_version`) and `TimeZone` exactly `UTC`
  (`runtime_timezone`), before the dry run.
- The re-read immediately before the push checks both values again, explicitly, before it compares the fingerprint.
- The access manifest is never regenerated silently against another version.

### 4.3 The #382 surface proof (additive)

- **The surface,** derived from the #382 migration: the relation `app.storefront_background_variants` (with its index
  and constraints), its twelve functions (eight in `app`, four in `public`, among them `public.storefront_menu_v7`),
  and its two Storage policies on `storage.objects`
  (`storefront_background_registered_select_v1`, `storefront_background_registered_insert_v1`).
- **PRE** requires the #382 history row with its one stored statement (`e5cf4b28…`), and these pins, as observed on
  the current-`main` sequential reference database:
  - each of the twelve functions: its identity arguments, body, security definer, config, volatility, language and
    whole definition (the SHA-256 of `pg_get_functiondef`, which also covers the result type, every argument,
    strictness, cost, rows and parallel safety), its owner and its exact access; an extra overload under a pinned
    name is refused;
  - the relation: its kind, RLS, owner, exact access, column grants and the SHA-256 of its catalog line (columns,
    constraints, policies, triggers and indexes, as the other-relation digest renders them). Its persistence,
    replica identity, storage options, rules and publication membership are not compared;
  - the two Storage policies: table, command, permissive flag, roles and expressions.
- **POST** requires the whole #382 answer above, and a digest of every policy on `storage.objects`, identical to PRE.
  No #382 function, policy or grant can be added, removed or changed without POST naming it, and neither can any
  attribute the relation's line covers.
- The existing broad digests of every other `app` / `public` function and relation and of every default privilege stay
  required; the #382 presence count joins the #379 / #380 one.

### 4.4 Unchanged

- **CR-EG-01:** the passfile holds exactly one active entry in total, the exact target.
- **CR-EG-02:** the exact access of the seven re-created functions (PRE) and of every 001D function, table, column and
  the sequence (POST); the default-privilege digest stays an additional check.
- **The default GR-37 route** and its tests; the one exact-gap CI step.

### 4.5 D-066

D-066 stays the same unpublished decision (no **D-067**). Its record is updated to the current-`main` facts: 188
migrations on `main`; 187 on hosted; the symmetric difference only `20261104141959`; the later hosted migrations
`20261105025413`, `20261105025604` and `20261105141815`, present on current `main` and on hosted, with their stored
statements pinned; generic `--include-all`, migration repair and manual history writes still forbidden; no hosted apply
authorized by D-066 itself; the next free decision ID still **D-067**.

## 5. Local proof (design)

Every database is disposable and local: this task's own stack (`BIZBOTZCREDIT001D`), never a linked or remote target.

- **Harness folders** (outside the repository and the evidence), each from `git archive` of `0fe8ef80` with
  `core.autocrlf=false`: the whole 188-file tree, the 183-file prefix, the prefix plus `20261104131256` and
  `20261104141959`, and a pristine wrapper workdir with `main`'s own `config.toml`.
- **The two final databases** share the route of every version and differ only in order:
  - **A (sequential):** the prefix by the CLI's normal local path; `20261104131256` by the emulation of the official
    operation; `20261104141959` by the CLI; `20261105025413`, `20261105025604` and `20261105141815` by the emulation;
  - **B (hosted shape):** the prefix; `20261104131256`, `20261105025413`, `20261105025604` and `20261105141815` by the
    emulation (history count 187; 001D absent); then the exact-gap wrapper's check mode and its one apply (history
    count 188; a normal dry run up to date).
- **Compared, A against B:** the whole schema-only dump, the existing 23 catalog categories, the #382 surface, the
  wrapper's state answer (including its runtime and #382 blocks), the default privileges, the D1 public surface,
  `record_payment` and its callers, the #379 / #380 / #382 surfaces and the 001D manifest. Ignored only: pg_dump's
  random `\restrict` sentinel pair and the state answer's session block.
- **Negative states,** each built and refused: the earlier set (no gap, two gaps, a missing #380 migration, a
  remote-only version, a changed #380 statement, a partial 001D, drifted re-created functions, a fifth role on a
  re-created function, default privileges that grant a fifth role on new objects), plus a missing #382 migration, a
  changed #382 statement, a #382 surface drift, a non-UTC `TimeZone` and an unexpected later remote version.
- **Tests on both final databases:** the full pgTAP aggregate, the dedicated guarded lanes, the seven 001D lanes, the
  001D concurrency runner twice, the 353 and acceptance-ETA runners, D1, the #380 and #382 database tests, the
  cinematic contract tests and the wrapper tests.
- **Wrapper unit tests** on Windows (Node 22) and Linux (Node 24), and mutation checks for every new pin and gate and
  for the retained passfile and fifth-role access gates.

## 6. CI

The one exact-gap step in `db-tests` stays the only CI change from `main`: `node --test
tools/supabase/bounded-db-push.test.mjs`, pure Node with fake and synthetic state, no hosted credential, no database,
no network and no production call. No #382 CI or cinematic guard is changed.

## 7. Review

One focused fresh-context Claude review: the clean recomposition, D-066's current-`main` wording, the 188 / 187 set
comparison, the #382 statement and surface pins, the PostgreSQL 17.6 gate, the preservation of CR-EG-01 and CR-EG-02,
the default route and the CI isolation. Only confirmed defects are fixed.

## 8. Drift rule

Before the package is sealed, `origin/main` is read again. A change that touches a migration, `supabase/config.toml`,
one of the seven paths, D1, the cinematic migration contract or runner, or the database-test baseline is a STOP. A
change elsewhere is recorded; the package is still finished against `0fe8ef80`, without a rebase, and push and PR stay
held.

## 9. Package

One sanitized source and review package outside Git: the provenance, the seven-path patch, the final blobs and their
hashes, the A/B evidence, the runtime, access and surface pins, the test and mutation logs, the review, the Draft PR
plan and a SHA-256 manifest. The two accepted packages are referenced, never rebuilt.

## 10. Results (local, 2026-11-05; every record is outside Git, in this task's evidence folder)

### 10.1 Source provenance

The recomposition proof (`source/RECOMPOSITION_PROOF_cba5c3b1.txt`) passed before any repin edit: the import commit
`cba5c3b1` carries the six exact-gap paths blob for blob from `3e9e2316`; every other path equals `0fe8ef80`; the
composed change has the corrected change's patch-id (`fb0ff1f8…`); and #382 touched none of the six paths or
`config.toml`. At the import commit the imported tests passed 48 of 48: they re-derive their pins from the oldest
`localCount` committed migrations, so main's move is caught by the wrapper's own `local_count` gate at run time, not by
those tests.

| Path | Current `main` blob | Corrected-source blob | Final blob | Permitted reason |
|---|---|---|---|---|
| `tools/supabase/bounded-db-push.mjs` | `3e4e268e` | `78d97427` | `52f82672` (commits `eef9d7de`, `fc075ada`) | the 188 / 187 count pins, the #382 migration pins, the PostgreSQL 17.6 runtime pins and the #382 PRE / POST surface proof, with the review's whole-definition fix |
| `tools/supabase/bounded-db-push.test.mjs` | `f9995175` | `afb51b2d` | `2c2b4594` (commits `eef9d7de`, `fc075ada`, `252f4853`) | the tests of those pins and gates, and of the review's two fixes; current facts and hashes |
| `.github/workflows/ci.yml` | `3779e0a6` | `226384d1` | `226384d1` (unchanged) | the accepted exact-gap CI step |
| `docs/DECISIONS.md` | `b97fc3fe` | `3a6b827b` | in the package's `HASHES.txt` | D-066's current-`main` facts (§4.5) |
| `docs/DEPLOYMENT.md` | `e6931380` | `571ffc3e` | in the package's `HASHES.txt` | the §18.2b amendment's current facts |
| exact-gap packet | — | `b575054a` | in the package's `HASHES.txt` | a REPIN-001 note and §16 (current facts) |
| this packet | — | — | in the package's `HASHES.txt` | the new repin packet |

A document cannot carry its own final hash, so the package records every final blob and SHA-256. Commits on
`0fe8ef80`, oldest first:
- `bccc6cd4`: this packet, before any implementation;
- `cba5c3b1`: the import;
- `eef9d7de`: the repin of the wrapper and its tests;
- `5286858f`: D-066, the §18.2b amendment and the exact-gap packet, with the current facts;
- `91a59b9f`: this packet's first results;
- `fc075ada`: the review's S382-01 fix, in the wrapper and its tests;
- `bde3c744`: the review's record corrections;
- `252f4853`: the review's SET-382-02 fix, two assertions in the existing PRE-gates test. This is the final code;
- the last record commit, which changes only this packet.

### 10.2 The repin as implemented

- **The wrapper** (final at `fc075ada`; SHA-256 `9d753bab…`): +246 / −61 lines against the corrected source, and
  +1070 / −2 against `main`.
  - The default route is unchanged. Both preservation checks pass against `0fe8ef80` (§10.5), and the only base lines
    changed are the two widened import lines, as before.
  - `run2/` ran `eef9d7de`'s repin (SHA-256 `2cc13668…`). `fc075ada` then added the review's S382-01 fix: the
    whole-definition digest.
- **The tests** (final at `252f4853`; SHA-256 `be5ee578…`): 56 tests, 36 of them new. `main`'s 20 tests are
  byte-identical. The file is +365 / −30 lines against the corrected source.
- **The state query** (SHA-256 `09a3d902…`, 179 lines; the unit tests pin it). Against the corrected source's query
  (`88cdc196…`) it inserts the `runtime` key, the `surface382` block and one column (`p.oid`) at the end of the `fn`
  CTE's select list, and extends the two surface name arrays. The other-relation line now comes from one shared
  helper; the generated text of every other earlier part is byte-identical. (`run2/` ran the query before the
  review's S382-01 fix, SHA-256 `2b6e4411…`; `run3/` ran the final one.)
- **Where each pin comes from.**
  - `localNamesSha256` `f48235ae…` and `localBytesSha256` `fe389ae9…`, the surface lists (46 functions, 3 tables) and
    #382's twelve function facts (body SHA-256, security definer, config, volatility, language, EXECUTE group): from the
    `0fe8ef80` blobs (`pins/GEN_PINS_0fe8ef80.txt`).
  - The catalog renderings — the identity arguments, the relation's definition digest `d37cc990…` and the two policy
    expressions — from the current-`main` sequential reference (an exploratory build, `explore/`), checked against the
    bytes-derived pins when they were filled in (`tools/rp_fill_surface_pins.py`), and equal on the final A and B of
    `run2/` (the pin check).
  - #382's twelve whole-definition digests (the SHA-256 of `pg_get_functiondef`), for example `93a3eaee…` for
    `public.storefront_menu_v7`. They come from `run2/`'s sequential reference A (`A_capture/cat_surface_382_exact.txt`,
    read as `supabase_admin`). When they were filled in (`tools/rp_fill_def_pins.py`), they had to equal the wrapper's
    own query of the same definitions, read as `postgres` (`explore/def_pins/`). They are also equal on `run3/`'s live
    A and B (the pin check).
  - The runtime pins: the command room's hosted observation (170006, UTC), equal to the local stack's.
- **New refusal codes:** `runtime_version`, `runtime_timezone` (PRE, and at the re-read immediately before the push);
  `surface382_unreadable`, `surface382_function`, `surface382_access`, `surface382_relation`, `surface382_policy` (PRE);
  `post_surface382` (POST).

### 10.3 The live proof (`run2/`, 2026-11-05T20:33Z–20:59Z, on `eef9d7de`)

The stack is this task's disposable `BIZBOTZCREDIT001D` (PostgreSQL 17.6, `server_version_num` 170006, `TimeZone`
UTC). The harness folders are `git archive` copies of `0fe8ef80`; the wrapper workdir has `main`'s own `config.toml`
(`447beeba…`), so the pinned CLI treats the stack as a remote database and honours `verify-full`.

Each state starts from a fresh `db reset` of the 183-file prefix and must report `TimeZone` UTC with no timezone
override. There are two exceptions:
- N2A resets 182 files: the prefix without `20261102015942`;
- N3 resets 184 files: the prefix with the synthetic `20261103000000`.

| State | How it is built | Result |
|---|---|---|
| N1 | the sequential database A (no gap) | refused `remote_count` (11 gates, among them `no_gap`) |
| N2A | the prefix also lacks `20261102015942` | refused `remote_count`, `gap_mismatch` |
| N2B | #380's `20261105025604` not applied (#382 is) | refused `remote_count`, `remote_tail`, `gap_mismatch`, `later_missing`, `surfaces_missing` |
| N3 | a synthetic remote-only `20261103000000` | refused `remote_count`, `remote_only` |
| N4 | #380's `20261105025604` from a modified copy | refused `stored_statement` |
| N5 | one 001D table created by hand | refused `partial_001d` |
| N6 | `app.sync_push` granted to PUBLIC; `app.audit_category` owned by `supabase_admin` | refused `recreated_access`, `recreated_drift` |
| N7 | EXECUTE on the re-created `app.audit_category` for a fifth role | refused `recreated_access` naming the role; revoking the grant changes the state fingerprint (only that function's access differs) and check mode then passes |
| N8 | default privileges give every new `app` object a fifth-role grant | the apply ends `POSTCHECK_MISMATCH` (exit 4): 47 `post_function_access`, 5 `post_table_access`, 1 `post_sequence_access`; the default-privilege digest is unchanged by the push |
| **N9** | #382's `20261105141815` not applied | refused `remote_count`, `remote_tail`, `gap_mismatch`, `later_missing`, `surfaces_missing`, `surface382_function` / `_relation` / `_policy` |
| **N10** | #382 from a modified copy (one comment line) | refused `stored_statement` |
| **N11** | EXECUTE on `public.storefront_menu_v7` for a fifth role | refused `surface382_access`, naming the role |
| **N12** | `alter database postgres set timezone` to a non-UTC zone | refused `runtime_timezone`; the setting was reset right after |
| **N13** | a synthetic later ledger row `20261106000000` | refused `remote_count`, `remote_tail`, `remote_only` |

Every refused run left the database unchanged (state fingerprint equal before and after).

**The hosted-shape database B** (`run2/B_gap_live/`, `run2/B_SHAPE.txt`):
- before the apply: 187 versions; the exact symmetric difference `{20261104141959}`; the four single stored statements
  with their pinned SHA-256 and names; no 001D object; the #379 / #380 / #382 surfaces (46 functions, 3 tables) and
  #382's own surface present; the runtime 170006 / UTC;
- the live negatives refused as before: a caller's `--include-all` and repair, a CRLF 001D copy, a CRLF `config.toml`, a
  dotenv file, a linked workdir and a passfile with an extra active entry (all before any CLI process); an unrelated CA, a
  host name the certificate does not cover and a wrong password (no session);
- check mode passed (two read-only TLS sessions) and left the database unchanged;
- the one apply: `RESULT: APPLIED_EXACT_GAP`, the push 946 ms, 6 read-only and 1 read-write session, all TLS, the
  pg-delta step off (no pg-delta file in the workdir);
- after the apply: 188 versions equal to the local set; `20261104141959` recorded once with its 125 statements; every
  earlier row unchanged; a normal dry run up to date; #382's surface and the `storage.objects` policy digest identical
  before and after.

**A against B** (`run2/COMPARISON_A_B.txt`): **EQUIVALENT**.
- All 24 catalog categories are equal: the earlier 23, with the surfaces category now covering #379 / #380 / #382, plus
  a new `surface_382_exact` category that renders #382's surface independently of the wrapper's query.
- The whole schema-only dump is equal (67,931 lines, SHA-256 `73cba6c2…`), and so is the wrapper's state answer.
  The comparison record says 67,932 lines because it also counts the empty piece after the final newline.
- Ignored only: pg_dump's random `\restrict` sentinel pair and the state answer's session block.
- The categories cover: every function's body, owner and ACL; relations, columns, constraints, indexes, triggers,
  policies and RLS; the normalized access of every object and column; the default privileges; the migration ledger
  (version, name, statements digest); the D1 public surface; `record_payment` and its callers; and the 001D manifest.

**The pins against the live states** (`run2/PIN_CHECK.txt`): PASS. The seven re-created functions' access just before
001D on A and before the apply on B; the runtime and #382's whole surface on B before the apply and on A and B after;
the 001D access on A and B after; and B's #382 surface identical before and after the apply.

**run3, on the final wrapper** (`run3/`, 2026-11-05T21:38Z–21:54Z). The worktree head was `bde3c744`, which
carries the final wrapper (`9d753bab…`) and its state query (`09a3d902…`). Every state was rebuilt on a fresh database
and run again:
- N1–N7 and N9–N13 refused with exactly the codes of run2, and each refused run left the database unchanged.
- N7 again passed check mode once the grant was revoked.
- N8's apply again ended `POSTCHECK_MISMATCH` (exit 4), with the same 47 / 5 / 1 POST access codes. The push left the
  default-privilege digest unchanged.
- **N14** (new; the review's S382-01) is B's shape with #382's `app.storefront_background_prefix_v1` no longer STRICT
  (`CALLED ON NULL INPUT`); its body, owner and access are unchanged. It is refused with `surface382_function`, naming
  that function.
- B passed again: the same live negatives, check mode, and the one apply (the push 920 ms; 6 read-only and 1
  read-write session, all TLS; pg-delta off). `B_SHAPE` passed.
- A against B is EQUIVALENT. A's dump equals run2's (`73cba6c2…`), and every category equals run2's.
- The pin check passed, now including the twelve whole-definition digests.
- The database test lanes of §10.4 were not run again: no migration changed, and run2's lane records are cited by their
  SHA-256 (`A_validate/status.txt` `e6149c54…`, `B_validate/status.txt` `9856c70f…`).

**The S382-01 reproducer** (`run3/N14R/`) used one fresh N14 database:
- the pre-fix wrapper (`eef9d7de`, `2cc13668…`) **passes** check mode, because the change is invisible to it;
- the final wrapper **refuses** `surface382_function`.

### 10.4 Tests on both final databases (`run2/A_validate/`, `run2/B_validate/`)

| Lane | A | B |
|---|---|---|
| 353 runner (task-owned fixture of the database's schema) | PASS | PASS |
| acceptance-ETA runner (106 assertions, 9 races) | PASS | PASS |
| 001D concurrency runner, twice | PASS, PASS | PASS, PASS |
| full pgTAP aggregate | `Files=338, Tests=13523, Result: FAIL`, exit 1 | the same |
| the four dedicated-database suites | 0 failing | 0 failing |
| the seven 001D lanes | all PASS (139, 397, 273, 140, 244, 343, 177 tests) | the same |
| D1 (`public_surface_acl_remediation_001_test.sql`) | PASS (62) | PASS (62) |
| #380 tests (product media, scene) | PASS (96, 28) | PASS (96, 28) |
| cinematic database tests (appearance, content readiness) | PASS (116, 49) | PASS (116, 49) |
| #382 database test (`storefront_background_clarity_api_test.sql`) | PASS (57) | PASS (57) |
| cinematic migration contract tests (node) | 19 of 19 | 19 of 19 |
| GR-37 wrapper unit tests | 55 of 55 | 55 of 55 |
| content-contract suite (its dedicated local marker) | PASS (38) | PASS (38) |

- **The aggregate is honestly a FAIL.** The plain `supabase test db` ends `Files=338, Tests=13523, Result: FAIL` with
  exit 1 on both databases. Six guarded files refuse to run in the shared local database; this is the known local
  limitation.
  - Five of them pass in their own dedicated modes above: the four dedicated-database suites and the content-contract
    suite.
  - The sixth, the featured-items concurrency file, is CI-only and is not run locally.
- **The cinematic atomicity runner** is CI-only by its own `requireEphemeralCi` guard, which was not bypassed. Its
  contract tests above include the pinned sequence through #382. The runner itself runs in the cinematic real-service
  job on a PR.

### 10.5 Unit tests, default-route preservation and mutation checks

These checks ran at the final code head `252f4853`; the last record commit changes only this packet. The records are
`proof/*_252f4853*`.

- **Unit tests.**
  - Windows, Node 22.14.0: 56 of 56 pass.
  - Linux, Node 24.21.0 in Docker, with no network and a read-only mount: 49 pass and 7 skip at `/repo`; 50 pass and
    6 skip at `/w/store/repo`. The skips are by design:
    - the five Git-backed pin tests (the image has no git);
    - the Windows device-path test;
    - at `/repo` only, the default-wiring passfile test: the repository's parent, `/`, holds the scratch folder.
  - The Linux redaction mutant M01 is killed (one failing test).
- **Default-route preservation against `0fe8ef80`.** The text check passes, and so does the strengthened check of the
  review's ABCD-1:
  - **by AST** (Node's bundled acorn): 47 of the base's 50 top-level statements are unchanged byte for byte. The other
    three are the two widened imports (`node:crypto` and `node:fs`, each a superset of the base's) and `main()`, which
    gains exactly the one dispatch statement in front of the base body. Only declarations are added (55), and no added
    code references or writes the base's mutable bindings;
  - **by behaviour:** 88 probes of the default route's exports and of `main()`, base against head;
  - **sensitivity:** the review's `LOOPBACK.add` mutant, an `INHERITED.push` mutant and a side-effecting `const` are
    refused, and a comment-only change passes.
- **Mutation checks.** Each mutant runs in a scratch copy outside Git. A mutant counts as killed only when it parses,
  the test count equals the baseline's, and a test fails.
  - Four of the five harnesses point the copied tests' Git-backed pin tests at the work tree (baseline 56 pass).
  - The retained fix-round harness takes no work-tree argument, so its five Git-backed tests skip (baseline 51 pass and
    5 skip).

| Set | Killed |
|---|---|
| REPIN-001's own: the count pins, the third later migration, #382's statement, #382's surface pins and gates, the whole-definition digest, the NULL name, the runtime gate and its re-read drift | **47 of 47** (`REPIN_MUTANTS_252f4853_R2.txt`) |
| retained CR-EG-01 / CR-EG-02: the one-entry passfile gate and the fifth-role access gates | 33 of 34; A16 is not applied by design (its pattern now occurs twice) and is replaced by A16a and A16b |
| retained fix round | 17 of 18; M19 is not applied by design (its line now also names the runtime check) and is replaced by the adapted M19 |
| retained earlier review | 19 of 19 |
| retained, adapted to the repin: A16a, A16b, M19 | **3 of 3** (`RETAINED_ADAPTED_MUTANTS_252f4853_R2.txt`) |

- **Four mutant patterns had to be re-anchored.** The first mutation run at `252f4853` found REPIN-001's S05, G05 and
  G10, and the adapted A16b, not applied: `fc075ada` had put the whole-definition digest on the lines they anchored on.
  They were re-anchored to the new lines, and both full sets ran again. The `_R2` records are the final ones; the first
  records are kept as written, and nothing was counted for those four from them.

### 10.6 Residuals (disclosed, for the command room)

- **The #382 pins are the local reference's values.** The owner, exact access, stored name, catalog rendering and
  whole definitions of #382's objects were pinned from the local sequential reference, where an emulation of the
  official operation ran the file as `postgres`. The command room's hosted observation for this repin states the
  version count, the newest version, the absent 001D history row, private card tables and `card_attempt` function
  family, and the runtime, not these. If hosted's #382 objects or row differ, the check-mode run refuses before any
  push (`surface382_*`, `stored_name` or `stored_statement`), and the command room decides.
- **The access of the objects 001D creates is decided at the push** by hosted's default privileges for `postgres`. The
  PostgreSQL version is now a PRE gate, but the default privileges are not pinned; a difference ends in
  `POSTCHECK_MISMATCH` after the push (N8). A read-only comparison of hosted's default privileges with the reference
  (`run2/A_capture/cat_access_default.txt`, `cat_default_privileges.txt`) before `--apply` is offered in the
  continuation plan.
- **The tests stay valid when later migrations land.** The unit tests re-derive their pins from the oldest
  `localCount` committed migrations, so a later migration on `main` does not fail them; the wrapper itself then refuses
  at run time (`local_count`, `local_tail`), which needs a new Work ID and repin.

### 10.7 The focused review

One focused, fresh-context Claude review ran at head `91a59b9f` (`review/`). Five reviewers each took one group of
lenses:
- the recomposition, the CI isolation and the default route;
- D-066 and the records;
- the 188 / 187 sets and the stored statements;
- #382's surface pins;
- the PostgreSQL 17.6 gate and the CR-EG-01 / CR-EG-02 preservation.

The review found 1 MAJOR, 7 MINOR and 5 NOTE findings. Adversarial verifiers then checked the 8 MAJOR and MINOR
findings: one verifier for each MINOR finding and two for the MAJOR one. The NOTEs were not verified. By finding, the
verifiers confirmed 7 (REC-01 by both of its verifiers) and judged 1, S382-02, partially valid. Only confirmed defects
were fixed, in one round. The NOTEs were wording corrections of the records, applied without a second round.

| ID | Severity | Verdict | Disposition |
|---|---|---|---|
| REC-01 | MAJOR | confirmed (2 of 2) | §1 now states the command room's hosted observation exactly, and the four stored-statement pins separately (`bde3c744`) |
| SET-382-01 | MINOR | confirmed | fixed with REC-01 (the same sentence) |
| S382-01 | MINOR | confirmed: in a PGlite reproduction, the pre-fix checks accepted a changed STRICT, PARALLEL or COST, a re-created `RETURNS TABLE` and an added default | **code fix** (`fc075ada`): the whole-definition digest, pinned at PRE and unchanged at POST; proven live by N14 and the reproducer (§10.3) |
| S382-02 | MINOR | partial: a wording issue; no code change needed | the wrapper comment and §4.3 now state exactly what the relation's catalog line covers and what it does not (`fc075ada`, `bde3c744`) |
| RT-CR-01 | MINOR | confirmed | the retained A16 is split into A16a and A16b, and M19 is retargeted to the new re-read line; the CR-EG-02 SQL fragments are counted per block (`fc075ada`) |
| ABCD-1 | MINOR | confirmed | the strengthened default-route preservation proof, by AST and behaviour, with sensitivity probes (§10.5) |
| REC-02 | MINOR | confirmed | §2 counts the D-066 mentions on `main` per file (`bde3c744`) |
| SET-382-02 | MINOR | confirmed | two new assertions in the existing PRE-gates test, so PRE refuses a NULL stored name on #382's row and on a #380 row (`252f4853`; no new test) |
| ABCD-2, REC-03 to REC-06 | NOTE | — | wording corrected in the records and the PR draft |

The full findings and dispositions are in `review/REVIEW_RESULTS.md` and `review/REVIEW_DISPOSITIONS.md`. No Codex
review was requested.

### 10.8 Hosted, remote, provider and device

- **Hosted:** no query, apply, repair or ledger write.
- **Remote:** no push and no PR.
- **Provider and devices:** no Edge deploy, secret, `providerProfile` wiring or provider call; no terminal, card, APK or
  printer action.
- **Network reads only:** `git ls-remote` and `gh pr` reads, and the pinned CLI's own version check.
- **After this packet's last commit:** the Vercel prediction on the final head adds one bounded `git fetch` of `main`
  from the public repository, in a throwaway clone. It is recorded in the evidence folder; nothing is deployed and
  Vercel is not contacted.

### 10.9 Process notes

- **run1 was stopped on purpose.** It was started with an MSYS-style output path, which the Windows Python fixture tool
  cannot open, so the 353 and acceptance-ETA lanes did not run on A. Its processes and its test container were stopped,
  and the stack had no TLS or password change at that moment. The run driver now converts its output path; `run2/` is
  the complete proof (`run1/NOTE_STOPPED.txt`).
- **Some outputs landed in the wrong folder.** With path conversion off, node resolved an MSYS path to a stray
  folder at the drive root, outside the evidence folder. That affected the exploratory build's and run1's access snapshots, captures and one refusal
  record. They were moved back into the evidence folder, and the empty folders this task created there were removed.
- **The worktree stayed untouched during `run2`:** head `eef9d7de`, porcelain 0 at its start and at its end. The same
  holds for `run3` (head `bde3c744`) and for the final checks (head `252f4853`).
- **run3's first N14 "before" half proved nothing.** The pre-fix wrapper copy sat in the session's scratch store,
  which also holds the private passfiles. Its passfile-location gate therefore refused before any CLI process, as
  designed (`run3/NOTE_N14_BEFORE_RETRY.txt`). The reproducer was redone with the copy outside that store
  (`run3/N14R/`).
- **Four mutants were re-anchored** after `fc075ada` (§10.5). The first record that found them not applied is kept,
  and none of them was counted from it.
- **These records were fact-checked before this commit.** This was a read-only check of the records against git and
  the evidence, not a second review round (`review/FACTCHECK_*`). Five checkers covered this section and the
  publication files, and one skeptic tried to refute each discrepancy they reported.
  - They reported 14 discrepancies, 9 of them distinct; the skeptics refuted none.
  - Each was a fact in these records: the SET-382-02 fix described as a new test, the review's verification counts,
    the fix-round harness's Git-backed tests, the exceptions of the AST check, N7 and N8 in run3, the prefix sizes of
    N2A and N3, the dump's line count, and a network read that runs only after this commit.
  - All are corrected here and in the evidence's own records. No code, test or proof result changed.
