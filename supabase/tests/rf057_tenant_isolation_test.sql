-- ============================================================================
-- RF-057 — pgTAP: tenant + branch isolation (RISK R-003)
-- ============================================================================
-- A pull is filtered by the SESSION-derived organization_id + branch_id, never by
-- client cursor/payload. A device in org A / branch b1 sees only org-A/b1 rows — not
-- a same-org other-branch row, not a cross-org row — and a forged cursor cannot
-- escape that scope. Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(5);

-- ---- Org A, two branches ----
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf057i-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1'),
  ('00000000-0000-0000-0000-00000000a1b2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A2');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('00000000-0000-0000-0000-00000000da12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b2', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active'),
  ('00000000-0000-0000-0000-00000000fa12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b2', '00000000-0000-0000-0000-00000000da12', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11'),
  ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b2', '00000000-0000-0000-0000-00000000da12', '00000000-0000-0000-0000-00000000fa12');
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee0a', 'rf057i-a@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab0a', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef00a', '00000000-0000-0000-0000-0000000000a0', null, null, '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-00000000ab0a');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c50a', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef00a', '00000000-0000-0000-0000-00000000ab0a', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c5a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b2', '00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000ef00a', '00000000-0000-0000-0000-00000000ab0a', now() + interval '1 hour');
-- ---- Org B ----
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf057i-b', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000db11', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fb11', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-00000000db11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005b1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-00000000db11', '00000000-0000-0000-0000-00000000fb11');
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee0b', 'rf057i-b@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab0b', '00000000-0000-0000-0000-00000000ee0b', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef00b', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-00000000ee0b', '00000000-0000-0000-0000-00000000ab0b');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c50b', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-0000000005b1', '00000000-0000-0000-0000-0000000ef00b', '00000000-0000-0000-0000-00000000ab0b', now() + interval '1 hour');
-- one order per (branch / org), all same timestamp
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000000da', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c50a','00000000-0000-0000-0000-0000000ef00a','00000000-0000-0000-0000-00000000ab0a','dine_in','submitted','USD',1000,1000,'oA','2026-06-20 10:00:00+00','2026-06-20 10:00:00+00'),
  ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b2','00000000-0000-0000-0000-00000000da12','00000000-0000-0000-0000-00000000c5a2','00000000-0000-0000-0000-0000000ef00a','00000000-0000-0000-0000-00000000ab0a','dine_in','submitted','USD',1000,1000,'oA2','2026-06-20 10:00:00+00','2026-06-20 10:00:00+00'),
  ('00000000-0000-0000-0000-0000000000db', '00000000-0000-0000-0000-0000000000b0','00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-00000000b1d1','00000000-0000-0000-0000-00000000db11','00000000-0000-0000-0000-00000000c50b','00000000-0000-0000-0000-0000000ef00b','00000000-0000-0000-0000-00000000ab0b','dine_in','submitted','USD',1000,1000,'oB','2026-06-20 10:00:00+00','2026-06-20 10:00:00+00');

-- org A / branch b1 device pull: only oA (oA2 is b2, oB is org B) ------------ 1-3
select is(jsonb_array_length(app.sync_pull('00000000-0000-0000-0000-00000000c50a','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,500) -> 'changes' -> 'orders' -> 'rows')::int, 1, 'org A / b1 device pulls exactly one order (its own branch)');
select is((app.sync_pull('00000000-0000-0000-0000-00000000c50a','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,500) -> 'changes' -> 'orders' -> 'rows' -> 0 ->> 'id'), '00000000-0000-0000-0000-0000000000da', 'the returned row is oA (not the other-branch oA2, not the cross-org oB)');
select is((app.sync_pull('00000000-0000-0000-0000-00000000c50a','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,500) -> 'changes' -> 'orders' -> 'rows' -> 0 ->> 'organization_id'), '00000000-0000-0000-0000-0000000000a0', 'the returned row belongs to org A');

-- org B device pull: only oB --------------------------------------------------- 4
select is((app.sync_pull('00000000-0000-0000-0000-00000000c50b','00000000-0000-0000-0000-00000000db11',array['orders'],'{}'::jsonb,500) -> 'changes' -> 'orders' -> 'rows' -> 0 ->> 'id'), '00000000-0000-0000-0000-0000000000db', 'org B device pulls oB');

-- a forged cursor (pointing at org B''s row) cannot escape org A''s scope ------ 5
select ok(
  not exists(
    select 1 from jsonb_array_elements(
      app.sync_pull('00000000-0000-0000-0000-00000000c50a','00000000-0000-0000-0000-00000000da11',array['orders'],
        jsonb_build_object('orders', jsonb_build_object('updated_at','2026-06-19 00:00:00+00','id','00000000-0000-0000-0000-0000000000db')), 500)
      -> 'changes' -> 'orders' -> 'rows') e
    where e->>'organization_id' <> '00000000-0000-0000-0000-0000000000a0'),
  'a forged cursor cannot make org A''s pull return any non-org-A row');

select * from finish();
rollback;
