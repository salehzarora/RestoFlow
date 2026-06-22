-- ============================================================================
-- RF-053 — pgTAP: audit rows written with old/new values (AC#2, D-013)
-- ============================================================================
-- A successful void writes one order.voided row (old/new status+revision+reason);
-- a successful discount writes one order.discount_applied row; a clean idempotency
-- replay writes NO second audit row. Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(7);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf053a-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11');
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee01', 'rf053a-mgr@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'manager');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, revision, local_operation_id) values
  ('00000000-0000-0000-0000-00000000a0d1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', 'dine_in', 'submitted', 'USD', 1000, 0, 0, 1000, 1, 'ord-1'),
  ('00000000-0000-0000-0000-00000000a0d2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', 'dine_in', 'submitted', 'USD', 1000, 0, 0, 1000, 1, 'ord-2');

-- successful void writes order.voided with old/new values -------------------- 1-4
select app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-v','customer cancelled', null);
select is((select count(*) from audit_events where action='order.voided')::int, 1, 'one order.voided audit row written');
select is((select old_values ->> 'status' from audit_events where action='order.voided'), 'submitted', 'order.voided old_values.status = submitted');
select is((select new_values ->> 'status' from audit_events where action='order.voided'), 'voided', 'order.voided new_values.status = voided');
select is((select new_values ->> 'void_reason' from audit_events where action='order.voided'), 'customer cancelled', 'order.voided new_values.void_reason recorded');

-- successful discount writes order.discount_applied -------------------------- 5-6
select app.apply_discount('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d2','00000000-0000-0000-0000-00000000da11','op-d','order', null, 'fixed', 200, 'manager promo', null);
select is((select count(*) from audit_events where action='order.discount_applied')::int, 1, 'one order.discount_applied audit row written');
select is((select (new_values ->> 'discount_total_minor')::bigint from audit_events where action='order.discount_applied'), 200::bigint, 'discount audit new_values.discount_total_minor = 200');

-- idempotent replay writes NO second audit row ------------------------------- 7
select app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-v','customer cancelled', null);
select is((select count(*) from audit_events where action='order.voided')::int, 1, 'a clean void replay writes NO second audit row');

select * from finish();
rollback;
