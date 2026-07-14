-- ============================================================================
-- PIN-SESSION-CAPABILITIES-HOTFIX-001 — pgTAP for app.pin_session_capabilities
-- ============================================================================
-- THE GAP THIS SUITE EXISTS TO CLOSE.
--
-- FULL-COMP-PERMISSION-001 shipped app.pin_session_capabilities selecting
-- `ps.status` / `ds.status` — columns that DO NOT EXIST. It raised SQLSTATE 42703
-- on every call in production and never once returned a value. Its 48-test suite
-- passed anyway, because it NEVER CALLED THE FUNCTION. plpgsql plans lazily, so a
-- body that is never executed is never checked against the catalog.
--
-- So this suite has TEETH, in three layers:
--   A. It proves, BEHAVIOURALLY (not by grepping source), that the OLD predicate is
--      invalid against the live schema — the old query itself is executed and must
--      raise 42703, and the columns it named must be absent while `is_active` is
--      present.
--   B. It CALLS the real, shipped function on EVERY path — valid, invalid, every
--      role, every capability combination.
--   C. It pins the security envelope: one indistinguishable invalid_session for
--      every failure, and no identifier of any kind in a success payload.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(27);

-- ---------------------------------------------------------------------------
-- Fixtures: one org / restaurant / branch, one paired device, and a PIN session
-- per scenario. A SECOND branch + a SECOND org exist so scope divergence is real.
-- ---------------------------------------------------------------------------
insert into organizations (id, name, slug, default_currency) values
  ('c1a00000-0000-0000-0000-0000000000a0', 'Cap Org A', 'cap001-a', 'USD'),
  ('c1b00000-0000-0000-0000-0000000000b0', 'Cap Org B', 'cap001-b', 'USD');
insert into restaurants (id, organization_id, name) values
  ('c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-0000000000a0', 'Cap Rest A1'),
  ('c1b00000-0000-0000-0000-0000000000b1', 'c1b00000-0000-0000-0000-0000000000b0', 'Cap Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'Cap Branch A1'),
  ('c1b00000-0000-0000-0000-00000000bb11', 'c1b00000-0000-0000-0000-0000000000b0', 'c1b00000-0000-0000-0000-0000000000b1', 'Cap Branch B1');

-- devices: d1 = the good one; d2 = will be REVOKED; d3 = pairing turned INACTIVE
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('c1a00000-0000-0000-0000-0000000d0a01', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'pos'),
  ('c1a00000-0000-0000-0000-0000000d0a02', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'pos'),
  ('c1a00000-0000-0000-0000-0000000d0a03', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'pos'),
  ('c1b00000-0000-0000-0000-0000000d0b01', 'c1b00000-0000-0000-0000-0000000000b0', 'c1b00000-0000-0000-0000-0000000000b1', 'c1b00000-0000-0000-0000-00000000bb11', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('c1a00000-0000-0000-0000-0000000f0a01', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000d0a01', 'active'),
  ('c1a00000-0000-0000-0000-0000000f0a02', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000d0a02', 'active'),
  ('c1a00000-0000-0000-0000-0000000f0a03', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000d0a03', 'active'),
  ('c1b00000-0000-0000-0000-0000000f0b01', 'c1b00000-0000-0000-0000-0000000000b0', 'c1b00000-0000-0000-0000-0000000000b1', 'c1b00000-0000-0000-0000-00000000bb11', 'c1b00000-0000-0000-0000-0000000d0b01', 'active');
-- All device sessions START active: a DB guard forbids opening a PIN session on a
-- dead one, so the revocations are applied BELOW — which is also the real-world
-- sequence (a device is revoked while a cashier is signed in on it).
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('c1a00000-0000-0000-0000-0000000500a1', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000d0a01', 'c1a00000-0000-0000-0000-0000000f0a01'),
  ('c1a00000-0000-0000-0000-0000000500a2', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000d0a02', 'c1a00000-0000-0000-0000-0000000f0a02'),
  ('c1a00000-0000-0000-0000-0000000500a3', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000d0a03', 'c1a00000-0000-0000-0000-0000000f0a03'),
  ('c1b00000-0000-0000-0000-0000000500b1', 'c1b00000-0000-0000-0000-0000000000b0', 'c1b00000-0000-0000-0000-0000000000b1', 'c1b00000-0000-0000-0000-00000000bb11', 'c1b00000-0000-0000-0000-0000000d0b01', 'c1b00000-0000-0000-0000-0000000f0b01');

insert into app_users (id, email) values
  ('c1a00000-0000-0000-0000-0000000000e1', 'cap-cashier-default@example.test'),
  ('c1a00000-0000-0000-0000-0000000000e2', 'cap-cashier-both@example.test'),
  ('c1a00000-0000-0000-0000-0000000000e3', 'cap-cashier-comp-only@example.test'),
  ('c1a00000-0000-0000-0000-0000000000e4', 'cap-manager@example.test'),
  ('c1a00000-0000-0000-0000-0000000000e5', 'cap-rest-owner@example.test'),
  ('c1a00000-0000-0000-0000-0000000000e6', 'cap-suspended@example.test'),
  ('c1b00000-0000-0000-0000-0000000000eb', 'cap-cashier-orgb@example.test');

-- CAPABILITY MODEL (unchanged by this hotfix):
--   apply_discount  — DENY-ONLY, DEFAULT ON  for a cashier: the KEY'S PRESENCE denies.
--   apply_full_comp — GRANT-ONLY, DEFAULT OFF for a cashier: only "true" grants.
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, status, permissions) values
  -- m1: a plain cashier, NO overrides at all -> discount ON (role default), comp OFF (no grant)
  ('c1a00000-0000-0000-0000-00000000ac01', 'c1a00000-0000-0000-0000-0000000000e1', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'cashier', 'active', '{}'::jsonb),
  -- m2: cashier explicitly GRANTED the comp -> both true
  ('c1a00000-0000-0000-0000-00000000ac02', 'c1a00000-0000-0000-0000-0000000000e2', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'cashier', 'active', '{"apply_full_comp":"true"}'::jsonb),
  -- m3: comp GRANTED but the general discount DENIED -> the grant is MOOT
  ('c1a00000-0000-0000-0000-00000000ac03', 'c1a00000-0000-0000-0000-0000000000e3', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'cashier', 'active', '{"apply_discount":"false","apply_full_comp":"true"}'::jsonb),
  ('c1a00000-0000-0000-0000-00000000ac04', 'c1a00000-0000-0000-0000-0000000000e4', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'manager', 'active', '{}'::jsonb),
  ('c1a00000-0000-0000-0000-00000000ac05', 'c1a00000-0000-0000-0000-0000000000e5', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'restaurant_owner', 'active', '{}'::jsonb),
  -- m6: membership that will be REVOKED below
  ('c1a00000-0000-0000-0000-00000000ac06', 'c1a00000-0000-0000-0000-0000000000e6', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'cashier', 'active', '{}'::jsonb),
  ('c1b00000-0000-0000-0000-00000000bc01', 'c1b00000-0000-0000-0000-0000000000eb', 'c1b00000-0000-0000-0000-0000000000b0', 'c1b00000-0000-0000-0000-0000000000b1', 'c1b00000-0000-0000-0000-00000000bb11', 'cashier', 'active', '{}'::jsonb);

insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('c1a00000-0000-0000-0000-00000000af01', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000000e1', 'c1a00000-0000-0000-0000-00000000ac01'),
  ('c1a00000-0000-0000-0000-00000000af02', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000000e2', 'c1a00000-0000-0000-0000-00000000ac02'),
  ('c1a00000-0000-0000-0000-00000000af03', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000000e3', 'c1a00000-0000-0000-0000-00000000ac03'),
  ('c1a00000-0000-0000-0000-00000000af04', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000000e4', 'c1a00000-0000-0000-0000-00000000ac04'),
  ('c1a00000-0000-0000-0000-00000000af05', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000000e5', 'c1a00000-0000-0000-0000-00000000ac05'),
  ('c1a00000-0000-0000-0000-00000000af06', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000000e6', 'c1a00000-0000-0000-0000-00000000ac06'),
  ('c1b00000-0000-0000-0000-00000000bf01', 'c1b00000-0000-0000-0000-0000000000b0', 'c1b00000-0000-0000-0000-0000000000b1', 'c1b00000-0000-0000-0000-00000000bb11', 'c1b00000-0000-0000-0000-0000000000eb', 'c1b00000-0000-0000-0000-00000000bc01');

insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at, is_active) values
  -- p1..p5: healthy sessions, one per persona, all on the GOOD device (d1)
  ('c1a00000-0000-0000-0000-00000000c501', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000500a1', 'c1a00000-0000-0000-0000-00000000af01', 'c1a00000-0000-0000-0000-00000000ac01', now() + interval '1 hour', true),
  ('c1a00000-0000-0000-0000-00000000c502', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000500a1', 'c1a00000-0000-0000-0000-00000000af02', 'c1a00000-0000-0000-0000-00000000ac02', now() + interval '1 hour', true),
  ('c1a00000-0000-0000-0000-00000000c503', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000500a1', 'c1a00000-0000-0000-0000-00000000af03', 'c1a00000-0000-0000-0000-00000000ac03', now() + interval '1 hour', true),
  ('c1a00000-0000-0000-0000-00000000c504', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000500a1', 'c1a00000-0000-0000-0000-00000000af04', 'c1a00000-0000-0000-0000-00000000ac04', now() + interval '1 hour', true),
  ('c1a00000-0000-0000-0000-00000000c505', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000500a1', 'c1a00000-0000-0000-0000-00000000af05', 'c1a00000-0000-0000-0000-00000000ac05', now() + interval '1 hour', true),
  -- p6: INACTIVE pin session   p7: EXPIRED pin session
  ('c1a00000-0000-0000-0000-00000000c506', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000500a1', 'c1a00000-0000-0000-0000-00000000af01', 'c1a00000-0000-0000-0000-00000000ac01', now() + interval '1 hour', false),
  ('c1a00000-0000-0000-0000-00000000c507', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000500a1', 'c1a00000-0000-0000-0000-00000000af01', 'c1a00000-0000-0000-0000-00000000ac01', now() - interval '1 hour', true),
  -- p8: on the device session that gets REVOKED   p9: on the pairing that goes INACTIVE
  ('c1a00000-0000-0000-0000-00000000c508', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000500a2', 'c1a00000-0000-0000-0000-00000000af01', 'c1a00000-0000-0000-0000-00000000ac01', now() + interval '1 hour', true),
  ('c1a00000-0000-0000-0000-00000000c509', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000500a3', 'c1a00000-0000-0000-0000-00000000af01', 'c1a00000-0000-0000-0000-00000000ac01', now() + interval '1 hour', true),
  -- p10: the membership that gets REVOKED
  ('c1a00000-0000-0000-0000-00000000c50a', 'c1a00000-0000-0000-0000-0000000000a0', 'c1a00000-0000-0000-0000-0000000000a1', 'c1a00000-0000-0000-0000-00000000ab11', 'c1a00000-0000-0000-0000-0000000500a1', 'c1a00000-0000-0000-0000-00000000af06', 'c1a00000-0000-0000-0000-00000000ac06', now() + interval '1 hour', true),
  -- pB: a healthy session in ORG B (cross-tenant probe target)
  ('c1b00000-0000-0000-0000-00000000c50b', 'c1b00000-0000-0000-0000-0000000000b0', 'c1b00000-0000-0000-0000-0000000000b1', 'c1b00000-0000-0000-0000-00000000bb11', 'c1b00000-0000-0000-0000-0000000500b1', 'c1b00000-0000-0000-0000-00000000bf01', 'c1b00000-0000-0000-0000-00000000bc01', now() + interval '1 hour', true);

-- Now break the things that must be broken (post-insert, as production does).
update device_sessions set is_active = false, revoked_at = now()
  where id = 'c1a00000-0000-0000-0000-0000000500a2';
update device_pairings set status = 'revoked'
  where id = 'c1a00000-0000-0000-0000-0000000f0a03';
update memberships set status = 'revoked'
  where id = 'c1a00000-0000-0000-0000-00000000ac06';


-- ===== A. THE DEFECT WAS REAL — proved BEHAVIOURALLY, not by grepping ==== 1-3
-- The old body's predicate is executed here against the LIVE schema. If `ps.status`
-- had ever existed, this would not raise — and the production function would have
-- worked. It raises 42703, which is exactly what every hosted call has been doing.
select throws_ok(
  'select ps.status from public.pin_sessions ps limit 1',
  '42703',
  null,
  'A1 the OLD predicate `ps.status` raises 42703 against the live schema — the production failure, reproduced'
);
select throws_ok(
  'select ds.status from public.device_sessions ds limit 1',
  '42703',
  null,
  'A2 the OLD predicate `ds.status` raises 42703 too — the defect was TWO columns, not one'
);
select ok(
  (select count(*) = 2 from information_schema.columns
    where table_schema = 'public'
      and ((table_name = 'pin_sessions' and column_name = 'is_active')
        or (table_name = 'device_sessions' and column_name = 'is_active'))),
  'A3 both tables really use `is_active` — the column the corrected body reads'
);


-- ===== B. THE FIXED FUNCTION IS CALLED, AND RETURNS ====================== 4-11
select is(app.pin_session_capabilities('c1a00000-0000-0000-0000-00000000c501','c1a00000-0000-0000-0000-0000000d0a01') ->> 'ok',
  'true', 'B1 a valid active PIN session returns ok=true (it returned NOTHING in production)');
select is(app.pin_session_capabilities('c1a00000-0000-0000-0000-00000000c501','c1a00000-0000-0000-0000-0000000d0a01') ->> 'role',
  'cashier', 'B2 ... and reports the role');
select is(app.pin_session_capabilities('c1a00000-0000-0000-0000-00000000c501','c1a00000-0000-0000-0000-0000000d0a01') -> 'capabilities' ->> 'apply_discount',
  'true', 'B3 a plain cashier holds apply_discount by ROLE DEFAULT (deny-only model)');
select is(app.pin_session_capabilities('c1a00000-0000-0000-0000-00000000c501','c1a00000-0000-0000-0000-0000000d0a01') -> 'capabilities' ->> 'apply_full_comp',
  'false', 'B4 a cashier with NO override resolves apply_full_comp=FALSE — the grant-only default');
-- The missing-key case must be FALSE, never NULL: a null would be neither true nor
-- false to the client and could read as "unknown" => not-denied => a fail-OPEN.
select is(jsonb_typeof(app.pin_session_capabilities('c1a00000-0000-0000-0000-00000000c501','c1a00000-0000-0000-0000-0000000d0a01') -> 'capabilities' -> 'apply_full_comp'),
  'boolean', 'B5 a MISSING apply_full_comp key yields a real BOOLEAN false, never NULL (a null would read as "unknown" and fail OPEN)');
select is(app.pin_session_capabilities('c1a00000-0000-0000-0000-00000000c502','c1a00000-0000-0000-0000-0000000d0a01') -> 'capabilities' ->> 'apply_full_comp',
  'true', 'B6 a cashier EXPLICITLY granted apply_full_comp gets it');
select is(app.pin_session_capabilities('c1a00000-0000-0000-0000-00000000c502','c1a00000-0000-0000-0000-0000000d0a01') -> 'capabilities' ->> 'apply_discount',
  'true', 'B7 ... and still holds apply_discount (both true)');
-- The comp grant is MOOT without the general discount right: the server's discount
-- gate refuses first, so the cashier cannot discount at all, let alone comp.
select is(app.pin_session_capabilities('c1a00000-0000-0000-0000-00000000c503','c1a00000-0000-0000-0000-0000000d0a01') -> 'capabilities' ->> 'apply_discount',
  'false', 'B8 apply_full_comp=true with apply_discount DENIED leaves the comp INEFFECTIVE — the discount gate refuses first');


-- ===== C. ROLE-DERIVED CAPABILITY IS UNCHANGED ========================== 12-15
select is(app.pin_session_capabilities('c1a00000-0000-0000-0000-00000000c504','c1a00000-0000-0000-0000-0000000d0a01') -> 'capabilities' ->> 'apply_discount',
  'true', 'C1 a MANAGER holds apply_discount by role');
select is(app.pin_session_capabilities('c1a00000-0000-0000-0000-00000000c504','c1a00000-0000-0000-0000-0000000d0a01') -> 'capabilities' ->> 'apply_full_comp',
  'true', 'C2 a MANAGER holds apply_full_comp by role (no grant needed)');
select is(app.pin_session_capabilities('c1a00000-0000-0000-0000-00000000c505','c1a00000-0000-0000-0000-0000000d0a01') -> 'capabilities' ->> 'apply_full_comp',
  'true', 'C3 a RESTAURANT_OWNER holds apply_full_comp by role');
select is(app.pin_session_capabilities('c1a00000-0000-0000-0000-00000000c505','c1a00000-0000-0000-0000-0000000d0a01') ->> 'role',
  'restaurant_owner', 'C4 ... and reports restaurant_owner');


-- ===== D. EVERY FAILURE => ONE INDISTINGUISHABLE invalid_session ======== 16-21
select is(app.pin_session_capabilities('c1a00000-0000-0000-0000-00000000c506','c1a00000-0000-0000-0000-0000000d0a01') ->> 'error',
  'invalid_session', 'D1 an INACTIVE pin session');
select is(app.pin_session_capabilities('c1a00000-0000-0000-0000-00000000c507','c1a00000-0000-0000-0000-0000000d0a01') ->> 'error',
  'invalid_session', 'D2 an EXPIRED pin session');
select is(app.pin_session_capabilities('c1a00000-0000-0000-0000-00000000c508','c1a00000-0000-0000-0000-0000000d0a02') ->> 'error',
  'invalid_session', 'D3 a REVOKED device session');
select is(app.pin_session_capabilities('c1a00000-0000-0000-0000-00000000c509','c1a00000-0000-0000-0000-0000000d0a03') ->> 'error',
  'invalid_session', 'D4 a REVOKED device PAIRING');
select is(app.pin_session_capabilities('c1a00000-0000-0000-0000-00000000c50a','c1a00000-0000-0000-0000-0000000d0a01') ->> 'error',
  'invalid_session', 'D5 a REVOKED membership');
select is(app.pin_session_capabilities('c1a00000-0000-0000-0000-00000000c501','c1a00000-0000-0000-0000-0000000d0a02') ->> 'error',
  'invalid_session', 'D6 a DEVICE MISMATCH (right session, wrong device)');


-- ===== E. No oracle, no leakage ========================================= 22-24
-- A caller in org A naming org B's session must learn NOTHING that distinguishes it
-- from a session that simply does not exist: the same envelope, byte for byte.
select is(
  app.pin_session_capabilities('c1b00000-0000-0000-0000-00000000c50b','c1a00000-0000-0000-0000-0000000d0a01')::text,
  app.pin_session_capabilities('00000000-0000-0000-0000-0000000000ff','c1a00000-0000-0000-0000-0000000d0a01')::text,
  'E1 a CROSS-TENANT session and a NON-EXISTENT one return the byte-identical envelope (no existence/scope oracle)'
);
-- A success payload must carry the role and two booleans — and nothing else. No
-- membership/employee/session/device UUID, no permissions JSON, no PIN material.
select is(
  (select array_agg(k order by k)
     from jsonb_object_keys(app.pin_session_capabilities('c1a00000-0000-0000-0000-00000000c502','c1a00000-0000-0000-0000-0000000d0a01')) k),
  array['capabilities','entity','ok','role'],
  'E2 a success payload exposes ONLY ok/entity/role/capabilities — no identifier, no permissions JSON'
);
select ok(
  app.pin_session_capabilities('c1a00000-0000-0000-0000-00000000c502','c1a00000-0000-0000-0000-0000000d0a01')::text
    not like '%c1a00000-0000-0000-0000-00000000ac02%'
  and app.pin_session_capabilities('c1a00000-0000-0000-0000-00000000c502','c1a00000-0000-0000-0000-0000000d0a01')::text
    not like '%apply_full_comp":"true%',
  'E3 neither the internal membership UUID nor the raw permissions JSON appears anywhere in the payload'
);


-- ===== F. ACLs unchanged by the repair ================================== 25-27
-- CREATE OR REPLACE with an unchanged signature preserves the ACL; the migration
-- re-asserts it anyway. Prove the end state rather than trusting either.
select ok(
  not has_function_privilege('public', 'app.pin_session_capabilities(uuid,uuid)', 'execute'),
  'F1 PUBLIC cannot execute app.pin_session_capabilities'
);
select ok(
  not has_function_privilege('anon', 'app.pin_session_capabilities(uuid,uuid)', 'execute'),
  'F2 anon cannot execute app.pin_session_capabilities'
);
-- authenticated IS intended: the POS reaches the public INVOKER wrapper with the anon
-- key + its PIN/device session, and the wrapper runs as the calling (authenticated)
-- role — so the inner app.* function must be executable by exactly that role.
select ok(
  has_function_privilege('authenticated', 'app.pin_session_capabilities(uuid,uuid)', 'execute'),
  'F3 authenticated CAN execute it — the intended POS path through the public wrapper'
);

select * from finish();
rollback;
