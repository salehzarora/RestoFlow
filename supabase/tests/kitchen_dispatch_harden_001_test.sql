-- ============================================================================
-- KITCHEN-DISPATCH-HARDEN-001 — fail-closed kitchen dispatch creation; dispatch
-- payloads carry live lines only (ORDER-EDIT slice 1, precursor for D-044).
--
-- 1. app.create_kitchen_dispatch has explicit initial_order / service_round /
--    void arms and RAISES 22023 before any write on anything else (or on a
--    NULL key). The old ELSE mapped every other type onto the order's
--    'void:<order>' key, where ON CONFLICT DO NOTHING would silently hand back
--    the real VOID dispatch's id.
-- 2. app.kitchen_dispatch_payload_initial / _round exclude voided and cancelled
--    lines. app.kitchen_dispatch_payload_void is NOT changed (the VOID slip
--    still counts every line of the order).
-- Known types, keys, supersession and idempotency are unchanged.
-- ============================================================================
begin;

set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(25);

-- ===== fixture ==============================================================
insert into organizations (id, name, slug, default_currency) values
  ('cd400000-0000-0000-0000-0000000000a0', 'Org KDH', 'org-kdh', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('cd400000-0000-0000-0000-0000000000a1', 'cd400000-0000-0000-0000-0000000000a0', 'Rest KDH');
insert into branches (id, organization_id, restaurant_id, name, kitchen_workflow_mode) values
  ('cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1', 'Branch KDH', 'printer_only');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('cd400000-0000-0000-0000-0000000000d1', 'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1', 'cd400000-0000-0000-0000-0000000000ab', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('cd400000-0000-0000-0000-0000000000f1', 'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1', 'cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-0000000000d1', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('cd400000-0000-0000-0000-00000000005a', 'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1', 'cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-0000000000d1', 'cd400000-0000-0000-0000-0000000000f1');
insert into app_users (id, email) values
  ('cd400000-0000-0000-0000-00000000006a', 'dispatch-harden@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('cd400000-0000-0000-0000-00000000007a', 'cd400000-0000-0000-0000-00000000006a', 'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1', 'cd400000-0000-0000-0000-0000000000ab', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('cd400000-0000-0000-0000-00000000008a', 'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1', 'cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-00000000006a', 'cd400000-0000-0000-0000-00000000007a');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('cd400000-0000-0000-0000-00000000009a', 'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1', 'cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-00000000005a', 'cd400000-0000-0000-0000-00000000008a', 'cd400000-0000-0000-0000-00000000007a', now() + interval '1 hour');

insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('cd400000-0000-0000-0000-0000000000c1', 'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1', null, 'Mains', 1),
  ('cd400000-0000-0000-0000-0000000000c2', 'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1', null, 'Sides', 2);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('cd400000-0000-0000-0000-000000001001', 'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1', null, 'cd400000-0000-0000-0000-0000000000c1', 'Burger', 4000, 'ILS', 1),
  ('cd400000-0000-0000-0000-000000001002', 'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1', null, 'cd400000-0000-0000-0000-0000000000c1', 'Salad',  3000, 'ILS', 2),
  ('cd400000-0000-0000-0000-000000001003', 'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1', null, 'cd400000-0000-0000-0000-0000000000c2', 'Fries',  1500, 'ILS', 1),
  ('cd400000-0000-0000-0000-000000001004', 'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1', null, 'cd400000-0000-0000-0000-0000000000c2', 'Cola',    800, 'ILS', 2);

insert into orders (
  id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
  opened_by_employee_profile_id, resolved_membership_id, order_type,
  currency_code, subtotal_minor, grand_total_minor, local_operation_id, status)
values (
  'cd400000-0000-0000-0000-00000000010a', 'cd400000-0000-0000-0000-0000000000a0',
  'cd400000-0000-0000-0000-0000000000a1', 'cd400000-0000-0000-0000-0000000000ab',
  'cd400000-0000-0000-0000-0000000000d1', 'cd400000-0000-0000-0000-00000000009a',
  'cd400000-0000-0000-0000-00000000008a', 'cd400000-0000-0000-0000-00000000007a',
  'takeaway', 'ILS', 9300, 9300, 'op-kdh-initial', 'submitted');
insert into order_service_rounds (
  id, organization_id, restaurant_id, branch_id, order_id, round_number,
  device_id, opened_by_employee_profile_id, status)
values (
  'cd400000-0000-0000-0000-00000000012a', 'cd400000-0000-0000-0000-0000000000a0',
  'cd400000-0000-0000-0000-0000000000a1', 'cd400000-0000-0000-0000-0000000000ab',
  'cd400000-0000-0000-0000-00000000010a', 2,
  'cd400000-0000-0000-0000-0000000000d1', 'cd400000-0000-0000-0000-00000000008a',
  'submitted');

-- Original ticket: Burger, Salad, Fries, Cola. Round 2: Burger, Fries, Cola.
-- All lines start LIVE; Salad / Cola (original) and Fries / Cola (round) are
-- retired below, after the "before" snapshots are taken.
insert into order_items (
  id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
  quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor,
  service_round_id)
values
  ('cd400000-0000-0000-0000-0000000100a1', 'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1', 'cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-00000000010a', 'cd400000-0000-0000-0000-000000001001', 1, 'Burger', 4000, 4000, null),
  ('cd400000-0000-0000-0000-0000000100a2', 'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1', 'cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-00000000010a', 'cd400000-0000-0000-0000-000000001002', 1, 'Salad',  3000, 3000, null),
  ('cd400000-0000-0000-0000-0000000100a3', 'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1', 'cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-00000000010a', 'cd400000-0000-0000-0000-000000001003', 1, 'Fries',  1500, 1500, null),
  ('cd400000-0000-0000-0000-0000000100a4', 'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1', 'cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-00000000010a', 'cd400000-0000-0000-0000-000000001004', 1, 'Cola',    800,  800, null),
  ('cd400000-0000-0000-0000-0000000100b1', 'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1', 'cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-00000000010a', 'cd400000-0000-0000-0000-000000001001', 1, 'Burger', 4000, 4000, 'cd400000-0000-0000-0000-00000000012a'),
  ('cd400000-0000-0000-0000-0000000100b2', 'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1', 'cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-00000000010a', 'cd400000-0000-0000-0000-000000001003', 1, 'Fries',  1500, 1500, 'cd400000-0000-0000-0000-00000000012a'),
  ('cd400000-0000-0000-0000-0000000100b3', 'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1', 'cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-00000000010a', 'cd400000-0000-0000-0000-000000001004', 1, 'Cola',    800,  800, 'cd400000-0000-0000-0000-00000000012a');

-- ===== A. definitions: posture unchanged, the hardening is present ==========
select ok(
  (select p.prosecdef and p.proconfig = array['search_path=""']
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'create_kitchen_dispatch'),
  'create_kitchen_dispatch stays SECURITY DEFINER with search_path=''''');

select ok(
  (select bool_and(not p.prosecdef and p.provolatile = 's'
                   and p.proconfig = array['search_path=""'])
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app'
      and p.proname in ('kitchen_dispatch_payload_initial', 'kitchen_dispatch_payload_round')),
  'both payload builders stay SECURITY INVOKER, STABLE, search_path=''''');

select ok(
  not has_function_privilege('anon', 'app.create_kitchen_dispatch(uuid, uuid, uuid, uuid, uuid, text, jsonb, uuid, uuid, uuid)', 'execute')
  and not has_function_privilege('authenticated', 'app.create_kitchen_dispatch(uuid, uuid, uuid, uuid, uuid, text, jsonb, uuid, uuid, uuid)', 'execute')
  and not has_function_privilege('anon', 'app.kitchen_dispatch_payload_initial(uuid, uuid)', 'execute')
  and not has_function_privilege('authenticated', 'app.kitchen_dispatch_payload_initial(uuid, uuid)', 'execute')
  and not has_function_privilege('anon', 'app.kitchen_dispatch_payload_round(uuid, uuid, uuid)', 'execute')
  and not has_function_privilege('authenticated', 'app.kitchen_dispatch_payload_round(uuid, uuid, uuid)', 'execute'),
  'all three functions stay INTERNAL-ONLY (no anon / authenticated execute)');

select ok(
  (select p.prosrc !~* 'else\s+''void:'''
      and p.prosrc ~* 'when\s+''void''\s+then\s+''void:'''
      and p.prosrc ~* 'using\s+errcode\s*=\s*''22023'''
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'create_kitchen_dispatch'),
  'create_kitchen_dispatch has an explicit void arm, no ELSE fallback, and a 22023 fail-closed raise');

select ok(
  (select bool_and(p.prosrc like '%oi.status not in (''voided'', ''cancelled'')%')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app'
      and p.proname in ('kitchen_dispatch_payload_initial', 'kitchen_dispatch_payload_round')),
  'both payload builders filter on oi.status not in (voided, cancelled)');

-- ===== B. payload builders: live lines only ================================
create temp table kdh_before as
  select app.kitchen_dispatch_payload_initial(
           'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-00000000010a') as initial_payload,
         app.kitchen_dispatch_payload_round(
           'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-00000000010a',
           'cd400000-0000-0000-0000-00000000012a') as round_payload;

select is(
  (select jsonb_path_query_array(initial_payload, '$.items[*].name') from kdh_before),
  '["Burger", "Salad", "Fries", "Cola"]'::jsonb,
  'all-live original ticket: every line, in canonical menu order (unchanged)');

select is(
  (select jsonb_path_query_array(round_payload, '$.items[*].name') from kdh_before),
  '["Burger", "Fries", "Cola"]'::jsonb,
  'all-live round ticket: every round line, in canonical menu order (unchanged)');

update order_items set status = 'voided'
  where id in ('cd400000-0000-0000-0000-0000000100a2', 'cd400000-0000-0000-0000-0000000100b2');
update order_items set status = 'cancelled'
  where id in ('cd400000-0000-0000-0000-0000000100a4', 'cd400000-0000-0000-0000-0000000100b3');

select is(
  jsonb_path_query_array(
    app.kitchen_dispatch_payload_initial(
      'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-00000000010a'),
    '$.items[*].name'),
  '["Burger", "Fries"]'::jsonb,
  'original ticket: the voided Salad and the cancelled Cola are excluded; order kept');

select is(
  jsonb_path_query_array(
    app.kitchen_dispatch_payload_round(
      'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-00000000010a',
      'cd400000-0000-0000-0000-00000000012a'),
    '$.items[*].name'),
  '["Burger"]'::jsonb,
  'round ticket: the voided Fries and the cancelled Cola are excluded');

select is(
  (app.kitchen_dispatch_payload_initial(
     'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-00000000010a') - 'items')
  , ((select initial_payload from kdh_before) - 'items'),
  'original ticket: every non-item key is byte-identical (shape unchanged)');

select is(
  (app.kitchen_dispatch_payload_round(
     'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-00000000010a',
     'cd400000-0000-0000-0000-00000000012a') - 'items')
  , ((select round_payload from kdh_before) - 'items'),
  'round ticket: every non-item key is byte-identical (shape unchanged)');

select is(
  (app.kitchen_dispatch_payload_void(
     'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-00000000010a', 'test')
   ->> 'affected_item_count')::int,
  7,
  'the VOID slip builder is unchanged: it still counts every line, voided and cancelled included');

-- ===== C. create_kitchen_dispatch: known types unchanged ====================
create temp table kdh_ids (k text primary key, id uuid);

insert into kdh_ids
  select 'initial', app.create_kitchen_dispatch(
    'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1',
    'cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-00000000010a',
    null, 'initial_order',
    app.kitchen_dispatch_payload_initial('cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-00000000010a'),
    'cd400000-0000-0000-0000-00000000008a', 'cd400000-0000-0000-0000-00000000007a',
    'cd400000-0000-0000-0000-0000000000d1');

select is(
  (select d.idempotency_key || '|' || d.dispatch_type from kitchen_print_dispatches d
    where d.id = (select id from kdh_ids where k = 'initial')),
  'initial:cd400000-0000-0000-0000-00000000010a|initial_order',
  'initial_order: key initial:<order> (unchanged)');

insert into kdh_ids
  select 'round', app.create_kitchen_dispatch(
    'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1',
    'cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-00000000010a',
    'cd400000-0000-0000-0000-00000000012a', 'service_round',
    app.kitchen_dispatch_payload_round('cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-00000000010a', 'cd400000-0000-0000-0000-00000000012a'),
    'cd400000-0000-0000-0000-00000000008a', 'cd400000-0000-0000-0000-00000000007a',
    'cd400000-0000-0000-0000-0000000000d1');

select is(
  (select d.idempotency_key || '|' || d.dispatch_type from kitchen_print_dispatches d
    where d.id = (select id from kdh_ids where k = 'round')),
  'round:cd400000-0000-0000-0000-00000000012a|service_round',
  'service_round: key round:<round> (unchanged)');

insert into kdh_ids
  select 'void', app.create_kitchen_dispatch(
    'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1',
    'cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-00000000010a',
    null, 'void',
    app.kitchen_dispatch_payload_void('cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-00000000010a', 'test'),
    'cd400000-0000-0000-0000-00000000008a', 'cd400000-0000-0000-0000-00000000007a',
    'cd400000-0000-0000-0000-0000000000d1');

select is(
  (select d.idempotency_key || '|' || d.dispatch_type from kitchen_print_dispatches d
    where d.id = (select id from kdh_ids where k = 'void')),
  'void:cd400000-0000-0000-0000-00000000010a|void',
  'void: key void:<order> through the new explicit arm');

select is(
  (select count(*)::int from kitchen_print_dispatches d
    where d.order_id = 'cd400000-0000-0000-0000-00000000010a'
      and d.dispatch_type in ('initial_order', 'service_round')
      and d.superseded_by_dispatch_id = (select id from kdh_ids where k = 'void')),
  2,
  'void still supersedes every unresolved prior dispatch of the order (CORRECTION-001 unchanged)');

select is(
  app.create_kitchen_dispatch(
    'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1',
    'cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-00000000010a',
    null, 'void',
    app.kitchen_dispatch_payload_void('cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-00000000010a', 'test'),
    'cd400000-0000-0000-0000-00000000008a', 'cd400000-0000-0000-0000-00000000007a',
    'cd400000-0000-0000-0000-0000000000d1'),
  (select id from kdh_ids where k = 'void'),
  'an idempotent void retry returns the same row (unchanged)');

select is(
  (select count(*)::int from audit_events a
    where a.organization_id = 'cd400000-0000-0000-0000-0000000000a0'
      and a.action in ('kitchen.dispatch_created', 'kitchen.dispatch_void_created')),
  3,
  'three logical dispatches, three audit rows: the retry did not re-audit (unchanged)');

-- ===== D. create_kitchen_dispatch: FAIL CLOSED ==============================
-- Simulate the moment ORDER-EDIT-001A widens the dispatch_type CHECK to admit
-- 'order_edit' (rolled back with the test). Before this slice, the CHECK was
-- the only thing stopping the old ELSE from mapping such a type onto the
-- order's 'void:<order>' key; with the CHECK widened, the pre-hardening body
-- silently returned the real VOID's id (asserts 19) or squatted the VOID key on
-- a fresh order so the later real void never got its own row (asserts 23-25).
alter table kitchen_print_dispatches
  drop constraint kitchen_print_dispatches_dispatch_type_check;
alter table kitchen_print_dispatches
  add constraint kitchen_print_dispatches_dispatch_type_check
  check (dispatch_type in ('initial_order', 'service_round', 'void', 'order_edit'));

select throws_ok(
  $$select app.create_kitchen_dispatch(
      'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1',
      'cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-00000000010a',
      null, 'order_edit', '{"v":1}'::jsonb,
      'cd400000-0000-0000-0000-00000000008a', 'cd400000-0000-0000-0000-00000000007a',
      'cd400000-0000-0000-0000-0000000000d1')$$,
  '22023', null,
  'an unsupported type RAISES 22023 — it never collapses onto the order''s existing void:<order> row');

select throws_ok(
  $$select app.create_kitchen_dispatch(
      'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1',
      'cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-00000000010a',
      null, null, '{"v":1}'::jsonb,
      'cd400000-0000-0000-0000-00000000008a', 'cd400000-0000-0000-0000-00000000007a',
      'cd400000-0000-0000-0000-0000000000d1')$$,
  '22023', null,
  'a NULL type RAISES 22023');

select throws_ok(
  $$select app.create_kitchen_dispatch(
      'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1',
      'cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-00000000010a',
      null, 'service_round', '{"v":1}'::jsonb,
      'cd400000-0000-0000-0000-00000000008a', 'cd400000-0000-0000-0000-00000000007a',
      'cd400000-0000-0000-0000-0000000000d1')$$,
  '22023', null,
  'a service_round without a round id (NULL key) RAISES 22023');

select throws_ok(
  $$select app.create_kitchen_dispatch(
      'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1',
      'cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-00000000010a',
      null, 'VOID', '{"v":1}'::jsonb,
      'cd400000-0000-0000-0000-00000000008a', 'cd400000-0000-0000-0000-00000000007a',
      'cd400000-0000-0000-0000-0000000000d1')$$,
  '22023', null,
  'type matching is exact: ''VOID'' is not ''void'' and RAISES 22023');

-- A second, fresh order with no dispatch yet: an unsupported type must not
-- squat its void:<order> key ahead of the real void.
insert into orders (
  id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
  opened_by_employee_profile_id, resolved_membership_id, order_type,
  currency_code, subtotal_minor, grand_total_minor, local_operation_id, status)
values (
  'cd400000-0000-0000-0000-00000000020a', 'cd400000-0000-0000-0000-0000000000a0',
  'cd400000-0000-0000-0000-0000000000a1', 'cd400000-0000-0000-0000-0000000000ab',
  'cd400000-0000-0000-0000-0000000000d1', 'cd400000-0000-0000-0000-00000000009a',
  'cd400000-0000-0000-0000-00000000008a', 'cd400000-0000-0000-0000-00000000007a',
  'takeaway', 'ILS', 0, 0, 'op-kdh-second', 'submitted');

select throws_ok(
  $$select app.create_kitchen_dispatch(
      'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1',
      'cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-00000000020a',
      null, 'order_edit', '{"v":1}'::jsonb,
      'cd400000-0000-0000-0000-00000000008a', 'cd400000-0000-0000-0000-00000000007a',
      'cd400000-0000-0000-0000-0000000000d1')$$,
  '22023', null,
  'fresh order: an unsupported type RAISES 22023 instead of squatting the void:<order> key');

-- (two statements: the dispatch row inserted by the call is visible only to a
--  LATER statement's snapshot)
insert into kdh_ids
  select 'void2', app.create_kitchen_dispatch(
    'cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-0000000000a1',
    'cd400000-0000-0000-0000-0000000000ab', 'cd400000-0000-0000-0000-00000000020a',
    null, 'void',
    app.kitchen_dispatch_payload_void('cd400000-0000-0000-0000-0000000000a0', 'cd400000-0000-0000-0000-00000000020a', 'test'),
    'cd400000-0000-0000-0000-00000000008a', 'cd400000-0000-0000-0000-00000000007a',
    'cd400000-0000-0000-0000-0000000000d1');

select is(
  (select d.dispatch_type || '|' || d.idempotency_key
     from kitchen_print_dispatches d
    where d.id = (select id from kdh_ids where k = 'void2')),
  'void|void:cd400000-0000-0000-0000-00000000020a',
  'the later real void gets its OWN void row (not a squatted row of another type)');

select is(
  (select count(*)::int from kitchen_print_dispatches d
    where d.organization_id = 'cd400000-0000-0000-0000-0000000000a0'
      and d.idempotency_key like 'void:%'
      and d.dispatch_type <> 'void'),
  0,
  'no row of any other type ever holds a void:<order> key');

select * from finish();
rollback;
