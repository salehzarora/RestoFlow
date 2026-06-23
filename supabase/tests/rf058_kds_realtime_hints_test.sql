-- ============================================================================
-- RF-058 — pgTAP: KDS realtime invalidation hints (emission + channel auth)
-- ============================================================================
-- The orders/order_items emission trigger broadcasts a MINIMAL, money-free hint
-- to the private topic kds:branch:{branch_id}; the realtime.messages RLS policy
-- lets an authenticated principal RECEIVE on that topic ONLY with an active
-- membership for that exact branch (R-003). No financial table emits, nothing is
-- enrolled in postgres_changes / the supabase_realtime publication, and the
-- revocation/redaction guarantees (RF-059/RF-061) remain on the sync_pull path.
-- Fixtures inserted as the BYPASSRLS connection role; the three RECEIVE checks
-- run under `set local role authenticated` with simulated JWT/topic GUCs.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(14);

-- ===== fixture: Org A (member aa01 on branch a1b1; revoked dd01) + Org B (cc01)
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000aa01', 'rf058-a@example.test'),
  ('00000000-0000-0000-0000-00000000cc01', 'rf058-c@example.test'),
  ('00000000-0000-0000-0000-00000000dd01', 'rf058-d@example.test');
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf058-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf058-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1'),
  ('00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('00000000-0000-0000-0000-00000000da12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos'); -- to revoke
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active'),
  ('00000000-0000-0000-0000-00000000fa12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da12', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11'),
  ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da12', '00000000-0000-0000-0000-00000000fa12');
insert into app_users (id, email, auth_user_id) values
  ('00000000-0000-0000-0000-00000000ee01', 'm-a@example.test', '00000000-0000-0000-0000-00000000aa01'),
  ('00000000-0000-0000-0000-00000000ee0c', 'm-c@example.test', '00000000-0000-0000-0000-00000000cc01'),
  ('00000000-0000-0000-0000-00000000ee0d', 'm-d@example.test', '00000000-0000-0000-0000-00000000dd01');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, status) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier', 'active'),
  ('00000000-0000-0000-0000-00000000ab0c', '00000000-0000-0000-0000-00000000ee0c', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', 'cashier', 'active'),
  ('00000000-0000-0000-0000-00000000ab0d', '00000000-0000-0000-0000-00000000ee0d', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier', 'revoked'); -- revoked membership
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c502', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');

-- a submit_order fires the emission trigger (orders + order_items hints)
select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-s','dine_in',null,null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":2,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Burger"}]'::jsonb,1000,0,0,1000,null);

-- revoke device da12 (so its sync_pull still 42501s — RF-061 unchanged)
update device_pairings set status='revoked', revoked_at=now() where id='00000000-0000-0000-0000-00000000fa12';
update device_sessions set is_active=false, revoked_at=now() where id='00000000-0000-0000-0000-0000000005a2';

-- ===== (1-3) emission objects exist ========================================
select has_function('app', 'emit_kds_invalidation_hint', 'app.emit_kds_invalidation_hint() exists');
select ok(exists(select 1 from pg_trigger where tgname='orders_emit_kds_hint' and tgrelid='public.orders'::regclass and not tgisinternal),
  'orders has the KDS hint emission trigger');
select ok(exists(select 1 from pg_trigger where tgname='order_items_emit_kds_hint' and tgrelid='public.order_items'::regclass and not tgisinternal),
  'order_items has the KDS hint emission trigger');

-- ===== (4-5) realtime.messages RLS policy is a narrow SELECT for authenticated
select ok(exists(select 1 from pg_policies where schemaname='realtime' and tablename='messages' and policyname='rf058_kds_branch_hint_receive' and cmd='SELECT'),
  'rf058_kds_branch_hint_receive SELECT policy exists on realtime.messages');
select ok((select roles from pg_policies where schemaname='realtime' and tablename='messages' and policyname='rf058_kds_branch_hint_receive') = '{authenticated}'::name[],
  'the realtime receive policy targets the authenticated role only');

-- ===== (6-8) emitted hint is minimal + money-free + KDS entities only =======
select ok(
  (select bool_and((p ? 'organization_id') and (p ? 'branch_id') and (p ? 'entity') and (p ? 'entity_id') and (p ? 'revision') and (p ? 'updated_at') and (p ? 'server_ts'))
   from (select payload p from realtime.messages where event='kds.invalidate' and payload->>'entity'='orders') q),
  'orders hint carries exactly the minimal hint keys (org/branch/entity/entity_id/revision/updated_at/server_ts)');
select is(
  (select count(*) from realtime.messages m, jsonb_object_keys(m.payload) k
   where m.event='kds.invalidate' and (k ~ '(^|_)minor($|_)' or k ~* 'price|payment|cash|receipt|total|amount|discount|tendered'))::int,
  0, 'NO emitted hint key is a money/financial key (no _minor, price, payment, receipt, cash, total, ...)');
select ok(
  (select bool_and(m.payload->>'entity' in ('orders','order_items')) from realtime.messages m where m.event='kds.invalidate'),
  'emitted hints reference ONLY orders / order_items (no financial entity)');

-- ===== (9-10) no financial-table emission + no postgres_changes publication ==
select is(
  (select count(*) from pg_trigger t join pg_proc p on p.oid=t.tgfoid
   where p.proname='emit_kds_invalidation_hint'
     and t.tgrelid in ('public.payments'::regclass,'public.shifts'::regclass,'public.cash_drawer_sessions'::regclass,'public.branch_receipt_counters'::regclass,'public.sync_operations'::regclass))::int,
  0, 'NO financial table (payments/shifts/cash_drawer_sessions/branch_receipt_counters/sync_operations) emits KDS hints');
select is(
  (select count(*) from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename in ('orders','order_items'))::int,
  0, 'orders/order_items were NOT enrolled in the supabase_realtime publication (no postgres_changes)');

-- ===== (11) revocation safety preserved: revoked device still 42501 =========
select throws_ok(
  $$ select app.sync_pull('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000da12',null,'{}'::jsonb,500) $$,
  '42501', NULL, 'a revoked device still gets 42501 from sync_pull — the hint never bypasses the auth gate (RF-061 intact)');

-- ===== (12-14) Realtime Authorization: member allowed, others denied ========
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000aa01';
set local realtime.topic = 'kds:branch:00000000-0000-0000-0000-00000000a1b1';
select ok((select count(*) from realtime.messages) >= 1,
  'an active member of branch A1 MAY receive on kds:branch:A1 (hints visible)');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000cc01';  -- Org B user
select is((select count(*) from realtime.messages)::int, 0,
  'a user from another org/branch may NOT receive on kds:branch:A1 (cross-tenant denied, R-003)');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000dd01';  -- revoked membership
select is((select count(*) from realtime.messages)::int, 0,
  'a user whose branch membership is revoked may NOT receive on kds:branch:A1');

reset role;

select * from finish();
rollback;
