-- ============================================================================
-- KITCHEN-MODIFIER-PREP-CLASSIFIER-019 - pgTAP.
-- ============================================================================
-- THE DEFECT, proven at the SQL boundary.
--
--   Saleh's meat comes from the selected SIZE option through the existing
--   per-option contribution (order_item_modifiers.meat_snapshot), NOT from a
--   product-level preparation resource. But app.kitchen_dispatch_payload_initial
--   and _round projected every modifier as {qty, name} ONLY - meat_snapshot has
--   never reached the durable dispatch payload. Moving the meat onto the size
--   option would therefore make it VANISH from the printer-only ticket the
--   kitchen actually receives after a crash or a retry.
--
-- This suite pins the corrected contract:
--   * the new app.kitchen_modifier_prep_projection allowlist (5 keys, hard type
--     guards, all-or-nothing classifier, fail-safe degradation),
--   * both dispatch builders carrying it on every modifier,
--   * the 017 canonical menu ordering and ticket scope untouched,
--   * the INTERNAL-only ACL / search_path posture.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(59);

-- ---------------------------------------------------------------------------
-- 1. The new projection exists with the expected posture.
-- ---------------------------------------------------------------------------
select has_function('app', 'kitchen_modifier_prep_projection', array['jsonb'],
  'app.kitchen_modifier_prep_projection(jsonb) exists');

select is(
  (select p.provolatile from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'kitchen_modifier_prep_projection'),
  'i'::"char",
  'the modifier projection is IMMUTABLE');

select is(
  (select p.prosecdef from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'kitchen_modifier_prep_projection'),
  false,
  'the modifier projection is NOT security definer (a pure helper)');

select is(
  (select p.proconfig::text from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'kitchen_modifier_prep_projection'),
  '{"search_path=\"\""}',
  'the modifier projection pins an EMPTY search_path');

select ok(
  not has_function_privilege('public', 'app.kitchen_modifier_prep_projection(jsonb)', 'EXECUTE'),
  'PUBLIC cannot execute the modifier projection');
select ok(
  not has_function_privilege('anon', 'app.kitchen_modifier_prep_projection(jsonb)', 'EXECUTE'),
  'anon cannot execute the modifier projection');
select ok(
  not has_function_privilege('authenticated', 'app.kitchen_modifier_prep_projection(jsonb)', 'EXECUTE'),
  'authenticated cannot execute the modifier projection');

-- The 017 functions keep their posture after the re-emission.
select ok(
  not has_function_privilege('anon', 'app.kitchen_dispatch_payload_initial(uuid, uuid)', 'EXECUTE'),
  'anon still cannot execute the initial payload builder');
select ok(
  not has_function_privilege('anon', 'app.kitchen_dispatch_payload_round(uuid, uuid, uuid)', 'EXECUTE'),
  'anon still cannot execute the round payload builder');
select ok(
  not has_function_privilege('authenticated', 'app.kitchen_dispatch_payload_initial(uuid, uuid)', 'EXECUTE'),
  'authenticated still cannot execute the initial payload builder');
select is(
  (select p.proconfig::text from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'kitchen_dispatch_payload_initial'),
  '{"search_path=\"\""}',
  'the initial builder still pins an EMPTY search_path');
select is(
  (select p.prosecdef from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'kitchen_dispatch_payload_round'),
  false,
  'the round builder is still NOT security definer');

-- ---------------------------------------------------------------------------
-- 2. THE FIX: a complete, well-typed contribution survives.
-- ---------------------------------------------------------------------------
select is(
  app.kitchen_modifier_prep_projection('{
    "quantity":2,"unit":"Meat pieces",
    "classifier_option_id":"opt-cheese",
    "classifier_option_name":"Cheese",
    "classifier_selected":true}'::jsonb),
  '{"quantity":2,"unit":"Meat pieces",
    "classifier_option_id":"opt-cheese",
    "classifier_option_name":"Cheese",
    "classifier_selected":true}'::jsonb,
  'a complete contribution + classifier survives the projection');

select is(
  app.kitchen_modifier_prep_projection('{
    "quantity":2,"unit":"Meat pieces",
    "classifier_option_id":"o","classifier_option_name":"Cheese",
    "classifier_selected":false}'::jsonb) -> 'classifier_selected',
  'false'::jsonb,
  'the WITHOUT bucket survives as boolean false, not as an absent key');

select is(
  app.kitchen_modifier_prep_projection('{
    "quantity":2,"unit":"قطع لحم",
    "classifier_option_id":"o","classifier_option_name":"جبنة",
    "classifier_selected":true}'::jsonb) -> 'classifier_option_name',
  '"جبنة"'::jsonb,
  'Arabic classifier names survive unmangled');

select is(
  app.kitchen_modifier_prep_projection('{"quantity":2,"unit":"Meat pieces"}'::jsonb),
  '{"quantity":2,"unit":"Meat pieces"}'::jsonb,
  'a LEGACY meat_snapshot projects unchanged (no classifier keys)');

select is(
  app.kitchen_modifier_prep_projection('{"quantity":1.5,"unit":"kg"}'::jsonb),
  '{"quantity":1.5,"unit":"kg"}'::jsonb,
  'a fractional contribution projects');

-- ---------------------------------------------------------------------------
-- 3. FAIL SAFE: nothing to contribute -> NULL (the modifier omits the key).
-- ---------------------------------------------------------------------------
select is(app.kitchen_modifier_prep_projection(null::jsonb), null::jsonb,
  'NULL meat_snapshot projects NULL');
select is(app.kitchen_modifier_prep_projection('[]'::jsonb), null::jsonb,
  'a non-object projects NULL');
select is(app.kitchen_modifier_prep_projection('{}'::jsonb), null::jsonb,
  'an empty object projects NULL');
select is(app.kitchen_modifier_prep_projection('{"quantity":0}'::jsonb), null::jsonb,
  'a ZERO quantity projects NULL (nothing is contributed)');
select is(app.kitchen_modifier_prep_projection('{"quantity":-2}'::jsonb), null::jsonb,
  'a NEGATIVE quantity projects NULL');
select is(app.kitchen_modifier_prep_projection('{"quantity":"2"}'::jsonb), null::jsonb,
  'a STRING quantity is not a number -> NULL');

-- 020 (Codex HIGH #3) — THE OUTER GATE. 019 emitted a phantom {"unit":"..."}
-- whenever the quantity was absent or unusable: jsonb_strip_nulls removed the
-- quantity and the unit alone survived, so a durable ticket could print a
-- bullet with a resource and no count. Both parts are now required.
select is(
  app.kitchen_modifier_prep_projection('{"unit":"Meat pieces"}'::jsonb),
  null::jsonb,
  'GATE: a MISSING quantity yields NULL, never a unit-only contribution');
select is(
  app.kitchen_modifier_prep_projection('{"quantity":0,"unit":"Meat pieces"}'::jsonb),
  null::jsonb,
  'GATE: a ZERO quantity with a valid unit yields NULL');
select is(
  app.kitchen_modifier_prep_projection('{"quantity":-1,"unit":"Meat pieces"}'::jsonb),
  null::jsonb,
  'GATE: a NEGATIVE quantity with a valid unit yields NULL');
select is(
  app.kitchen_modifier_prep_projection('{"quantity":"oops","unit":"Meat pieces"}'::jsonb),
  null::jsonb,
  'GATE: a NON-NUMERIC quantity with a valid unit yields NULL');
select is(
  app.kitchen_modifier_prep_projection('{"quantity":null,"unit":"Meat pieces"}'::jsonb),
  null::jsonb,
  'GATE: an explicit NULL quantity yields NULL');
select is(
  app.kitchen_modifier_prep_projection('{"quantity":2}'::jsonb),
  null::jsonb,
  'GATE: a MISSING unit yields NULL (nothing to name on the ticket)');
select is(
  app.kitchen_modifier_prep_projection('{"quantity":2,"unit":"   "}'::jsonb),
  null::jsonb,
  'GATE: a BLANK unit yields NULL');
select is(
  app.kitchen_modifier_prep_projection('{"quantity":2,"unit":7}'::jsonb),
  null::jsonb,
  'GATE: a NON-STRING unit yields NULL');
select ok(
  app.kitchen_modifier_prep_projection('{"unit":"Meat pieces"}'::jsonb) is null
  and app.kitchen_modifier_prep_projection('{"quantity":0,"unit":"X"}'::jsonb) is null,
  'GATE: the projection can NEVER emit a contribution without a positive quantity');

-- ...and a malformed CLASSIFIER still keeps the valid contribution.
select is(
  app.kitchen_modifier_prep_projection('{"quantity":2,"unit":"Meat pieces",
    "classifier_option_id":{"x":1},"classifier_selected":"nope"}'::jsonb),
  '{"quantity":2,"unit":"Meat pieces"}'::jsonb,
  'GATE: malformed classifier metadata degrades to UNSPLIT, never to NULL');

-- ---------------------------------------------------------------------------
-- 4. FAIL SAFE: malformed / partial classifiers degrade to unsplit.
-- ---------------------------------------------------------------------------
select is(
  app.kitchen_modifier_prep_projection('{
    "quantity":2,"unit":"Meat pieces",
    "classifier_option_id":{"amount_minor":5},
    "classifier_option_name":"Cheese","classifier_selected":true}'::jsonb),
  '{"quantity":2,"unit":"Meat pieces"}'::jsonb,
  'an OBJECT classifier id is dropped, never serialized as text');

select is(
  app.kitchen_modifier_prep_projection('{
    "quantity":2,"unit":"Meat pieces","classifier_option_id":["a"],
    "classifier_option_name":"Cheese","classifier_selected":true}'::jsonb),
  '{"quantity":2,"unit":"Meat pieces"}'::jsonb,
  'an ARRAY classifier id is dropped');

select is(
  app.kitchen_modifier_prep_projection('{
    "quantity":2,"unit":"Meat pieces","classifier_option_id":42,
    "classifier_option_name":"Cheese","classifier_selected":true}'::jsonb),
  '{"quantity":2,"unit":"Meat pieces"}'::jsonb,
  'a NUMERIC classifier id is dropped');

select is(
  app.kitchen_modifier_prep_projection('{
    "quantity":2,"unit":"Meat pieces","classifier_option_id":"o",
    "classifier_option_name":7,"classifier_selected":true}'::jsonb),
  '{"quantity":2,"unit":"Meat pieces"}'::jsonb,
  'a NUMERIC classifier name is dropped');

select is(
  app.kitchen_modifier_prep_projection('{
    "quantity":2,"unit":"Meat pieces","classifier_option_id":"o",
    "classifier_option_name":"Cheese","classifier_selected":"yes"}'::jsonb),
  '{"quantity":2,"unit":"Meat pieces"}'::jsonb,
  'a STRING classifier_selected is dropped (booleans only)');

select is(
  app.kitchen_modifier_prep_projection('{
    "quantity":2,"unit":"Meat pieces","classifier_option_id":"o",
    "classifier_option_name":"Cheese"}'::jsonb),
  '{"quantity":2,"unit":"Meat pieces"}'::jsonb,
  'a triple MISSING the answer is not a classification');

select is(
  app.kitchen_modifier_prep_projection('{
    "quantity":2,"unit":"Meat pieces","classifier_option_id":"   ",
    "classifier_option_name":"Cheese","classifier_selected":true}'::jsonb),
  '{"quantity":2,"unit":"Meat pieces"}'::jsonb,
  'a BLANK classifier id is dropped');

select is(
  app.kitchen_modifier_prep_projection('{
    "quantity":2,"unit":"Meat pieces",
    "classifier_option_id":{"x":1},"classifier_option_name":{"y":2},
    "classifier_selected":{"z":3}}'::jsonb),
  '{"quantity":2,"unit":"Meat pieces"}'::jsonb,
  'quantity + unit survive a FULLY malformed classifier');

select lives_ok($$
  select app.kitchen_modifier_prep_projection('{"quantity":1,
    "classifier_option_id":{"a":{"b":[1,2,3]}},"classifier_selected":[true]}'::jsonb)
$$, 'a deeply malformed classifier does not crash dispatch');

-- ---------------------------------------------------------------------------
-- 5. The allowlist is closed: no other key can reach a dispatch.
-- ---------------------------------------------------------------------------
select is(
  app.kitchen_modifier_prep_projection('{
    "quantity":2,"unit":"Meat pieces",
    "supplier":"ACME","price_minor":500,"colour":"red"}'::jsonb),
  '{"quantity":2,"unit":"Meat pieces"}'::jsonb,
  'unknown client keys - including a money key - are dropped');

select is(
  (select count(*) from jsonb_object_keys(
     app.kitchen_modifier_prep_projection('{
       "quantity":2,"unit":"u","classifier_option_id":"o",
       "classifier_option_name":"C","classifier_selected":true,
       "extra":"nope"}'::jsonb))),
  5::bigint,
  'exactly five keys can ever survive');

select ok(
  not (app.kitchen_modifier_prep_projection('{
    "quantity":2,"unit":"u","classifier_option_id":"o",
    "classifier_option_name":"C","classifier_selected":true}'::jsonb)::text
    ~* '(^|_)minor($|_)'),
  'the projected output carries no money token');

select is(
  length(app.kitchen_modifier_prep_projection(
    jsonb_build_object('quantity', 1, 'unit', 'u',
      'classifier_option_id', repeat('x', 200),
      'classifier_option_name', 'C',
      'classifier_selected', true)) ->> 'classifier_option_id'),
  64,
  'classifier_option_id is bounded to 64 characters');

select is(
  length(app.kitchen_modifier_prep_projection(
    jsonb_build_object('quantity', 1, 'unit', 'u',
      'classifier_option_id', 'o',
      'classifier_option_name', repeat('y', 300),
      'classifier_selected', true)) ->> 'classifier_option_name'),
  120,
  'classifier_option_name is bounded to 120 characters');

select is(
  length(app.kitchen_modifier_prep_projection(
    jsonb_build_object('quantity', 1, 'unit', repeat('u', 90))) ->> 'unit'),
  40,
  'unit is bounded to 40 characters');

-- ---------------------------------------------------------------------------
-- 6. REAL dispatch fixtures: the contribution reaches the durable payload.
-- ---------------------------------------------------------------------------
insert into organizations (id, name, slug, default_currency) values
  ('a9000000-0000-0000-0000-000000000190', 'Org 019', 'org-019', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('a9000000-0000-0000-0000-000000000191', 'a9000000-0000-0000-0000-000000000190', 'Rest 019');
insert into branches (id, organization_id, restaurant_id, name) values
  ('a9000000-0000-0000-0000-00000000019b', 'a9000000-0000-0000-0000-000000000190', 'a9000000-0000-0000-0000-000000000191', 'Branch 019');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('a9000000-0000-0000-0000-0000000019d1', 'a9000000-0000-0000-0000-000000000190', 'a9000000-0000-0000-0000-000000000191', 'a9000000-0000-0000-0000-00000000019b', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('a9000000-0000-0000-0000-0000000019f1', 'a9000000-0000-0000-0000-000000000190', 'a9000000-0000-0000-0000-000000000191', 'a9000000-0000-0000-0000-00000000019b', 'a9000000-0000-0000-0000-0000000019d1', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('a9000000-0000-0000-0000-00000000195a', 'a9000000-0000-0000-0000-000000000190', 'a9000000-0000-0000-0000-000000000191', 'a9000000-0000-0000-0000-00000000019b', 'a9000000-0000-0000-0000-0000000019d1', 'a9000000-0000-0000-0000-0000000019f1');
insert into app_users (id, email) values
  ('a9000000-0000-0000-0000-00000000196a', 'modifier-prep-019@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('a9000000-0000-0000-0000-00000000197a', 'a9000000-0000-0000-0000-00000000196a', 'a9000000-0000-0000-0000-000000000190', 'a9000000-0000-0000-0000-000000000191', 'a9000000-0000-0000-0000-00000000019b', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('a9000000-0000-0000-0000-00000000198a', 'a9000000-0000-0000-0000-000000000190', 'a9000000-0000-0000-0000-000000000191', 'a9000000-0000-0000-0000-00000000019b', 'a9000000-0000-0000-0000-00000000196a', 'a9000000-0000-0000-0000-00000000197a');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('a9000000-0000-0000-0000-00000000199a', 'a9000000-0000-0000-0000-000000000190', 'a9000000-0000-0000-0000-000000000191', 'a9000000-0000-0000-0000-00000000019b', 'a9000000-0000-0000-0000-00000000195a', 'a9000000-0000-0000-0000-00000000198a', 'a9000000-0000-0000-0000-00000000197a', now() + interval '1 hour');

insert into orders (
  id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
  opened_by_employee_profile_id, resolved_membership_id, order_type,
  currency_code, subtotal_minor, grand_total_minor, local_operation_id, status)
values (
  'a9000000-0000-0000-0000-00000000190a', 'a9000000-0000-0000-0000-000000000190',
  'a9000000-0000-0000-0000-000000000191', 'a9000000-0000-0000-0000-00000000019b',
  'a9000000-0000-0000-0000-0000000019d1', 'a9000000-0000-0000-0000-00000000199a',
  'a9000000-0000-0000-0000-00000000198a', 'a9000000-0000-0000-0000-00000000197a',
  'takeaway', 'ILS', 0, 0, 'op-019-initial', 'submitted');

-- One burger: Bread at item level, the meat on its 240g SIZE modifier.
insert into order_items (
  id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
  quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor,
  prep_snapshot)
values (
  'a9000000-0000-0000-0000-0000001900a1', 'a9000000-0000-0000-0000-000000000190',
  'a9000000-0000-0000-0000-000000000191', 'a9000000-0000-0000-0000-00000000019b',
  'a9000000-0000-0000-0000-00000000190a', 'a9000000-0000-0000-0000-000000019001',
  1, 'Burger', 4500, 4500,
  '[{"name":"Bread","quantity":1,"unit":"Piece"}]'::jsonb);

insert into order_item_modifiers (
  id, organization_id, restaurant_id, branch_id, order_item_id,
  modifier_option_id, option_name_snapshot, price_minor_snapshot, quantity,
  meat_snapshot, created_at)
values
  ('a9000000-0000-0000-0000-000000190101', 'a9000000-0000-0000-0000-000000000190',
   'a9000000-0000-0000-0000-000000000191', 'a9000000-0000-0000-0000-00000000019b',
   'a9000000-0000-0000-0000-0000001900a1', 'a9000000-0000-0000-0000-000000019240',
   '240g', 0, 1,
   '{"quantity":2,"unit":"Meat pieces","classifier_option_id":"a9000000-0000-0000-0000-0000001901cc","classifier_option_name":"Cheese","classifier_selected":true}'::jsonb,
   now() - interval '2 minutes'),
  -- The Cheese option itself contributes NOTHING (its own count toggle is off).
  ('a9000000-0000-0000-0000-000000190102', 'a9000000-0000-0000-0000-000000000190',
   'a9000000-0000-0000-0000-000000000191', 'a9000000-0000-0000-0000-00000000019b',
   'a9000000-0000-0000-0000-0000001900a1', 'a9000000-0000-0000-0000-0000001901cc',
   'Cheese', 300, 1, null, now() - interval '1 minute');

select is(
  jsonb_path_query_first(
    app.kitchen_dispatch_payload_initial(
      'a9000000-0000-0000-0000-000000000190',
      'a9000000-0000-0000-0000-00000000190a'),
    '$.items[0].modifiers[0].prep'),
  '{"quantity":2,"unit":"Meat pieces",
    "classifier_option_id":"a9000000-0000-0000-0000-0000001901cc",
    "classifier_option_name":"Cheese","classifier_selected":true}'::jsonb,
  'INITIAL dispatch carries the size option''s contribution + classifier');

select is(
  jsonb_path_query_first(
    app.kitchen_dispatch_payload_initial(
      'a9000000-0000-0000-0000-000000000190',
      'a9000000-0000-0000-0000-00000000190a'),
    '$.items[0].modifiers[1].prep'),
  null::jsonb,
  'a modifier with NO contribution emits no prep key (payload unchanged)');

select is(
  jsonb_path_query_first(
    app.kitchen_dispatch_payload_initial(
      'a9000000-0000-0000-0000-000000000190',
      'a9000000-0000-0000-0000-00000000190a'),
    '$.items[0].prep[0].name'),
  '"Bread"'::jsonb,
  'the item-level Bread resource is untouched beside it');

select is(
  jsonb_path_query_array(
    app.kitchen_dispatch_payload_initial(
      'a9000000-0000-0000-0000-000000000190',
      'a9000000-0000-0000-0000-00000000190a'),
    '$.items[0].modifiers[*].name'),
  '["240g", "Cheese"]'::jsonb,
  'modifier order (created_at, id) is unchanged');

-- Add-items / round work unit.
insert into order_service_rounds (
  id, organization_id, restaurant_id, branch_id, order_id, round_number,
  device_id, opened_by_employee_profile_id, status)
values (
  'a9000000-0000-0000-0000-00000000192a', 'a9000000-0000-0000-0000-000000000190',
  'a9000000-0000-0000-0000-000000000191', 'a9000000-0000-0000-0000-00000000019b',
  'a9000000-0000-0000-0000-00000000190a', 2,
  'a9000000-0000-0000-0000-0000000019d1', 'a9000000-0000-0000-0000-00000000198a',
  'submitted');

insert into order_items (
  id, organization_id, restaurant_id, branch_id, order_id, service_round_id,
  menu_item_id, quantity, menu_item_name_snapshot, unit_price_minor_snapshot,
  line_total_minor)
values (
  'a9000000-0000-0000-0000-0000001902a1', 'a9000000-0000-0000-0000-000000000190',
  'a9000000-0000-0000-0000-000000000191', 'a9000000-0000-0000-0000-00000000019b',
  'a9000000-0000-0000-0000-00000000190a', 'a9000000-0000-0000-0000-00000000192a',
  'a9000000-0000-0000-0000-000000019001', 1, 'Burger', 4500, 4500);

insert into order_item_modifiers (
  id, organization_id, restaurant_id, branch_id, order_item_id,
  modifier_option_id, option_name_snapshot, price_minor_snapshot, quantity,
  meat_snapshot)
values (
  'a9000000-0000-0000-0000-000000190201', 'a9000000-0000-0000-0000-000000000190',
  'a9000000-0000-0000-0000-000000000191', 'a9000000-0000-0000-0000-00000000019b',
  'a9000000-0000-0000-0000-0000001902a1', 'a9000000-0000-0000-0000-000000019120',
  '120g', 0, 1,
  '{"quantity":1,"unit":"Meat pieces","classifier_option_id":"a9000000-0000-0000-0000-0000001901cc","classifier_option_name":"Cheese","classifier_selected":false}'::jsonb);

select is(
  jsonb_path_query_first(
    app.kitchen_dispatch_payload_round(
      'a9000000-0000-0000-0000-000000000190',
      'a9000000-0000-0000-0000-00000000190a',
      'a9000000-0000-0000-0000-00000000192a'),
    '$.items[0].modifiers[0].prep'),
  '{"quantity":1,"unit":"Meat pieces",
    "classifier_option_id":"a9000000-0000-0000-0000-0000001901cc",
    "classifier_option_name":"Cheese","classifier_selected":false}'::jsonb,
  'ADD-ITEMS dispatch carries the contribution + the WITHOUT bucket');

-- Malformed metadata on a real row degrades only the classifier.
update public.order_item_modifiers
   set meat_snapshot = '{"quantity":2,"unit":"Meat pieces","classifier_option_id":{"x":1},"classifier_option_name":"Cheese","classifier_selected":true}'::jsonb
 where id = 'a9000000-0000-0000-0000-000000190101';

select is(
  jsonb_path_query_first(
    app.kitchen_dispatch_payload_initial(
      'a9000000-0000-0000-0000-000000000190',
      'a9000000-0000-0000-0000-00000000190a'),
    '$.items[0].modifiers[0].prep'),
  '{"quantity":2,"unit":"Meat pieces"}'::jsonb,
  'malformed classifier metadata degrades ONLY the classifier, on a real row');

-- Scope + ordering installed by 017 are untouched.
select is(
  jsonb_array_length(
    app.kitchen_dispatch_payload_initial(
      'a9000000-0000-0000-0000-000000000190',
      'a9000000-0000-0000-0000-00000000190a') -> 'items'),
  1,
  'the initial ticket still excludes round items (scope unchanged)');

select is(
  jsonb_array_length(
    app.kitchen_dispatch_payload_round(
      'a9000000-0000-0000-0000-000000000190',
      'a9000000-0000-0000-0000-00000000190a',
      'a9000000-0000-0000-0000-00000000192a') -> 'items'),
  1,
  'the round ticket carries only its own item (scope unchanged)');

select ok(
  (select pg_get_functiondef(p.oid) like '%coalesce(oi.category_display_order_snapshot, 0)%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'kitchen_dispatch_payload_initial'),
  'the 017 canonical menu ordering is preserved in the initial builder');

select ok(
  (select pg_get_functiondef(p.oid) like '%coalesce(oi.category_display_order_snapshot, 0)%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'kitchen_dispatch_payload_round'),
  'the 017 canonical menu ordering is preserved in the round builder');

select ok(
  not (app.kitchen_dispatch_payload_initial(
    'a9000000-0000-0000-0000-000000000190',
    'a9000000-0000-0000-0000-00000000190a')::text ~* '(^|_)minor($|_)'),
  'the whole dispatch payload still carries no money token');

select * from finish();
rollback;
