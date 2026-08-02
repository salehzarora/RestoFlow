-- ============================================================================
-- KITCHEN-MODIFIER-PREP-CLASSIFIER-STALE-SNAPSHOT-FIX-021 (pgTAP).
-- ============================================================================
-- THE DEFECT (Codex HIGH, second review of migration 019).
--
--   `app.trusted_modifier_prep_snapshot` REPLACED the client's frozen
--   meat_snapshot with a LIVE re-derivation at first acceptance. So:
--
--     1. the POS froze  240g -> 2 Meat pieces, split by Cheese, selected;
--     2. the first delivery attempt never completed;
--     3. the owner edited the live menu (240g now contributes 3);
--     4. the POS retried the SAME frozen operation;
--     5. the server stored THREE — while the POS confirmation, the direct
--        kitchen print and every local reprint still said TWO.
--
--   Silent replacement of a submitted frozen snapshot is not acceptable: one
--   accepted order must not carry two different preparation answers.
--
-- THE CORRECTION.
--
--   The server still derives its own trusted snapshot and still trusts nothing
--   the client says. But instead of overwriting, it COMPARES:
--
--     app.kitchen_modifier_prep_projection(client meat_snapshot)   -- canonical
--       must equal
--     app.trusted_modifier_prep_snapshot(org, item, option, mods)  -- canonical
--
--   Equal   -> accept and store the VALIDATED SUBMITTED value (never a second
--              live re-read, so a menu edit mid-transaction cannot slip in).
--   Differ  -> refuse the whole operation atomically with
--              `modifier_prep_snapshot_stale`. Nothing is inserted.
--
--   The comparison sits AFTER the idempotency replay lookup, so an operation
--   the server already accepted keeps replaying its stored result forever, and
--   BEFORE every insert, so a refusal is atomic by construction.
--
-- These drive the REAL authoritative RPCs and read back real database state.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(60);

-- ------------------------------------------------------------------- scope
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-000000021a00', 'Org 021', 'org-021', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-000000021a01', '00000000-0000-0000-0000-000000021a00', 'Rest 021');
-- printer_only so an ACCEPTED operation really does create a kitchen dispatch —
-- otherwise "a refusal creates no dispatch" would be vacuously true.
insert into branches (id, organization_id, restaurant_id, name, kitchen_workflow_mode) values
  ('00000000-0000-0000-0000-000000021b01', '00000000-0000-0000-0000-000000021a00', '00000000-0000-0000-0000-000000021a01', 'Branch 021', 'printer_only');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-000000021d01', '00000000-0000-0000-0000-000000021a00', '00000000-0000-0000-0000-000000021a01', '00000000-0000-0000-0000-000000021b01', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-000000021f01', '00000000-0000-0000-0000-000000021a00', '00000000-0000-0000-0000-000000021a01', '00000000-0000-0000-0000-000000021b01', '00000000-0000-0000-0000-000000021d01', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-000000021501', '00000000-0000-0000-0000-000000021a00', '00000000-0000-0000-0000-000000021a01', '00000000-0000-0000-0000-000000021b01', '00000000-0000-0000-0000-000000021d01', '00000000-0000-0000-0000-000000021f01');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-000000021e01', 'stale021@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-000000021601', '00000000-0000-0000-0000-000000021e01', '00000000-0000-0000-0000-000000021a00', '00000000-0000-0000-0000-000000021a01', '00000000-0000-0000-0000-000000021b01', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-000000021701', '00000000-0000-0000-0000-000000021a00', '00000000-0000-0000-0000-000000021a01', '00000000-0000-0000-0000-000000021b01', '00000000-0000-0000-0000-000000021e01', '00000000-0000-0000-0000-000000021601');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-000000021c01', '00000000-0000-0000-0000-000000021a00', '00000000-0000-0000-0000-000000021a01', '00000000-0000-0000-0000-000000021b01', '00000000-0000-0000-0000-000000021501', '00000000-0000-0000-0000-000000021701', '00000000-0000-0000-0000-000000021601', now() + interval '1 hour');

-- --------------------------------------------------------------- catalogue
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('00000000-0000-0000-0000-0000000210c1', '00000000-0000-0000-0000-000000021a00', '00000000-0000-0000-0000-000000021a01', null, 'Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('00000000-0000-0000-0000-000000021101', '00000000-0000-0000-0000-000000021a00', '00000000-0000-0000-0000-000000021a01', null, '00000000-0000-0000-0000-0000000210c1', 'Burger', 4500, 'ILS', 1),
  ('00000000-0000-0000-0000-000000021102', '00000000-0000-0000-0000-000000021a00', '00000000-0000-0000-0000-000000021a01', null, '00000000-0000-0000-0000-0000000210c1', 'Chicken', 4500, 'ILS', 2);
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name) values
  ('00000000-0000-0000-0000-000000021201', '00000000-0000-0000-0000-000000021a00', '00000000-0000-0000-0000-000000021a01', null, '00000000-0000-0000-0000-000000021101', 'Size'),
  ('00000000-0000-0000-0000-000000021202', '00000000-0000-0000-0000-000000021a00', '00000000-0000-0000-0000-000000021a01', null, '00000000-0000-0000-0000-000000021101', 'Extras'),
  ('00000000-0000-0000-0000-000000021203', '00000000-0000-0000-0000-000000021a00', '00000000-0000-0000-0000-000000021a01', null, '00000000-0000-0000-0000-000000021102', 'Extras');
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, kitchen_meat) values
  -- 240g contributes 2 Meat pieces, split by Cheese.
  ('00000000-0000-0000-0000-000000021301', '00000000-0000-0000-0000-000000021a00', '00000000-0000-0000-0000-000000021a01', null, '00000000-0000-0000-0000-000000021201', '240g', 0,
   '{"quantity":2,"unit":"Meat pieces","classifier_option_id":"00000000-0000-0000-0000-000000021302","classifier_option_name":"Cheese"}'::jsonb),
  ('00000000-0000-0000-0000-000000021302', '00000000-0000-0000-0000-000000021a00', '00000000-0000-0000-0000-000000021a01', null, '00000000-0000-0000-0000-000000021202', 'Cheese', 300, null),
  -- 120g contributes 1 Meat piece, unclassified.
  ('00000000-0000-0000-0000-000000021303', '00000000-0000-0000-0000-000000021a00', '00000000-0000-0000-0000-000000021a01', null, '00000000-0000-0000-0000-000000021201', '120g', 0,
   '{"quantity":1,"unit":"Meat pieces"}'::jsonb),
  -- The CHICKEN's own Cheese: same name, different product.
  ('00000000-0000-0000-0000-000000021304', '00000000-0000-0000-0000-000000021a00', '00000000-0000-0000-0000-000000021a01', null, '00000000-0000-0000-0000-000000021203', 'Cheese', 300, null),
  -- A size option carrying NO configured contribution at all.
  ('00000000-0000-0000-0000-000000021305', '00000000-0000-0000-0000-000000021a00', '00000000-0000-0000-0000-000000021a01', null, '00000000-0000-0000-0000-000000021201', 'Plain', 0, null);

-- ----------------------------------------------------------------- helpers
create or replace function pg_temp.body(
  p_size uuid, p_with_cheese boolean, p_client_meat jsonb)
  returns jsonb language sql immutable as $fn$
  select jsonb_build_array(jsonb_build_object(
    'menu_item_id', '00000000-0000-0000-0000-000000021101',
    'quantity', 1,
    'unit_price_minor_snapshot', 4500,
    'menu_item_name_snapshot', 'Burger',
    'modifiers',
      jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'modifier_option_id', p_size,
        'price_minor_snapshot', 0,
        'quantity', 1,
        'modifier_name_snapshot', 'Size',
        'option_name_snapshot', 'Size choice',
        -- A real client OMITS the key when the option contributes nothing.
        'meat_snapshot', p_client_meat)))
      || case when p_with_cheese then jsonb_build_array(jsonb_build_object(
             'modifier_option_id', '00000000-0000-0000-0000-000000021302',
             'price_minor_snapshot', 300,
             'quantity', 1,
             'modifier_name_snapshot', 'Extras',
             'option_name_snapshot', 'Cheese'))
         else '[]'::jsonb end));
$fn$;

create or replace function pg_temp.submit(
  p_order uuid, p_op text, p_size uuid, p_with_cheese boolean, p_client_meat jsonb)
  returns jsonb language sql as $fn$
  select app.submit_order(
    '00000000-0000-0000-0000-000000021c01', p_order,
    '00000000-0000-0000-0000-000000021d01', p_op, 'takeaway', null, null, 'ILS', null,
    pg_temp.body(p_size, p_with_cheese, p_client_meat),
    case when p_with_cheese then 4800 else 4500 end, 0, 0,
    case when p_with_cheese then 4800 else 4500 end, null);
$fn$;

create or replace function pg_temp.stored(p_order uuid)
  returns jsonb language sql as $fn$
  select om.meat_snapshot
    from public.order_item_modifiers om
    join public.order_items oi
      on oi.organization_id = om.organization_id and oi.id = om.order_item_id
   where oi.order_id = p_order
     and om.modifier_option_id in ('00000000-0000-0000-0000-000000021301',
                                   '00000000-0000-0000-0000-000000021303',
                                   '00000000-0000-0000-0000-000000021305')
   limit 1;
$fn$;

create or replace function pg_temp.audits() returns bigint language sql as $fn$
  select count(*) from public.audit_events
   where organization_id = '00000000-0000-0000-0000-000000021a00';
$fn$;

create or replace function pg_temp.dispatches() returns bigint language sql as $fn$
  select count(*) from public.kitchen_print_dispatches
   where organization_id = '00000000-0000-0000-0000-000000021a00';
$fn$;

-- The exact frozen snapshot a CURRENT POS produces for 240g with Cheese.
create or replace function pg_temp.frozen(p_selected boolean)
  returns jsonb language sql immutable as $fn$
  select jsonb_build_object(
    'quantity', 2, 'unit', 'Meat pieces',
    'classifier_option_id', '00000000-0000-0000-0000-000000021302',
    'classifier_option_name', 'Cheese',
    'classifier_selected', p_selected);
$fn$;

-- ============================================================================
-- S1 — an HONEST frozen snapshot is accepted and stored EXACTLY as submitted
-- ============================================================================
select is(
  (pg_temp.submit('00000000-0000-0000-0000-000000021901', 'op-S1',
                  '00000000-0000-0000-0000-000000021301', true,
                  pg_temp.frozen(true)) ->> 'ok')::boolean,
  true, 'S1a a frozen snapshot matching the live menu is accepted');

select is(
  pg_temp.stored('00000000-0000-0000-0000-000000021901'),
  pg_temp.frozen(true),
  'S1b the stored snapshot IS the validated submitted value');

-- ============================================================================
-- S2 — DELAYED FIRST ACCEPTANCE after the owner changed the contribution
-- ============================================================================
update public.modifier_options
   set kitchen_meat = '{"quantity":3,"unit":"Meat pieces","classifier_option_id":"00000000-0000-0000-0000-000000021302","classifier_option_name":"Cheese"}'::jsonb
 where id = '00000000-0000-0000-0000-000000021301';

select is(
  pg_temp.submit('00000000-0000-0000-0000-000000021902', 'op-S2',
                 '00000000-0000-0000-0000-000000021301', true,
                 pg_temp.frozen(true)) ->> 'error',
  'modifier_prep_snapshot_stale',
  'S2a a frozen quantity of 2 against a live 3 is refused as STALE');

select is(
  (pg_temp.submit('00000000-0000-0000-0000-000000021903', 'op-S2b',
                  '00000000-0000-0000-0000-000000021301', true,
                  pg_temp.frozen(true)) ->> 'ok')::boolean,
  false, 'S2b the stale refusal is ok:false');

select is(
  (select count(*) from public.orders
    where id in ('00000000-0000-0000-0000-000000021902',
                 '00000000-0000-0000-0000-000000021903')),
  0::bigint, 'S2c a stale refusal creates NO orders row');

select is(
  (select count(*) from public.order_items
    where order_id in ('00000000-0000-0000-0000-000000021902',
                       '00000000-0000-0000-0000-000000021903')),
  0::bigint, 'S2d a stale refusal creates NO order_items');

select is(
  (select count(*) from public.order_item_modifiers om
     join public.order_items oi on oi.id = om.order_item_id
    where oi.order_id in ('00000000-0000-0000-0000-000000021902',
                          '00000000-0000-0000-0000-000000021903')),
  0::bigint, 'S2e a stale refusal creates NO order_item_modifiers');

select is(
  (select count(*) from public.kitchen_print_dispatches
    where order_id in ('00000000-0000-0000-0000-000000021902',
                       '00000000-0000-0000-0000-000000021903')),
  0::bigint, 'S2f a stale refusal creates NO kitchen dispatch');

select is(
  (select count(*) from public.audit_events
    where organization_id = '00000000-0000-0000-0000-000000021a00'
      and action = 'order.submitted'
      and new_values ->> 'order_id' in ('00000000-0000-0000-0000-000000021902',
                                        '00000000-0000-0000-0000-000000021903')),
  0::bigint, 'S2g a stale refusal writes NO order.submitted audit event');

select is(
  pg_temp.submit('00000000-0000-0000-0000-000000021904', 'op-S2c',
                 '00000000-0000-0000-0000-000000021301', true,
                 pg_temp.frozen(true)) ->> 'entity',
  'order', 'S2h the refusal carries the established entity key');

select is(
  pg_temp.submit('00000000-0000-0000-0000-000000021905', 'op-S2d',
                 '00000000-0000-0000-0000-000000021301', true,
                 pg_temp.frozen(true)) -> 'modifiers' -> 0 ->> 'option_name_snapshot',
  'Size choice',
  'S2i the refusal names the line using the CLIENT''s own snapshot label');

-- ============================================================================
-- S3 — ACCEPTED REPLAY survives the very same menu change
-- ============================================================================
-- op-S1 was accepted BEFORE the quantity changed to 3. Replaying it must return
-- the stored result, never re-run the comparison, and never restate the answer.
select is(
  (pg_temp.submit('00000000-0000-0000-0000-000000021901', 'op-S1',
                  '00000000-0000-0000-0000-000000021301', true,
                  pg_temp.frozen(true)) ->> 'idempotency_replay')::boolean,
  true, 'S3a an ALREADY-ACCEPTED operation still replays after the menu changed');

select is(
  (pg_temp.submit('00000000-0000-0000-0000-000000021901', 'op-S1',
                  '00000000-0000-0000-0000-000000021301', true,
                  pg_temp.frozen(true)) ->> 'ok')::boolean,
  true, 'S3b the replay is a SUCCESS, not a stale refusal');

select is(
  pg_temp.stored('00000000-0000-0000-0000-000000021901'),
  pg_temp.frozen(true),
  'S3c the replay left the originally frozen answer untouched (2, not 3)');

-- Restore the healthy configuration for the remaining cases.
update public.modifier_options
   set kitchen_meat = '{"quantity":2,"unit":"Meat pieces","classifier_option_id":"00000000-0000-0000-0000-000000021302","classifier_option_name":"Cheese"}'::jsonb
 where id = '00000000-0000-0000-0000-000000021301';

-- ============================================================================
-- S4 — the classifier OPTION was renamed after the draft froze
-- ============================================================================
update public.modifier_options set name = 'Yellow Cheese'
 where id = '00000000-0000-0000-0000-000000021302';

select is(
  pg_temp.submit('00000000-0000-0000-0000-000000021906', 'op-S4',
                 '00000000-0000-0000-0000-000000021301', true,
                 pg_temp.frozen(true)) ->> 'error',
  'modifier_prep_snapshot_stale',
  'S4a a frozen classifier NAME against a renamed live option is refused');

select is(
  (select count(*) from public.orders where id = '00000000-0000-0000-0000-000000021906'),
  0::bigint, 'S4b the rename refusal creates no order');

-- A client holding a REFRESHED menu sends the new name and is accepted — the
-- refusal is recoverable, not a dead end.
select is(
  (pg_temp.submit('00000000-0000-0000-0000-000000021907', 'op-S4c',
                  '00000000-0000-0000-0000-000000021301', true,
                  jsonb_build_object(
                    'quantity', 2, 'unit', 'Meat pieces',
                    'classifier_option_id', '00000000-0000-0000-0000-000000021302',
                    'classifier_option_name', 'Yellow Cheese',
                    'classifier_selected', true)) ->> 'ok')::boolean,
  true, 'S4c a REFRESHED client snapshot with the new name is accepted');

update public.modifier_options set name = 'Cheese'
 where id = '00000000-0000-0000-0000-000000021302';

-- ============================================================================
-- S5 — a LYING client is refused, never silently corrected
-- ============================================================================
select is(
  pg_temp.submit('00000000-0000-0000-0000-000000021908', 'op-S5',
                 '00000000-0000-0000-0000-000000021301', false,
                 pg_temp.frozen(true)) ->> 'error',
  'modifier_prep_snapshot_stale',
  'S5a classifier_selected=true WITHOUT selecting Cheese is refused');

select is(
  pg_temp.submit('00000000-0000-0000-0000-000000021909', 'op-S5b',
                 '00000000-0000-0000-0000-000000021301', true,
                 pg_temp.frozen(false)) ->> 'error',
  'modifier_prep_snapshot_stale',
  'S5b classifier_selected=false WHILE selecting Cheese is refused');

select is(
  pg_temp.submit('00000000-0000-0000-0000-00000002190a', 'op-S5c',
                 '00000000-0000-0000-0000-000000021301', true,
                 '{"quantity":2,"unit":"Meat pieces","classifier_option_id":"00000000-0000-0000-0000-000000021302","classifier_option_name":"TOTALLY FAKE","classifier_selected":true}'::jsonb) ->> 'error',
  'modifier_prep_snapshot_stale',
  'S5c a FAKE classifier name is refused');

select is(
  (select count(*) from public.order_item_modifiers om
     join public.order_items oi on oi.id = om.order_item_id
    where oi.order_id = '00000000-0000-0000-0000-00000002190a'),
  0::bigint, 'S5d the fake name is not stored — nothing is');

select is(
  pg_temp.submit('00000000-0000-0000-0000-00000002190b', 'op-S5e',
                 '00000000-0000-0000-0000-000000021301', true,
                 '{"quantity":2,"unit":"Meat pieces","classifier_option_id":"00000000-0000-0000-0000-000000021304","classifier_option_name":"Cheese","classifier_selected":true}'::jsonb) ->> 'error',
  'modifier_prep_snapshot_stale',
  'S5e a FOREIGN product''s classifier id is refused');

select is(
  pg_temp.submit('00000000-0000-0000-0000-00000002190c', 'op-S5f',
                 '00000000-0000-0000-0000-000000021301', true,
                 '{"quantity":9,"unit":"Free Beer"}'::jsonb) ->> 'error',
  'modifier_prep_snapshot_stale',
  'S5f an invented quantity and unit are refused');

-- ============================================================================
-- S6 — CANONICALISATION: unknown keys are stripped, never a false refusal
-- ============================================================================
select is(
  (pg_temp.submit('00000000-0000-0000-0000-00000002190d', 'op-S6',
                  '00000000-0000-0000-0000-000000021301', true,
                  pg_temp.frozen(true)
                    || '{"nonsense":"x","note":{"deep":1},"extra":[1,2]}'::jsonb) ->> 'ok')::boolean,
  true, 'S6a unknown client keys are stripped and do NOT cause a stale refusal');

select is(
  pg_temp.stored('00000000-0000-0000-0000-00000002190d'),
  pg_temp.frozen(true),
  'S6b only the five canonical keys are stored');

select is(
  (select count(*) from jsonb_object_keys(pg_temp.stored('00000000-0000-0000-0000-00000002190d'))),
  5::bigint, 'S6c exactly five keys survive');

-- ============================================================================
-- S7 — an OMITTED snapshot against a configured option is stale
-- ============================================================================
select is(
  pg_temp.submit('00000000-0000-0000-0000-00000002190e', 'op-S7',
                 '00000000-0000-0000-0000-000000021301', true, null) ->> 'error',
  'modifier_prep_snapshot_stale',
  'S7a omitting meat_snapshot while the option IS configured is refused');

-- ============================================================================
-- S8 — both sides canonically ABSENT is the historical, accepted shape
-- ============================================================================
select is(
  (pg_temp.submit('00000000-0000-0000-0000-00000002190f', 'op-S8',
                  '00000000-0000-0000-0000-000000021305', false, null) ->> 'ok')::boolean,
  true, 'S8a an unconfigured option with no client snapshot is accepted');

select is(
  pg_temp.stored('00000000-0000-0000-0000-00000002190f'),
  null::jsonb, 'S8b nothing is stored for it (the historical shape)');

select is(
  (pg_temp.submit('00000000-0000-0000-0000-000000021910', 'op-S8c',
                  '00000000-0000-0000-0000-000000021303', false,
                  '{"quantity":1,"unit":"Meat pieces"}'::jsonb) ->> 'ok')::boolean,
  true, 'S8c an UNCLASSIFIED contribution that matches is accepted');

select is(
  pg_temp.stored('00000000-0000-0000-0000-000000021910'),
  '{"quantity":1,"unit":"Meat pieces"}'::jsonb,
  'S8d ...and stored as the plain two-key contribution');

-- ============================================================================
-- S9 — an INVALID configuration is canonically unsplit on BOTH sides
-- ============================================================================
-- Point 240g at the CHICKEN's Cheese: the server degrades to unsplit, so a
-- client that also canonicalises to unsplit matches and is accepted.
update public.modifier_options
   set kitchen_meat = '{"quantity":2,"unit":"Meat pieces","classifier_option_id":"00000000-0000-0000-0000-000000021304","classifier_option_name":"Cheese"}'::jsonb
 where id = '00000000-0000-0000-0000-000000021301';

select is(
  (pg_temp.submit('00000000-0000-0000-0000-000000021911', 'op-S9',
                  '00000000-0000-0000-0000-000000021301', true,
                  '{"quantity":2,"unit":"Meat pieces"}'::jsonb) ->> 'ok')::boolean,
  true, 'S9a a degraded (foreign classifier) configuration accepts an unsplit snapshot');

select is(
  pg_temp.stored('00000000-0000-0000-0000-000000021911'),
  '{"quantity":2,"unit":"Meat pieces"}'::jsonb,
  'S9b ...and stores the unsplit contribution');

update public.modifier_options
   set kitchen_meat = '{"quantity":2,"unit":"Meat pieces","classifier_option_id":"00000000-0000-0000-0000-000000021302","classifier_option_name":"Cheese"}'::jsonb
 where id = '00000000-0000-0000-0000-000000021301';

-- ============================================================================
-- D — ADD-ITEMS enforces the identical contract
-- ============================================================================
select is(
  (pg_temp.submit('00000000-0000-0000-0000-000000021920', 'op-D0',
                  '00000000-0000-0000-0000-000000021303', false,
                  '{"quantity":1,"unit":"Meat pieces"}'::jsonb) ->> 'ok')::boolean,
  true, 'D0 the parent order is accepted');

select is(
  (app.add_order_items(
     '00000000-0000-0000-0000-000000021c01', '00000000-0000-0000-0000-000000021920',
     '00000000-0000-0000-0000-000000021d01', 'op-D1',
     pg_temp.body('00000000-0000-0000-0000-000000021301', true, pg_temp.frozen(true)),
     now()) ->> 'ok')::boolean,
  true, 'D1 an HONEST Add-items round is accepted');

select is(
  (select om.meat_snapshot
     from public.order_item_modifiers om
     join public.order_items oi
       on oi.organization_id = om.organization_id and oi.id = om.order_item_id
     join public.order_service_rounds r
       on r.id = oi.service_round_id and r.local_operation_id = 'op-D1'
    where oi.order_id = '00000000-0000-0000-0000-000000021920'
      and om.modifier_option_id = '00000000-0000-0000-0000-000000021301'),
  pg_temp.frozen(true),
  'D2 Add-items stores the validated SUBMITTED snapshot');

-- Freeze the parent's observable state, then change the live menu.
create temporary table d_before as
  select o.revision, o.subtotal_minor, o.grand_total_minor,
         (select count(*) from public.order_service_rounds r where r.order_id = o.id) as rounds,
         (select count(*) from public.order_items i where i.order_id = o.id) as items,
         (select count(*) from public.order_item_modifiers m
            join public.order_items i2 on i2.id = m.order_item_id
           where i2.order_id = o.id) as mods,
         (select count(*) from public.kitchen_print_dispatches k where k.order_id = o.id) as dispatches,
         (select count(*) from public.audit_events a
           where a.organization_id = o.organization_id) as audits
    from public.orders o where o.id = '00000000-0000-0000-0000-000000021920';

update public.modifier_options
   set kitchen_meat = '{"quantity":3,"unit":"Meat pieces","classifier_option_id":"00000000-0000-0000-0000-000000021302","classifier_option_name":"Cheese"}'::jsonb
 where id = '00000000-0000-0000-0000-000000021301';

select is(
  app.add_order_items(
     '00000000-0000-0000-0000-000000021c01', '00000000-0000-0000-0000-000000021920',
     '00000000-0000-0000-0000-000000021d01', 'op-D3',
     pg_temp.body('00000000-0000-0000-0000-000000021301', true, pg_temp.frozen(true)),
     now()) ->> 'error',
  'modifier_prep_snapshot_stale',
  'D3 a stale Add-items FIRST acceptance is refused');

select is(
  (select count(*) from public.order_service_rounds r
    where r.order_id = '00000000-0000-0000-0000-000000021920'),
  (select rounds from d_before),
  'D4 no service round was created');

select is(
  (select revision from public.orders where id = '00000000-0000-0000-0000-000000021920'),
  (select revision from d_before)::integer,
  'D5 the parent revision did not move');

select is(
  (select subtotal_minor from public.orders where id = '00000000-0000-0000-0000-000000021920'),
  (select subtotal_minor from d_before)::bigint,
  'D6 the parent subtotal did not move');

select is(
  (select grand_total_minor from public.orders where id = '00000000-0000-0000-0000-000000021920'),
  (select grand_total_minor from d_before)::bigint,
  'D7 the parent grand total did not move');

select is(
  (select count(*) from public.order_items where order_id = '00000000-0000-0000-0000-000000021920'),
  (select items from d_before),
  'D8 no order_items were added');

select is(
  (select count(*) from public.order_item_modifiers m
     join public.order_items i on i.id = m.order_item_id
    where i.order_id = '00000000-0000-0000-0000-000000021920'),
  (select mods from d_before),
  'D9 no order_item_modifiers were added');

select is(
  (select count(*) from public.kitchen_print_dispatches
    where order_id = '00000000-0000-0000-0000-000000021920'),
  (select dispatches from d_before),
  'D10 no kitchen dispatch was created');

select is(
  pg_temp.audits(),
  (select audits from d_before),
  'D11 NO audit event of any kind was written for the stale refusal');

-- The already-accepted round still replays under the changed menu.
select is(
  (app.add_order_items(
     '00000000-0000-0000-0000-000000021c01', '00000000-0000-0000-0000-000000021920',
     '00000000-0000-0000-0000-000000021d01', 'op-D1',
     pg_temp.body('00000000-0000-0000-0000-000000021301', true, pg_temp.frozen(true)),
     now()) ->> 'idempotency_replay')::boolean,
  true, 'D12 the ACCEPTED round still replays after the menu changed');

select is(
  (select om.meat_snapshot
     from public.order_item_modifiers om
     join public.order_items oi
       on oi.organization_id = om.organization_id and oi.id = om.order_item_id
     join public.order_service_rounds r
       on r.id = oi.service_round_id and r.local_operation_id = 'op-D1'
    where oi.order_id = '00000000-0000-0000-0000-000000021920'
      and om.modifier_option_id = '00000000-0000-0000-0000-000000021301'),
  pg_temp.frozen(true),
  'D13 the replayed round kept its originally frozen answer');

-- ============================================================================
-- H — the CANONICAL comparison itself, stated case by case
-- ============================================================================
select ok(
  not (app.kitchen_modifier_prep_projection(null) is distinct from
       null::jsonb),
  'H1 both canonically NULL is a MATCH (case A)');

select ok(
  not (app.kitchen_modifier_prep_projection(pg_temp.frozen(true)) is distinct from
       pg_temp.frozen(true)),
  'H2 identical canonical values MATCH (case B)');

select ok(
  app.kitchen_modifier_prep_projection(pg_temp.frozen(true) || '{"quantity":3}'::jsonb)
    is distinct from pg_temp.frozen(true),
  'H3 a different QUANTITY is stale (case C)');

select ok(
  app.kitchen_modifier_prep_projection(pg_temp.frozen(true) || '{"unit":"Fish"}'::jsonb)
    is distinct from pg_temp.frozen(true),
  'H4 a different UNIT is stale (case D)');

select ok(
  app.kitchen_modifier_prep_projection(
    pg_temp.frozen(true) || '{"classifier_option_id":"00000000-0000-0000-0000-000000021304"}'::jsonb)
    is distinct from pg_temp.frozen(true),
  'H5 a different classifier ID is stale (cases E and H)');

select ok(
  app.kitchen_modifier_prep_projection(
    pg_temp.frozen(true) || '{"classifier_option_name":"Yellow Cheese"}'::jsonb)
    is distinct from pg_temp.frozen(true),
  'H6 a different classifier NAME is stale (cases F and I)');

select ok(
  app.kitchen_modifier_prep_projection(pg_temp.frozen(false))
    is distinct from pg_temp.frozen(true),
  'H7 a contradicted classifier_selected is stale (case G)');

select ok(
  not (app.kitchen_modifier_prep_projection(
         pg_temp.frozen(true) || '{"junk":1,"more":"x"}'::jsonb)
       is distinct from pg_temp.frozen(true)),
  'H8 unknown keys are stripped before comparison, never stale (case L)');

select ok(
  not (app.kitchen_modifier_prep_projection('{"quantity":2.0,"unit":"Meat pieces"}'::jsonb)
       is distinct from '{"quantity":2,"unit":"Meat pieces"}'::jsonb),
  'H9 the comparison is SEMANTIC: 2.0 and 2 are the same number');

select ok(
  not (app.kitchen_modifier_prep_projection(
         '{"unit":"Meat pieces","quantity":2}'::jsonb)
       is distinct from '{"quantity":2,"unit":"Meat pieces"}'::jsonb),
  'H10 key ORDER never causes a stale refusal');

-- ============================================================================
-- P — DURABLE DISPATCH PARITY: the printer-only ticket carries the FROZEN answer
-- ============================================================================
-- This is what the whole correction is for. The POS confirmation, the direct
-- kitchen print and every local reprint render the frozen operation; the durable
-- spool renders whatever the server projected. Storing the submitted value is
-- what keeps those two the same paper — including AFTER the owner edits the menu.
create or replace function pg_temp.dispatch_prep(p_order uuid)
  returns jsonb language sql as $fn$
  select m -> 'prep'
    from jsonb_array_elements(
           app.kitchen_dispatch_payload_initial(
             '00000000-0000-0000-0000-000000021a00', p_order) -> 'items') i
    cross join lateral jsonb_array_elements(i -> 'modifiers') m
   where m ->> 'name' = 'Size choice'
   limit 1;
$fn$;

select is(
  pg_temp.dispatch_prep('00000000-0000-0000-0000-000000021901'),
  pg_temp.frozen(true),
  'P1 the durable dispatch payload carries the SUBMITTED frozen snapshot');

-- Now move the live menu underneath the already-accepted order.
update public.modifier_options
   set kitchen_meat = '{"quantity":7,"unit":"Fish cakes"}'::jsonb
 where id = '00000000-0000-0000-0000-000000021301';

select is(
  pg_temp.dispatch_prep('00000000-0000-0000-0000-000000021901'),
  pg_temp.frozen(true),
  'P2 a later menu edit CANNOT change the ticket of an accepted order');

select is(
  pg_temp.stored('00000000-0000-0000-0000-000000021901'),
  pg_temp.dispatch_prep('00000000-0000-0000-0000-000000021901'),
  'P3 stored row and durable dispatch are the same answer, always');

select * from finish();
rollback;
