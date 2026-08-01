-- ============================================================================
-- KITCHEN-PREP-MODIFIER-SPLIT-CODEX-FIX-017 - pgTAP for the dispatch projection.
-- ============================================================================
-- THE DEFECT (Codex BLOCKER #1), proven at the SQL boundary.
--
--   KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016 carries the classification of a
--   preparation resource inside order_items.prep_snapshot. But
--   app.kitchen_prep_projection (20260725090000) is a STRICT ALLOWLIST of
--   {name, quantity, unit}, so every DURABLE dispatch - the printer-only
--   initial ticket and the Add-items round ticket - silently dropped it. The
--   cashier's direct print showed "Meat pieces with Cheese"; the durable copy
--   the kitchen receives after a crash/retry showed an undifferentiated total.
--
-- This suite pins the corrected contract:
--   * a complete, well-typed classifier triple SURVIVES the projection,
--   * legacy prep (no classifier keys) projects byte-identically to before,
--   * every malformed/partial classifier degrades to an ORDINARY UNSPLIT
--     resource and NEVER crashes, and never forwards an arbitrary JSON type,
--   * the resource's own {name, quantity, unit} are never lost to bad
--     classifier metadata,
--   * no key outside the six-key allowlist can ever reach a dispatch payload,
--   * the INTERNAL-only ACL posture and search_path='' are intact.
--
-- Pure function tests: app.kitchen_prep_projection is IMMUTABLE and reads no
-- data, so no tenant fixture is required and nothing is written.
-- ============================================================================
begin;
select plan(55);

-- ---------------------------------------------------------------------------
-- 1. The function still exists with the expected shape/posture.
-- ---------------------------------------------------------------------------
select has_function('app', 'kitchen_prep_projection', array['jsonb'],
  'app.kitchen_prep_projection(jsonb) exists');

select is(
  (select p.provolatile from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'kitchen_prep_projection'),
  'i'::"char",
  'the projection is still IMMUTABLE');

select is(
  (select p.prosecdef from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'kitchen_prep_projection'),
  false,
  'the projection is NOT security definer (a pure helper)');

select ok(
  (select p.proconfig::text like '%search_path=%' from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'kitchen_prep_projection'),
  'the projection pins search_path');

select is(
  (select p.proconfig::text from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'kitchen_prep_projection'),
  '{"search_path=\"\""}',
  'search_path is EMPTY (fully schema-qualified)');

-- ACL: internal only. No PUBLIC / anon / authenticated EXECUTE regression.
select ok(
  not has_function_privilege('public', 'app.kitchen_prep_projection(jsonb)', 'EXECUTE'),
  'PUBLIC cannot execute the projection');
select ok(
  not has_function_privilege('anon', 'app.kitchen_prep_projection(jsonb)', 'EXECUTE'),
  'anon cannot execute the projection');
select ok(
  not has_function_privilege('authenticated', 'app.kitchen_prep_projection(jsonb)', 'EXECUTE'),
  'authenticated cannot execute the projection');

select ok(
  not has_function_privilege('anon', 'app.kitchen_dispatch_payload_initial(uuid, uuid)', 'EXECUTE'),
  'anon cannot execute the initial payload builder');
select ok(
  not has_function_privilege('anon', 'app.kitchen_dispatch_payload_round(uuid, uuid, uuid)', 'EXECUTE'),
  'anon cannot execute the round payload builder');
select ok(
  not has_function_privilege('authenticated', 'app.kitchen_dispatch_payload_initial(uuid, uuid)', 'EXECUTE'),
  'authenticated cannot execute the initial payload builder');
select ok(
  not has_function_privilege('authenticated', 'app.kitchen_dispatch_payload_round(uuid, uuid, uuid)', 'EXECUTE'),
  'authenticated cannot execute the round payload builder');

-- ---------------------------------------------------------------------------
-- 2. THE FIX: a complete, well-typed classifier triple survives.
-- ---------------------------------------------------------------------------
select is(
  app.kitchen_prep_projection('[
    {"name":"Meat pieces","quantity":2,
     "classifier_option_id":"opt-cheese",
     "classifier_option_name":"Cheese",
     "classifier_selected":true}]'::jsonb),
  '[{"name":"Meat pieces","quantity":2,
     "classifier_option_id":"opt-cheese",
     "classifier_option_name":"Cheese",
     "classifier_selected":true}]'::jsonb,
  'a complete classifier triple survives the projection');

select is(
  app.kitchen_prep_projection('[
    {"name":"Meat pieces","quantity":2,
     "classifier_option_id":"opt-cheese",
     "classifier_option_name":"Cheese",
     "classifier_selected":false}]'::jsonb) -> 0 -> 'classifier_selected',
  'false'::jsonb,
  'the WITHOUT bucket survives as boolean false, not as an absent key');

select is(
  app.kitchen_prep_projection('[
    {"name":"قطع لحم","quantity":2,"unit":"قطع",
     "classifier_option_id":"opt-1",
     "classifier_option_name":"جبنة",
     "classifier_selected":true}]'::jsonb) -> 0 -> 'classifier_option_name',
  '"جبنة"'::jsonb,
  'Arabic classifier names survive unmangled');

select is(
  jsonb_array_length(app.kitchen_prep_projection('[
    {"name":"Bread","quantity":1},
    {"name":"Meat pieces","quantity":2,
     "classifier_option_id":"opt-cheese",
     "classifier_option_name":"Cheese",
     "classifier_selected":true}]'::jsonb)),
  2,
  'a mixed unsplit + classified array keeps both elements');

select is(
  app.kitchen_prep_projection('[
    {"name":"Bread","quantity":1},
    {"name":"Meat","quantity":2,"classifier_option_id":"o","classifier_option_name":"C","classifier_selected":true}]'::jsonb) -> 0,
  '{"name":"Bread","quantity":1}'::jsonb,
  'element ORDER is preserved and the unsplit element is untouched');

-- ---------------------------------------------------------------------------
-- 3. Legacy prep is byte-identical to the pre-017 projection.
-- ---------------------------------------------------------------------------
select is(
  app.kitchen_prep_projection('[{"name":"Meat pieces","quantity":2,"unit":"pcs"}]'::jsonb),
  '[{"name":"Meat pieces","quantity":2,"unit":"pcs"}]'::jsonb,
  'legacy prep projects unchanged');

select is(
  app.kitchen_prep_projection(null::jsonb), null::jsonb,
  'NULL prep still projects NULL');

select is(
  app.kitchen_prep_projection('"not an array"'::jsonb), null::jsonb,
  'a non-array still projects NULL');

select is(
  app.kitchen_prep_projection('[]'::jsonb), null::jsonb,
  'an empty array still collapses to NULL');

-- ---------------------------------------------------------------------------
-- 4. FAIL-SAFE: malformed / partial classifiers degrade to unsplit.
-- ---------------------------------------------------------------------------
select is(
  app.kitchen_prep_projection('[
    {"name":"Meat pieces","quantity":2,
     "classifier_option_id":{"amount_minor":5},
     "classifier_option_name":"Cheese",
     "classifier_selected":true}]'::jsonb),
  '[{"name":"Meat pieces","quantity":2}]'::jsonb,
  'an OBJECT classifier id is dropped, never serialized as text');

select is(
  app.kitchen_prep_projection('[
    {"name":"Meat pieces","quantity":2,
     "classifier_option_id":["a"],
     "classifier_option_name":"Cheese",
     "classifier_selected":true}]'::jsonb),
  '[{"name":"Meat pieces","quantity":2}]'::jsonb,
  'an ARRAY classifier id is dropped');

select is(
  app.kitchen_prep_projection('[
    {"name":"Meat pieces","quantity":2,
     "classifier_option_id":42,
     "classifier_option_name":"Cheese",
     "classifier_selected":true}]'::jsonb),
  '[{"name":"Meat pieces","quantity":2}]'::jsonb,
  'a NUMERIC classifier id is dropped');

select is(
  app.kitchen_prep_projection('[
    {"name":"Meat pieces","quantity":2,
     "classifier_option_id":"opt-cheese",
     "classifier_option_name":7,
     "classifier_selected":true}]'::jsonb),
  '[{"name":"Meat pieces","quantity":2}]'::jsonb,
  'a NUMERIC classifier name is dropped');

select is(
  app.kitchen_prep_projection('[
    {"name":"Meat pieces","quantity":2,
     "classifier_option_id":"opt-cheese",
     "classifier_option_name":"Cheese",
     "classifier_selected":"yes"}]'::jsonb),
  '[{"name":"Meat pieces","quantity":2}]'::jsonb,
  'a STRING classifier_selected is dropped (booleans only)');

select is(
  app.kitchen_prep_projection('[
    {"name":"Meat pieces","quantity":2,
     "classifier_option_id":"opt-cheese",
     "classifier_option_name":"Cheese",
     "classifier_selected":1}]'::jsonb),
  '[{"name":"Meat pieces","quantity":2}]'::jsonb,
  'a NUMERIC classifier_selected is dropped');

select is(
  app.kitchen_prep_projection('[
    {"name":"Meat pieces","quantity":2,
     "classifier_option_id":"opt-cheese",
     "classifier_option_name":"Cheese"}]'::jsonb),
  '[{"name":"Meat pieces","quantity":2}]'::jsonb,
  'a triple MISSING the answer is not a classification');

select is(
  app.kitchen_prep_projection('[
    {"name":"Meat pieces","quantity":2,
     "classifier_option_id":"opt-cheese",
     "classifier_selected":true}]'::jsonb),
  '[{"name":"Meat pieces","quantity":2}]'::jsonb,
  'a triple MISSING the name is not a classification');

select is(
  app.kitchen_prep_projection('[
    {"name":"Meat pieces","quantity":2,
     "classifier_option_name":"Cheese",
     "classifier_selected":true}]'::jsonb),
  '[{"name":"Meat pieces","quantity":2}]'::jsonb,
  'a triple MISSING the id is not a classification');

select is(
  app.kitchen_prep_projection('[
    {"name":"Meat pieces","quantity":2,
     "classifier_option_id":"   ",
     "classifier_option_name":"Cheese",
     "classifier_selected":true}]'::jsonb),
  '[{"name":"Meat pieces","quantity":2}]'::jsonb,
  'a BLANK classifier id is dropped');

select is(
  app.kitchen_prep_projection('[
    {"name":"Meat pieces","quantity":2,
     "classifier_option_id":null,
     "classifier_option_name":null,
     "classifier_selected":null}]'::jsonb),
  '[{"name":"Meat pieces","quantity":2}]'::jsonb,
  'explicit JSON nulls degrade to unsplit');

-- The resource is NEVER suppressed by malformed classifier metadata.
select is(
  app.kitchen_prep_projection('[
    {"name":"Meat pieces","quantity":2,"unit":"pcs",
     "classifier_option_id":{"x":1},
     "classifier_option_name":{"y":2},
     "classifier_selected":{"z":3}}]'::jsonb),
  '[{"name":"Meat pieces","quantity":2,"unit":"pcs"}]'::jsonb,
  'name/quantity/unit all survive a fully malformed classifier');

select lives_ok($$
  select app.kitchen_prep_projection('[
    {"name":"M","quantity":1,"classifier_option_id":{"a":{"b":[1,2,3]}},
     "classifier_selected":[true]}]'::jsonb)
$$, 'a deeply malformed classifier does not crash dispatch');

-- ---------------------------------------------------------------------------
-- 5. The allowlist is still closed: no other key can reach a dispatch.
-- ---------------------------------------------------------------------------
select is(
  app.kitchen_prep_projection('[
    {"name":"Meat pieces","quantity":2,
     "classifier_option_colour":"red",
     "supplier":"ACME",
     "price_minor":500}]'::jsonb),
  '[{"name":"Meat pieces","quantity":2}]'::jsonb,
  'unknown client keys - including a money key - are still dropped');

select is(
  (select count(*) from jsonb_object_keys(
     app.kitchen_prep_projection('[
       {"name":"M","quantity":1,"unit":"u",
        "classifier_option_id":"o","classifier_option_name":"C",
        "classifier_selected":true,
        "extra":"nope"}]'::jsonb) -> 0)),
  6::bigint,
  'exactly six keys can ever survive');

select ok(
  not (app.kitchen_prep_projection('[
    {"name":"M","quantity":1,
     "classifier_option_id":"o","classifier_option_name":"C",
     "classifier_selected":true}]'::jsonb)::text ~* '(^|_)minor($|_)'),
  'the projected output carries no money token');

-- ---------------------------------------------------------------------------
-- 6. Length bounds still apply to the new text fields.
-- ---------------------------------------------------------------------------
select is(
  length(app.kitchen_prep_projection(
    jsonb_build_array(jsonb_build_object(
      'name', 'M', 'quantity', 1,
      'classifier_option_id', repeat('x', 200),
      'classifier_option_name', 'C',
      'classifier_selected', true))) -> 0 ->> 'classifier_option_id'),
  64,
  'classifier_option_id is bounded to 64 characters');

select is(
  length(app.kitchen_prep_projection(
    jsonb_build_array(jsonb_build_object(
      'name', 'M', 'quantity', 1,
      'classifier_option_id', 'o',
      'classifier_option_name', repeat('y', 300),
      'classifier_selected', true))) -> 0 ->> 'classifier_option_name'),
  120,
  'classifier_option_name is bounded to 120 characters');

-- ---------------------------------------------------------------------------
-- 7. The payload builders still exist and stayed money-free helpers.
-- ---------------------------------------------------------------------------
select has_function('app', 'kitchen_dispatch_payload_initial', array['uuid','uuid'],
  'app.kitchen_dispatch_payload_initial(uuid,uuid) exists');
select has_function('app', 'kitchen_dispatch_payload_round', array['uuid','uuid','uuid'],
  'app.kitchen_dispatch_payload_round(uuid,uuid,uuid) exists');

select is(
  (select p.proconfig::text from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'kitchen_dispatch_payload_initial'),
  '{"search_path=\"\""}',
  'the initial payload builder still pins an EMPTY search_path');

select is(
  (select p.proconfig::text from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'kitchen_dispatch_payload_round'),
  '{"search_path=\"\""}',
  'the round payload builder still pins an EMPTY search_path');

-- ---------------------------------------------------------------------------
-- 8. REAL ORDERING FIXTURES (018, Codex MEDIUM #3).
-- ---------------------------------------------------------------------------
-- 017 shipped the builders with `line_position` LEADING, which is NOT the
-- canonical menu order the POS receipt, the POS direct kitchen ticket and the
-- KDS ticket use. Text-inspecting the function body could not catch that, so
-- these fixtures EXECUTE the real builders.
--
-- The menu-order snapshots are NOT hand-written here: the MENU-ORDER-001
-- BEFORE INSERT trigger derives them server-side from the real menu rows below
-- (D-008 — a client-supplied display order is never trusted), so this exercises
-- the production derivation as well as the ordering.
--
-- THE CONFLICT, built deliberately:
--   * category CAT-1 ranks before CAT-2
--   * product B lives in CAT-2 but is rung up FIRST, so it takes line_position 1
--     and the earliest created_at
--   * product A lives in CAT-1 and is rung up second (line_position 2)
-- Canonical menu order must still print A before B. Under the 954c9d6 ordering
-- (line_position leading) B leads and these assertions fail.
insert into organizations (id, name, slug, default_currency) values
  ('f0000000-0000-0000-0000-000000000180', 'Org 018', 'org-018', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('f0000000-0000-0000-0000-000000000181', 'f0000000-0000-0000-0000-000000000180', 'Rest 018');
insert into branches (id, organization_id, restaurant_id, name) values
  ('f0000000-0000-0000-0000-00000000018b', 'f0000000-0000-0000-0000-000000000180', 'f0000000-0000-0000-0000-000000000181', 'Branch 018');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('f0000000-0000-0000-0000-0000000018d1', 'f0000000-0000-0000-0000-000000000180', 'f0000000-0000-0000-0000-000000000181', 'f0000000-0000-0000-0000-00000000018b', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('f0000000-0000-0000-0000-0000000018f1', 'f0000000-0000-0000-0000-000000000180', 'f0000000-0000-0000-0000-000000000181', 'f0000000-0000-0000-0000-00000000018b', 'f0000000-0000-0000-0000-0000000018d1', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('f0000000-0000-0000-0000-00000000185a', 'f0000000-0000-0000-0000-000000000180', 'f0000000-0000-0000-0000-000000000181', 'f0000000-0000-0000-0000-00000000018b', 'f0000000-0000-0000-0000-0000000018d1', 'f0000000-0000-0000-0000-0000000018f1');
insert into app_users (id, email) values
  ('f0000000-0000-0000-0000-00000000186a', 'ordering-018@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('f0000000-0000-0000-0000-00000000187a', 'f0000000-0000-0000-0000-00000000186a', 'f0000000-0000-0000-0000-000000000180', 'f0000000-0000-0000-0000-000000000181', 'f0000000-0000-0000-0000-00000000018b', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('f0000000-0000-0000-0000-00000000188a', 'f0000000-0000-0000-0000-000000000180', 'f0000000-0000-0000-0000-000000000181', 'f0000000-0000-0000-0000-00000000018b', 'f0000000-0000-0000-0000-00000000186a', 'f0000000-0000-0000-0000-00000000187a');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('f0000000-0000-0000-0000-00000000189a', 'f0000000-0000-0000-0000-000000000180', 'f0000000-0000-0000-0000-000000000181', 'f0000000-0000-0000-0000-00000000018b', 'f0000000-0000-0000-0000-00000000185a', 'f0000000-0000-0000-0000-00000000188a', 'f0000000-0000-0000-0000-00000000187a', now() + interval '1 hour');

-- The MENU the trigger snapshots from: CAT-1 ranks before CAT-2.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order, is_active) values
  ('f0000000-0000-0000-0000-0000000c0001', 'f0000000-0000-0000-0000-000000000180', 'f0000000-0000-0000-0000-000000000181', null, 'CAT-1 Mains', 1, true),
  ('f0000000-0000-0000-0000-0000000c0002', 'f0000000-0000-0000-0000-000000000180', 'f0000000-0000-0000-0000-000000000181', null, 'CAT-2 Drinks', 2, true);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order, is_active) values
  -- CAT-1, rank 1 — three DISTINCT products sharing the same menu rank, so the
  -- tie-break inside an equal menu-order group can be observed.
  ('f0000000-0000-0000-0000-000000010001', 'f0000000-0000-0000-0000-000000000180', 'f0000000-0000-0000-0000-000000000181', null, 'f0000000-0000-0000-0000-0000000c0001', 'A', 1000, 'ILS', 1, true),
  ('f0000000-0000-0000-0000-000000010002', 'f0000000-0000-0000-0000-000000000180', 'f0000000-0000-0000-0000-000000000181', null, 'f0000000-0000-0000-0000-0000000c0001', 'A tie later-line', 1000, 'ILS', 1, true),
  ('f0000000-0000-0000-0000-000000010003', 'f0000000-0000-0000-0000-000000000180', 'f0000000-0000-0000-0000-000000000181', null, 'f0000000-0000-0000-0000-0000000c0001', 'A tie newest', 1000, 'ILS', 1, true),
  -- CAT-1, rank 9 — same category, later item rank.
  ('f0000000-0000-0000-0000-000000010009', 'f0000000-0000-0000-0000-000000000180', 'f0000000-0000-0000-0000-000000000181', null, 'f0000000-0000-0000-0000-0000000c0001', 'A2 later-item', 1000, 'ILS', 9, true),
  -- CAT-2, rank 1 — later CATEGORY, so it prints last regardless of cart order.
  ('f0000000-0000-0000-0000-000000020001', 'f0000000-0000-0000-0000-000000000180', 'f0000000-0000-0000-0000-000000000181', null, 'f0000000-0000-0000-0000-0000000c0002', 'B late-category', 1000, 'ILS', 1, true);

insert into orders (
  id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
  opened_by_employee_profile_id, resolved_membership_id, order_type,
  currency_code, subtotal_minor, grand_total_minor, local_operation_id, status)
values (
  'f0000000-0000-0000-0000-00000000180a', 'f0000000-0000-0000-0000-000000000180',
  'f0000000-0000-0000-0000-000000000181', 'f0000000-0000-0000-0000-00000000018b',
  'f0000000-0000-0000-0000-0000000018d1', 'f0000000-0000-0000-0000-00000000189a',
  'f0000000-0000-0000-0000-00000000188a', 'f0000000-0000-0000-0000-00000000187a',
  'takeaway', 'ILS', 0, 0, 'op-018-initial', 'submitted');

-- INITIAL work unit. B is rung up FIRST (line_position 1, earliest created_at)
-- but belongs to the LATER category; A must still print first. The snapshot
-- columns are deliberately NOT supplied — the trigger derives them.
insert into order_items (
  id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
  quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor,
  line_position, created_at)
values
  ('f0000000-0000-0000-0000-0000001800b1', 'f0000000-0000-0000-0000-000000000180',
   'f0000000-0000-0000-0000-000000000181', 'f0000000-0000-0000-0000-00000000018b',
   'f0000000-0000-0000-0000-00000000180a', 'f0000000-0000-0000-0000-000000020001',
   1, 'B late-category', 1000, 1000, 1, now() - interval '9 minutes'),
  ('f0000000-0000-0000-0000-0000001800a1', 'f0000000-0000-0000-0000-000000000180',
   'f0000000-0000-0000-0000-000000000181', 'f0000000-0000-0000-0000-00000000018b',
   'f0000000-0000-0000-0000-00000000180a', 'f0000000-0000-0000-0000-000000010001',
   1, 'A early-category', 1000, 1000, 2, now() - interval '1 minute');

-- The trigger really did derive the ranks from the menu (proves the fixture).
select is(
  (select array[category_display_order_snapshot, item_display_order_snapshot]
     from public.order_items
    where id = 'f0000000-0000-0000-0000-0000001800a1'),
  array[1, 1],
  'the MENU-ORDER-001 trigger derived A''s ranks from the real menu');

select is(
  jsonb_path_query_array(
    app.kitchen_dispatch_payload_initial(
      'f0000000-0000-0000-0000-000000000180',
      'f0000000-0000-0000-0000-00000000180a'),
    '$.items[*].name'),
  '["A early-category", "B late-category"]'::jsonb,
  'INITIAL dispatch orders by CATEGORY rank first, beating cart line_position');

-- Equal category rank -> the ITEM rank decides; rung up third, prints second.
insert into order_items (
  id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
  quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor,
  line_position, created_at)
values
  ('f0000000-0000-0000-0000-0000001800c2', 'f0000000-0000-0000-0000-000000000180',
   'f0000000-0000-0000-0000-000000000181', 'f0000000-0000-0000-0000-00000000018b',
   'f0000000-0000-0000-0000-00000000180a', 'f0000000-0000-0000-0000-000000010009',
   1, 'A2 later-item', 1000, 1000, 3, now() - interval '30 seconds');

select is(
  jsonb_path_query_array(
    app.kitchen_dispatch_payload_initial(
      'f0000000-0000-0000-0000-000000000180',
      'f0000000-0000-0000-0000-00000000180a'),
    '$.items[*].name'),
  '["A early-category", "A2 later-item", "B late-category"]'::jsonb,
  'INITIAL dispatch orders by ITEM rank within an equal category rank');

-- Equal category AND item rank -> line_position tie-breaks, and ONLY there.
-- This row has the LATER line_position but a much EARLIER created_at, so a
-- created_at-led ordering would wrongly hoist it to the front of its group.
insert into order_items (
  id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
  quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor,
  line_position, created_at)
values
  ('f0000000-0000-0000-0000-0000001800d2', 'f0000000-0000-0000-0000-000000000180',
   'f0000000-0000-0000-0000-000000000181', 'f0000000-0000-0000-0000-00000000018b',
   'f0000000-0000-0000-0000-00000000180a', 'f0000000-0000-0000-0000-000000010002',
   1, 'A tie later-line', 1000, 1000, 7, now() - interval '8 minutes');

select is(
  jsonb_path_query_array(
    app.kitchen_dispatch_payload_initial(
      'f0000000-0000-0000-0000-000000000180',
      'f0000000-0000-0000-0000-00000000180a'),
    '$.items[*].name'),
  '["A early-category", "A tie later-line", "A2 later-item", "B late-category"]'::jsonb,
  'line_position tie-breaks ONLY inside an equal menu-order group (created_at never leads)');

-- Fully equal menu-order keys AND line_position -> created_at, then id, decide.
insert into order_items (
  id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
  quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor,
  line_position, created_at)
values
  ('f0000000-0000-0000-0000-0000001800e9', 'f0000000-0000-0000-0000-000000000180',
   'f0000000-0000-0000-0000-000000000181', 'f0000000-0000-0000-0000-00000000018b',
   'f0000000-0000-0000-0000-00000000180a', 'f0000000-0000-0000-0000-000000010003',
   1, 'A tie newest', 1000, 1000, 7, now() - interval '7 minutes');

select is(
  jsonb_path_query_array(
    app.kitchen_dispatch_payload_initial(
      'f0000000-0000-0000-0000-000000000180',
      'f0000000-0000-0000-0000-00000000180a'),
    '$.items[*].name'),
  '["A early-category", "A tie later-line", "A tie newest", "A2 later-item", "B late-category"]'::jsonb,
  'created_at is the deterministic tie-break once every menu-order key is equal');

-- Deterministic: the same payload twice, byte for byte.
select is(
  app.kitchen_dispatch_payload_initial(
    'f0000000-0000-0000-0000-000000000180', 'f0000000-0000-0000-0000-00000000180a'),
  app.kitchen_dispatch_payload_initial(
    'f0000000-0000-0000-0000-000000000180', 'f0000000-0000-0000-0000-00000000180a'),
  'the initial dispatch payload is deterministic across runs');

-- ADD-ITEMS / round work unit: the same conflict, scoped to one round.
insert into order_service_rounds (
  id, organization_id, restaurant_id, branch_id, order_id, round_number,
  device_id, opened_by_employee_profile_id, status)
values (
  'f0000000-0000-0000-0000-00000000182a', 'f0000000-0000-0000-0000-000000000180',
  'f0000000-0000-0000-0000-000000000181', 'f0000000-0000-0000-0000-00000000018b',
  'f0000000-0000-0000-0000-00000000180a', 2,
  'f0000000-0000-0000-0000-0000000018d1', 'f0000000-0000-0000-0000-00000000188a',
  'submitted');

insert into order_items (
  id, organization_id, restaurant_id, branch_id, order_id, service_round_id,
  menu_item_id, quantity, menu_item_name_snapshot, unit_price_minor_snapshot,
  line_total_minor, line_position, created_at)
values
  ('f0000000-0000-0000-0000-0000001802b1', 'f0000000-0000-0000-0000-000000000180',
   'f0000000-0000-0000-0000-000000000181', 'f0000000-0000-0000-0000-00000000018b',
   'f0000000-0000-0000-0000-00000000180a', 'f0000000-0000-0000-0000-00000000182a',
   'f0000000-0000-0000-0000-000000020001', 1, 'R-B late-category', 1000, 1000,
   11, now() - interval '5 minutes'),
  ('f0000000-0000-0000-0000-0000001802a9', 'f0000000-0000-0000-0000-000000000180',
   'f0000000-0000-0000-0000-000000000181', 'f0000000-0000-0000-0000-00000000018b',
   'f0000000-0000-0000-0000-00000000180a', 'f0000000-0000-0000-0000-00000000182a',
   'f0000000-0000-0000-0000-000000010009', 1, 'R-A2 later-item', 1000, 1000,
   12, now() - interval '4 minutes'),
  ('f0000000-0000-0000-0000-0000001802a1', 'f0000000-0000-0000-0000-000000000180',
   'f0000000-0000-0000-0000-000000000181', 'f0000000-0000-0000-0000-00000000018b',
   'f0000000-0000-0000-0000-00000000180a', 'f0000000-0000-0000-0000-00000000182a',
   'f0000000-0000-0000-0000-000000010001', 1, 'R-A early-category', 1000, 1000,
   13, now() - interval '3 minutes');

select is(
  jsonb_path_query_array(
    app.kitchen_dispatch_payload_round(
      'f0000000-0000-0000-0000-000000000180',
      'f0000000-0000-0000-0000-00000000180a',
      'f0000000-0000-0000-0000-00000000182a'),
    '$.items[*].name'),
  '["R-A early-category", "R-A2 later-item", "R-B late-category"]'::jsonb,
  'ADD-ITEMS dispatch orders by canonical menu order, beating cart line_position');

select is(
  app.kitchen_dispatch_payload_round(
    'f0000000-0000-0000-0000-000000000180', 'f0000000-0000-0000-0000-00000000180a',
    'f0000000-0000-0000-0000-00000000182a'),
  app.kitchen_dispatch_payload_round(
    'f0000000-0000-0000-0000-000000000180', 'f0000000-0000-0000-0000-00000000180a',
    'f0000000-0000-0000-0000-00000000182a'),
  'the round dispatch payload is deterministic across runs');

-- Ticket SCOPE is unchanged by the reordering.
select is(
  jsonb_array_length(
    app.kitchen_dispatch_payload_round(
      'f0000000-0000-0000-0000-000000000180',
      'f0000000-0000-0000-0000-00000000180a',
      'f0000000-0000-0000-0000-00000000182a') -> 'items'),
  3,
  'the round ticket carries exactly its own three items (scope unchanged)');

select is(
  jsonb_array_length(
    app.kitchen_dispatch_payload_initial(
      'f0000000-0000-0000-0000-000000000180',
      'f0000000-0000-0000-0000-00000000180a') -> 'items'),
  5,
  'the initial ticket still excludes every round item (scope unchanged)');

-- Quantities are untouched by the reordering.
select is(
  jsonb_path_query_array(
    app.kitchen_dispatch_payload_initial(
      'f0000000-0000-0000-0000-000000000180',
      'f0000000-0000-0000-0000-00000000180a'),
    '$.items[*].qty'),
  '[1, 1, 1, 1, 1]'::jsonb,
  'item quantities are unchanged by the reordering');

-- 017 regression: the classifier still rides a canonically-ordered payload.
update public.order_items
   set prep_snapshot = '[{"name":"Meat pieces","quantity":2,
                          "classifier_option_id":"opt-cheese",
                          "classifier_option_name":"Cheese",
                          "classifier_selected":true}]'::jsonb
 where id = 'f0000000-0000-0000-0000-0000001800a1';

select is(
  jsonb_path_query_first(
    app.kitchen_dispatch_payload_initial(
      'f0000000-0000-0000-0000-000000000180',
      'f0000000-0000-0000-0000-00000000180a'),
    '$.items[0].prep[0].classifier_option_name'),
  '"Cheese"'::jsonb,
  'the classifier still rides the canonically-ordered initial payload');

select * from finish();
rollback;
