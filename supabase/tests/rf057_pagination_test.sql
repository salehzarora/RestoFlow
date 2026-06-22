-- ============================================================================
-- RF-057 — pgTAP: pagination + limit bounds (A7)
-- ============================================================================
-- The limit is honored; has_more + next_cursor let the client page deterministically
-- through all rows with no skips/duplicates; limit <= 0 or > 1000 is rejected.
-- Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(8);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf057p-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee01', 'rf057p-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');
-- five orders, strictly increasing updated_at
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id, created_at, updated_at) values
  ('00000000-0000-0000-0000-00000000c0d1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'o1','2026-06-20 10:00:00+00','2026-06-20 10:00:00+00'),
  ('00000000-0000-0000-0000-00000000c0d2', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'o2','2026-06-20 10:01:00+00','2026-06-20 10:01:00+00'),
  ('00000000-0000-0000-0000-00000000c0d3', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'o3','2026-06-20 10:02:00+00','2026-06-20 10:02:00+00'),
  ('00000000-0000-0000-0000-00000000c0d4', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'o4','2026-06-20 10:03:00+00','2026-06-20 10:03:00+00'),
  ('00000000-0000-0000-0000-00000000c0d5', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'o5','2026-06-20 10:04:00+00','2026-06-20 10:04:00+00');

-- page 1 (limit 2, no cursor) -> o1, o2 + has_more ---------------------------- 1-2
select is(jsonb_array_length(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,2) -> 'changes' -> 'orders' -> 'rows')::int, 2, 'page 1 returns exactly the limit (2 rows)');
select is((app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,2) -> 'changes' -> 'orders' ->> 'has_more')::boolean, true, 'page 1 has_more is true');

-- page 2 (cursor at o2) -> o3, o4 --------------------------------------------- 3-4
select is(jsonb_array_length(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'], jsonb_build_object('orders', jsonb_build_object('updated_at','2026-06-20 10:01:00+00','id','00000000-0000-0000-0000-00000000c0d2')),2) -> 'changes' -> 'orders' -> 'rows')::int, 2, 'page 2 returns 2 rows');
select is((app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'], jsonb_build_object('orders', jsonb_build_object('updated_at','2026-06-20 10:01:00+00','id','00000000-0000-0000-0000-00000000c0d2')),2) -> 'changes' -> 'orders' -> 'rows' -> 0 ->> 'id'), '00000000-0000-0000-0000-00000000c0d3', 'page 2 begins at o3 (no overlap/skip with page 1)');

-- page 3 (cursor at o4) -> o5, has_more false -------------------------------- 5-6
select is(jsonb_array_length(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'], jsonb_build_object('orders', jsonb_build_object('updated_at','2026-06-20 10:03:00+00','id','00000000-0000-0000-0000-00000000c0d4')),2) -> 'changes' -> 'orders' -> 'rows')::int, 1, 'page 3 returns the final row');
select is((app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'], jsonb_build_object('orders', jsonb_build_object('updated_at','2026-06-20 10:03:00+00','id','00000000-0000-0000-0000-00000000c0d4')),2) -> 'changes' -> 'orders' ->> 'has_more')::boolean, false, 'page 3 has_more is false (drained)');

-- limit bounds: <= 0 and > 1000 are rejected --------------------------------- 7-8
select throws_ok($$ select app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,0) $$, '42501', NULL, 'a limit of 0 is rejected');
select throws_ok($$ select app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,1001) $$, '42501', NULL, 'a limit above the 1000 cap is rejected');

select * from finish();
rollback;
