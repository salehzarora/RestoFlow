-- ============================================================================
-- KITCHEN-MODE-001A — pgTAP: schema, DORMANCY (no activation path) and the
-- READ-ONLY workflow-mode RPCs.
--
--   * branches.kitchen_workflow_mode — text NOT NULL DEFAULT 'kds',
--     CHECK in ('kds','printer_only'); every existing branch reads 'kds'.
--   * NO ACTIVATION PATH: app roles cannot write the column directly (revoked
--     UPDATE privilege => 42501), NO setter function exists anywhere in
--     app/public, and an unrelated branch-settings setter (RF-113) cannot
--     touch the column. The ONLY write path is privileged SQL (the fixture).
--   * app.get_branch_kitchen_workflow_mode — member READ (rank > 0), typed
--     not_found on no-coverage/cross-tenant, 42501 unauthenticated.
--   * app.get_device_kitchen_workflow_mode — TOKEN-PROVEN device READ; every
--     failure is a TYPED {ok:false, error:invalid_session} and NEVER a silent
--     fabricated 'kds' (the future fail-closed POS depends on this).
--   * Security: SECURITY DEFINER + pinned search_path; grants to authenticated
--     only; app.try_auto_complete_order stays INTERNAL; branches RLS still
--     ENABLED + FORCED.
--   * Correction pass (review HIGH-2 / MEDIUM-1): the device getter enforces
--     the FULL liveness contract — expired session, inactive session,
--     suspended branch, suspended restaurant, suspended organization, inactive
--     device, revoked pairing, forged token, cross-device token reuse all
--     return the SAME typed invalid_session with NO mode key; a cross-branch
--     session row is proven STRUCTURALLY impossible (composite FKs); the
--     no-activation-path check inspects EVERY function that updates branches.
-- Session pinned to UTC; hex-only UUIDs; GUC/PIN conventions as RF-113.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(45);

-- ===== fixture ===============================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0001a0000a00', 'Org A', 'km1a-a', 'ILS'),
  ('00000000-0000-0000-0000-0001a0000b00', 'Org B', 'km1a-b', 'EUR');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0001a0000a10', '00000000-0000-0000-0000-0001a0000a00', 'Rest A1', 'UTC'),
  ('00000000-0000-0000-0000-0001a0000b10', '00000000-0000-0000-0000-0001a0000b00', 'Rest B1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0001a0000a1a', '00000000-0000-0000-0000-0001a0000a00', '00000000-0000-0000-0000-0001a0000a10', 'Branch A1a'),
  ('00000000-0000-0000-0000-0001a0000a2a', '00000000-0000-0000-0000-0001a0000a00', '00000000-0000-0000-0000-0001a0000a10', 'Branch A2a (stays kds)'),
  ('00000000-0000-0000-0000-0001a0000b1a', '00000000-0000-0000-0000-0001a0000b00', '00000000-0000-0000-0000-0001a0000b10', 'Branch B1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0001a0000e01', 'km1a-owner@example.test'),
  ('00000000-0000-0000-0000-0001a0000e02', 'km1a-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0001a0000f01', '00000000-0000-0000-0000-0001a0000e01', '00000000-0000-0000-0000-0001a0000a00', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0001a0000f02', '00000000-0000-0000-0000-0001a0000e02', '00000000-0000-0000-0000-0001a0000a00', '00000000-0000-0000-0000-0001a0000a10', '00000000-0000-0000-0000-0001a0000a1a', 'cashier');
-- a paired POS device @ A1a with a LIVE + a REVOKED token-proven session (RF-161 shape),
-- and a FOREIGN device in Org B (no session) for the forged-device assertion.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('00000000-0000-0000-0000-0001a0004001', '00000000-0000-0000-0000-0001a0000a00', '00000000-0000-0000-0000-0001a0000a10', '00000000-0000-0000-0000-0001a0000a1a', 'pos', 'Front POS'),
  ('00000000-0000-0000-0000-0001a0004002', '00000000-0000-0000-0000-0001a0000a00', '00000000-0000-0000-0000-0001a0000a10', '00000000-0000-0000-0000-0001a0000a2a', 'pos', 'A2a POS'),
  ('00000000-0000-0000-0000-0001a0004b01', '00000000-0000-0000-0000-0001a0000b00', '00000000-0000-0000-0000-0001a0000b10', '00000000-0000-0000-0000-0001a0000b1a', 'pos', 'Org B POS');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-0001a0004011', '00000000-0000-0000-0000-0001a0000a00', '00000000-0000-0000-0000-0001a0000a10', '00000000-0000-0000-0000-0001a0000a1a', '00000000-0000-0000-0000-0001a0004001', 'active'),
  ('00000000-0000-0000-0000-0001a0004021', '00000000-0000-0000-0000-0001a0000a00', '00000000-0000-0000-0000-0001a0000a10', '00000000-0000-0000-0000-0001a0000a2a', '00000000-0000-0000-0000-0001a0004002', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, revoked_at, expires_at) values
  -- the LIVE session, a REVOKED one, an EXPIRED one (RF-118), an INACTIVE
  -- (never revoked) one — all on device 4001 — and a live session on the
  -- SECOND device 4002 in the kds branch (cross-device reuse + per-branch read).
  ('00000000-0000-0000-0000-0001a0004051', '00000000-0000-0000-0000-0001a0000a00', '00000000-0000-0000-0000-0001a0000a10', '00000000-0000-0000-0000-0001a0000a1a', '00000000-0000-0000-0000-0001a0004001', '00000000-0000-0000-0000-0001a0004011', app.hash_provisioning_secret('tok-km1a-pos'),      true,  null,  null),
  ('00000000-0000-0000-0000-0001a0004052', '00000000-0000-0000-0000-0001a0000a00', '00000000-0000-0000-0000-0001a0000a10', '00000000-0000-0000-0000-0001a0000a1a', '00000000-0000-0000-0000-0001a0004001', '00000000-0000-0000-0000-0001a0004011', app.hash_provisioning_secret('tok-km1a-revoked'),  false, now(), null),
  ('00000000-0000-0000-0000-0001a0004053', '00000000-0000-0000-0000-0001a0000a00', '00000000-0000-0000-0000-0001a0000a10', '00000000-0000-0000-0000-0001a0000a1a', '00000000-0000-0000-0000-0001a0004001', '00000000-0000-0000-0000-0001a0004011', app.hash_provisioning_secret('tok-km1a-expired'),  true,  null,  now() - interval '1 hour'),
  ('00000000-0000-0000-0000-0001a0004054', '00000000-0000-0000-0000-0001a0000a00', '00000000-0000-0000-0000-0001a0000a10', '00000000-0000-0000-0000-0001a0000a1a', '00000000-0000-0000-0000-0001a0004001', '00000000-0000-0000-0000-0001a0004011', app.hash_provisioning_secret('tok-km1a-inactive'), false, null,  null),
  ('00000000-0000-0000-0000-0001a0004061', '00000000-0000-0000-0000-0001a0000a00', '00000000-0000-0000-0000-0001a0000a10', '00000000-0000-0000-0000-0001a0000a2a', '00000000-0000-0000-0000-0001a0004002', '00000000-0000-0000-0000-0001a0004021', app.hash_provisioning_secret('tok-km1a-a2'),       true,  null,  null);

-- ===== A. schema (as the BYPASSRLS owner) ====================================
select is(
  (select data_type from information_schema.columns
    where table_schema = 'public' and table_name = 'branches' and column_name = 'kitchen_workflow_mode'),
  'text', 'branches.kitchen_workflow_mode exists and is text');                                                  -- 1
select is(
  (select is_nullable from information_schema.columns
    where table_schema = 'public' and table_name = 'branches' and column_name = 'kitchen_workflow_mode'),
  'NO', 'kitchen_workflow_mode is NOT NULL');                                                                    -- 2
select ok(
  (select column_default like '%kds%' from information_schema.columns
    where table_schema = 'public' and table_name = 'branches' and column_name = 'kitchen_workflow_mode'),
  'kitchen_workflow_mode defaults to ''kds''');                                                                  -- 3
select is(
  (select kitchen_workflow_mode from branches where id = '00000000-0000-0000-0000-0001a0000a1a'),
  'kds', 'a branch created WITHOUT the column reads the default ''kds'' (existing rows untouched)');             -- 4
select throws_ok(
  $$ update branches set kitchen_workflow_mode = 'both' where id = '00000000-0000-0000-0000-0001a0000a1a' $$,
  '23514', NULL, 'the CHECK rejects any value outside (kds, printer_only)');                                     -- 5

-- the ONLY write path in this phase: privileged (BYPASSRLS/superuser) SQL.
update branches set kitchen_workflow_mode = 'printer_only' where id = '00000000-0000-0000-0000-0001a0000a1a';
select is(
  (select kitchen_workflow_mode from branches where id = '00000000-0000-0000-0000-0001a0000a1a'),
  'printer_only', 'privileged SQL (the test fixture path) can flip a branch to printer_only');                   -- 6

-- ===== B. NO ACTIVATION PATH =================================================
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('app', 'public')
      and p.proname like '%kitchen_workflow_mode%'
      and p.proname not like 'get\_%'),
  0, 'NO setter/updater function for kitchen_workflow_mode exists anywhere in app/public');                      -- 7
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('app', 'public')
      and p.proname in ('get_branch_kitchen_workflow_mode', 'get_device_kitchen_workflow_mode')),
  4, 'exactly the four READ functions exist (app + public wrapper, member + device)');                           -- 8

set local role authenticated;
select throws_ok(
  $$ update branches set kitchen_workflow_mode = 'printer_only'
       where id = '00000000-0000-0000-0000-0001a0000b1a' $$,
  '42501', NULL, 'an app role cannot write branches directly (revoked privilege => 42501)');                     -- 9

-- ===== C. member READ (Dashboard) ============================================
set local app.current_app_user_id = '00000000-0000-0000-0000-0001a0000e01';  -- org_owner
select is(
  (app.get_branch_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0000a00','00000000-0000-0000-0000-0001a0000a10','00000000-0000-0000-0000-0001a0000a1a') ->> 'ok'),
  'true', 'org_owner may read the branch workflow mode');                                                        -- 10
select is(
  (app.get_branch_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0000a00','00000000-0000-0000-0000-0001a0000a10','00000000-0000-0000-0000-0001a0000a1a') ->> 'kitchen_workflow_mode'),
  'printer_only', 'the member read reflects the REAL persisted state (never a fabricated default)');             -- 11

set local app.current_app_user_id = '00000000-0000-0000-0000-0001a0000e02';  -- cashier
select is(
  (app.get_branch_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0000a00','00000000-0000-0000-0000-0001a0000a10','00000000-0000-0000-0000-0001a0000a1a') ->> 'ok'),
  'true', 'any active member covering the branch (cashier) may READ the mode');                                  -- 12

set local app.current_app_user_id = '00000000-0000-0000-0000-0001a0000e01';  -- org_owner of Org A
select is(
  (app.get_branch_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0000b00','00000000-0000-0000-0000-0001a0000b10','00000000-0000-0000-0000-0001a0000b1a') ->> 'error'),
  'not_found', 'Org A''s owner cannot read Org B''s mode (not_found, no scope leak)');                           -- 13
select is(
  (app.get_branch_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0000a00','00000000-0000-0000-0000-0001a0000a10', null) ->> 'error'),
  'not_found', 'a null branch id is a typed not_found, never an error leak');                                    -- 14
select is(
  (public.get_branch_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0000a00','00000000-0000-0000-0000-0001a0000a10','00000000-0000-0000-0000-0001a0000a1a') ->> 'kitchen_workflow_mode'),
  'printer_only', 'the public.get_branch_kitchen_workflow_mode wrapper works');                                  -- 15

set local app.current_app_user_id = '';   -- unauthenticated
select throws_ok(
  $$ select app.get_branch_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0000a00','00000000-0000-0000-0000-0001a0000a10','00000000-0000-0000-0000-0001a0000a1a') $$,
  '42501', NULL, 'an unauthenticated member read is rejected (42501)');                                          -- 16

-- ===== D. TOKEN-PROVEN device READ ===========================================
select is(
  (app.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0004001', 'tok-km1a-pos') ->> 'ok'),
  'true', 'a valid device token reads its own branch mode');                                                     -- 17
select is(
  (app.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0004001', 'tok-km1a-pos') ->> 'kitchen_workflow_mode'),
  'printer_only', 'the device read reflects the REAL persisted state');                                          -- 18
select is(
  (app.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0004001', 'wrong-token') ->> 'error'),
  'invalid_session', 'a wrong device token fails closed (typed invalid_session)');                               -- 19
select ok(
  not (app.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0004001', 'wrong-token') ? 'kitchen_workflow_mode'),
  'a failed device read carries NO kitchen_workflow_mode key — NEVER a silent fabricated ''kds''');              -- 20
select is(
  (app.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0004001', 'tok-km1a-revoked') ->> 'error'),
  'invalid_session', 'a REVOKED device session fails closed (invalid_session)');                                 -- 21
select is(
  (app.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0004b01', 'tok-km1a-pos') ->> 'error'),
  'invalid_session', 'a FORGED device id (Org B''s device + Org A''s token) fails closed');                      -- 22
select is(
  (app.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0004001', null) ->> 'error'),
  'invalid_session', 'a null token fails closed (invalid_session)');                                             -- 23
select is(
  (public.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0004001', 'tok-km1a-pos') ->> 'kitchen_workflow_mode'),
  'printer_only', 'the public.get_device_kitchen_workflow_mode wrapper works');                                  -- 24

-- ===== E. an UNRELATED branch setter cannot touch the mode ===================
set local app.current_app_user_id = '00000000-0000-0000-0000-0001a0000e01';  -- org_owner
select is(
  (app.set_branch_pos_shift_close_enabled('00000000-0000-0000-0000-0001a0000c01','00000000-0000-0000-0000-0001a0000a00','00000000-0000-0000-0000-0001a0000a10','00000000-0000-0000-0000-0001a0000a1a', false) ->> 'ok'),
  'true', 'the RF-113 shift-close setter (an explicit-column branch UPDATE) still runs');                        -- 25

reset role;
select is(
  (select kitchen_workflow_mode from branches where id = '00000000-0000-0000-0000-0001a0000a1a'),
  'printer_only', 'the unrelated setter did NOT touch kitchen_workflow_mode (explicit column lists)');           -- 26

-- ===== F. security posture ===================================================
select ok(
  (select p.prosecdef and p.proconfig::text like '%search_path%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'get_branch_kitchen_workflow_mode'),
  'app.get_branch_kitchen_workflow_mode is SECURITY DEFINER with a pinned search_path');                         -- 27
select ok(
  (select p.prosecdef and p.proconfig::text like '%search_path%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'get_device_kitchen_workflow_mode'),
  'app.get_device_kitchen_workflow_mode is SECURITY DEFINER with a pinned search_path');                         -- 28
select ok(
  not has_function_privilege('anon', 'public.get_branch_kitchen_workflow_mode(uuid,uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.get_device_kitchen_workflow_mode(uuid,text)', 'execute'),
  'anon cannot execute either public read wrapper');                                                             -- 29
select ok(
  has_function_privilege('authenticated', 'public.get_branch_kitchen_workflow_mode(uuid,uuid,uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.get_device_kitchen_workflow_mode(uuid,text)', 'execute')
  and has_function_privilege('authenticated', 'app.get_branch_kitchen_workflow_mode(uuid,uuid,uuid)', 'execute')
  and has_function_privilege('authenticated', 'app.get_device_kitchen_workflow_mode(uuid,text)', 'execute'),
  'authenticated can execute the read RPCs (app + public)');                                                     -- 30
select ok(
  not has_function_privilege('authenticated',
    'app.try_auto_complete_order(uuid,uuid,uuid,uuid,text,uuid,uuid,uuid,text,uuid,text)', 'execute'),
  'app.try_auto_complete_order stays INTERNAL (not executable by authenticated)');                               -- 31
select ok(
  (select c.relrowsecurity and c.relforcerowsecurity
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'branches'),
  'RLS on branches is still ENABLED and FORCED');                                                                -- 32

-- ===== G. device getter FULL liveness contract (review HIGH-2) ===============
-- Every failure mode below must yield the SAME typed invalid_session with NO
-- mode key — no distinction between expiry, suspension, revocation and forgery.
select is(
  (app.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0004001', 'tok-km1a-expired') ->> 'error'),
  'invalid_session', 'an EXPIRED device session (RF-118 expires_at) fails closed');                              -- 33
select is(
  (app.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0004001', 'tok-km1a-inactive') ->> 'error'),
  'invalid_session', 'an INACTIVE (never-revoked) device session fails closed');                                 -- 34
select is(
  (app.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0004001', 'tok-km1a-a2') ->> 'error'),
  'invalid_session', 'CROSS-DEVICE token reuse inside the SAME org fails closed');                               -- 35
select is(
  (app.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0004002', 'tok-km1a-a2') ->> 'kitchen_workflow_mode'),
  'kds', 'each device reads its OWN branch: the A2a device sees kds while A1a is printer_only');                 -- 36
select throws_ok(
  $$ insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref)
       values ('00000000-0000-0000-0000-0001a0004099', '00000000-0000-0000-0000-0001a0000a00',
               '00000000-0000-0000-0000-0001a0000a10', '00000000-0000-0000-0000-0001a0000a2a',
               '00000000-0000-0000-0000-0001a0004001', '00000000-0000-0000-0000-0001a0004011',
               app.hash_provisioning_secret('tok-km1a-forged')) $$,
  '23503', NULL,
  'a CROSS-BRANCH session row (A2a scope on the A1a device/pairing) is STRUCTURALLY impossible (composite FK)'); -- 37

update branches set status = 'suspended' where id = '00000000-0000-0000-0000-0001a0000a1a';
select is(
  (app.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0004001', 'tok-km1a-pos') ->> 'error'),
  'invalid_session', 'a SUSPENDED branch fails closed even for a perfectly valid token');                        -- 38
select ok(
  not (app.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0004001', 'tok-km1a-expired') ? 'kitchen_workflow_mode')
  and not (app.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0004001', 'tok-km1a-inactive') ? 'kitchen_workflow_mode')
  and not (app.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0004001', 'tok-km1a-pos') ? 'kitchen_workflow_mode'),
  'NO liveness failure ever carries a kitchen_workflow_mode key (no silent kds, no mode leak)');                 -- 39
update branches set status = 'active' where id = '00000000-0000-0000-0000-0001a0000a1a';

update restaurants set status = 'suspended' where id = '00000000-0000-0000-0000-0001a0000a10';
select is(
  (app.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0004001', 'tok-km1a-pos') ->> 'error'),
  'invalid_session', 'a SUSPENDED restaurant fails closed');                                                     -- 40
update restaurants set status = 'active' where id = '00000000-0000-0000-0000-0001a0000a10';

update organizations set status = 'suspended' where id = '00000000-0000-0000-0000-0001a0000a00';
select is(
  (app.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0004001', 'tok-km1a-pos') ->> 'error'),
  'invalid_session', 'a SUSPENDED organization fails closed');                                                   -- 41
update organizations set status = 'active' where id = '00000000-0000-0000-0000-0001a0000a00';

update devices set is_active = false where id = '00000000-0000-0000-0000-0001a0004001';
select is(
  (app.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0004001', 'tok-km1a-pos') ->> 'error'),
  'invalid_session', 'an INACTIVE device fails closed');                                                         -- 42
update devices set is_active = true where id = '00000000-0000-0000-0000-0001a0004001';

update device_pairings set status = 'revoked' where id = '00000000-0000-0000-0000-0001a0004011';
select is(
  (app.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0004001', 'tok-km1a-pos') ->> 'error'),
  'invalid_session', 'a REVOKED pairing fails closed');                                                          -- 43
update device_pairings set status = 'active' where id = '00000000-0000-0000-0000-0001a0004011';

select is(
  (app.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001a0004001', 'tok-km1a-pos') ->> 'kitchen_workflow_mode'),
  'printer_only', 'with EVERY liveness dimension restored, the valid token reads the real mode again');          -- 44

-- ===== H. broadened no-activation-path (review MEDIUM-1) =====================
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('app', 'public')
      and p.prosrc ~* 'update\s+(public\.)?branches\y'
      and p.prosrc ilike '%kitchen_workflow_mode%'),
  0, 'NO function in app/public that UPDATEs branches touches kitchen_workflow_mode (all current and future branch/settings setters inspected by source)'); -- 45

select * from finish();
rollback;
