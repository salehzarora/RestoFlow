-- ============================================================================
-- STOREFRONT-SEC-001 — public-surface ACL posture (Postgres role `anon`)
--
-- Pins the posture established by migration
-- 20260913164029_public_surface_acl_remediation_001.sql and the rule recorded
-- as DECISION D-037 / SECURITY_AND_THREAT_MODEL T-016:
--
--   A. the set of `public` functions EXECUTE-able by `anon` EQUALS the
--      enumerated allowlist — dynamic over pg_proc, culprits are printed on
--      failure. STOREFRONT-READ-001 (2026-09-23, owner decision D1: D-037
--      ratified with ONE amendment) moved the allowlist from EMPTY to exactly
--      {public.storefront_menu(text)}, the one SECURITY DEFINER function
--      `public` may carry, and the one public function `authenticated` may
--      NOT execute; A1 / A5 / D1 pin that set by equality;
--   B. `anon` has no USAGE on schema `app` and keeps USAGE on `public`;
--   C. `anon` holds no privilege on any `public` table, view or sequence;
--   D. `authenticated` is untouched — every wrapper stays executable and the
--      representative device / kiosk / POS / management wrappers are reachable
--      at the GRANT layer (business refusals are fine, grant refusals are not);
--   E. the REAL database role `anon` (set local role anon — no faked JWT) is
--      refused at the grant layer, and the migration's statements are proven
--      effective against a hosted-shaped pre-state reproduced inside this
--      transaction (grant-then-revoke idiom, audit_log_dashboard_001 precedent);
--   F. default privileges of the migration-running owner (`postgres`) in
--      `public` no longer hand `anon` anything, proven by creating throwaway
--      objects under the legacy default and under the remediated default.
--
-- Hosted Supabase's legacy "auto-expose new entities" default is what this
-- suite guards against; the local CLI stack (v2.107) never carried it, which is
-- why sections E and F REPRODUCE it inside the rolled-back transaction instead
-- of trusting the clean local baseline (POS-124B lesson: "anon may execute
-- nothing" passed locally and was false on hosted).
--
-- No tenant fixtures are needed: every assertion is about catalog state or a
-- grant-layer refusal. Session pinned to UTC. Run via `supabase test db`.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(62);

-- The D-037 allowlist as amended by STOREFRONT-READ-001: exactly one function,
-- named by identity. Every A1 / A5 / D1 assertion below compares against THIS
-- literal, so a second anon-callable or DEFINER public function fails here
-- until it is enumerated in its own migration + suite (D-037 point 2).
create temp table sec001_allowlist (identity text primary key);
insert into sec001_allowlist values ('storefront_menu(text)');

-- ----------------------------------------------------------------------------
-- A. anon function family guard (effective privileges, dynamic) ............ (6)
-- ----------------------------------------------------------------------------
select is(
  (select coalesce(string_agg(regexp_replace(p.oid::regprocedure::text, '^public.', ''), ', ' order by regexp_replace(p.oid::regprocedure::text, '^public.', '')), '')
     from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.prokind = 'f'
      and has_function_privilege('anon', p.oid, 'EXECUTE')),
  (select string_agg(identity, ', ' order by identity) from sec001_allowlist),
  'A1. anon-executable public function set EQUALS the enumerated allowlist {storefront_menu(text)} — any extra culprit prints here');

select cmp_ok(
  (select count(*)::int from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'),
  '>=', 100,
  'A2. the guard covers the real wrapper population (>= 100 public functions; not vacuous)');

select is(
  (select count(*)::int from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.proacl is null),
  0,
  'A3. every public function carries an EXPLICIT ACL (a NULL ACL would mean implicit PUBLIC EXECUTE)');

select is(
  (select coalesce(string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text), '')
     from pg_proc p
     cross join lateral aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
    where p.pronamespace = 'public'::regnamespace
      and p.prokind = 'f'
      and a.grantee = 0
      and a.privilege_type = 'EXECUTE'),
  '',
  'A4. the PUBLIC pseudo-role holds EXECUTE on no public function (acldefault-aware)');

select is(
  (select coalesce(string_agg(regexp_replace(p.oid::regprocedure::text, '^public.', ''), ', ' order by regexp_replace(p.oid::regprocedure::text, '^public.', '')), '')
     from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.prosecdef),
  (select string_agg(identity, ', ' order by identity) from sec001_allowlist),
  'A5. the ONLY public SECURITY DEFINER function is the enumerated allowlist (D-037 amendment) — no wrapper can carry anon into app.*');

select is(
  (select coalesce(string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text), '')
     from pg_proc p
     cross join lateral aclexplode(p.proacl) a
    where p.pronamespace = 'app'::regnamespace
      and a.grantee = (select oid from pg_roles where rolname = 'anon')),
  '',
  'A6. no app.* function carries an explicit anon grant');

-- ----------------------------------------------------------------------------
-- B. schema boundary ....................................................... (3)
-- ----------------------------------------------------------------------------
select ok(not has_schema_privilege('anon', 'app', 'USAGE'),
  'B1. anon has no USAGE on schema app (every SECURITY INVOKER wrapper is a dead end for it)');
select ok(has_schema_privilege('authenticated', 'app', 'USAGE'),
  'B2. authenticated keeps USAGE on schema app (RLS helper expressions evaluate as the caller)');
select ok(has_schema_privilege('anon', 'public', 'USAGE'),
  'B3. anon keeps USAGE on schema public (PostgREST needs it; the future explicit allowlist lives there)');

-- ----------------------------------------------------------------------------
-- C. anon table / view / sequence guard + RLS posture unchanged ........... (5)
-- ----------------------------------------------------------------------------
select is(
  (select coalesce(string_agg(c.relname, ', ' order by c.relname), '')
     from pg_class c
    where c.relnamespace = 'public'::regnamespace
      and c.relkind in ('r', 'p', 'v', 'm')
      and (   has_table_privilege('anon', c.oid, 'SELECT')
           or has_table_privilege('anon', c.oid, 'INSERT')
           or has_table_privilege('anon', c.oid, 'UPDATE')
           or has_table_privilege('anon', c.oid, 'DELETE')
           or has_table_privilege('anon', c.oid, 'TRUNCATE')
           or has_table_privilege('anon', c.oid, 'REFERENCES')
           or has_table_privilege('anon', c.oid, 'TRIGGER')
           or has_table_privilege('anon', c.oid, 'MAINTAIN'))),
  '',
  'C1. anon holds NO privilege on any public table or view (culprits would print)');

select is(
  (select coalesce(string_agg(c.relname, ', ' order by c.relname), '')
     from pg_class c
    where c.relnamespace = 'public'::regnamespace
      and c.relkind = 'S'
      and (   has_sequence_privilege('anon', c.oid, 'USAGE')
           or has_sequence_privilege('anon', c.oid, 'SELECT')
           or has_sequence_privilege('anon', c.oid, 'UPDATE'))),
  '',
  'C2. anon holds NO privilege on any public sequence');

select cmp_ok(
  (select count(*)::int from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'),
  '>=', 40,
  'C3. the relation guard covers the real table population (>= 40 public tables; not vacuous)');

select is(
  (select count(*)::int from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and not c.relrowsecurity),
  0,
  'C4. RLS is enabled on every public table (unchanged by SEC-001)');

select is(
  (select coalesce(string_agg(c.relname, ', ' order by c.relname), '')
     from pg_class c
    where c.relnamespace = 'public'::regnamespace
      and c.relkind = 'r'
      and not c.relforcerowsecurity),
  'plans',
  'C5. FORCE RLS everywhere except the reference table plans (pre-existing rf093 shape, documented, not changed)');

-- ----------------------------------------------------------------------------
-- D. authenticated regression — grants untouched ........................... (23)
-- ----------------------------------------------------------------------------
select is(
  (select coalesce(string_agg(regexp_replace(p.oid::regprocedure::text, '^public.', ''), ', ' order by regexp_replace(p.oid::regprocedure::text, '^public.', '')), '')
     from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
      and not has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  (select string_agg(identity, ', ' order by identity) from sec001_allowlist),
  'D1. every public function remains EXECUTE-able by authenticated EXCEPT the enumerated anon-only allowlist (explicitly revoked)');

-- device / pairing
select ok(has_function_privilege('authenticated', 'public.redeem_device_pairing(text, text)', 'EXECUTE'),
  'D2. device: redeem_device_pairing stays available to authenticated');
select ok(has_function_privilege('authenticated', 'public.restore_device_session(uuid, text)', 'EXECUTE'),
  'D3. device: restore_device_session stays available to authenticated');
select ok(has_function_privilege('authenticated', 'public.redeem_device_enrollment_code(uuid, uuid, text)', 'EXECUTE'),
  'D4. device: redeem_device_enrollment_code stays available to authenticated');
-- kiosk
select ok(has_function_privilege('authenticated', 'public.kiosk_menu(uuid, text)', 'EXECUTE'),
  'D5. kiosk: kiosk_menu stays available to authenticated');
select ok(has_function_privilege('authenticated', 'public.kiosk_tables(uuid, text)', 'EXECUTE'),
  'D6. kiosk: kiosk_tables stays available to authenticated');
select ok(has_function_privilege('authenticated',
  'public.kiosk_submit_order(uuid, text, uuid, text, text, uuid, text, text, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz, boolean)', 'EXECUTE'),
  'D7. kiosk: kiosk_submit_order stays available to authenticated');
-- POS
select ok(has_function_privilege('authenticated', 'public.pos_menu(uuid, uuid)', 'EXECUTE'),
  'D8. POS: pos_menu stays available to authenticated');
select ok(has_function_privilege('authenticated', 'public.sync_push(uuid, uuid, jsonb)', 'EXECUTE'),
  'D9. POS: sync_push stays available to authenticated');
select ok(has_function_privilege('authenticated', 'public.sync_pull(uuid, uuid, text[], jsonb, integer)', 'EXECUTE'),
  'D10. POS: sync_pull stays available to authenticated');
select ok(has_function_privilege('authenticated', 'public.start_pin_session(uuid, uuid, text, text)', 'EXECUTE'),
  'D11. POS: start_pin_session stays available to authenticated');
-- management surfaces
select ok(has_function_privilege('authenticated', 'public.get_my_context()', 'EXECUTE'),
  'D12. management: get_my_context stays available to authenticated');
select ok(has_function_privilege('authenticated', 'public.create_organization(uuid, text, text, text, text, text, text, text)', 'EXECUTE'),
  'D13. management: create_organization stays available to authenticated');
select ok(has_function_privilege('authenticated', 'public.list_org_structure(uuid)', 'EXECUTE'),
  'D14. management: list_org_structure stays available to authenticated');
select ok(has_function_privilege('authenticated', 'public.owner_daily_report(uuid, uuid, uuid)', 'EXECUTE'),
  'D15. management: owner_daily_report stays available to authenticated');
select ok(has_function_privilege('authenticated', 'public.platform_admin_console_overview(text)', 'EXECUTE'),
  'D16. management: platform_admin_console_overview stays available to authenticated');

-- authenticated table posture is exactly what earlier migrations set (SEC-001 names anon only)
select ok(has_table_privilege('authenticated', 'public.orders', 'SELECT'),
  'D17. authenticated keeps SELECT on orders (rf052 shape)');
select ok(not has_table_privilege('authenticated', 'public.orders', 'INSERT'),
  'D18. authenticated still has no direct INSERT on orders (rf052 shape — RPC-only writes)');
select ok(has_table_privilege('authenticated', 'public.plans', 'SELECT'),
  'D19. authenticated keeps SELECT on plans (rf093 shape)');
select ok(has_table_privilege('authenticated', 'public.daily_branch_sales_report', 'SELECT'),
  'D20. authenticated keeps SELECT on the report views (rf075 shape)');
select ok(not has_table_privilege('authenticated', 'public.kitchen_print_dispatches', 'SELECT'),
  'D21. the kitchen ledger stays closed to authenticated (kitchen_mode_001c1 shape)');

-- grant-layer reachability as the REAL authenticated role: business refusals
-- (invalid session, no actor, ...) are expected and fine; a
-- "permission denied for function/schema" would mean SEC-001 broke a grant.
create temp table sec001_auth_probe (probe text, code text, msg text);
grant all on sec001_auth_probe to authenticated;
set local role authenticated;
do $probe$
begin
  begin
    perform public.restore_device_session('00000000-0000-0000-0000-000000000000'::uuid, 'sec001-bogus-token');
    insert into sec001_auth_probe values ('device', '00000', 'ok');
  exception when others then
    insert into sec001_auth_probe values ('device', sqlstate, sqlerrm);
  end;
  begin
    perform public.kiosk_menu('00000000-0000-0000-0000-000000000000'::uuid, 'sec001-bogus-token');
    insert into sec001_auth_probe values ('kiosk', '00000', 'ok');
  exception when others then
    insert into sec001_auth_probe values ('kiosk', sqlstate, sqlerrm);
  end;
  begin
    perform public.pos_menu('00000000-0000-0000-0000-000000000000'::uuid, '00000000-0000-0000-0000-000000000000'::uuid);
    insert into sec001_auth_probe values ('pos', '00000', 'ok');
  exception when others then
    insert into sec001_auth_probe values ('pos', sqlstate, sqlerrm);
  end;
  begin
    perform public.get_my_context();
    insert into sec001_auth_probe values ('management', '00000', 'ok');
  exception when others then
    insert into sec001_auth_probe values ('management', sqlstate, sqlerrm);
  end;
end
$probe$;
reset role;

select is(
  (select coalesce(string_agg(probe || ': ' || msg, ' | ' order by probe), '')
     from sec001_auth_probe
    where msg ilike 'permission denied for function%'
       or msg ilike 'permission denied for schema%'),
  '',
  'D22. no representative wrapper is refused at the GRANT layer for authenticated (device/kiosk/POS/management)');
select is((select count(*)::int from sec001_auth_probe), 4,
  'D23. all four family probes executed');

-- ----------------------------------------------------------------------------
-- E. REAL anon principal + effectiveness against a hosted-shaped pre-state . (14)
-- ----------------------------------------------------------------------------
-- Reproduce the hosted legacy shape on samples (explicit anon grants stamped
-- at CREATE time), then run the migration's own statement forms against them.
grant execute on function public.list_timezones() to anon;
grant execute on function public.get_my_context() to anon;
grant select, insert, update, delete, truncate, references, trigger, maintain on table public.plans to anon;
grant select on table public.daily_branch_sales_report to anon;

select ok(has_function_privilege('anon', 'public.list_timezones()', 'EXECUTE'),
  'E1. simulation: a hosted-style explicit anon EXECUTE grant is reproduced on list_timezones');
select ok(has_table_privilege('anon', 'public.plans', 'SELECT'),
  'E2. simulation: a hosted-style anon table grant is reproduced on plans');

revoke all on function public.list_timezones() from anon;
revoke all on function public.get_my_context() from anon;
revoke all privileges on all functions in schema public from anon;
revoke all privileges on table public.plans from anon;
revoke all privileges on all tables in schema public from anon;

select ok(not has_function_privilege('anon', 'public.list_timezones()', 'EXECUTE'),
  'E3. the migration statement form removes the explicit anon EXECUTE grant');
select ok(not has_function_privilege('anon', 'public.get_my_context()', 'EXECUTE'),
  'E3b. the migration statement form also removes the second simulated anon EXECUTE grant (get_my_context)');
select ok(not has_table_privilege('anon', 'public.plans', 'SELECT')
      and not has_table_privilege('anon', 'public.plans', 'MAINTAIN')
      and not has_table_privilege('anon', 'public.daily_branch_sales_report', 'SELECT'),
  'E4. the migration statement form removes anon table and view grants (incl. MAINTAIN)');
select ok(has_function_privilege('authenticated', 'public.list_timezones()', 'EXECUTE'),
  'E5. authenticated EXECUTE is untouched by the anon revoke');
select ok(has_table_privilege('authenticated', 'public.plans', 'SELECT'),
  'E6. authenticated SELECT is untouched by the anon revoke');
-- STOREFRONT-READ-001: the SEC-001 statement form above is NOT a drift remedy
-- any more. Re-running it would strip the allowlist grant (proven here, inside
-- this rolled-back transaction) — DEPLOYMENT.md §16 records the rule. The
-- grant is restored so the remaining assertions see the real posture.
select ok(not has_function_privilege('anon', 'public.storefront_menu(text)', 'EXECUTE'),
  'E6b. re-running the SEC-001 schema-wide revoke STRIPS the READ-001 allowlist — SEC-001 must never be re-applied as a drift remedy');
grant execute on function public.storefront_menu(text) to anon;

set local role anon;
select throws_ok(
  $$ select public.list_timezones() $$,
  '42501', 'permission denied for function list_timezones',
  'E7. REAL anon (set local role anon, no JWT) is refused at the FUNCTION grant layer (not merely at schema app)');
select throws_ok(
  $$ select public.get_my_context() $$,
  '42501', 'permission denied for function get_my_context',
  'E8. REAL anon is refused at the FUNCTION grant layer on get_my_context');
select throws_ok(
  $$ select count(*) from public.orders $$,
  '42501', null,
  'E9. REAL anon cannot read orders (grant layer, before RLS is even consulted)');
select throws_ok(
  $$ select count(*) from public.plans $$,
  '42501', null,
  'E10. REAL anon cannot read plans (RLS is no longer the only barrier)');
select throws_ok(
  $$ select count(*) from public.daily_branch_sales_report $$,
  '42501', null,
  'E11. REAL anon cannot read a report view');
select throws_ok(
  $$ insert into public.audit_events (id) values (gen_random_uuid()) $$,
  '42501', 'permission denied for table audit_events',
  'E12. REAL anon cannot INSERT — refused at the TABLE grant layer, before RLS or any constraint');
select throws_ok(
  $$ select app.current_app_user_id() $$,
  '42501', null,
  'E13. REAL anon cannot reach schema app — the GUC-fallback helper is unreachable for it');
reset role;

-- ----------------------------------------------------------------------------
-- F. default-privilege guard for the migration-running owner ............... (10)
-- ----------------------------------------------------------------------------
select is(
  (select coalesce(string_agg(d.defaclobjtype::text || ':' || a.privilege_type, ', ' order by d.defaclobjtype::text, a.privilege_type), '')
     from pg_default_acl d
     left join pg_namespace n on n.oid = d.defaclnamespace
     cross join lateral aclexplode(d.defaclacl) a
    where (n.nspname = 'public' or d.defaclnamespace = 0)
      and d.defaclrole = (select oid from pg_roles where rolname = 'postgres')
      and a.grantee   = (select oid from pg_roles where rolname = 'anon')),
  '',
  'F1. role postgres has NO default privilege for anon in schema public nor globally (objtype:privilege would print)');

-- Reproduce the hosted legacy default inside this transaction, prove it bites,
-- then apply the migration's default-privilege revoke and prove it no longer does.
-- Postgres semantics pinned here: a per-schema default ACL is ADDED ON TOP of the
-- built-in default (functions: owner + PUBLIC EXECUTE). The migration removes the
-- explicit `anon` stamp; the built-in PUBLIC EXECUTE on a brand-new function is
-- closed by the house rule `revoke all on function ... from public` that every
-- migration issues (and A3/A4 above fail if one forgets).
set local role postgres;
alter default privileges for role postgres in schema public grant execute on functions to anon;
create function public.sec001_probe_fn_legacy() returns integer language sql as $$ select 1 $$;
select ok(
  exists (select 1 from pg_proc p cross join lateral aclexplode(p.proacl) a
           where p.oid = 'public.sec001_probe_fn_legacy()'::regprocedure
             and a.grantee = (select oid from pg_roles where rolname = 'anon')),
  'F2. simulation: under the legacy default a NEW public function is stamped with an explicit anon EXECUTE at CREATE (hosted mechanics reproduced)');
alter default privileges for role postgres in schema public revoke execute on functions from anon;
create function public.sec001_probe_fn_remediated() returns integer language sql as $$ select 1 $$;
select ok(
  not exists (select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
               where p.oid = 'public.sec001_probe_fn_remediated()'::regprocedure
                 and a.grantee = (select oid from pg_roles where rolname = 'anon')),
  'F3. after the migration''s default-privilege revoke a NEW public function carries NO explicit anon grant');
select ok(has_function_privilege('anon', 'public.sec001_probe_fn_remediated()', 'EXECUTE'),
  'F3b. before the house revoke, the built-in PUBLIC EXECUTE still reaches anon on a NEW function (why every migration must `revoke ... from public`)');
revoke all on function public.sec001_probe_fn_remediated() from public;
select ok(not has_function_privilege('anon', 'public.sec001_probe_fn_remediated()', 'EXECUTE'),
  'F4. with the house `revoke ... from public` on top, the NEW function is not anon-executable at all (effective)');

alter default privileges for role postgres in schema public grant all on tables to anon;
create table public.sec001_probe_t_legacy (id integer);
select ok(has_table_privilege('anon', 'public.sec001_probe_t_legacy', 'SELECT'),
  'F5. simulation: under the legacy default a NEW public table is anon-readable at CREATE');
alter default privileges for role postgres in schema public revoke all privileges on tables from anon;
create table public.sec001_probe_t_remediated (id integer);
select ok(not has_table_privilege('anon', 'public.sec001_probe_t_remediated', 'SELECT')
      and not has_table_privilege('anon', 'public.sec001_probe_t_remediated', 'INSERT')
      and not has_table_privilege('anon', 'public.sec001_probe_t_remediated', 'TRUNCATE')
      and not has_table_privilege('anon', 'public.sec001_probe_t_remediated', 'MAINTAIN'),
  'F6. after the migration''s default-privilege revoke a NEW public table gets no anon privilege at all (tables have no built-in PUBLIC grant, so this is complete)');

-- sequences (none exist in public today — C2 is a population-free guard, so
-- prove the sequence default with created objects, like F5/F6 for tables)
alter default privileges for role postgres in schema public grant all on sequences to anon;
create sequence public.sec001_probe_seq_legacy;
select ok(has_sequence_privilege('anon', 'public.sec001_probe_seq_legacy', 'USAGE'),
  'F7. simulation: under the legacy default a NEW public sequence is anon-usable at CREATE (hosted S: anon=rwU reproduced)');
alter default privileges for role postgres in schema public revoke all privileges on sequences from anon;
create sequence public.sec001_probe_seq_remediated;
select ok(not has_sequence_privilege('anon', 'public.sec001_probe_seq_remediated', 'USAGE')
      and not has_sequence_privilege('anon', 'public.sec001_probe_seq_remediated', 'SELECT')
      and not has_sequence_privilege('anon', 'public.sec001_probe_seq_remediated', 'UPDATE'),
  'F8. after the migration''s default-privilege revoke a NEW public sequence gets no anon privilege');
-- global (schema-less) defaults: the migration also revokes them; prove a
-- global anon default would have been visible to F1 and is absent
select is(
  (select count(*)::int from pg_default_acl d
    where d.defaclnamespace = 0
      and d.defaclrole = (select oid from pg_roles where rolname = 'postgres')),
  0,
  'F9. role postgres holds no global (schema-less) default-privilege row at all');
reset role;

select * from finish();
rollback;
