-- ============================================================================
-- MVP — pgTAP: app.list_printers (GUC-free printer-config LIST). Owner listing
-- (printers + routes + live stations), branch narrowing, rank denial, cross-org
-- structural denial (RISK R-003), tombstone + dead-branch filtering (D-020),
-- empty-scope shape, and public-wrapper introspection. GUC-FREE (identity GUC
-- only), mirroring rf160_list_devices_test.sql.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(22);

-- ===== fixture: Org A (Rest A1: branches A1a, A1b, dead A1x; Rest A2: A2a) =====
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-000011500a00', 'Org A', 'mvplp-a', 'USD'),
  ('00000000-0000-0000-0000-000011500b00', 'Org B', 'mvplp-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-000011500a10', '00000000-0000-0000-0000-000011500a00', 'Rest A1'),
  ('00000000-0000-0000-0000-000011500a20', '00000000-0000-0000-0000-000011500a00', 'Rest A2'),
  ('00000000-0000-0000-0000-000011500b10', '00000000-0000-0000-0000-000011500b00', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name, deleted_at) values
  ('00000000-0000-0000-0000-000011500a1a', '00000000-0000-0000-0000-000011500a00', '00000000-0000-0000-0000-000011500a10', 'Branch A1a', null),
  ('00000000-0000-0000-0000-000011500a1b', '00000000-0000-0000-0000-000011500a00', '00000000-0000-0000-0000-000011500a10', 'Branch A1b', null),
  ('00000000-0000-0000-0000-000011500a1e', '00000000-0000-0000-0000-000011500a00', '00000000-0000-0000-0000-000011500a10', 'Branch A1x (dead)', now()),
  ('00000000-0000-0000-0000-000011500a2a', '00000000-0000-0000-0000-000011500a00', '00000000-0000-0000-0000-000011500a20', 'Branch A2a', null),
  ('00000000-0000-0000-0000-000011500b1a', '00000000-0000-0000-0000-000011500b00', '00000000-0000-0000-0000-000011500b10', 'Branch B1a', null);
-- stations: S1/S2 live @ A1a; S3 inactive @ A1a; S4 on the dead branch A1x.
insert into stations (id, organization_id, restaurant_id, branch_id, name, is_active) values
  ('00000000-0000-0000-0000-000011501001', '00000000-0000-0000-0000-000011500a00', '00000000-0000-0000-0000-000011500a10', '00000000-0000-0000-0000-000011500a1a', 'Grill', true),
  ('00000000-0000-0000-0000-000011501002', '00000000-0000-0000-0000-000011500a00', '00000000-0000-0000-0000-000011500a10', '00000000-0000-0000-0000-000011500a1a', 'Fry',   true),
  ('00000000-0000-0000-0000-000011501003', '00000000-0000-0000-0000-000011500a00', '00000000-0000-0000-0000-000011500a10', '00000000-0000-0000-0000-000011500a1a', 'Legacy', false),
  ('00000000-0000-0000-0000-000011501004', '00000000-0000-0000-0000-000011500a00', '00000000-0000-0000-0000-000011500a10', '00000000-0000-0000-0000-000011500a1e', 'Ghost', true);
-- printers: P1 live @ A1a; P2 live @ A1b; P3 tombstoned @ A1a; P4 on the dead
-- branch A1x; P5 in Org B.
insert into printer_devices (id, organization_id, restaurant_id, branch_id, display_name, connection_type, role, deleted_at) values
  ('00000000-0000-0000-0000-000011502001', '00000000-0000-0000-0000-000011500a00', '00000000-0000-0000-0000-000011500a10', '00000000-0000-0000-0000-000011500a1a', 'Alpha Printer', 'network', 'kitchen', null),
  ('00000000-0000-0000-0000-000011502002', '00000000-0000-0000-0000-000011500a00', '00000000-0000-0000-0000-000011500a10', '00000000-0000-0000-0000-000011500a1b', 'Bravo Printer', 'usb',     'receipt', null),
  ('00000000-0000-0000-0000-000011502003', '00000000-0000-0000-0000-000011500a00', '00000000-0000-0000-0000-000011500a10', '00000000-0000-0000-0000-000011500a1a', 'Dead Printer',  'network', 'receipt', now()),
  ('00000000-0000-0000-0000-000011502004', '00000000-0000-0000-0000-000011500a00', '00000000-0000-0000-0000-000011500a10', '00000000-0000-0000-0000-000011500a1e', 'Ghost Printer', 'network', 'kitchen', null),
  ('00000000-0000-0000-0000-000011502005', '00000000-0000-0000-0000-000011500b00', '00000000-0000-0000-0000-000011500b10', '00000000-0000-0000-0000-000011500b1a', 'OrgB Printer',  'network', 'receipt', null);
-- routes: R1 live (Grill -> Alpha); R2 tombstoned (Fry -> Alpha).
insert into printer_routes (id, organization_id, restaurant_id, branch_id, station_id, printer_device_id, deleted_at) values
  ('00000000-0000-0000-0000-000011503001', '00000000-0000-0000-0000-000011500a00', '00000000-0000-0000-0000-000011500a10', '00000000-0000-0000-0000-000011500a1a', '00000000-0000-0000-0000-000011501001', '00000000-0000-0000-0000-000011502001', null),
  ('00000000-0000-0000-0000-000011503002', '00000000-0000-0000-0000-000011500a00', '00000000-0000-0000-0000-000011500a10', '00000000-0000-0000-0000-000011500a1a', '00000000-0000-0000-0000-000011501002', '00000000-0000-0000-0000-000011502001', now());
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-000011500e01', 'mvplp-owner@example.test'),
  ('00000000-0000-0000-0000-000011500e02', 'mvplp-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-000011500f01', '00000000-0000-0000-0000-000011500e01', '00000000-0000-0000-0000-000011500a00', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-000011500f02', '00000000-0000-0000-0000-000011500e02', '00000000-0000-0000-0000-000011500a00', '00000000-0000-0000-0000-000011500a10', '00000000-0000-0000-0000-000011500a1a', 'cashier');

-- ===== (1-7) org_owner lists org-wide: printers + routes + live stations =======
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-000011500e01';
create temp table t_all as select app.list_printers('00000000-0000-0000-0000-000011500a00', null, null) as res;
reset role;
select is((select (res->>'ok')::boolean from t_all), true, 'org_owner lists printers org-wide (ok:true)');
select is((select jsonb_array_length(res->'printers') from t_all), 2,
          'org-wide printers = 2 (tombstoned, dead-branch and Org B printers excluded)');
select is((select res->'printers'->0->>'display_name' from t_all), 'Alpha Printer',
          'printers are ordered by display_name');
select is((select jsonb_array_length(res->'routes') from t_all), 1,
          'org-wide routes = 1 (the tombstoned route is excluded)');
select is((select res->'routes'->0->>'station_id' from t_all), '00000000-0000-0000-0000-000011501001',
          'the returned route carries its station_id (Grill -> Alpha)');
select is((select jsonb_array_length(res->'stations') from t_all), 2,
          'org-wide stations = 2 live only (inactive + dead-branch stations excluded)');
select is((select res->'stations'->0->>'name' from t_all), 'Fry',
          'stations are ordered by name');

-- ===== (8-9) branch filter narrows =============================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-000011500e01';
create temp table t_branch as select app.list_printers(
  '00000000-0000-0000-0000-000011500a00', '00000000-0000-0000-0000-000011500a10', '00000000-0000-0000-0000-000011500a1a') as res;
reset role;
select is((select jsonb_array_length(res->'printers') from t_branch), 1,
          'branch filter narrows to the 1 Branch A1a printer');
select is((select res->'printers'->0->>'id' from t_branch), '00000000-0000-0000-0000-000011502001',
          'the branch-filtered printer is Alpha (A1a)');

-- ===== (10-12) tombstone / dead-branch rows never resurface (D-020) ============
select is((select count(*) from t_all, jsonb_array_elements(res->'printers') e
            where e->>'id'='00000000-0000-0000-0000-000011502003')::int, 0,
          'a soft-deleted printer is NOT returned');
select is((select count(*) from t_all, jsonb_array_elements(res->'printers') e
            where e->>'id'='00000000-0000-0000-0000-000011502004')::int, 0,
          'a printer on a soft-deleted branch is NOT returned');
select is((select count(*) from t_all, jsonb_array_elements(res->'routes') e
            where e->>'id'='00000000-0000-0000-0000-000011503002')::int, 0,
          'a soft-deleted route is NOT returned');

-- ===== (13) rank denial: in-scope cashier -> permission_denied =================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-000011500e02';
create temp table t_cashier as select app.list_printers(
  '00000000-0000-0000-0000-000011500a00', '00000000-0000-0000-0000-000011500a10', '00000000-0000-0000-0000-000011500a1a') as res;
reset role;
select is((select res->>'error' from t_cashier), 'permission_denied', 'cashier cannot list printers (permission_denied)');

-- ===== (14) cross-org caller is structurally rejected (42501) ==================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-000011500e01';  -- Org A owner
select throws_ok(
  $$ select app.list_printers('00000000-0000-0000-0000-000011500b00', null, null) $$,
  '42501', NULL, 'an Org A owner cannot list Org B printers (cross-org 42501)');
reset role;

-- ===== (15-16) empty scope returns ok with empty arrays ========================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-000011500e01';
create temp table t_empty as select app.list_printers(
  '00000000-0000-0000-0000-000011500a00', '00000000-0000-0000-0000-000011500a20', '00000000-0000-0000-0000-000011500a2a') as res;
reset role;
select is((select (res->>'ok')::boolean from t_empty), true, 'an empty scope still returns ok:true');
select ok((select jsonb_array_length(res->'printers') = 0
             and jsonb_array_length(res->'routes')   = 0
             and jsonb_array_length(res->'stations') = 0 from t_empty),
          'an empty scope returns empty printers/routes/stations arrays');

-- ===== (17) public.* wrapper delegates verbatim ================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-000011500e01';
select is(
  public.list_printers('00000000-0000-0000-0000-000011500a00', null, null),
  app.list_printers('00000000-0000-0000-0000-000011500a00', null, null),
  'public.list_printers delegates verbatim to app.list_printers');
reset role;

-- ===== (18-22) wrapper introspection: invoker / search_path / grants ===========
select is(
  (select prosecdef from pg_proc where proname='list_printers' and pronamespace='public'::regnamespace and pronargs=3),
  false, 'public.list_printers is SECURITY INVOKER (not definer)');
select ok(
  (select exists(
     select 1 from pg_proc p
     cross join lateral unnest(coalesce(p.proconfig, '{}'::text[])) as cfg
     where p.proname='list_printers' and p.pronamespace='public'::regnamespace and p.pronargs=3
       and cfg like 'search_path=%')),
  'public.list_printers has a locked search_path');
select ok(
  not has_function_privilege('public', 'public.list_printers(uuid, uuid, uuid)', 'execute'),
  'PUBLIC may NOT execute public.list_printers (revoked)');
select ok(
  not has_function_privilege('anon', 'public.list_printers(uuid, uuid, uuid)', 'execute'),
  'anon may NOT execute public.list_printers');
select ok(
  has_function_privilege('authenticated', 'public.list_printers(uuid, uuid, uuid)', 'execute'),
  'authenticated MAY execute public.list_printers');

select * from finish();
rollback;
