-- ============================================================================
-- PILOT-OPERATIONS-CORRECTIONS-001 — pgTAP: server-authoritative open-shift summary
-- ============================================================================
-- Exercises app.get_open_shift_summary: no shift -> has_open_shift=false; an open
-- shift -> expected_cash_minor computed with the CANONICAL close_shift formula
-- (opening float + completed CASH payments on the drawer); non-cash / non-completed
-- payments excluded; a kitchen_staff principal receives NO money keys (T-003); a
-- different device does not see another device's shift; ACLs (public wrapper +
-- authenticated only). Fixtures as BYPASSRLS; hex UUIDs (prefix 9f).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(16);

insert into organizations (id, name, slug, default_currency) values
  ('9f000000-0000-0000-0000-0000000000a0', 'Org F', 'pilotshift-a', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', 'Branch B1');
insert into app_users (id, email) values
  ('9f000000-0000-0000-0000-00000000ee03', 'pilotshift-cashier@example.test'),
  ('9f000000-0000-0000-0000-00000000ee04', 'pilotshift-cashier2@example.test'),
  ('9f000000-0000-0000-0000-00000000ee05', 'pilotshift-manager@example.test'),
  ('9f000000-0000-0000-0000-00000000ee09', 'pilotshift-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('9f000000-0000-0000-0000-00000000ab03', '9f000000-0000-0000-0000-00000000ee03', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('9f000000-0000-0000-0000-00000000ab04', '9f000000-0000-0000-0000-00000000ee04', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('9f000000-0000-0000-0000-00000000ab05', '9f000000-0000-0000-0000-00000000ee05', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', 'manager'),
  ('9f000000-0000-0000-0000-00000000ab09', '9f000000-0000-0000-0000-00000000ee09', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', 'kitchen_staff');
-- two POS devices: da11 (will have an open shift), da22 (none)
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('9f000000-0000-0000-0000-00000000da22', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('9f000000-0000-0000-0000-00000000fa11', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da11', 'active'),
  ('9f000000-0000-0000-0000-00000000fa22', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da22', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('9f000000-0000-0000-0000-0000000005a1', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-00000000fa11'),
  ('9f000000-0000-0000-0000-0000000005a2', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da22', '9f000000-0000-0000-0000-00000000fa22');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('9f000000-0000-0000-0000-0000000ef003', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000ee03', '9f000000-0000-0000-0000-00000000ab03'),
  ('9f000000-0000-0000-0000-0000000ef004', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000ee04', '9f000000-0000-0000-0000-00000000ab04'),
  ('9f000000-0000-0000-0000-0000000ef005', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000ee05', '9f000000-0000-0000-0000-00000000ab05'),
  ('9f000000-0000-0000-0000-0000000ef009', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000ee09', '9f000000-0000-0000-0000-00000000ab09');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('9f000000-0000-0000-0000-00000000c503', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-0000000005a1', '9f000000-0000-0000-0000-0000000ef003', '9f000000-0000-0000-0000-00000000ab03', now() + interval '1 hour'),
  ('9f000000-0000-0000-0000-00000000c504', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-0000000005a1', '9f000000-0000-0000-0000-0000000ef004', '9f000000-0000-0000-0000-00000000ab04', now() + interval '1 hour'),
  ('9f000000-0000-0000-0000-00000000c505', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-0000000005a1', '9f000000-0000-0000-0000-0000000ef005', '9f000000-0000-0000-0000-00000000ab05', now() + interval '1 hour'),
  ('9f000000-0000-0000-0000-00000000c522', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-0000000005a2', '9f000000-0000-0000-0000-0000000ef003', '9f000000-0000-0000-0000-00000000ab03', now() + interval '1 hour'),
  ('9f000000-0000-0000-0000-00000000c509', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-0000000005a1', '9f000000-0000-0000-0000-0000000ef009', '9f000000-0000-0000-0000-00000000ab09', now() + interval '1 hour');

-- ===== (1) da22 has NO open shift -> has_open_shift=false =====================
select is(
  (select (app.get_open_shift_summary('9f000000-0000-0000-0000-00000000c522','9f000000-0000-0000-0000-00000000da22') ->> 'has_open_shift')::boolean),
  false, 'a device with no open shift reports has_open_shift=false');

-- open shift + drawer (opening float 1000) on da11
insert into shifts (id, organization_id, restaurant_id, branch_id, device_id, opened_by_employee_profile_id, resolved_membership_id, local_operation_id, status) values
  ('9f000000-0000-0000-0000-000000005f01', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-0000000ef003', '9f000000-0000-0000-0000-00000000ab03', 'shift-open-1', 'open');
insert into cash_drawer_sessions (id, organization_id, restaurant_id, branch_id, device_id, shift_id, opened_by_employee_profile_id, opening_float_minor, local_operation_id) values
  ('9f000000-0000-0000-0000-000000005d01', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-000000005f01', '9f000000-0000-0000-0000-0000000ef003', 1000, 'drawer-open-1');
-- one order per payment (a completed payment is unique per order)
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, currency_code, subtotal_minor, grand_total_minor, local_operation_id, status) values
  ('9f000000-0000-0000-0000-00000000a001', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-00000000c503', '9f000000-0000-0000-0000-0000000ef003', '9f000000-0000-0000-0000-00000000ab03', 'takeaway', 'ILS', 500, 500, 'ord-1', 'submitted'),
  ('9f000000-0000-0000-0000-00000000a002', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-00000000c503', '9f000000-0000-0000-0000-0000000ef003', '9f000000-0000-0000-0000-00000000ab03', 'takeaway', 'ILS', 300, 300, 'ord-2', 'submitted'),
  ('9f000000-0000-0000-0000-00000000a003', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-00000000c503', '9f000000-0000-0000-0000-0000000ef003', '9f000000-0000-0000-0000-00000000ab03', 'takeaway', 'ILS', 500, 500, 'ord-3', 'submitted'),
  ('9f000000-0000-0000-0000-00000000a004', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-00000000c503', '9f000000-0000-0000-0000-0000000ef003', '9f000000-0000-0000-0000-00000000ab03', 'takeaway', 'ILS', 200, 200, 'ord-4', 'submitted');
-- payments: two COMPLETED CASH (500 + 300) = 800 count; one COMPLETED CARD (500) + one PENDING CASH (200) EXCLUDED
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, cash_drawer_session_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id) values
  ('9f000000-0000-0000-0000-00000000ba01', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000a001', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-0000000ef003', '9f000000-0000-0000-0000-00000000ab03', '9f000000-0000-0000-0000-000000005d01', 'cash', 'completed', 500, 500, 0, 'ILS', 'pay-1'),
  ('9f000000-0000-0000-0000-00000000ba02', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000a002', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-0000000ef003', '9f000000-0000-0000-0000-00000000ab03', '9f000000-0000-0000-0000-000000005d01', 'cash', 'completed', 300, 300, 0, 'ILS', 'pay-2'),
  ('9f000000-0000-0000-0000-00000000ba03', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000a003', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-0000000ef003', '9f000000-0000-0000-0000-00000000ab03', '9f000000-0000-0000-0000-000000005d01', 'card', 'completed', 500, 500, 0, 'ILS', 'pay-3'),
  ('9f000000-0000-0000-0000-00000000ba04', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000a004', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-0000000ef003', '9f000000-0000-0000-0000-00000000ab03', '9f000000-0000-0000-0000-000000005d01', 'cash', 'pending', 200, 200, 0, 'ILS', 'pay-4');

create temp table ts as select app.get_open_shift_summary('9f000000-0000-0000-0000-00000000c503','9f000000-0000-0000-0000-00000000da11') as res;

-- ===== (2-7) the open-shift summary ==========================================
select is((select (res->>'has_open_shift')::boolean from ts), true, 'da11 reports an open shift');
select is((select res->>'shift_id' from ts), '9f000000-0000-0000-0000-000000005f01', 'the summary carries the shift id');
select is((select res->>'status' from ts), 'open', 'the shift status is open');
select is((select (res->>'opening_float_minor')::bigint from ts), 1000::bigint, 'opening float is the drawer''s opening float');
select is((select (res->>'cash_sales_minor')::bigint from ts), 800::bigint, 'cash_sales = only COMPLETED CASH payments on the drawer (500+300; card + pending excluded)');
select is((select (res->>'expected_cash_minor')::bigint from ts), 1800::bigint, 'expected_cash = opening float + completed cash (1000+800) — the canonical close_shift formula');

-- ===== (8) the value equals what app.close_shift would compute ================
select is(
  (select (res->>'expected_cash_minor')::bigint from ts),
  (select (1000 + coalesce(sum(p.amount_minor),0))::bigint from payments p
     where p.organization_id='9f000000-0000-0000-0000-0000000000a0'
       and p.cash_drawer_session_id='9f000000-0000-0000-0000-000000005d01'
       and p.method='cash' and p.status='completed'),
  'expected_cash matches the exact close_shift SQL (opening + completed cash on the drawer)');

-- ===== (9) a kitchen_staff principal receives NO money keys (T-003) ==========
select is(
  (select app.get_open_shift_summary('9f000000-0000-0000-0000-00000000c509','9f000000-0000-0000-0000-00000000da11') ? 'expected_cash_minor'),
  false, 'a kitchen_staff session receives NO expected_cash_minor (money redaction, T-003)');

-- ===== (10-11) ACLs ==========================================================
select is(
  (select has_function_privilege('authenticated', 'public.get_open_shift_summary(uuid,uuid)', 'execute')),
  true, 'authenticated may execute public.get_open_shift_summary');
select is(
  (select has_function_privilege('anon', 'public.get_open_shift_summary(uuid,uuid)', 'execute')),
  false, 'anon may NOT execute public.get_open_shift_summary');

-- ===== (12-16) B1: recovery ownership mirrors app.close_shift =================
-- A DIFFERENT cashier (ef004, c504) on the SAME device does NOT get ef003's shift as
-- their own: has_open_shift=true but can_close=false + a typed owner-mismatch + NO money.
create temp table tb1 as
  select app.get_open_shift_summary('9f000000-0000-0000-0000-00000000c504','9f000000-0000-0000-0000-00000000da11') as res;
select is((select res->>'error' from tb1), 'shift_owner_mismatch',
  'a non-owner cashier gets a typed shift_owner_mismatch, not another employee''s shift');
select is((select (res->>'can_close')::boolean from tb1), false,
  'a non-owner cashier cannot close the shift (mirrors app.close_shift)');
select is((select res ? 'expected_cash_minor' from tb1), false,
  'a non-owner cashier receives NO money figure (the drawer belongs to the owner)');
select is((select res->>'opened_by_employee_profile_id' from tb1), '9f000000-0000-0000-0000-0000000ef003',
  'the mismatch names the ACTUAL owner (ef003), never the current actor');
-- A MANAGER (ef005, c505) may recover ANY shift on the device (can_close=true + money).
select is(
  (select (app.get_open_shift_summary('9f000000-0000-0000-0000-00000000c505','9f000000-0000-0000-0000-00000000da11') ->> 'can_close')::boolean),
  true, 'a manager may recover (and close) any shift on the device — can_close=true');

select * from finish();
rollback;
