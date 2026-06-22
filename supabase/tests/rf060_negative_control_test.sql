-- ============================================================================
-- RF-060 — CANONICAL gate: safety invariants + documented NEGATIVE CONTROL
-- ============================================================================
-- Append-only audit (tenant audit_events UPDATE/DELETE/TRUNCATE blocked); sync_operations
-- has NO direct authenticated read (RF-059 A4) and current-device operation statuses are
-- exposed only via sync_pull (no raw payload); and a DOCUMENTED negative control that
-- proves the suite's policy-coverage detector goes RED on a deliberately broken/unguarded
-- tenant table — created inside the transaction and rolled back (no schema left behind).
-- Fixtures as the BYPASSRLS connection role; the direct sync_operations read runs under
-- `set local role authenticated`.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(9);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf060neg-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('00000000-0000-0000-0000-00000000da12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');  -- a SECOND device (other-device scoping)
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active'),
  ('00000000-0000-0000-0000-00000000fa12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da12', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11'),
  ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da12', '00000000-0000-0000-0000-00000000fa12');
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee01', 'rf060neg-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c502', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');
-- push an op on device da11 (op-a) so sync_operations + audit_events have real rows
select app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
  '[{"local_operation_id":"op-a","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","order_type":"dine_in","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb);
-- push a DIFFERENT op on the SECOND device da12 (op-b) — must NOT be visible to device da11
select app.sync_push('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000da12',
  '[{"local_operation_id":"op-b","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d2","order_type":"dine_in","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb);

-- ===== sync_operations: no direct read; status only via sync_pull ============ 1-3
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee01';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select throws_ok($$ select count(*) from sync_operations $$, '42501', NULL,
  'sync_operations has NO direct authenticated SELECT (RF-059 A4)');
reset role;
select ok(
  (select bool_or(e->>'local_operation_id' = 'op-a')
   from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,500) -> 'operation_statuses' -> 'rows') e),
  'current-device operation status is exposed via sync_pull operation_statuses');
select is(
  (select count(*) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,500) -> 'operation_statuses' -> 'rows') e where e ? 'payload')::int,
  0, 'operation_statuses rows never expose the raw payload');
-- RF060-B3: device da11 must NOT see device da12's operation status (current-device scoping)
select ok(
  not coalesce((select bool_or(e->>'local_operation_id' = 'op-b')
   from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,500) -> 'operation_statuses' -> 'rows') e), false),
  'current device (da11) operation_statuses does NOT include the OTHER device (da12) op-b — current-device scoping, not just payload hiding');

-- ===== audit_events append-only (UPDATE/DELETE/TRUNCATE blocked) ============= 4-6
select throws_ok($$ update audit_events set action = 'tampered' $$, '42501', NULL, 'audit_events UPDATE is blocked (append-only, D-013)');
select throws_ok($$ delete from audit_events $$, '42501', NULL, 'audit_events DELETE is blocked (append-only)');
select throws_ok($$ truncate audit_events $$, '42501', NULL, 'audit_events TRUNCATE is blocked (append-only)');

-- ===== NEGATIVE CONTROL: the gate detects a broken/unguarded tenant table ==== 7-8
-- (a) a tenant-scoped table (organization_id) with NO RLS at all -> NOT guarded.
create table public.rf060_negctl_bad (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null
);
select is(
  (select (c.relrowsecurity and c.relforcerowsecurity and exists (select 1 from pg_policy p where p.polrelid = c.oid))
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'rf060_negctl_bad'),
  false,
  'negative control (a): an unguarded tenant-scoped table (no RLS) is detected as NOT guarded — the gate goes red');
-- (b) RLS enabled+forced but ZERO policies -> still NOT guarded (the canonical slip).
create table public.rf060_negctl_norls (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null
);
alter table public.rf060_negctl_norls enable row level security;
alter table public.rf060_negctl_norls force  row level security;
select is(
  (select (c.relrowsecurity and c.relforcerowsecurity and exists (select 1 from pg_policy p where p.polrelid = c.oid))
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'rf060_negctl_norls'),
  false,
  'negative control (b): RLS enabled+forced but ZERO policies is detected as NOT guarded');

select * from finish();
rollback;  -- removes the rf060_negctl_* throwaway tables; no schema left behind
