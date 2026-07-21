-- ============================================================================
-- KITCHEN-MODE-001C3B1A2 — pgTAP: authoritative POS spool-COUNT CERTAINTY.
--
--   * additive spool_count_state (text, NOT NULL, default 'unknown', closed
--     CHECK counted|absent|unknown) + the cross-field CHECK (absent => 0);
--   * report_kitchen_pos_status 6-arg (legacy, delegates 'unknown') + 7-arg
--     (canonical) overloads, exact count, grants, typed rejections;
--   * closed-vocab + cross-field validation; POS-only device-token auth;
--   * dormancy: no setter/writer/resolver; branches remain kds/rev 1.
-- Session pinned to UTC; hex-only UUIDs; GUC conventions per house style.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(33);

-- ===== fixture ===============================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0003b12000a0', 'Org A', 'kmc3b2-a', 'ILS');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0003b1200a10', '00000000-0000-0000-0000-0003b12000a0', 'Rest A1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0003b1200a2b', '00000000-0000-0000-0000-0003b12000a0', '00000000-0000-0000-0000-0003b1200a10', 'Branch P (printer-only)'),
  ('00000000-0000-0000-0000-0003b1200a1a', '00000000-0000-0000-0000-0003b12000a0', '00000000-0000-0000-0000-0003b1200a10', 'Branch K (kds)');
update branches set kitchen_workflow_mode = 'printer_only'
  where id = '00000000-0000-0000-0000-0003b1200a2b';

-- devices: pos@P d001, kds@P d002.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-0003b120d001', '00000000-0000-0000-0000-0003b12000a0', '00000000-0000-0000-0000-0003b1200a10', '00000000-0000-0000-0000-0003b1200a2b', 'pos'),
  ('00000000-0000-0000-0000-0003b120d002', '00000000-0000-0000-0000-0003b12000a0', '00000000-0000-0000-0000-0003b1200a10', '00000000-0000-0000-0000-0003b1200a2b', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-0003b120c001', '00000000-0000-0000-0000-0003b12000a0', '00000000-0000-0000-0000-0003b1200a10', '00000000-0000-0000-0000-0003b1200a2b', '00000000-0000-0000-0000-0003b120d001', 'active'),
  ('00000000-0000-0000-0000-0003b120c002', '00000000-0000-0000-0000-0003b12000a0', '00000000-0000-0000-0000-0003b1200a10', '00000000-0000-0000-0000-0003b1200a2b', '00000000-0000-0000-0000-0003b120d002', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, revoked_at) values
  ('00000000-0000-0000-0000-0003b120e001', '00000000-0000-0000-0000-0003b12000a0', '00000000-0000-0000-0000-0003b1200a10', '00000000-0000-0000-0000-0003b1200a2b', '00000000-0000-0000-0000-0003b120d001', '00000000-0000-0000-0000-0003b120c001', app.hash_provisioning_secret('tok-c3b2-posp'), true, null),
  ('00000000-0000-0000-0000-0003b120e002', '00000000-0000-0000-0000-0003b12000a0', '00000000-0000-0000-0000-0003b1200a10', '00000000-0000-0000-0000-0003b1200a2b', '00000000-0000-0000-0000-0003b120d002', '00000000-0000-0000-0000-0003b120c002', app.hash_provisioning_secret('tok-c3b2-kdsp'), true, null);

-- ===== A. schema =============================================================
select col_type_is('public', 'kitchen_pos_status_reports', 'spool_count_state', 'text',
  'spool_count_state is TEXT');                                                                                  -- 1
select col_not_null('public', 'kitchen_pos_status_reports', 'spool_count_state',
  'spool_count_state is NOT NULL');                                                                              -- 2
select col_default_is('public', 'kitchen_pos_status_reports', 'spool_count_state', 'unknown',
  'spool_count_state DEFAULTS to unknown (legacy rows fail closed)');                                            -- 3
-- direct-insert the closed-vocab CHECK (bypasses the RPC).
select throws_ok(
  $$ insert into kitchen_pos_status_reports (organization_id, restaurant_id, branch_id, device_id, app_build, mode_revision, secure_spool_available, unresolved_local_jobs, spool_count_state, expires_at)
     values ('00000000-0000-0000-0000-0003b12000a0','00000000-0000-0000-0000-0003b1200a10','00000000-0000-0000-0000-0003b1200a2b','00000000-0000-0000-0000-0003b120d001','b',1,true,0,'bogus', now()) $$,
  '23514', null, 'the closed-vocab CHECK rejects an unknown state value');                                       -- 4
select throws_ok(
  $$ insert into kitchen_pos_status_reports (organization_id, restaurant_id, branch_id, device_id, app_build, mode_revision, secure_spool_available, unresolved_local_jobs, spool_count_state, expires_at)
     values ('00000000-0000-0000-0000-0003b12000a0','00000000-0000-0000-0000-0003b1200a10','00000000-0000-0000-0000-0003b1200a2b','00000000-0000-0000-0000-0003b120d001','b',1,true,3,'absent', now()) $$,
  '23514', null, 'the cross-field CHECK rejects absent + nonzero unresolved');                                   -- 5
-- no sensitive columns snuck in.
select ok(
  not exists (select 1 from information_schema.columns
    where table_schema='public' and table_name='kitchen_pos_status_reports'
      and column_name in ('printer_assignment_id','printer_fingerprint','transport_kind','paper_width','connection_config','host','port','address','payload','capability','printer_purpose')),
  'no printer/endpoint/money/fingerprint column was added');                                                     -- 6

-- ===== B. overloads ==========================================================
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='app' and p.proname='report_kitchen_pos_status'),
  2, 'app.report_kitchen_pos_status has EXACTLY two overloads');                                                 -- 7
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='report_kitchen_pos_status'),
  2, 'public.report_kitchen_pos_status has EXACTLY two overloads');                                              -- 8
-- legacy 6-arg still works, stores UNKNOWN.
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b120d001', 'tok-c3b2-posp', 'b1', 1, true, 0) ->> 'ok'),
  'true', 'the LEGACY 6-arg status signature still works');                                                      -- 9
select is(
  (select spool_count_state from kitchen_pos_status_reports where device_id='00000000-0000-0000-0000-0003b120d001'),
  'unknown', 'the 6-arg legacy call stores spool_count_state=unknown (fail closed)');                            -- 10
-- 7-arg counted.
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b120d001', 'tok-c3b2-posp', 'b1', 1, true, 4, 'counted') ->> 'ok'),
  'true', 'the 7-arg canonical signature works (counted)');                                                      -- 11
select is(
  (select spool_count_state||':'||unresolved_local_jobs from kitchen_pos_status_reports where device_id='00000000-0000-0000-0000-0003b120d001'),
  'counted:4', '7-arg stores counted + the exact count');                                                        -- 12
-- 7-arg absent (0).
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b120d001', 'tok-c3b2-posp', 'b1', 1, false, 0, 'absent') ->> 'ok'),
  'true', '7-arg absent (secure_spool=false, 0) works');                                                         -- 13
select is(
  (select spool_count_state from kitchen_pos_status_reports where device_id='00000000-0000-0000-0000-0003b120d001'),
  'absent', '7-arg stores absent');                                                                              -- 14
-- 7-arg unknown.
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b120d001', 'tok-c3b2-posp', 'b1', 1, false, 0, 'unknown') ->> 'ok'),
  'true', '7-arg unknown works');                                                                                -- 15
select is(
  (select spool_count_state from kitchen_pos_status_reports where device_id='00000000-0000-0000-0000-0003b120d001'),
  'unknown', '7-arg stores unknown');                                                                            -- 16
-- one row per device across all the upserts.
select is(
  (select count(*)::int from kitchen_pos_status_reports where device_id='00000000-0000-0000-0000-0003b120d001'),
  1, 'still ONE current row per device after every upsert');                                                     -- 17
-- invalid state typed.
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b120d001', 'tok-c3b2-posp', 'b1', 1, true, 0, 'bogus') ->> 'error'),
  'invalid_spool_count_state', '7-arg rejects a non-vocab state, typed');                                        -- 18
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b120d001', 'tok-c3b2-posp', 'b1', 1, true, 0, null) ->> 'error'),
  'invalid_spool_count_state', '7-arg rejects a null state, typed');                                             -- 19
-- absent + nonzero rejected typed (before the CHECK).
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b120d001', 'tok-c3b2-posp', 'b1', 1, false, 5, 'absent') ->> 'error'),
  'invalid_spool_count_state', '7-arg rejects absent + nonzero, typed (cross-field)');                           -- 20
-- the rejected calls never changed the stored row.
select is(
  (select spool_count_state from kitchen_pos_status_reports where device_id='00000000-0000-0000-0000-0003b120d001'),
  'unknown', 'a rejected 7-arg call never overwrote the stored row');                                            -- 21

-- ===== C. RPC security =======================================================
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b120d002', 'tok-c3b2-kdsp', 'b1', 1, true, 0, 'counted') ->> 'error'),
  'invalid_session', 'a KDS device is denied the 7-arg status path');                                           -- 22
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b120d001', 'tok-wrong', 'b1', 1, true, 0, 'counted') ->> 'error'),
  'invalid_session', 'a bad token is denied');                                                                   -- 23
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b120d001', 'tok-c3b2-posp', 'b1', 99, true, 0, 'counted') ->> 'error'),
  'stale_mode_revision', 'a stale revision is typed');                                                           -- 24
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b120d001', 'tok-c3b2-posp', 'b1', 99, true, 0, 'counted') -> 'mode_revision')::text,
  '1', 'stale revision carries the authoritative current revision');                                            -- 25
update device_sessions set revoked_at = now() where id = '00000000-0000-0000-0000-0003b120e001';
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b120d001', 'tok-c3b2-posp', 'b1', 1, true, 0, 'counted') ->> 'error'),
  'invalid_session', 'a revoked session is denied');                                                             -- 26
update device_sessions set revoked_at = null where id = '00000000-0000-0000-0000-0003b120e001';
select ok(
  not has_function_privilege('anon', 'public.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer, text)', 'execute')
  and has_function_privilege('authenticated', 'public.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer, text)', 'execute')
  and not has_function_privilege('anon', 'app.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer, text)', 'execute'),
  'the 7-arg overload: anon denied on both signatures; authenticated granted');                                 -- 27
select ok(
  not has_function_privilege('anon', 'public.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer)', 'execute')
  and has_function_privilege('authenticated', 'public.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer)', 'execute'),
  'the legacy 6-arg overload keeps its grants (anon denied, authenticated allowed)');                            -- 28
select ok(
  (select c.relrowsecurity and c.relforcerowsecurity from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='kitchen_pos_status_reports')
  and (select count(*)::int from information_schema.role_table_grants
        where table_name='kitchen_pos_status_reports' and grantee in ('anon','authenticated')
          and privilege_type in ('SELECT','INSERT','UPDATE','DELETE')) = 0,
  'the status table keeps FORCE RLS and ZERO direct client grants');                                             -- 29

-- ===== D. dormancy ===========================================================
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('app','public')
      and (p.proname like 'set_%kitchen_workflow_mode%' or p.proname like 'resolve_kitchen_dispatch_ambiguous_hold%')),
  0, 'dormancy: NO setter / writer / resolver function exists');                                                 -- 30
select ok(
  (select kitchen_workflow_mode = 'kds' and kitchen_workflow_mode_revision = 1
     from branches where id = '00000000-0000-0000-0000-0003b1200a1a'),
  'dormancy: the kds branch remains kds at revision 1');                                                         -- 31
select is(
  (select kitchen_workflow_mode_revision from branches where id = '00000000-0000-0000-0000-0003b1200a2b'),
  1, 'dormancy: the printer_only fixture branch was never revision-bumped by this migration');                  -- 32
-- old-client status is structurally non-authoritative (unknown) => future
-- escape ineligible. Prove the stored row is unknown after a legacy report.
select public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b120d001', 'tok-c3b2-posp', 'b1', 1, true, 0);
select is(
  (select spool_count_state from kitchen_pos_status_reports where device_id='00000000-0000-0000-0000-0003b120d001'),
  'unknown', 'a legacy-client report is stored UNKNOWN (future escape fail-closed)');                            -- 33

select * from finish();
rollback;
