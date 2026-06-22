-- ============================================================================
-- RF-057 — pgTAP: changed-since (updated_at, id) cursor (A1)
-- ============================================================================
-- Rows are returned strictly after the (updated_at, id) cursor, ordered by
-- (updated_at asc, id asc), same-timestamp ties broken deterministically by id;
-- next_cursor is the last row's watermark; has_more reflects hitting the limit.
-- Orders are inserted directly (connection role) with controlled updated_at so the
-- ordering is deterministic. Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(8);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf057c-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee01', 'rf057c-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');
-- four orders with controlled updated_at; o3 and o3b SHARE a timestamp (tie-break by id)
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id, created_at, updated_at) values
  ('00000000-0000-0000-0000-00000000c0d1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'o1','2026-06-20 10:00:00+00','2026-06-20 10:00:00+00'),
  ('00000000-0000-0000-0000-00000000c0d2', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'o2','2026-06-20 10:01:00+00','2026-06-20 10:01:00+00'),
  ('00000000-0000-0000-0000-00000000c0d3', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'o3','2026-06-20 10:02:00+00','2026-06-20 10:02:00+00'),
  ('00000000-0000-0000-0000-00000000c0d4', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'o4','2026-06-20 10:02:00+00','2026-06-20 10:02:00+00');

-- cursor at (t1, o1) -> returns o2, o3, o3b (3 rows after the cursor) ---------- 1-2
select is(
  jsonb_array_length(
    app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],
      jsonb_build_object('orders', jsonb_build_object('updated_at','2026-06-20 10:00:00+00','id','00000000-0000-0000-0000-00000000c0d1')), 500)
    -> 'changes' -> 'orders' -> 'rows')::int,
  3, 'cursor at (t1,o1) returns the 3 rows strictly after it');
select is(
  (app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],
    jsonb_build_object('orders', jsonb_build_object('updated_at','2026-06-20 10:00:00+00','id','00000000-0000-0000-0000-00000000c0d1')), 500)
   -> 'changes' -> 'orders' -> 'rows' -> 0 ->> 'id'),
  '00000000-0000-0000-0000-00000000c0d2', 'the first returned row is o2 (smallest after the cursor)');

-- same-timestamp tie-break by id: o3 (c0d3) before o3b (c0d4) ----------------- 3-4
select is(
  (app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],
    jsonb_build_object('orders', jsonb_build_object('updated_at','2026-06-20 10:00:00+00','id','00000000-0000-0000-0000-00000000c0d1')), 500)
   -> 'changes' -> 'orders' -> 'rows' -> 1 ->> 'id'),
  '00000000-0000-0000-0000-00000000c0d3', 'same-timestamp rows are ordered by id (o3 before o3b)');
select is(
  (app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],
    jsonb_build_object('orders', jsonb_build_object('updated_at','2026-06-20 10:00:00+00','id','00000000-0000-0000-0000-00000000c0d1')), 500)
   -> 'changes' -> 'orders' -> 'rows' -> 2 ->> 'id'),
  '00000000-0000-0000-0000-00000000c0d4', 'the last tie row is o3b');

-- next_cursor = last row watermark; has_more false (3 < 500) ------------------ 5-6
select is(
  (app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],
    jsonb_build_object('orders', jsonb_build_object('updated_at','2026-06-20 10:00:00+00','id','00000000-0000-0000-0000-00000000c0d1')), 500)
   -> 'changes' -> 'orders' -> 'next_cursor' ->> 'id'),
  '00000000-0000-0000-0000-00000000c0d4', 'next_cursor.id is the last returned row');
select is(
  (app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],
    jsonb_build_object('orders', jsonb_build_object('updated_at','2026-06-20 10:00:00+00','id','00000000-0000-0000-0000-00000000c0d1')), 500)
   -> 'changes' -> 'orders' ->> 'has_more')::boolean,
  false, 'has_more is false when fewer rows than the limit');

-- no cursor -> all 4 rows from oldest ---------------------------------------- 7
select is(
  jsonb_array_length(
    app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,500)
    -> 'changes' -> 'orders' -> 'rows')::int,
  4, 'no cursor returns all visible rows from the oldest');

-- limit honored: limit 2 from oldest -> 2 rows + has_more true --------------- 8
select is(
  ((app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,2)
    -> 'changes' -> 'orders' ->> 'has_more')::boolean),
  true, 'limit 2 sets has_more true (more rows remain)');

select * from finish();
rollback;
