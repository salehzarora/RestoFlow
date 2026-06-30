-- ============================================================================
-- RF-150 — pgTAP: printer_devices / printer_routes schema, constraints, RLS, and
-- cross-tenant isolation (PRINTERS_AND_HARDWARE_SPEC; RISK R-003, D-012).
-- ============================================================================
-- The config tables exist, carry NO money columns, are RLS enabled+forced with
-- policies, reject invalid enum values, structurally forbid cross-branch routing,
-- isolate one org's printers/routes from another's, and refuse all direct client
-- writes (writes are the owner/manager RPCs only).
-- Fixtures inserted as the BYPASSRLS connection role; isolation reads run as
-- `authenticated` with a tenant context GUC (the RF-019/RF-059 test pattern).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(19);

-- ===== fixture: org A (2 branches+stations) and org B (1), one org_owner each ====
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf150s-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf150s-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1'),
  ('00000000-0000-0000-0000-00000000a2b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A2'),
  ('00000000-0000-0000-0000-00000000b1b1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1');
insert into stations (id, organization_id, restaurant_id, branch_id, name) values
  ('00000000-0000-0000-0000-00000000a1c1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'Grill A1'),
  ('00000000-0000-0000-0000-00000000a2c1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a2b1', 'Grill A2'),
  ('00000000-0000-0000-0000-00000000b1c1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1b1', 'Grill B1');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000150aee0a', 'rf150s-owner-a@example.test'),
  ('00000000-0000-0000-0000-0000150bee0b', 'rf150s-owner-b@example.test');
insert into memberships (app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-0000150aee0a', '00000000-0000-0000-0000-0000000000a0', 'org_owner'),
  ('00000000-0000-0000-0000-0000150bee0b', '00000000-0000-0000-0000-0000000000b0', 'org_owner');

-- printers + routes (as the BYPASSRLS connection role): one kitchen printer + route per org.
insert into printer_devices (id, organization_id, restaurant_id, branch_id, display_name, connection_type, role) values
  ('00000000-0000-0000-0000-0000150a0d01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'Kitchen A1', 'network', 'kitchen'),
  ('00000000-0000-0000-0000-0000150a0d02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a2b1', 'Kitchen A2', 'usb', 'kitchen'),
  ('00000000-0000-0000-0000-0000150b0d01', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1b1', 'Kitchen B1', 'bluetooth', 'kitchen');
insert into printer_routes (organization_id, restaurant_id, branch_id, station_id, printer_device_id) values
  ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000a1c1', '00000000-0000-0000-0000-0000150a0d01'),
  ('00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1b1', '00000000-0000-0000-0000-00000000b1c1', '00000000-0000-0000-0000-0000150b0d01');

-- ===== (1-2) tables exist =====================================================
select has_table('public', 'printer_devices', 'printer_devices table exists');
select has_table('public', 'printer_routes',  'printer_routes table exists');

-- ===== (3-4) NO money columns (printer config is money-free; D-007/T-003) ======
select is((select count(*) from information_schema.columns
           where table_schema='public' and table_name='printer_devices' and column_name ~ '(^|_)minor($|_)')::int,
          0, 'printer_devices has no money (_minor) column');
select is((select count(*) from information_schema.columns
           where table_schema='public' and table_name='printer_routes' and column_name ~ '(^|_)minor($|_)')::int,
          0, 'printer_routes has no money (_minor) column');

-- ===== (5-8) RLS enabled + forced + has a policy (RF-019 baseline) =============
select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid='public.printer_devices'::regclass),
          'printer_devices: RLS enabled AND forced');
select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid='public.printer_routes'::regclass),
          'printer_routes: RLS enabled AND forced');
select ok((select count(*) from pg_policy where polrelid='public.printer_devices'::regclass) >= 1,
          'printer_devices has >=1 policy');
select ok((select count(*) from pg_policy where polrelid='public.printer_routes'::regclass) >= 1,
          'printer_routes has >=1 policy');

-- ===== (9-11) enum CHECK constraints reject invalid values ====================
select throws_ok(
  $$ insert into printer_devices (organization_id, restaurant_id, branch_id, display_name, connection_type, role)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','Bad','carrier_pigeon','kitchen') $$,
  '23514', NULL, 'connection_type CHECK rejects an unknown transport');
select throws_ok(
  $$ insert into printer_devices (organization_id, restaurant_id, branch_id, display_name, connection_type, role)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','Bad','network','billboard') $$,
  '23514', NULL, 'role CHECK rejects an unknown role');
select throws_ok(
  $$ insert into printer_devices (organization_id, restaurant_id, branch_id, display_name, connection_type, role, paper_width)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','Bad','network','kitchen','111mm') $$,
  '23514', NULL, 'paper_width CHECK rejects an unsupported width');

-- ===== (12) cross-branch routing is STRUCTURALLY impossible (composite FK) =====
-- a route in branch A1 pointing at the printer in branch A2 violates the
-- (org, restaurant, branch, printer_device_id) -> printer_devices FK.
select throws_ok(
  $$ insert into printer_routes (organization_id, restaurant_id, branch_id, station_id, printer_device_id)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1',
             '00000000-0000-0000-0000-00000000a1c1','00000000-0000-0000-0000-0000150a0d02') $$,
  '23503', NULL, 'a route cannot reference a printer in a DIFFERENT branch (composite FK; no cross-branch routing)');

-- ===== (13-16) cross-tenant isolation: Org A principal sees only Org A =========
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000150aee0a';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from printer_devices)::int, 2, 'Org A owner sees its 2 printers');
select is((select count(*) from printer_devices where organization_id='00000000-0000-0000-0000-0000000000b0')::int, 0,
          'Org A owner cannot read the Org B printer');
select is((select count(*) from printer_routes)::int, 1, 'Org A owner sees its 1 route');
select is((select count(*) from printer_routes where organization_id='00000000-0000-0000-0000-0000000000b0')::int, 0,
          'Org A owner cannot read the Org B route');

-- ===== (17-19) direct client writes are DENIED (writes are RPC-only) ===========
select throws_ok(
  $$ insert into printer_devices (organization_id, restaurant_id, branch_id, display_name, connection_type, role)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','Rogue','network','kitchen') $$,
  '42501', NULL, 'authenticated cannot directly INSERT a printer_device (no grant; RPC-only)');
select throws_ok(
  $$ update printer_devices set display_name='hijack' where id='00000000-0000-0000-0000-0000150a0d01' $$,
  '42501', NULL, 'authenticated cannot directly UPDATE a printer_device');
select throws_ok(
  $$ delete from printer_routes where organization_id='00000000-0000-0000-0000-0000000000a0' $$,
  '42501', NULL, 'authenticated cannot directly DELETE a printer_route');

reset role;
select * from finish();
rollback;
