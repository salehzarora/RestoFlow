-- ============================================================================
-- RF-057 — pgTAP: authorization / role visibility (A5, A8)
-- ============================================================================
-- An expired PIN session, a device mismatch, and a revoked backing device session
-- each reject the pull (42501). Role visibility is server-derived: kitchen_staff may
-- pull only non-financial entities (orders/order_items/order_item_modifiers) and is
-- rejected when requesting a financial entity; cashier+ pulls the full set. Fixtures
-- inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(7);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf057z-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11'),
  ('00000000-0000-0000-0000-0000000005b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf057z-cashier@example.test'),
  ('00000000-0000-0000-0000-00000000ee04', 'rf057z-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('00000000-0000-0000-0000-00000000ab04', '00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef004', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-00000000ab04');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000005e1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() - interval '1 hour'),
  ('00000000-0000-0000-0000-0000000005c4', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef004', '00000000-0000-0000-0000-00000000ab04', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000005f1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005b1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');
-- revoke the backing device session of the c5f1 PIN session (after the backing-guard insert)
update device_sessions set revoked_at = now() where id = '00000000-0000-0000-0000-0000000005b1';

-- batch-level rejections ----------------------------------------------------- 1-3
select throws_ok($$ select app.sync_pull('00000000-0000-0000-0000-0000000005e1','00000000-0000-0000-0000-00000000da11',null,'{}'::jsonb,500) $$, '42501', NULL, 'an expired PIN session cannot pull');
select throws_ok($$ select app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000000ff',null,'{}'::jsonb,500) $$, '42501', NULL, 'a device_id not matching the PIN session device is rejected');
select throws_ok($$ select app.sync_pull('00000000-0000-0000-0000-0000000005f1','00000000-0000-0000-0000-00000000da11',null,'{}'::jsonb,500) $$, '42501', NULL, 'a revoked backing device session cannot pull (R-007)');

-- kitchen_staff cannot request a financial entity ---------------------------- 4
select throws_ok($$ select app.sync_pull('00000000-0000-0000-0000-0000000005c4','00000000-0000-0000-0000-00000000da11',array['payments'],'{}'::jsonb,500) $$, '42501', NULL, 'kitchen_staff requesting a financial entity (payments) is rejected');

-- kitchen_staff default scope excludes financial, includes non-financial ----- 5-6
select ok(not ((app.sync_pull('00000000-0000-0000-0000-0000000005c4','00000000-0000-0000-0000-00000000da11',null,'{}'::jsonb,500) -> 'changes') ? 'payments'), 'kitchen_staff default pull does NOT include payments');
select ok((app.sync_pull('00000000-0000-0000-0000-0000000005c4','00000000-0000-0000-0000-00000000da11',null,'{}'::jsonb,500) -> 'changes') ? 'orders', 'kitchen_staff default pull DOES include orders');

-- cashier default scope includes the financial set --------------------------- 7
select ok((app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',null,'{}'::jsonb,500) -> 'changes') ? 'payments', 'cashier default pull includes payments');

select * from finish();
rollback;
