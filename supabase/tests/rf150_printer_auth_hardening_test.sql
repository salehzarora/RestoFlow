-- ============================================================================
-- RF-150 (review fix) — pgTAP: printer-config authorization hardening.
-- Covers Codex's two blockers + the requested regressions:
--   (BLOCKER 1) a branch-scoped manager cannot soft-delete a sibling-branch printer,
--               but CAN delete a printer in their own branch (authorize against the
--               target's ACTUAL scope).
--   (BLOCKER 2) the public printer wrappers authorize a REAL JWT principal with NO
--               app.current_organization_id GUC (GUC-free actor_rank_in_scope).
--   + public soft-delete wrapper behavior, wrapper introspection, branch-scoped SELECT
--     isolation, soft-deleted route behavior, and platform-admin non-member denial.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(18);

-- ===== fixture: org A with two branches, a BRANCH-scoped manager, an org owner, a ===
-- ===== JWT-linked owner, and a platform admin with NO tenant membership ===========
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000f00aa01', 'rf150h-jwt-owner@example.test');
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf150h-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1'),
  ('00000000-0000-0000-0000-00000000a2b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A2');
insert into stations (id, organization_id, restaurant_id, branch_id, name) values
  ('00000000-0000-0000-0000-00000000a1c1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'Grill A1');
insert into app_users (id, email, auth_user_id) values
  ('00000000-0000-0000-0000-0000015fe001', 'rf150h-owner@example.test',    null),
  ('00000000-0000-0000-0000-0000015fe002', 'rf150h-mgr-a1@example.test',   null),
  ('00000000-0000-0000-0000-0000015fe0aa', 'rf150h-jwt-owner@example.test','00000000-0000-0000-0000-00000f00aa01'),
  ('00000000-0000-0000-0000-0000015fe0fa', 'rf150h-platadmin@example.test',null);
insert into memberships (app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000015fe001', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000015fe002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'manager'),
  ('00000000-0000-0000-0000-0000015fe0aa', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner');
-- platform admin grant, deliberately with NO tenant membership (D-026).
insert into platform_admin_grants (app_user_id, granted_by) values
  ('00000000-0000-0000-0000-0000015fe0fa', '00000000-0000-0000-0000-0000015fe0fa');
-- two printers: one per branch; a route in branch A1.
insert into printer_devices (id, organization_id, restaurant_id, branch_id, display_name, connection_type, role) values
  ('00000000-0000-0000-0000-0000150f0d01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'Kitchen A1', 'network', 'kitchen'),
  ('00000000-0000-0000-0000-0000150f0d02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a2b1', 'Kitchen A2', 'usb', 'kitchen');
insert into printer_routes (organization_id, restaurant_id, branch_id, station_id, printer_device_id) values
  ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000a1c1', '00000000-0000-0000-0000-0000150f0d01');

-- ===== (1-8) public-wrapper introspection (still INVOKER / VOLATILE / authenticated-only)
select has_function('public', 'upsert_printer_device',
  array['uuid','uuid','uuid','uuid','text','text','text','text','jsonb','boolean'], 'public.upsert_printer_device exists');
select has_function('public', 'set_printer_route',
  array['uuid','uuid','uuid','uuid','uuid','boolean'], 'public.set_printer_route exists');
select has_function('public', 'soft_delete_printer_device',
  array['uuid','uuid','uuid','uuid'], 'public.soft_delete_printer_device exists');
select is((select prosecdef from pg_proc where proname='soft_delete_printer_device' and pronamespace='public'::regnamespace),
          false, 'public.soft_delete_printer_device is SECURITY INVOKER');
select is((select provolatile from pg_proc where proname='soft_delete_printer_device' and pronamespace='public'::regnamespace),
          'v', 'public.soft_delete_printer_device is VOLATILE (PostgREST POST)');
select ok((select exists(
     select 1 from pg_proc p cross join lateral unnest(coalesce(p.proconfig,'{}'::text[])) as cfg
     where p.proname='soft_delete_printer_device' and p.pronamespace='public'::regnamespace and cfg like 'search_path=%')),
  'public.soft_delete_printer_device has a locked search_path');
select ok(has_function_privilege('authenticated','public.soft_delete_printer_device(uuid, uuid, uuid, uuid)','execute'),
  'authenticated MAY execute public.soft_delete_printer_device');
select ok(not has_function_privilege('anon','public.soft_delete_printer_device(uuid, uuid, uuid, uuid)','execute'),
  'anon may NOT execute public.soft_delete_printer_device');

-- ===== (9-10) branch-scoped SELECT isolation: a branch-A1 manager sees ONLY ========
-- ===== branch A1 printers, never the sibling branch A2 printer (RLS) ===============
set local role authenticated;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{}';
set local app.current_app_user_id = '00000000-0000-0000-0000-0000015fe002';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from printer_devices)::int, 1, 'branch-A1 manager sees exactly its branch A1 printer');
select is((select count(*) from printer_devices where branch_id='00000000-0000-0000-0000-00000000a2b1')::int, 0,
          'branch-A1 manager cannot read the sibling branch A2 printer (branch-scoped RLS)');
reset role;

-- ===== (11-12) BLOCKER 2: a REAL JWT principal configures + deletes a printer with =
-- ===== NO app.current_organization_id GUC (GUC-free authorization) =================
set local role authenticated;
set local app.current_app_user_id = '';
set local app.current_organization_id = '';
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000f00aa01';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000f00aa01","email":"rf150h-jwt-owner@example.test","aal":"aal2"}';
create temp table h_jwt as select public.upsert_printer_device(
  '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1',
  '00000000-0000-0000-0000-0000150f0d0a','JWT Printer','network','receipt') as res;
create temp table h_jwt_del as select public.soft_delete_printer_device(
  '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1',
  '00000000-0000-0000-0000-0000150f0d0a') as res;
reset role;
select is((select (res->>'ok')::boolean from h_jwt), true,
          'a real JWT owner configures a printer via the public wrapper WITHOUT an org GUC (BLOCKER 2)');
select is((select (res->>'ok')::boolean from h_jwt_del), true,
          'the public soft-delete wrapper works for the JWT owner without an org GUC');

-- ===== (13) BLOCKER 1: a branch-A1 manager CANNOT soft-delete the branch A2 printer =
-- ===== even when passing branch A1 as the (advisory) scope ========================
set local role authenticated;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{}';
set local app.current_app_user_id = '00000000-0000-0000-0000-0000015fe002';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select throws_ok(
  $$ select app.soft_delete_printer_device(
       '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1',
       '00000000-0000-0000-0000-0000150f0d02') $$,
  '42501', NULL, 'a branch-A1 manager cannot delete the branch A2 printer (authz against the target''s actual scope)');
reset role;
select ok((select deleted_at is null from printer_devices where id='00000000-0000-0000-0000-0000150f0d02'),
          'the branch A2 printer was NOT deleted by the branch-A1 manager');

-- ===== (15-16) BLOCKER 1: the branch-A1 manager CAN delete a printer in its OWN ====
-- ===== branch; the printer + its live route are tombstoned ========================
set local role authenticated;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{}';
set local app.current_app_user_id = '00000000-0000-0000-0000-0000015fe002';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
create temp table h_owndel as select app.soft_delete_printer_device(
  '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1',
  '00000000-0000-0000-0000-0000150f0d01') as res;
reset role;
select is((select (res->>'ok')::boolean and res->>'action'='deleted' from h_owndel), true,
          'a branch-A1 manager CAN delete a printer in its own branch A1');
select is((select count(*) from printer_routes
            where printer_device_id='00000000-0000-0000-0000-0000150f0d01' and deleted_at is not null)::int, 1,
          'the deleted printer''s live route was soft-deleted (cascade after authorization)');

-- ===== (17) platform-admin with NO tenant membership is denied (D-026) =============
set local role authenticated;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{}';
set local app.current_app_user_id = '00000000-0000-0000-0000-0000015fe0fa';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select throws_ok(
  $$ select app.upsert_printer_device(
       '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1',
       null,'PA Printer','network','kitchen') $$,
  '42501', NULL, 'a platform_admin grant confers NO tenant write authority over printers (D-026)');
reset role;

-- ===== (18) soft-deleted routes do not block new routing: the owner re-routes the ==
-- ===== same station to a NEW printer after the old printer + route were deleted ====
set local role authenticated;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{}';
set local app.current_app_user_id = '00000000-0000-0000-0000-0000015fe001';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select public.upsert_printer_device(
  '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1',
  '00000000-0000-0000-0000-0000150f0d0e','Kitchen A1 v2','network','kitchen');
create temp table h_reroute as select public.set_printer_route(
  '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1',
  '00000000-0000-0000-0000-00000000a1c1','00000000-0000-0000-0000-0000150f0d0e') as res;
reset role;
select is((select (res->>'ok')::boolean from h_reroute), true,
          'station A1 re-routes to a new printer after the old printer + route were soft-deleted');

select * from finish();
rollback;
