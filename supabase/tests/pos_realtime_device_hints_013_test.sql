-- ============================================================================
-- POS-OPEN-ORDERS-REALTIME-GATE-013 — pgTAP: POS device RECEIVE authorization
-- on the RF-058 branch invalidation topic.
-- ============================================================================
-- RF-058 already emits the money-free hint to kds:branch:{branch_id} on every
-- orders/order_items INSERT/UPDATE. This gate adds ONE additive SELECT policy
-- (rf058_pos_device_branch_hint_receive) admitting the ANONYMOUS POS DEVICE
-- principal via its CURRENTLY-VALID device session — the same binding the
-- device storage policies use (device_sessions.auth_user_id, re-bound each
-- launch by app.restore_device_session) but with the FULL RF-118 validity
-- chain including expires_at. The existing membership policy
-- (rf058_kds_branch_hint_receive) is untouched; emission is untouched; there
-- is still no SEND/INSERT right for any client.
--
-- Fixtures inserted as the BYPASSRLS connection role; RECEIVE checks run under
-- `set local role authenticated` with simulated JWT sub + realtime.topic GUCs
-- (the rf058 test template).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(25);

-- ===== fixture graph =========================================================
-- Org A: branches A1B1 + A1B2. Org B: branch B1D1.
-- Device principals (auth.users, anonymous-style — bound via
-- device_sessions.auth_user_id, NO app_users rows):
--   aa0001 valid POS on A1B1        aa0002 valid POS on A1B2 (cross-branch)
--   aa0003 valid POS on B1D1 (org B) aa0004 POS on A1B1, REVOKED
--   aa0005 POS on A1B1, EXPIRED      aa0006 authenticated but UNBOUND
--   aa0007 valid KDS device on A1B1  aa0008 human MEMBER on A1B1 (old policy)
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00d013aa0001', 'g013-d1@example.test'),
  ('00000000-0000-0000-0000-00d013aa0002', 'g013-d2@example.test'),
  ('00000000-0000-0000-0000-00d013aa0003', 'g013-d3@example.test'),
  ('00000000-0000-0000-0000-00d013aa0004', 'g013-d4@example.test'),
  ('00000000-0000-0000-0000-00d013aa0005', 'g013-d5@example.test'),
  ('00000000-0000-0000-0000-00d013aa0006', 'g013-d6@example.test'),
  ('00000000-0000-0000-0000-00d013aa0007', 'g013-d7@example.test'),
  ('00000000-0000-0000-0000-00d013aa0008', 'g013-m8@example.test');
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-00d01300a000', 'G013 Org A', 'g013-a', 'USD'),
  ('00000000-0000-0000-0000-00d01300b000', 'G013 Org B', 'g013-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d01300a000', 'G013 Rest A1'),
  ('00000000-0000-0000-0000-00d01300b100', '00000000-0000-0000-0000-00d01300b000', 'G013 Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00d013a1b100', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', 'G013 Branch A1'),
  ('00000000-0000-0000-0000-00d013a1b200', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', 'G013 Branch A2'),
  ('00000000-0000-0000-0000-00d013b1d100', '00000000-0000-0000-0000-00d01300b000', '00000000-0000-0000-0000-00d01300b100', 'G013 Branch B1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00d013dd0100', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b100', 'pos'),
  ('00000000-0000-0000-0000-00d013dd0200', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b200', 'pos'),
  ('00000000-0000-0000-0000-00d013dd0300', '00000000-0000-0000-0000-00d01300b000', '00000000-0000-0000-0000-00d01300b100', '00000000-0000-0000-0000-00d013b1d100', 'pos'),
  ('00000000-0000-0000-0000-00d013dd0400', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b100', 'pos'), -- to revoke
  ('00000000-0000-0000-0000-00d013dd0500', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b100', 'pos'), -- expired session
  ('00000000-0000-0000-0000-00d013dd0700', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b100', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00d013fa0100', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b100', '00000000-0000-0000-0000-00d013dd0100', 'active'),
  ('00000000-0000-0000-0000-00d013fa0200', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b200', '00000000-0000-0000-0000-00d013dd0200', 'active'),
  ('00000000-0000-0000-0000-00d013fa0300', '00000000-0000-0000-0000-00d01300b000', '00000000-0000-0000-0000-00d01300b100', '00000000-0000-0000-0000-00d013b1d100', '00000000-0000-0000-0000-00d013dd0300', 'active'),
  ('00000000-0000-0000-0000-00d013fa0400', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b100', '00000000-0000-0000-0000-00d013dd0400', 'active'),
  ('00000000-0000-0000-0000-00d013fa0500', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b100', '00000000-0000-0000-0000-00d013dd0500', 'active'),
  ('00000000-0000-0000-0000-00d013fa0700', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b100', '00000000-0000-0000-0000-00d013dd0700', 'active');
-- Sessions bound to the anonymous principals (the restore-time rebind result).
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, auth_user_id, expires_at) values
  ('00000000-0000-0000-0000-00d013050100', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b100', '00000000-0000-0000-0000-00d013dd0100', '00000000-0000-0000-0000-00d013fa0100', '00000000-0000-0000-0000-00d013aa0001', now() + interval '1 day'),
  ('00000000-0000-0000-0000-00d013050200', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b200', '00000000-0000-0000-0000-00d013dd0200', '00000000-0000-0000-0000-00d013fa0200', '00000000-0000-0000-0000-00d013aa0002', now() + interval '1 day'),
  ('00000000-0000-0000-0000-00d013050300', '00000000-0000-0000-0000-00d01300b000', '00000000-0000-0000-0000-00d01300b100', '00000000-0000-0000-0000-00d013b1d100', '00000000-0000-0000-0000-00d013dd0300', '00000000-0000-0000-0000-00d013fa0300', '00000000-0000-0000-0000-00d013aa0003', now() + interval '1 day'),
  ('00000000-0000-0000-0000-00d013050400', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b100', '00000000-0000-0000-0000-00d013dd0400', '00000000-0000-0000-0000-00d013fa0400', '00000000-0000-0000-0000-00d013aa0004', now() + interval '1 day'),
  ('00000000-0000-0000-0000-00d013050500', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b100', '00000000-0000-0000-0000-00d013dd0500', '00000000-0000-0000-0000-00d013fa0500', '00000000-0000-0000-0000-00d013aa0005', now() - interval '1 hour'), -- EXPIRED
  ('00000000-0000-0000-0000-00d013050700', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b100', '00000000-0000-0000-0000-00d013dd0700', '00000000-0000-0000-0000-00d013fa0700', '00000000-0000-0000-0000-00d013aa0007', now() + interval '1 day');
-- The human member (OLD policy coexistence) + the pin/order chain the raw
-- orders inserts need. A1B2 gets its own membership/employee/pin chain.
insert into app_users (id, email, auth_user_id) values
  ('00000000-0000-0000-0000-00d013ee0800', 'g013-m8-app@example.test', '00000000-0000-0000-0000-00d013aa0008');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, status) values
  ('00000000-0000-0000-0000-00d013ab0800', '00000000-0000-0000-0000-00d013ee0800', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b100', 'cashier', 'active'),
  ('00000000-0000-0000-0000-00d013ab0900', '00000000-0000-0000-0000-00d013ee0800', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b200', 'cashier', 'active');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-00d013ef0800', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b100', '00000000-0000-0000-0000-00d013ee0800', '00000000-0000-0000-0000-00d013ab0800'),
  ('00000000-0000-0000-0000-00d013ef0900', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b200', '00000000-0000-0000-0000-00d013ee0800', '00000000-0000-0000-0000-00d013ab0900');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00d013c50800', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b100', '00000000-0000-0000-0000-00d013050100', '00000000-0000-0000-0000-00d013ef0800', '00000000-0000-0000-0000-00d013ab0800', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00d013c50880', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b200', '00000000-0000-0000-0000-00d013050200', '00000000-0000-0000-0000-00d013ef0900', '00000000-0000-0000-0000-00d013ab0900', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00d013c50900', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b100', '00000000-0000-0000-0000-00d013050400', '00000000-0000-0000-0000-00d013ef0800', '00000000-0000-0000-0000-00d013ab0800', now() + interval '1 hour');

-- Fire the RF-058 emission on BOTH Org-A branches with raw inserts (the AFTER
-- trigger fires regardless of the writing role — the RPC path is already
-- covered by rf058_kds_realtime_hints_test.sql).
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00d0130d0100', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b100', '00000000-0000-0000-0000-00d013dd0100', '00000000-0000-0000-0000-00d013c50800', '00000000-0000-0000-0000-00d013ef0800', '00000000-0000-0000-0000-00d013ab0800', 'takeaway', 'submitted', 'USD', 1000, 0, 0, 1000, 'g013-o1'),
  ('00000000-0000-0000-0000-00d0130d0200', '00000000-0000-0000-0000-00d01300a000', '00000000-0000-0000-0000-00d01300a100', '00000000-0000-0000-0000-00d013a1b200', '00000000-0000-0000-0000-00d013dd0200', '00000000-0000-0000-0000-00d013c50880', '00000000-0000-0000-0000-00d013ef0900', '00000000-0000-0000-0000-00d013ab0900', 'takeaway', 'submitted', 'USD', 1000, 0, 0, 1000, 'g013-o2');

-- Revoke device 4's session + pairing AFTER the emission fixtures.
update device_pairings set status='revoked', revoked_at=now() where id='00000000-0000-0000-0000-00d013fa0400';
update device_sessions set is_active=false, revoked_at=now() where id='00000000-0000-0000-0000-00d013050400';

-- ===== (1-4) the helper exists with the exact safety attributes =============
select has_function('app', 'device_can_receive_branch_hints', array['text'],
  'app.device_can_receive_branch_hints(text) exists');
select ok(
  (select p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app' and p.proname = 'device_can_receive_branch_hints'),
  'the helper is SECURITY DEFINER');
select ok(
  (select coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'
      and coalesce(array_to_string(p.proconfig, ','), '') not like '%public%'
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app' and p.proname = 'device_can_receive_branch_hints'),
  'the helper pins an EMPTY search_path');
select ok(
  (select p.provolatile = 's' from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app' and p.proname = 'device_can_receive_branch_hints'),
  'the helper is STABLE');

-- ===== (5-8) both policies present, narrow, and unchanged ===================
select ok(exists(select 1 from pg_policies where schemaname='realtime' and tablename='messages' and policyname='rf058_pos_device_branch_hint_receive' and cmd='SELECT'),
  'rf058_pos_device_branch_hint_receive SELECT policy exists on realtime.messages');
select ok((select roles from pg_policies where schemaname='realtime' and tablename='messages' and policyname='rf058_pos_device_branch_hint_receive') = '{authenticated}'::name[],
  'the POS device receive policy targets the authenticated role only');
select ok(exists(select 1 from pg_policies where schemaname='realtime' and tablename='messages' and policyname='rf058_kds_branch_hint_receive' and cmd='SELECT'
    and roles = '{authenticated}'::name[] and qual like '%memberships%'),
  'the ORIGINAL membership policy is still present, SELECT-only, authenticated-only, membership-joined (untouched)');
select is((select count(*) from pg_policies where schemaname='realtime' and tablename='messages')::int, 2,
  'exactly TWO policies exist on realtime.messages (member + POS device), nothing else');

-- ===== (9-10) no SEND/write right, no anon/PUBLIC widening ==================
select is((select count(*) from pg_policies where schemaname='realtime' and tablename='messages' and cmd <> 'SELECT')::int, 0,
  'NO policy grants INSERT/SEND/UPDATE/DELETE on realtime.messages — clients still cannot broadcast');
select ok(not exists(select 1 from pg_policies where schemaname='realtime' and tablename='messages'
    and ('anon' = any(roles) or 'public' = any(roles))),
  'no realtime.messages policy widens to anon/PUBLIC');

-- ===== (11-12) emission surface unchanged ===================================
select is(
  (select count(*) from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename in ('orders','order_items'))::int,
  0, 'orders/order_items are still NOT enrolled in postgres_changes (publication unchanged)');
select is(
  (select count(*) from pg_trigger t join pg_proc p on p.oid=t.tgfoid
   where p.proname='emit_kds_invalidation_hint'
     and t.tgrelid in ('public.payments'::regclass,'public.shifts'::regclass,'public.cash_drawer_sessions'::regclass,'public.branch_receipt_counters'::regclass,'public.sync_operations'::regclass))::int,
  0, 'still NO financial-table emission (payments/shifts/cash_drawer/receipt_counters/sync_operations)');

-- ===== (13) the hint still bypasses no auth: revoked device 42501 ===========
select throws_ok(
  $$ select app.sync_pull('00000000-0000-0000-0000-00d013c50900','00000000-0000-0000-0000-00d013dd0400',null,'{}'::jsonb,500) $$,
  '42501', NULL, 'a revoked device still gets 42501 from the authoritative pull — hints never bypass the auth gate');

-- ===== (14-25) RECEIVE authorization matrix =================================
set local role authenticated;
set local realtime.topic = 'kds:branch:00000000-0000-0000-0000-00d013a1b100';

set local request.jwt.claim.sub = '00000000-0000-0000-0000-00d013aa0001';
select ok((select count(*) from realtime.messages) >= 1,
  'a VALID POS device session of branch A1 MAY receive on its own branch topic');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-00d013aa0002';
select is((select count(*) from realtime.messages)::int, 0,
  'a valid POS device of ANOTHER branch may NOT receive on branch A1 (branch isolation)');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-00d013aa0003';
select is((select count(*) from realtime.messages)::int, 0,
  'a valid POS device of ANOTHER ORG may NOT receive on branch A1 (tenant isolation, R-003)');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-00d013aa0004';
select is((select count(*) from realtime.messages)::int, 0,
  'a REVOKED device session may NOT receive (session + pairing revocation respected)');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-00d013aa0005';
select is((select count(*) from realtime.messages)::int, 0,
  'an EXPIRED device session may NOT receive (RF-118 expires_at enforced — stricter than the storage gates)');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-00d013aa0006';
select is((select count(*) from realtime.messages)::int, 0,
  'an authenticated principal with NO bound device session may NOT receive');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-00d013aa0007';
select is((select count(*) from realtime.messages)::int, 0,
  'a KDS-TYPE device principal may NOT receive through the POS policy (this gate is pos-only)');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-00d013aa0008';
select ok((select count(*) from realtime.messages) >= 1,
  'an ACTIVE MEMBER still receives through the ORIGINAL policy (coexistence, nothing weakened)');

-- Cross-branch device on its OWN topic: allowed (proves per-branch binding,
-- not a special case of branch A1).
set local realtime.topic = 'kds:branch:00000000-0000-0000-0000-00d013a1b200';
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00d013aa0002';
select ok((select count(*) from realtime.messages) >= 1,
  'the SAME cross-branch device MAY receive on its OWN branch topic');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-00d013aa0001';
select is((select count(*) from realtime.messages)::int, 0,
  'and the branch-A1 device may NOT receive on branch A2 (isolation is symmetric)');

-- Malformed / wrong-prefix topics: denied for the fully valid principal.
set local realtime.topic = 'kds:branch:not-a-real-branch';
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00d013aa0001';
select is((select count(*) from realtime.messages)::int, 0,
  'a malformed branch topic is denied even for a fully valid device');

set local realtime.topic = 'pos:branch:00000000-0000-0000-0000-00d013a1b100';
select is((select count(*) from realtime.messages)::int, 0,
  'a pos:branch:* topic does not exist in this design and stays denied (default-deny intact)');

reset role;

select * from finish();
rollback;
