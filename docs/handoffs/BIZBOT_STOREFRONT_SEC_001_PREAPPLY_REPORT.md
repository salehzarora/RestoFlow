# STOREFRONT-SEC-001 — Public Surface Hardening Pre-Apply Report

**Ticket:** STOREFRONT-SEC-001 (BIZBOT Storefront Phase 1A.1)
**Date:** 2026-09-13
**Author:** Claude Code (security / backend lead)
**Phase:** PRE-APPLY ONLY. Nothing has been applied to hosted. Production is unchanged (proven by a
post-work re-inventory, §Hosted Pre-Apply Recheck).

## Baseline

- Production Supabase project: `oqmevrndtivqxgyvcmwy` ("RestoFlow", `eu-west-1`), migrations **139/139**,
  head `20260905090001`, PostgreSQL 17.6 (`aarch64`).
- Repository: `salehzarora/RestoFlow`, `origin/main` = `fc8969ed` (fetched at the start of this ticket;
  local `main` `f94ac5fc` was four commits behind and was **not** used).
- Phase 0 architecture audit (`docs/handoffs/BIZBOT_STOREFRONT_PHASE0_ARCHITECTURE_AUDIT.md`, untracked)
  named this remediation as the prerequisite of every public Storefront RPC.
- Standing rule (CLAUDE.md, D-011/D-012): clients hold only the publishable key; the Postgres role
  `anon` must have no authority beyond an explicit allowlist. Supabase anonymous sign-ins are role
  `authenticated`, not `anon` — paired POS/KDS/Kiosk devices are untouched by this ticket.

## Exact Git Base

| Item | Value |
|---|---|
| `origin/main` at start | `fc8969ed fix(vercel): acquire first-preview baselines from canonical source (#278)` |
| Worktree | `C:\Users\saleh\Desktop\ClaudeAi\RestoFlow\worktrees\storefront-sec-001` |
| Branch | `feat/STOREFRONT-SEC-001-public-surface-hardening` (created from `origin/main`) |
| Migration set at base | identical to hosted (139 files, head `20260905090001`) |

## Supabase Production Identity Proof

Five independent signals agree that `oqmevrndtivqxgyvcmwy` is the BIZBOT production project:

| Signal | Evidence |
|---|---|
| CLI link | `supabase/.temp/project-ref` = `oqmevrndtivqxgyvcmwy`; `supabase/.temp/linked-project.json` = `{"ref":"oqmevrndtivqxgyvcmwy","name":"RestoFlow","organization_id":"uunzdrspduzcqfbrfdtr"}`; pooler host `aws-0-eu-west-1.pooler.supabase.com` |
| Account project list | `supabase projects list`: `oqmevrndtivqxgyvcmwy` — name **RestoFlow**, region **eu-west-1**, `ACTIVE_HEALTHY`, `linked: true`, created 2026-07-04; the only other project on the account is `xcfjxgdfgjvsqkhuiczu` (`madaf-staging-frankfurt`, `INACTIVE`) |
| Migration history | `supabase migration list --linked`: 139 applied, head `20260905090001` — byte-for-byte the repository's set |
| Live tables | read-only counts: 6 organizations, 6 restaurants, 881 orders, 45 menu items, 119 devices, 1,130 auth users (1,124 anonymous device principals); server address in the AWS `eu-west-1` IPv6 range |
| Release tooling | `tools/android_release/build_official_pair.ps1:100` pins `https://oqmevrndtivqxgyvcmwy.supabase.co` as the expected backend baked into official APKs; `verify_official_apk.ps1:116` verifies it |

Every hosted query in this ticket was run with `supabase db query --linked` from the linked main
checkout (`C:\Users\saleh\Desktop\ClaudeAi\RestoFlow\RestoFlow`) and was SELECT-only.

## MCP / CLI Project Mismatch

- `.mcp.json` (git-ignored, untracked) points the Supabase MCP server at `project_ref=txdckbptxkvsscxkrnen`.
- That ref is **not** in the CLI account's project list at all — it is neither production nor the inactive
  staging project. It cannot be the BIZBOT production project.
- The MCP server was unauthenticated in this session and was **not** used; `.mcp.json` was **not**
  changed (owner action: retarget it to `oqmevrndtivqxgyvcmwy` or delete it).
- Consequence for runbooks: any hosted command must be preceded by `cat supabase/.temp/project-ref` =
  `oqmevrndtivqxgyvcmwy` (DEPLOYMENT.md §13 already requires this; §16 repeats it).

## Hosted Function ACL Inventory

Fresh read-only inventory (`pg_proc` ⨝ `pg_namespace`, `has_function_privilege`, `aclexplode`):

| Fact | Value |
|---|---|
| `public` functions | **118** (116 names; overload pairs `report_kitchen_pos_status` 6/7-arg and `report_kitchen_printer_readiness` 11/12-arg) |
| Owner | `postgres` for all 118 |
| `SECURITY DEFINER` in `public` | **0** (all INVOKER wrappers, `search_path=""`) |
| Effective `anon` EXECUTE | **78 of 118** — every one via an explicit `anon=X/postgres` ACL entry |
| Explicit PUBLIC EXECUTE / NULL ACL | 0 / 0 |
| Effective `authenticated` EXECUTE | 118 of 118 |
| `app` functions | 232 (191 DEFINER); 6 have a NULL ACL (`set_updated_at`, `emit_kds_invalidation_hint`, `clear_table_reservation_on_seat`, `jsonb_is_*` ×3) — moot for `anon` (no USAGE on `app`) |
| `graphql_public.graphql` | anon-executable, platform-owned, `pg_graphql` not installed — out of scope |

The 78 anon-executable functions are exactly the wrappers whose migrations revoked PUBLIC only
(pre-2026-07-11 house form); the 40 blocked ones carry an explicit `revoke … from anon`. Full list with
ACLs: private evidence `PRE_q1_functions.json`.

**Function ACL fingerprint (sha256 over `schema.name(args)|acl` for public+app+graphql_public):**
`38ba02c5b74aff1e8616c8a6736929c0e1583a23b6a5eff40c59658b0b33e079`

## Hosted Table / Sequence ACL Inventory

| Fact | Value |
|---|---|
| `public` tables | 49, all owned by `postgres`; views 6; sequences **0** |
| `anon` with full DML (`arwdDxtm` = INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN) | **45 tables + 6 views = 51 relations** |
| Tables where `anon` holds nothing | `kitchen_pos_status_reports`, `kitchen_print_dispatches`, `kitchen_printer_readiness_reports`, `platform_support_sessions` (their migrations revoked anon explicitly) |
| `authenticated` | SELECT on 44, INSERT 16, UPDATE 17, DELETE 17; TRUNCATE/REFERENCES/TRIGGER/MAINTAIN on 45 (platform baseline; **not** changed by SEC-001, see Risks) |
| Views | all six are `security_invoker = true` |
| `storage.*` tables | platform-owned (`supabase_storage_admin`), anon grants are Supabase's own — **not touched** |

**Relation ACL fingerprint:** `03e5646877d491dc5c8a6fe3cc643ab976cfc12145380feeb049d7e4303d2f41`

## Hosted Default Privileges

`pg_default_acl` rows for the migration-running owner in schema `public`:

| Owner | Obj | ACL |
|---|---|---|
| `postgres` | `f` | `{postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}` |
| `postgres` | `r` | `{postgres=arwdDxtm/postgres,anon=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}` |
| `postgres` | `S` | `{postgres=rwU/postgres,anon=rwU/postgres,authenticated=rwU/postgres,service_role=rwU/postgres}` |

This is Supabase's legacy "auto-expose new entities" behaviour (`supabase/config.toml:17-22` documents
the setting and its 2026-10-30 removal). `supabase_admin` also holds default entries in `public`
containing `anon`; they cannot be altered by `postgres` and do not apply to migration-created objects
(all owned by `postgres`). Same-shape rows exist for schema `storage` — platform-managed, untouched.

**Local CLI stack (v2.107) after `db reset`:** `f` = `{postgres=X/postgres}`, `r` = `{…,anon=Dxtm,…}`,
`S` = `{…,anon=w,…}` — the "always-revoked" shape. This asymmetry is why the repository's pgTAP could
not see the hosted grants (POS-124B lesson) and why the new suite reproduces the hosted shape inside
its transaction.

**Postgres semantics verified empirically (local):** a per-schema default ACL is *added on top of* the
built-in default. For functions the built-in default includes PUBLIC EXECUTE, so removing `anon` from
the per-schema entry removes the explicit `anon` stamp, while a brand-new function still has PUBLIC
EXECUTE until the house `revoke all … from public` runs; tables have no built-in PUBLIC grant, so the
table default becomes fully closed for `anon`.

## RLS / FORCE RLS Findings

- RLS **enabled** on 49/49 public tables, **forced** on 48/49 — `plans` (reference data, rf093) is
  enabled but not forced; three tables (`platform_admin_audit_events`, `platform_admin_grants`,
  `platform_support_sessions`) have RLS + zero policies = deny-all. Not changed by SEC-001.
- All 218 policies are `TO authenticated`; `realtime.messages` has exactly the two RF-058 policies;
  `storage.objects` has ten, all `TO authenticated`. Buckets `menu-images` / `restaurant-logos` are
  private (28 / 1 objects).
- Before SEC-001, RLS is the **only** barrier between `anon` and 51 relations. After SEC-001 the grant
  layer refuses first (42501), RLS stays as the second barrier.

## Existing Effective Anon Attack Surface

What the Postgres role `anon` (publishable key, no session) can do on hosted today:

1. **EXECUTE 78 public wrappers** — including `sync_push`, `sync_pull`, `create_organization`,
   `kiosk_submit_order`, `set_branch_tax`, all `menu_upsert_*`, `platform_admin_*`. Every wrapper is
   `SECURITY INVOKER` and dead-ends with 42501 at `app.*` because `anon` has no USAGE on schema `app`.
   That single, accidental layer is the only thing between the internet and every tenant RPC.
2. **SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER on 51 relations** — refused row-by-row
   by forced RLS (SELECT → 0 rows; writes → 42501 from `WITH CHECK`). TRUNCATE is **not** subject to
   RLS but is not reachable through PostgREST.
3. Nothing in `app`, `auth`, `storage` (beyond platform defaults), `realtime`.

Compatibility proof (repository, read-only): **no legitimate path uses role `anon`.** Every app signs in
before its first RPC (`packages/auth_identity/lib/src/supabase_auth_bootstrap.dart:73-84` calls
`signInAnonymously()` before building the transport; Dashboard/Admin gate `get_my_context` behind a
signed-in status); there are zero `client.from('<table>')` reads in `apps/*/lib` or `packages/*/lib`;
`site/`, `e2e/` and `tools/` never hit the Data API; zero `grant … to anon` / `to public` in 139
migrations; 218/218 policies name `authenticated`. The only sessionless transports
(`pos_session.dart:149-154`, `kds_session.dart:145-150`, `auth_context_fetcher.dart:29-34`) already
receive 42501 from PUBLIC revokes and map it to `AuthDeniedFailure` — SEC-001 changes nothing for
them. Two pgTAP files read `storage.objects` as `anon` and expect 0 rows — SEC-001 is scoped to schema
`public`, so they are unaffected (full suite green, below).

## current_app_user_id Audit

**Helper:** `app.current_app_user_id()` — live body is the RF-050 definition
(`supabase/migrations/20260621090000_rf050_supabase_auth_principal_mfa.sql:80-102`), confirmed
byte-identical on hosted (`pg_get_functiondef`, private evidence `PRE_hosted_current_app_user_id.csv`):
`STABLE SECURITY DEFINER SET search_path=''`; ACL `{postgres=X, authenticated=X}` (PUBLIC revoked,
no `anon`).

| Question | Finding |
|---|---|
| `auth.uid()` IS NULL | returns `nullif(current_setting('app.current_app_user_id', true), '')::uuid` — the GUC is trusted verbatim (unset/'' → NULL, non-uuid → 22P02). When a JWT `sub` exists the GUC is **never** consulted (unlinked principal → NULL, fail closed; `rf050_membership_resolution_test.sql:84-100`) |
| GUC fallback exists? | yes (`app.current_app_user_id`); the RF-050 comment "tightened at RF-059" never shipped (rf059 A5 left it unchanged) |
| Can an untrusted caller influence it? | **No.** PostgREST sets only `role`, `request.jwt.claims`, `request.headers/cookies/method/path`; no exposed function calls `set_config`/`SET` on that name (only `app.menu_reordering` and `app.platform_report_read` are set, with hard-coded values); no dynamic SQL sink; no `public.*` function is `SECURITY DEFINER` |
| Participates in authorization? | yes — every tenant/rank/platform helper (`current_org_id`, `has_scope`, `has_role_in_scope`, `is_platform_admin`, `actor_rank_in_scope`, `platform_admin_guard`, ~130 RPC bodies) derives identity from it |
| Reachable by `anon` today? | **No**: no USAGE on `app`, no EXECUTE on the function, no policy targets `anon`, no public DEFINER carrier; after SEC-001 `anon` cannot execute any public wrapper either (pinned: E13 in the new suite) |
| `authenticated` callers? | always carry `sub` through PostgREST → the fallback branch is dead for them |
| Would restricting it break trusted flows? | removing it breaks 120 pgTAP files (GUC-driven fixtures); the smallest safe hardening (honour the GUC only when `request.jwt.claims` is absent) would need edits in 4 test files / 11 spots |

**Verdict: not exploitable by an untrusted caller today → per ticket §5 the helper is left unchanged.**
Recommended follow-up ticket (own RF id, R-003 sign-off): `else case when nullif(current_setting('request.jwt.claims', true), '') is null then <GUC> else null end`
so no HTTP-originated request can ever take the fallback even if a future `set_config` bug appears.

## Remediation Design

Target posture (Phase 1A, before any Storefront RPC exists):

| Dimension | Before (hosted) | After |
|---|---|---|
| `anon` EXECUTE on `public` functions | 78 / 118 | **0** (empty allowlist) |
| `anon` privileges on `public` tables/views/sequences | 51 relations, full DML | **none** |
| `anon` USAGE on `app` | none | none (made explicit) |
| `anon` USAGE on `public` | yes | yes (kept — PostgREST + future allowlist) |
| `authenticated` / `service_role` | unchanged | **unchanged** (asserted) |
| `postgres` default privileges in `public` | anon on f/r/S | **anon removed** from all three |
| Future Storefront RPCs | — | granted to `anon` one by one, by exact signature, each with its own real-`anon` pgTAP proof; **not** granted to `authenticated` unless proven necessary (D-037) |

Design choices: every privilege change is a flat, explicit statement in house style (118 exact
identity signatures, 49 tables, 6 views, plus schema-wide `on all functions/tables/sequences`
catch-alls for anything created between inventory and apply); two `do` blocks change nothing — step 0
aborts if any `public` object is not owned by `postgres` (the role the default-privilege statements
name), step 6 asserts the full target posture and aborts the transaction on any miss, so hosted can
never be half-applied. The built-in PUBLIC EXECUTE on brand-new functions is closed by the mandatory
per-function `revoke … from public` and pinned by the new suite (A3/A4); a global
`ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` was evaluated and
deliberately **not** included (it would also affect future extension/helper functions created by
`postgres` in every schema — a wider blast radius than this ticket; recorded as a follow-up).

## Migration

`supabase/migrations/20260913164029_public_surface_acl_remediation_001.sql` (created with
`supabase migration new public_surface_acl_remediation_001`; sorts after `20260905090001`).

| Step | Statements | Names |
|---|---|---|
| 0 | owner precondition (`do`, read-only) | — |
| 1 | `revoke all on function public.<sig> from anon;` × **118** (exact identity signatures from the hosted catalog, incl. both overload pairs) | anon |
| 2 | `revoke all privileges on all functions in schema public from anon;` | anon |
| 3 | `revoke all privileges on table public.<t> from anon;` × 49 tables + × 6 views; `… on all tables / all sequences in schema public from anon;` | anon |
| 4 | `revoke usage on schema app from anon;` (already absent — explicit) | anon |
| 5 | `alter default privileges for role postgres in schema public revoke execute on functions / all privileges on tables / all privileges on sequences from anon;` plus the same three **global** (schema-less) revokes — no global row exists on hosted or locally, so they are no-ops that leave no row behind | anon |
| 6 | posture assertion (`do`, read-only; raises on miss) | — |

Not in the file: any `grant`, any statement naming `authenticated`/`service_role`/`public`
(PUBLIC), any DDL on tables/functions/policies, any data write, any `storage`/`realtime`/`auth`
object, any GUC helper change, any Storefront object. Forward-only; idempotent; local `db reset`
applied it cleanly and printed
`SEC-001 posture reached: anon_exec_functions=0, anon_relations=0, anon_app_usage=false, anon_default_acl_entries(postgres; public+global)=0, authenticated_functions=118/118`.

## Tests

`supabase/tests/public_surface_acl_remediation_001_test.sql` — **61 assertions**, house skeleton
(`begin; … select plan(61); … reset role; select * from finish(); rollback;`):

| Ticket requirement | Section | What is pinned |
|---|---|---|
| A. anon function family guard | A1–A6 | dynamic over `pg_proc`: anon-executable `public` set = `''` (culprits print), ≥100 functions (anti-vacuity), every function has an explicit ACL, PUBLIC holds EXECUTE on none (`acldefault`-aware), no `public` DEFINER, no explicit anon grant on any `app.*` |
| B. app schema boundary | B1–B3 | anon no USAGE on `app`; authenticated keeps it; anon keeps USAGE on `public` |
| C. anon table guard | C1–C5 | no anon privilege on any table/view (all 8 PG17 privilege types incl. MAINTAIN) or sequence; ≥40 tables; RLS enabled on all; forced everywhere except `plans` |
| D. authenticated regression | D1–D23 | all 118 wrappers executable by authenticated; explicit pins for device/pairing (3), kiosk (3), POS (4), management (5); table posture pins (orders SELECT yes / INSERT no, plans, report view, kitchen ledger closed); behavioural probe as the REAL `authenticated` role calling one wrapper per family and asserting no "permission denied for function/schema" |
| E. real anon principal | E1–E14 | hosted-shape simulation (`grant … to anon` on samples, incl. MAINTAIN) → the migration's own statement forms remove it → `set local role anon` (no JWT): wrapper and `get_my_context` refused with the exact message `permission denied for function …` (so the proof is the function grant layer, not the `app` schema dead-end), `orders`/`plans`/report view SELECT 42501, INSERT refused with `permission denied for table audit_events`, `app.current_app_user_id()` 42501; authenticated grants untouched |
| F. default privilege guard | F1–F9 (10 assertions) | no `anon` entry in `postgres` defaults for `public` **or globally**; created-object simulations prove the legacy default stamps anon on a new function / table / sequence and the migration's revoke stops it (function: explicit stamp gone, F3b pins that built-in PUBLIC EXECUTE still reaches anon until the house `revoke … from public`, F4 that it is then closed; table and sequence: fully closed); no global default row exists |
| G. GUC tests | — | not applicable: helper unchanged (§current_app_user_id Audit) |

All simulations run inside the test transaction and are rolled back.

## Local Reset / pgTAP

| Gate | Result |
|---|---|
| `supabase db reset` (139 + 1 migrations) | OK; SEC-001 assertion NOTICE printed the reached posture |
| `supabase test db --local supabase/tests/public_surface_acl_remediation_001_test.sql` | **61/61 PASS** |
| `supabase test db --local` (full suite) | **Files=273, Tests=6862, all successful** (run twice: before and after the review fixes) |
| `bash tools/check_secrets.sh` | OK: no committable secrets |
| `git diff --check` | clean |
| `supabase migration list --local` | head `20260913164029` |

No pre-existing failures were observed. (Local ports were shifted to `5532x` in `supabase/config.toml`
for this machine's WinNAT/TakeTor clash per the documented workaround; that edit is reverted and
**not committed**.)

## Authenticated Regression Proof

- Grant layer: D1 (118/118 executable by `authenticated`), D2–D16 explicit pins for
  `redeem_device_pairing`, `restore_device_session`, `redeem_device_enrollment_code`, `kiosk_menu`,
  `kiosk_tables`, `kiosk_submit_order`, `pos_menu`, `sync_push`, `sync_pull`, `start_pin_session`,
  `get_my_context`, `create_organization`, `list_org_structure`, `owner_daily_report`,
  `platform_admin_console_overview`; D17–D21 table posture unchanged.
- Behavioural: D22/D23 — as the real `authenticated` role, one wrapper per family executes past the
  grant layer.
- Whole product: the existing 272 suites (device pairing, kiosk menu/order, POS menu/sync/payments,
  management, platform admin, storage, realtime) are green on the remediated database.

## Documentation Corrections

| File | Change |
|---|---|
| `docs/DECISIONS.md` | new **D-037** ADR (explicit `anon` allowlist; empty at Phase 1A; rule for future Storefront RPCs; correction record) + changelog line (next free ID D-038); D-035 (:673) and D-036 (:698) "doubly blocked (revoked from public …)" mechanism text corrected — the decisions stand |
| `docs/SECURITY_AND_THREAT_MODEL.md` | §3 Layer 3: new SECURITY REQUIREMENT paragraph (owner of the allowlist rule); §14: new **T-016**; line 113 recipe now "REVOKEd from PUBLIC **and anon**" |
| `docs/API_CONTRACT.md` | §4 preamble: public-schema ACL posture note (D-037); five per-RPC recipe lines corrected to name the explicit anon revoke (:344, :380, :408, :528, :531) |
| `docs/TESTING_STRATEGY.md` | §2 deny-by-default bullet for the real `anon` role; §6 harness bullet (T-016); §7 item 1 qualifier |
| `docs/DEPLOYMENT.md` | new **§16** hosted PRE/POST verification queries + drift watch |
| `docs/audits/RESTOFLOW-AUDIT-001-full-project-review.md` | one-line erratum under the "zero anon grants anywhere" claim (dated snapshot kept) |
| `supabase/recovery/README.md` | new: rules for evidence-derived recovery scripts |

Frozen-document note: DECISIONS / SECURITY / API_CONTRACT / TESTING_STRATEGY are frozen; these edits
go through the §9 architecture-change procedure via this ticket's PR (Codex review + owner approval),
as the ticket instructed.

## Hosted Pre-Apply Recheck

Re-run at the end of the work (read-only, from the linked main checkout):

| Fact | Start of ticket | Recheck |
|---|---|---|
| migrations | 139 / head `20260905090001` | 139 / head `20260905090001` |
| public functions / anon-executable | 118 / 78 | 118 / 78 |
| relations with anon privileges | 51 | 51 |
| function ACL fingerprint | `38ba02c5…b33e079` | `38ba02c5…b33e079` (identical) |
| relation ACL fingerprint | `03e56468…303d2f41` | `03e56468…303d2f41` (identical) |
| `postgres` defaults in `public` | anon on f/r/S | anon on f/r/S |
| live counts | 6/6/881/45/119/1130 | 6/6/881/45/119/1130 |

**Production is unchanged.**

## Exact Production Apply Plan

**Do NOT execute without explicit owner approval.** Preconditions: PR merged to `main`; the linked
main checkout (`C:\Users\saleh\Desktop\ClaudeAi\RestoFlow\RestoFlow`) pulled to the merged commit
(`--linked` commands only work where `supabase/.temp/project-ref` exists — not in the worktree).

1. Identity gate: `cat supabase/.temp/project-ref` → must print `oqmevrndtivqxgyvcmwy`;
   `supabase projects list` → RestoFlow, eu-west-1, `linked: true`.
2. `supabase migration list --linked` → exactly one pending: `20260913164029`. Anything else → STOP.
3. Record PRE values: DEPLOYMENT §16 queries 1–7 (expected PRE: `anon_exec = 78`, `auth_missing = 0`,
   query 3 lists 51 relations, query 5 `false,true,true`, query 6 rows contain `anon=`, query 7 = 1)
   plus the fingerprint script in private evidence. Save the outputs next to `PRE_*.json`.
4. Owner says GO.
5. `supabase db push --linked --yes` (no `db reset`, no seed, no `--include-all`). Expected output:
   one migration applied and the NOTICE `SEC-001 posture reached: …`. The `pgdelta … ca.crt ENOENT`
   warning is a harmless local cache step (documented). Any ERROR → the transaction has rolled back;
   STOP and report.
6. Run DEPLOYMENT §16 queries 1–8 (expected AFTER column) and the fingerprint script; save as `POST_*`.
7. Smoke: on a paired POS, open the Orders sheet (sync_pull) and print a test receipt; on the
   Dashboard, load Overview (`get_my_context`, reports); on a kiosk, load the menu. All are
   `authenticated` paths that SEC-001 must not touch.
8. `NOTIFY pgrst, 'reload schema';` only if a Dashboard RPC returns `PGRST202` (documented recipe).

Blast radius: grant-layer only, role `anon` only, schema `public` only. Zero data rows, zero function
bodies, zero policies. A regression can only manifest as a 42501 on a request made with the publishable
key and **no** session — a path no shipped client uses.

Expected post-apply: anon function allowlist **empty**; anon relation privileges **none**;
`authenticated` 118/118 functions, table grants unchanged; `postgres` defaults in `public` without
`anon`.

## Exact Post-Apply Verification Queries

See `docs/DEPLOYMENT.md` §16 (queries 1–8 with expected values). Fingerprint script:
`scratchpad/sec001/gen_sql.py` logic (canonical `schema.name(args)|acl` and
`schema.name|relkind|acl|rls` lines, sha256) — the POST function fingerprint must differ from
`38ba02c5…` (78 ACLs change) while `authenticated` tokens are identical row-for-row; the POST relation
fingerprint must differ from `03e56468…` while every `authenticated=` token is identical.

## Exact Recovery Plan

`supabase/recovery/sec001_restore_prior_anon_privileges.sql` — generated from the PRE inventory,
restores **only** what was proven present: `grant execute … to anon` for the 78 functions (exact
signatures); `grant insert, select, update, delete, truncate, references, trigger, maintain on table …
to anon` for the 51 relations; the three `alter default privileges for role postgres in schema public
grant … to anon` entries (tables ALL = `arwdDxtm`, sequences ALL = `rwU`, functions EXECUTE = `X`).
No `GRANT ALL ON ALL …`, nothing for `authenticated`/`service_role`/PUBLIC, nothing outside `public`.

If the hosted apply causes a verified regression: stop; do not improvise; run the recovery script
(after owner approval) from the linked checkout with `supabase db query --linked -f`; re-run
DEPLOYMENT §16 and the fingerprint script and confirm the PRE fingerprints return; record the outcome.
The migration stays in the ledger (forward-only); the next migration carries the corrected posture.

Private evidence (outside git): `C:\Users\saleh\Desktop\ClaudeAi\RestoFlow\private-evidence\sec001\`
(`PRE_q1_functions.json`, `PRE_q2_schemas_roles.json`, `PRE_q3_tables.json`,
`PRE_q4_defaults_policies_storage_identity.json`, `PRE_q5.json`, `PRE_hosted_current_app_user_id.csv`,
copy of the recovery script).

## Changed Files

| File | Kind |
|---|---|
| `supabase/migrations/20260913164029_public_surface_acl_remediation_001.sql` | new migration |
| `supabase/tests/public_surface_acl_remediation_001_test.sql` | new pgTAP suite (61) |
| `supabase/recovery/sec001_restore_prior_anon_privileges.sql` | new recovery script |
| `supabase/recovery/README.md` | new |
| `docs/DECISIONS.md` | D-037 + D-035/D-036 correction + changelog |
| `docs/SECURITY_AND_THREAT_MODEL.md` | §3 requirement, T-016, line 113 |
| `docs/API_CONTRACT.md` | §4 preamble + 5 recipe lines |
| `docs/TESTING_STRATEGY.md` | 3 bullets |
| `docs/DEPLOYMENT.md` | §16 |
| `docs/audits/RESTOFLOW-AUDIT-001-full-project-review.md` | erratum |
| `docs/handoffs/BIZBOT_STOREFRONT_SEC_001_PREAPPLY_REPORT.md` | this report |

Not changed: `supabase/config.toml` (local port shift reverted before commit), `.mcp.json`, any app
code, any Vercel/DNS/env, Supabase Auth, hosted anything.

## Branch

`feat/STOREFRONT-SEC-001-public-surface-hardening` from `origin/main` `fc8969ed`, worktree
`…\worktrees\storefront-sec-001`. Commit: `fix(security): harden public Supabase anon surface [STOREFRONT-SEC-001]`.

## PR

`fix(security): harden BIZBOT public anon surface [STOREFRONT-SEC-001]` — preparation only; hosted
migration NOT applied; production unchanged; explicit owner approval required before apply; not to be
merged by the agent. (URL recorded in the final response.)

## Explicit Non-Changes

No hosted migration applied; no hosted SQL write; no production ACL/schema/data/RLS/function/policy
changed; no Supabase Auth setting changed; no Vercel/DNS/env change; no deploy; no merge; no `.mcp.json`
change; no app/POS/KDS/Kiosk/Dashboard code change; no dependency installed; no Storefront object
(`storefront/`, slug, profile, public RPC, web-order tables, inbox, delivery, WhatsApp) created; no
`current_app_user_id` change; no grant to `authenticated`/`service_role`; no `GRANT ALL` anywhere.

## Risks

1. **Hosted default-privilege drift.** A Supabase platform upgrade may re-apply the legacy `postgres`
   default; the `supabase_admin` defaults already contain `anon` and cannot be altered by `postgres`.
   Mitigation: DEPLOYMENT §16 drift watch; T-016 catches any *migration* that re-grants. Owner
   option: disable "Expose new tables/functions automatically" in the Supabase Dashboard Data API
   settings (project setting — not done here).
2. **`db-tests` is not a required status check.** Branch protection requires only
   `format · bootstrap · analyze · test · guardrails`; the pgTAP job (`supabase pgTAP …`) is not in the
   required set, so T-016 blocks nothing by itself. Recommend adding it (GitHub setting, owner action).
3. **Built-in PUBLIC EXECUTE on new functions** remains (Postgres default, both environments); the
   house `revoke … from public` + A3/A4 are the control. A global `REVOKE EXECUTE ON FUNCTIONS FROM
   PUBLIC` for role `postgres` is a candidate follow-up with its own blast-radius review.
4. **`authenticated`/`anon` TRUNCATE·REFERENCES·TRIGGER·MAINTAIN baseline** — anon's is removed here;
   `authenticated` keeps the platform baseline on 45 tables (TRUNCATE is not RLS-governed but is not
   reachable through PostgREST). Follow-up candidate, out of SEC-001 scope.
5. **`plans` not forced** — pre-existing rf093 shape; DEFINER reads rely on it; unchanged.
6. **`graphql_public.graphql`** stays anon-executable (platform object; `pg_graphql` not installed).
7. **GUC fallback** in `app.current_app_user_id()` — latent impersonation primitive, unreachable
   today; follow-up ticket recommended (§current_app_user_id Audit).
8. **Apply must run from a linked checkout** at the merged commit; running `db push` from a checkout
   with extra local migrations would push them too — the §16 preflight (`exactly one pending`) guards it.

## Independent Review (pre-commit)

A read-only adversarial review (4 lenses: SQL correctness / hosted-apply safety, pgTAP rigor,
recovery + blast radius, ticket scope; every finding independently re-verified) confirmed 13
findings and refuted none. All were fixed before commit: MAINTAIN (PG17's eighth table privilege)
added to the migration assertion and the tests; global (schema-less) default-privilege revokes added
and the assertion/F1/§16 query widened to see global rows; E7/E8/E12 now match the exact
`permission denied for function/table …` message so the proof is the grant layer rather than the
`app` schema dead-end; a second simulated function grant asserted (E3b); the built-in PUBLIC EXECUTE
mechanic pinned (F3b); sequence created-object probes (F7/F8) and a global-row check (F9);
migration header wording about "future objects" corrected; recovery README pinned to the exact
migration head; this report committed so the migration's references resolve; the local port
workaround in `supabase/config.toml` excluded from the commit. The review also confirmed: all 118
signatures and 55 relations exist in the migration set; the step-0/step-6 blocks change nothing;
no statement names `authenticated`/`service_role`/PUBLIC; storage/realtime/auth are untouched;
D-037 and T-016 were free identifiers.

## Recommendation

Ready for owner review and, after PR review, for the explicit hosted-apply decision. The migration is
narrow (role `anon`, schema `public`, grants only), asserts its own outcome, is proven locally against
a reproduced hosted shape with the full 273-file suite green, has an evidence-derived recovery script,
and no client path depends on the privileges it removes.
