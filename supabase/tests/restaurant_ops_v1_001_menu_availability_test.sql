-- ============================================================================
-- RESTAURANT-OPERATIONS-V1-001 — pgTAP: branch-scoped menu item availability
-- ============================================================================
-- Covers: manager sets sold_out/paused/available (state changes + audit rows
-- with before/after + the structured reason in the reason column); no_change
-- calls write NO audit row; cashier denial (permission_denied + committed
-- denial audit, NO success audit); a branch-scoped manager cannot write a
-- SIBLING branch (42501 — cross-branch mutation unreachable); shape errors
-- (unavailable without reason / bad tokens) raise 42501; a branch-pinned
-- sibling item and a tombstoned item are not_found (no cross-branch leak,
-- R-003); pos_menu KEEPS unavailable items in the payload tagged with
-- availability+reason for the SESSION branch only; list_menu carries the keys
-- only when a branch is requested; direct DML is RLS-denied; the reason-shape
-- CHECK and one-row-per-(branch,item) UNIQUE hold at the DB layer (D-012
-- layer 4); ACLs: PUBLIC/anon nothing, authenticated execute, wrapper INVOKER.
-- Fixtures inserted as the BYPASSRLS connection role; hex-only UUIDs.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(37);

-- ===== fixture: org A — Rest A1, branches B1 + B2; owner/managerB1/cashier ===
insert into organizations (id, name, slug, default_currency) values
  ('7a000000-0000-0000-0000-0000000000a0', 'Org A', 'ropsv1-a', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', 'Branch B1'),
  ('7a000000-0000-0000-0000-00000000a1b2', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', 'Branch B2');
insert into app_users (id, email) values
  ('7a000000-0000-0000-0000-00000000ee01', 'ropsv1-owner@example.test'),
  ('7a000000-0000-0000-0000-00000000ee02', 'ropsv1-manager-b1@example.test'),
  ('7a000000-0000-0000-0000-00000000ee03', 'ropsv1-cashier@example.test'),
  ('7a000000-0000-0000-0000-00000000ee05', 'ropsv1-nobody@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('7a000000-0000-0000-0000-00000000ab01', '7a000000-0000-0000-0000-00000000ee01', '7a000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('7a000000-0000-0000-0000-00000000ab02', '7a000000-0000-0000-0000-00000000ee02', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-00000000a1b1', 'manager'),
  ('7a000000-0000-0000-0000-00000000ab03', '7a000000-0000-0000-0000-00000000ee03', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-00000000a1b1', 'cashier');

-- menu: one restaurant-wide category; I1 global live, I2 pinned to B2, I3 tombstoned.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('7a000000-0000-0000-0000-00000000ca01', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', null, 'Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order, is_active, deleted_at) values
  ('7a000000-0000-0000-0000-0000000000f1', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', null,
   '7a000000-0000-0000-0000-00000000ca01', 'Falafel', 2500, 'ILS', 1, true, null),
  ('7a000000-0000-0000-0000-0000000000f2', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-00000000a1b2',
   '7a000000-0000-0000-0000-00000000ca01', 'B2 Special', 3000, 'ILS', 2, true, null),
  ('7a000000-0000-0000-0000-0000000000f3', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', null,
   '7a000000-0000-0000-0000-00000000ca01', 'Retired', 1000, 'ILS', 3, true, now());

-- device stack on B1 (for the pos_menu session read): POS device + cashier PIN session.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('7a000000-0000-0000-0000-00000000da11', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('7a000000-0000-0000-0000-00000000fa11', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('7a000000-0000-0000-0000-0000000005a1', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-00000000da11', '7a000000-0000-0000-0000-00000000fa11');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('7a000000-0000-0000-0000-0000000ef003', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-00000000ee03', '7a000000-0000-0000-0000-00000000ab03');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('7a000000-0000-0000-0000-00000000c501', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-0000000005a1', '7a000000-0000-0000-0000-0000000ef003', '7a000000-0000-0000-0000-00000000ab03', now() + interval '1 hour');

-- ===== (1-5) manager (B1-scoped) marks Falafel SOLD OUT in B1 ================
set local role authenticated;
set local app.current_app_user_id = '7a000000-0000-0000-0000-00000000ee02';
create temp table t_set1 as select app.menu_set_item_availability(
  '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
  '7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-0000000000f1',
  'unavailable', 'sold_out') as res;
reset role;
select is((select (res->>'ok')::boolean from t_set1), true, 'manager can mark a live item unavailable in her branch');
select is((select res->>'availability' from t_set1), 'unavailable', 'the envelope reports availability=unavailable');
select is((select res->>'reason' from t_set1), 'sold_out', 'the envelope reports reason=sold_out');
select is(
  (select (availability, reason)::text from menu_item_branch_availability
    where organization_id = '7a000000-0000-0000-0000-0000000000a0'
      and branch_id = '7a000000-0000-0000-0000-00000000a1b1'
      and menu_item_id = '7a000000-0000-0000-0000-0000000000f1'),
  '(unavailable,sold_out)', 'exactly the (unavailable, sold_out) override row is stored');
select is(
  (select count(*)::int from menu_item_branch_availability
    where organization_id = '7a000000-0000-0000-0000-0000000000a0'),
  1, 'exactly ONE override row exists (one row per branch+item)');

-- ===== (6-9) the audit row: before/after + structured reason =================
select is(
  (select count(*)::int from audit_events
    where organization_id = '7a000000-0000-0000-0000-0000000000a0'
      and action = 'menu.menu_item.availability_changed'),
  1, 'exactly one availability_changed audit row was written');
select is(
  (select old_values from audit_events
    where organization_id = '7a000000-0000-0000-0000-0000000000a0'
      and action = 'menu.menu_item.availability_changed'),
  jsonb_build_object('availability', 'available', 'availability_reason', null),
  'BEFORE = {available, reason null} (absence of a row is available)');
select is(
  (select (new_values->>'availability') || '|' || (new_values->>'availability_reason') || '|' || (new_values->>'item_name')
     from audit_events
    where organization_id = '7a000000-0000-0000-0000-0000000000a0'
      and action = 'menu.menu_item.availability_changed'),
  'unavailable|sold_out|Falafel',
  'AFTER carries availability + reason + the item name');
select is(
  (select reason || '|' || branch_id::text from audit_events
    where organization_id = '7a000000-0000-0000-0000-0000000000a0'
      and action = 'menu.menu_item.availability_changed'),
  'sold_out|7a000000-0000-0000-0000-00000000a1b1',
  'the reason COLUMN carries the structured token and the row is branch-scoped');

-- ===== (10-12) POS read: unavailable item STAYS visible, session branch only =
create temp table t_pos as select app.pos_menu(
  '7a000000-0000-0000-0000-00000000c501', '7a000000-0000-0000-0000-00000000da11') as res;
select is(
  (select e->>'availability' || '|' || coalesce(e->>'availability_reason', 'NULL')
     from t_pos, jsonb_array_elements(res->'items') e
    where e->>'id' = '7a000000-0000-0000-0000-0000000000f1'),
  'unavailable|sold_out',
  'pos_menu KEEPS the sold-out item in the payload, tagged unavailable+sold_out');
select is(
  (select count(*) from t_pos, jsonb_array_elements(res->'items') e
    where e->>'id' = '7a000000-0000-0000-0000-0000000000f1'
      and e ? 'base_price_minor')::int,
  1, 'the unavailable item still carries its price (cashier surface unchanged)');
select is(
  (select count(*) from t_pos, jsonb_array_elements(res->'items') e
    where e->>'availability' is null)::int,
  0, 'every pos_menu item row carries an availability value');

-- ===== (13-15) list_menu: keys only when a branch is requested ===============
set local role authenticated;
set local app.current_app_user_id = '7a000000-0000-0000-0000-00000000ee01';
create temp table t_lm_b1 as select app.list_menu(
  '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
  '7a000000-0000-0000-0000-00000000a1b1') as res;
create temp table t_lm_b2 as select app.list_menu(
  '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
  '7a000000-0000-0000-0000-00000000a1b2') as res;
create temp table t_lm_all as select app.list_menu(
  '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', null) as res;
reset role;
select is(
  (select e->>'availability' || '|' || coalesce(e->>'availability_reason', 'NULL')
     from t_lm_b1, jsonb_array_elements(res->'items') e
    where e->>'id' = '7a000000-0000-0000-0000-0000000000f1'),
  'unavailable|sold_out', 'list_menu(B1) shows the B1 override on the item');
select is(
  (select e->>'availability' from t_lm_b2, jsonb_array_elements(res->'items') e
    where e->>'id' = '7a000000-0000-0000-0000-0000000000f1'),
  'available', 'list_menu(B2) shows the SAME item available — the override is branch-isolated');
select is(
  (select count(*) from t_lm_all, jsonb_array_elements(res->'items') e
    where e ? 'availability')::int,
  0, 'list_menu with NO branch carries NO availability keys (no single truthful answer)');

-- ===== (16-18) reason change + no_change idempotence =========================
set local role authenticated;
set local app.current_app_user_id = '7a000000-0000-0000-0000-00000000ee02';
create temp table t_set2 as select app.menu_set_item_availability(
  '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
  '7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-0000000000f1',
  'unavailable', 'paused') as res;
create temp table t_set2b as select app.menu_set_item_availability(
  '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
  '7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-0000000000f1',
  'unavailable', 'paused') as res;
reset role;
select is(
  (select old_values->>'availability_reason' || '>' || (new_values->>'availability_reason') from audit_events
    where organization_id = '7a000000-0000-0000-0000-0000000000a0'
      and action = 'menu.menu_item.availability_changed'
      and new_values->>'availability_reason' = 'paused'),
  'sold_out>paused', 'a reason change audits sold_out -> paused with honest before/after');
select is((select (res->>'no_change')::boolean from t_set2b), true,
  'repeating the same state returns ok + no_change');
select is(
  (select count(*)::int from audit_events
    where organization_id = '7a000000-0000-0000-0000-0000000000a0'
      and action = 'menu.menu_item.availability_changed'),
  2, 'the no_change call wrote NO third audit row');

-- ===== (19-21) back to available: reason cleared =============================
set local role authenticated;
set local app.current_app_user_id = '7a000000-0000-0000-0000-00000000ee02';
create temp table t_set3 as select app.menu_set_item_availability(
  '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
  '7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-0000000000f1',
  'available', 'sold_out') as res;  -- a stray reason on available is CLEARED, not stored
reset role;
select is((select (res->>'ok')::boolean from t_set3), true, 're-enabling succeeds');
select is(
  (select availability || '|' || coalesce(reason, 'NULL') from menu_item_branch_availability
    where organization_id = '7a000000-0000-0000-0000-0000000000a0'
      and menu_item_id = '7a000000-0000-0000-0000-0000000000f1'),
  'available|NULL', 'available never stores a reason (stray client reason cleared)');
select is(
  (select new_values from audit_events
    where organization_id = '7a000000-0000-0000-0000-0000000000a0'
      and action = 'menu.menu_item.availability_changed'
      and new_values->>'availability' = 'available'),
  jsonb_build_object('availability', 'available', 'availability_reason', null,
                     'item_name', 'Falafel',
                     'menu_item_id', '7a000000-0000-0000-0000-0000000000f1'),
  'the re-enable audit AFTER = {available, reason null} + item identity');

-- ===== (22-24) authorization: cashier denied, sibling-branch manager 42501 ===
set local role authenticated;
set local app.current_app_user_id = '7a000000-0000-0000-0000-00000000ee03';
create temp table t_deny as select app.menu_set_item_availability(
  '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
  '7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-0000000000f1',
  'unavailable', 'sold_out') as res;
reset role;
select is((select res->>'error' from t_deny), 'permission_denied',
  'a cashier (covering member below manager) gets a typed permission_denied');
select is(
  (select count(*)::int from audit_events
    where organization_id = '7a000000-0000-0000-0000-0000000000a0'
      and action = 'menu.menu_item.availability_denied'),
  1, 'the denial is audited (availability_denied)');
select is(
  (select count(*)::int from audit_events
    where organization_id = '7a000000-0000-0000-0000-0000000000a0'
      and action = 'menu.menu_item.availability_changed'),
  3, 'the denied attempt wrote NO success audit row (still exactly 3)');

-- (24b/25) a B1-scoped manager has NO authority over sibling branch B2 -> 42501.
set local role authenticated;
set local app.current_app_user_id = '7a000000-0000-0000-0000-00000000ee02';
select throws_ok(
  $$select app.menu_set_item_availability(
      '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
      '7a000000-0000-0000-0000-00000000a1b2', '7a000000-0000-0000-0000-0000000000f1',
      'unavailable', 'sold_out')$$,
  '42501', null,
  'a branch-scoped manager cannot flip availability in a SIBLING branch (42501)');
reset role;
set local role authenticated;
set local app.current_app_user_id = '7a000000-0000-0000-0000-00000000ee05';
select throws_ok(
  $$select app.menu_set_item_availability(
      '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
      '7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-0000000000f1',
      'unavailable', 'sold_out')$$,
  '42501', null,
  'a non-member gets 42501 (fail closed)');
reset role;

-- ===== (26-28) shape errors raise 42501 ======================================
set local role authenticated;
set local app.current_app_user_id = '7a000000-0000-0000-0000-00000000ee02';
select throws_ok(
  $$select app.menu_set_item_availability(
      '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
      '7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-0000000000f1',
      'unavailable', null)$$,
  '42501', null, 'unavailable WITHOUT a structured reason is a 42501 shape error');
select throws_ok(
  $$select app.menu_set_item_availability(
      '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
      '7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-0000000000f1',
      'unavailable', 'ran_out_of_vibes')$$,
  '42501', null, 'a free-form reason is refused (structured tokens only)');
select throws_ok(
  $$select app.menu_set_item_availability(
      '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
      '7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-0000000000f1',
      'sold_out', null)$$,
  '42501', null, 'availability itself must be available|unavailable');
reset role;

-- ===== (29-31) target item rules: pinned sibling / tombstoned / unknown ======
set local role authenticated;
set local app.current_app_user_id = '7a000000-0000-0000-0000-00000000ee01';
create temp table t_nf as select
  app.menu_set_item_availability(
    '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
    '7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-0000000000f2',
    'unavailable', 'sold_out') as pinned,
  app.menu_set_item_availability(
    '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
    '7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-0000000000f3',
    'unavailable', 'sold_out') as dead,
  app.menu_set_item_availability(
    '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
    '7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-00000000beef',
    'unavailable', 'sold_out') as unknown;
reset role;
select is((select pinned->>'error' from t_nf), 'not_found',
  'an item PINNED to a sibling branch cannot receive an override here (not_found — no leak)');
select is((select dead->>'error' from t_nf), 'not_found',
  'a tombstoned item is not_found');
select is((select unknown->>'error' from t_nf), 'not_found',
  'an unknown item id is not_found');

-- ===== (32-33) DB layer: RLS denies direct writes; constraints hold ==========
set local role authenticated;
set local app.current_app_user_id = '7a000000-0000-0000-0000-00000000ee01';
select throws_ok(
  $$insert into public.menu_item_branch_availability
      (organization_id, restaurant_id, branch_id, menu_item_id, availability, reason)
    values ('7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
            '7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-0000000000f1',
            'unavailable', 'sold_out')$$,
  '42501', null, 'direct INSERT as authenticated is RLS/grant-denied (writes are RPC-only)');
reset role;
select throws_ok(
  $$insert into menu_item_branch_availability
      (organization_id, restaurant_id, branch_id, menu_item_id, availability, reason)
    values ('7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
            '7a000000-0000-0000-0000-00000000a1b2', '7a000000-0000-0000-0000-0000000000f1',
            'unavailable', null)$$,
  '23514', null, 'the reason-shape CHECK holds at the DB layer (unavailable requires a reason)');

-- ===== (34-36) ACL + wrapper posture =========================================
select ok(
  not has_function_privilege('anon',
    'app.menu_set_item_availability(uuid, uuid, uuid, uuid, text, text)', 'execute')
  and not has_function_privilege('anon',
    'public.menu_set_item_availability(uuid, uuid, uuid, uuid, text, text)', 'execute'),
  'anon (and PUBLIC through it) cannot execute the availability mutation');
select ok(
  has_function_privilege('authenticated',
    'app.menu_set_item_availability(uuid, uuid, uuid, uuid, text, text)', 'execute')
  and has_function_privilege('authenticated',
    'public.menu_set_item_availability(uuid, uuid, uuid, uuid, text, text)', 'execute'),
  'authenticated can execute both the app function and the public wrapper');
select ok(
  (select p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'menu_set_item_availability')
  and not (select p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'menu_set_item_availability'),
  'app fn is SECURITY DEFINER; the public wrapper is SECURITY INVOKER');

select * from finish();
rollback;
