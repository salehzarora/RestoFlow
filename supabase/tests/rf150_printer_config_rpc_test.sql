-- ============================================================================
-- RF-150 — pgTAP: printer-config management RPCs — owner/manager authorization,
-- role denial + audit, cross-org structural denial, soft delete, idempotent
-- routing, immutable scope, and public-wrapper delegation (D-011/D-013/D-028).
-- ============================================================================
-- Write roles are org_owner/restaurant_owner/manager ONLY; cashier/kitchen_staff/
-- accountant are role-denied (committed *_denied audit + {ok:false}); a cross-org
-- caller is structurally rejected (42501); soft delete tombstones the printer AND
-- its live routes; the public.* wrapper delegates verbatim. Principals are set via
-- the GUC test path (set local role authenticated + app.current_app_user_id +
-- app.current_organization_id), the established RF-109/RF-112 pattern.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(20);

-- ===== fixture: org A (2 branches + stations), org B; one member per role ======
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf150r-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf150r-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1'),
  ('00000000-0000-0000-0000-00000000a2b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A2'),
  ('00000000-0000-0000-0000-00000000b1b1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1');
insert into stations (id, organization_id, restaurant_id, branch_id, name) values
  ('00000000-0000-0000-0000-00000000a1c1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'Grill A1');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000015e001', 'rf150r-owner@example.test'),
  ('00000000-0000-0000-0000-00000015e002', 'rf150r-manager@example.test'),
  ('00000000-0000-0000-0000-00000015e003', 'rf150r-cashier@example.test'),
  ('00000000-0000-0000-0000-00000015e004', 'rf150r-kitchen@example.test'),
  ('00000000-0000-0000-0000-00000015e005', 'rf150r-accountant@example.test');
insert into memberships (app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-00000015e001', '00000000-0000-0000-0000-0000000000a0', 'org_owner'),
  ('00000000-0000-0000-0000-00000015e002', '00000000-0000-0000-0000-0000000000a0', 'manager'),
  ('00000000-0000-0000-0000-00000015e003', '00000000-0000-0000-0000-0000000000a0', 'cashier'),
  ('00000000-0000-0000-0000-00000015e004', '00000000-0000-0000-0000-0000000000a0', 'kitchen_staff'),
  ('00000000-0000-0000-0000-00000015e005', '00000000-0000-0000-0000-0000000000a0', 'accountant');

-- ===== (1-4) org_owner CREATES a printer ======================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000015e001';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
create temp table t_create as select app.upsert_printer_device(
  '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1',
  '00000000-0000-0000-0000-0000150a0d01','Kitchen 1','network','kitchen','80mm','{"host":"10.0.0.50","port":9100}'::jsonb,true) as res;
reset role;
select is((select (res->>'ok')::boolean from t_create), true, 'org_owner upsert_printer_device returns ok=true');
select is((select res->>'action' from t_create), 'created', 'org_owner upsert is a create');
select is((select connection_type||'/'||role from printer_devices where id='00000000-0000-0000-0000-0000150a0d01'),
          'network/kitchen', 'printer persisted with the given transport + role');
select is((select count(*) from audit_events where action='printer.printer_device.created'
            and organization_id='00000000-0000-0000-0000-0000000000a0' and actor_app_user_id='00000000-0000-0000-0000-00000015e001')::int,
          1, 'create wrote a printer.printer_device.created audit (D-013)');

-- ===== (5-6) manager SETS a station -> printer route ==========================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000015e002';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
create temp table t_route as select app.set_printer_route(
  '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1',
  '00000000-0000-0000-0000-00000000a1c1','00000000-0000-0000-0000-0000150a0d01',true) as res;
reset role;
select is((select (res->>'ok')::boolean from t_route), true, 'manager set_printer_route returns ok=true');
select is((select count(*) from printer_routes
            where station_id='00000000-0000-0000-0000-00000000a1c1' and printer_device_id='00000000-0000-0000-0000-0000150a0d01'
              and deleted_at is null)::int, 1, 'the station -> printer route exists');

-- ===== (7-9) cashier is ROLE-DENIED (committed _denied audit, no write) ========
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000015e003';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
create temp table t_cashier as select app.upsert_printer_device(
  '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1',
  '00000000-0000-0000-0000-0000150a0d09','Sneaky','network','kitchen') as res;
reset role;
select is((select res->>'error' from t_cashier), 'permission_denied', 'cashier upsert is permission_denied (not a write role)');
select is((select count(*) from audit_events where action='printer.printer_device.upsert_denied'
            and actor_app_user_id='00000000-0000-0000-0000-00000015e003')::int, 1, 'cashier denial wrote a committed upsert_denied audit');
select is((select count(*) from printer_devices where id='00000000-0000-0000-0000-0000150a0d09')::int, 0,
          'cashier denial created NO printer');

-- ===== (10-11) kitchen_staff + accountant are also denied ======================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000015e004';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
create temp table t_kitchen as select app.set_printer_route(
  '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1',
  '00000000-0000-0000-0000-00000000a1c1','00000000-0000-0000-0000-0000150a0d01') as res;
reset role;
select is((select res->>'error' from t_kitchen), 'permission_denied', 'kitchen_staff set_printer_route is permission_denied');

set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000015e005';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
create temp table t_acct as select app.upsert_printer_device(
  '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1',
  '00000000-0000-0000-0000-0000150a0d08','Acct','usb','receipt') as res;
reset role;
select is((select res->>'error' from t_acct), 'permission_denied', 'accountant upsert is permission_denied (read-only, D-028)');

-- ===== (12) cross-org caller is STRUCTURALLY rejected (42501) ==================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000015e001';  -- org A owner
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select throws_ok(
  $$ select app.upsert_printer_device(
       '00000000-0000-0000-0000-0000000000b0','00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-00000000b1b1',
       null,'Cross','network','kitchen') $$,
  '42501', NULL, 'an Org A owner cannot configure an Org B printer (cross-org 42501)');
reset role;

-- ===== (13-14) org_owner UPDATES the printer (revision bumps) ==================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000015e001';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
create temp table t_update as select app.upsert_printer_device(
  '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1',
  '00000000-0000-0000-0000-0000150a0d01','Kitchen 1 (renamed)','usb','kitchen','58mm','{}'::jsonb,false) as res;
reset role;
select is((select res->>'action' from t_update), 'updated', 'upsert with an existing id is an update');
select is((select revision from printer_devices where id='00000000-0000-0000-0000-0000150a0d01')::int, 2,
          'update bumped revision 1 -> 2');

-- ===== (15) org/restaurant/branch are immutable on update =====================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000015e001';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select throws_ok(
  $$ select app.upsert_printer_device(
       '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a2b1',
       '00000000-0000-0000-0000-0000150a0d01','Move','network','kitchen') $$,
  '42501', NULL, 'cannot move a printer to another branch on update (scope immutable)');
reset role;

-- ===== (16-18) org_owner SOFT-DELETES the printer + its live routes ============
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000015e001';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
create temp table t_delete as select app.soft_delete_printer_device(
  '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1',
  '00000000-0000-0000-0000-0000150a0d01') as res;
reset role;
select is((select (res->>'ok')::boolean and res->>'action'='deleted' from t_delete), true, 'soft_delete returns ok + action=deleted');
select ok((select deleted_at is not null from printer_devices where id='00000000-0000-0000-0000-0000150a0d01'),
          'the printer is tombstoned (deleted_at set)');
select is((select count(*) from printer_routes
            where printer_device_id='00000000-0000-0000-0000-0000150a0d01' and deleted_at is not null)::int, 1,
          'the printer''s live route was soft-deleted too (a removed printer is not left routed)');

-- ===== (19) public.* wrapper delegates verbatim ================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000015e001';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
create temp table t_wrap as select public.upsert_printer_device(
  '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1',
  '00000000-0000-0000-0000-0000150a0d20','Via Wrapper','network','receipt') as res;
reset role;
select is((select (res->>'ok')::boolean from t_wrap), true, 'public.upsert_printer_device wrapper delegates (ok=true)');

-- ===== (20) an unauthenticated caller is rejected (no principal) ===============
set local role authenticated;
set local app.current_app_user_id = '';
set local app.current_organization_id = '';
select throws_ok(
  $$ select app.upsert_printer_device(
       '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1',
       null,'NoAuth','network','kitchen') $$,
  '42501', NULL, 'an unauthenticated caller (no principal) is rejected with 42501');
reset role;

select * from finish();
rollback;
