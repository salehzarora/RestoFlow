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
select plan(45);

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

-- Both builders order items by the canonical print order (line_position first),
-- so the durable spool ticket cannot list the preparation summary in a
-- different sequence than the POS direct print and the KDS.
select ok(
  (select pg_get_functiondef(p.oid) like '%coalesce(oi.line_position, 0), oi.created_at, oi.id%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'kitchen_dispatch_payload_initial'),
  'the initial builder orders items by (line_position, created_at, id)');

select ok(
  (select pg_get_functiondef(p.oid) like '%coalesce(oi.line_position, 0), oi.created_at, oi.id%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'kitchen_dispatch_payload_round'),
  'the round builder orders items by (line_position, created_at, id)');

select * from finish();
rollback;
