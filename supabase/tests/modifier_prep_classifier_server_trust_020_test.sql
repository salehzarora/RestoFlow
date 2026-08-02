-- ============================================================================
-- KITCHEN-MODIFIER-PREP-CLASSIFIER-CODEX-FIX-020 - SERVER-SIDE TRUST (pgTAP).
-- ============================================================================
-- THE DEFECT (Codex MEDIUM #4).
--
--   app.submit_order and app.add_order_items stored the client's
--   `meat_snapshot` VERBATIM. A modified authenticated client could therefore
--   declare:
--     * classifier_selected = true for a classifier it never selected,
--     * classifier_selected = false for one it did,
--     * a classifier option belonging to ANOTHER product,
--     * a fake classifier NAME,
--     * a self-reference,
--   and the KDS, the printed ticket and the durable spool would all have
--   believed it. A client-side resolver is necessary but not sufficient.
--
-- These tests drive the REAL authoritative RPCs — not the projection helper —
-- and read back what the server actually STORED in order_item_modifiers.
--
-- The catalogue below is Saleh's shape: a Size group whose 240g option carries
-- the Meat contribution, an Extras group holding Cheese, and a DIFFERENT product
-- that also has an option called "Cheese".
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(27);

-- ------------------------------------------------------------------- scope
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-000000020a00', 'Org 020', 'org-020', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-000000020a01', '00000000-0000-0000-0000-000000020a00', 'Rest 020');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-000000020b01', '00000000-0000-0000-0000-000000020a00', '00000000-0000-0000-0000-000000020a01', 'Branch 020');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-000000020d01', '00000000-0000-0000-0000-000000020a00', '00000000-0000-0000-0000-000000020a01', '00000000-0000-0000-0000-000000020b01', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-000000020f01', '00000000-0000-0000-0000-000000020a00', '00000000-0000-0000-0000-000000020a01', '00000000-0000-0000-0000-000000020b01', '00000000-0000-0000-0000-000000020d01', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-000000020501', '00000000-0000-0000-0000-000000020a00', '00000000-0000-0000-0000-000000020a01', '00000000-0000-0000-0000-000000020b01', '00000000-0000-0000-0000-000000020d01', '00000000-0000-0000-0000-000000020f01');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-000000020e01', 'trust020@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-000000020601', '00000000-0000-0000-0000-000000020e01', '00000000-0000-0000-0000-000000020a00', '00000000-0000-0000-0000-000000020a01', '00000000-0000-0000-0000-000000020b01', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-000000020701', '00000000-0000-0000-0000-000000020a00', '00000000-0000-0000-0000-000000020a01', '00000000-0000-0000-0000-000000020b01', '00000000-0000-0000-0000-000000020e01', '00000000-0000-0000-0000-000000020601');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-000000020c01', '00000000-0000-0000-0000-000000020a00', '00000000-0000-0000-0000-000000020a01', '00000000-0000-0000-0000-000000020b01', '00000000-0000-0000-0000-000000020501', '00000000-0000-0000-0000-000000020701', '00000000-0000-0000-0000-000000020601', now() + interval '1 hour');

-- --------------------------------------------------------------- catalogue
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('00000000-0000-0000-0000-0000000200c1', '00000000-0000-0000-0000-000000020a00', '00000000-0000-0000-0000-000000020a01', null, 'Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('00000000-0000-0000-0000-000000020101', '00000000-0000-0000-0000-000000020a00', '00000000-0000-0000-0000-000000020a01', null, '00000000-0000-0000-0000-0000000200c1', 'Burger', 4500, 'ILS', 1),
  ('00000000-0000-0000-0000-000000020102', '00000000-0000-0000-0000-000000020a00', '00000000-0000-0000-0000-000000020a01', null, '00000000-0000-0000-0000-0000000200c1', 'Chicken', 4500, 'ILS', 2);

-- Burger: a Size group (the meat lives here) + an Extras group (Cheese).
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name) values
  ('00000000-0000-0000-0000-000000020201', '00000000-0000-0000-0000-000000020a00', '00000000-0000-0000-0000-000000020a01', null, '00000000-0000-0000-0000-000000020101', 'Size'),
  ('00000000-0000-0000-0000-000000020202', '00000000-0000-0000-0000-000000020a00', '00000000-0000-0000-0000-000000020a01', null, '00000000-0000-0000-0000-000000020101', 'Extras'),
  -- The CHICKEN's own Extras group — a different product.
  ('00000000-0000-0000-0000-000000020203', '00000000-0000-0000-0000-000000020a00', '00000000-0000-0000-0000-000000020a01', null, '00000000-0000-0000-0000-000000020102', 'Extras');

insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, kitchen_meat) values
  -- 240g contributes 2 Meat pieces and is CONFIGURED to be split by Cheese.
  ('00000000-0000-0000-0000-000000020301', '00000000-0000-0000-0000-000000020a00', '00000000-0000-0000-0000-000000020a01', null, '00000000-0000-0000-0000-000000020201', '240g', 0,
   '{"quantity":2,"unit":"Meat pieces","classifier_option_id":"00000000-0000-0000-0000-000000020302","classifier_option_name":"Cheese"}'::jsonb),
  -- Cheese: the classifier. Its OWN contribution is deliberately absent.
  ('00000000-0000-0000-0000-000000020302', '00000000-0000-0000-0000-000000020a00', '00000000-0000-0000-0000-000000020a01', null, '00000000-0000-0000-0000-000000020202', 'Cheese', 300, null),
  -- 120g contributes 1 Meat piece, unclassified.
  ('00000000-0000-0000-0000-000000020303', '00000000-0000-0000-0000-000000020a00', '00000000-0000-0000-0000-000000020a01', null, '00000000-0000-0000-0000-000000020201', '120g', 0,
   '{"quantity":1,"unit":"Meat pieces"}'::jsonb),
  -- The CHICKEN's "Cheese" — same name, different product.
  ('00000000-0000-0000-0000-000000020304', '00000000-0000-0000-0000-000000020a00', '00000000-0000-0000-0000-000000020a01', null, '00000000-0000-0000-0000-000000020203', 'Cheese', 300, null);

-- ----------------------------------------------------------------- helpers
-- One Burger line with a chosen size, optionally with Cheese, and whatever
-- meat_snapshot the CLIENT chose to declare for the size option.
create or replace function pg_temp.body(
  p_size uuid, p_with_cheese boolean, p_client_meat jsonb)
  returns jsonb language sql immutable as $fn$
  select jsonb_build_array(jsonb_build_object(
    'menu_item_id', '00000000-0000-0000-0000-000000020101',
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
             'modifier_option_id', '00000000-0000-0000-0000-000000020302',
             'price_minor_snapshot', 300,
             'quantity', 1,
             'modifier_name_snapshot', 'Extras',
             'option_name_snapshot', 'Cheese'))
         else '[]'::jsonb end));
$fn$;

create or replace function pg_temp.submit(
  p_order uuid, p_op text, p_size uuid, p_with_cheese boolean,
  p_client_meat jsonb)
  returns jsonb language sql as $fn$
  select app.submit_order(
    '00000000-0000-0000-0000-000000020c01', p_order,
    '00000000-0000-0000-0000-000000020d01', p_op, 'takeaway', null, null, 'ILS', null,
    pg_temp.body(p_size, p_with_cheese, p_client_meat),
    case when p_with_cheese then 4800 else 4500 end, 0, 0,
    case when p_with_cheese then 4800 else 4500 end, null);
$fn$;

-- The snapshot the SERVER stored for the size option of an order.
create or replace function pg_temp.stored(p_order uuid)
  returns jsonb language sql as $fn$
  select om.meat_snapshot
    from public.order_item_modifiers om
    join public.order_items oi
      on oi.organization_id = om.organization_id and oi.id = om.order_item_id
   where oi.order_id = p_order
     and om.modifier_option_id in ('00000000-0000-0000-0000-000000020301',
                                   '00000000-0000-0000-0000-000000020303')
   limit 1;
$fn$;

-- ============================================================================
-- A — the honest cases
-- ============================================================================
select is(
  (pg_temp.submit('00000000-0000-0000-0000-000000020901', 'op-A1',
                  '00000000-0000-0000-0000-000000020301', true, null) ->> 'ok')::boolean,
  true, 'A1 a normal 240g + Cheese submit is accepted');

select is(
  pg_temp.stored('00000000-0000-0000-0000-000000020901'),
  '{"quantity":2,"unit":"Meat pieces",
    "classifier_option_id":"00000000-0000-0000-0000-000000020302",
    "classifier_option_name":"Cheese","classifier_selected":true}'::jsonb,
  'A2 the server DERIVED the whole snapshot (client sent none at all)');

select is(
  (pg_temp.submit('00000000-0000-0000-0000-000000020902', 'op-A3',
                  '00000000-0000-0000-0000-000000020301', false, null) -> 'ok')::text,
  'true', 'A3 the same order without Cheese is accepted');

select is(
  pg_temp.stored('00000000-0000-0000-0000-000000020902') -> 'classifier_selected',
  'false'::jsonb,
  'A4 without Cheese the server stores classifier_selected = false');

select is(
  pg_temp.stored('00000000-0000-0000-0000-000000020902') -> 'quantity',
  '2'::jsonb,
  'A5 the PER-UNIT quantity is stored (modifier units stay in their own column)');

-- ============================================================================
-- B — a lying client (the whole point of Codex MEDIUM #4)
-- ============================================================================
select ok(
  (pg_temp.submit('00000000-0000-0000-0000-000000020903', 'op-B1',
     '00000000-0000-0000-0000-000000020301', false,
     '{"quantity":2,"unit":"Meat pieces",
       "classifier_option_id":"00000000-0000-0000-0000-000000020302",
       "classifier_option_name":"Cheese","classifier_selected":true}'::jsonb) ->> 'ok')::boolean,
  'B1 a submit claiming classifier_selected=true WITHOUT selecting Cheese is accepted');

select is(
  pg_temp.stored('00000000-0000-0000-0000-000000020903') -> 'classifier_selected',
  'false'::jsonb,
  'B2 ...but the SERVER stores FALSE: Cheese was never selected');

select ok(
  (pg_temp.submit('00000000-0000-0000-0000-000000020904', 'op-B3',
     '00000000-0000-0000-0000-000000020301', true,
     '{"quantity":2,"unit":"Meat pieces",
       "classifier_option_id":"00000000-0000-0000-0000-000000020302",
       "classifier_option_name":"Cheese","classifier_selected":false}'::jsonb) ->> 'ok')::boolean,
  'B3 a submit claiming classifier_selected=false WHILE selecting Cheese is accepted');

select is(
  pg_temp.stored('00000000-0000-0000-0000-000000020904') -> 'classifier_selected',
  'true'::jsonb,
  'B4 ...but the SERVER stores TRUE: Cheese was selected');

select is(
  pg_temp.stored('00000000-0000-0000-0000-000000020904') ->> 'classifier_option_name',
  'Cheese',
  'B5 the stored NAME comes from the server row, not the payload');

-- A fake NAME on the wire is ignored entirely.
select ok(
  (pg_temp.submit('00000000-0000-0000-0000-000000020905', 'op-B6',
     '00000000-0000-0000-0000-000000020301', true,
     '{"quantity":99,"unit":"Free Beer",
       "classifier_option_id":"00000000-0000-0000-0000-000000020302",
       "classifier_option_name":"TOTALLY FAKE","classifier_selected":true}'::jsonb) ->> 'ok')::boolean,
  'B6 a submit with a fake name and a fake quantity is accepted');

select is(
  pg_temp.stored('00000000-0000-0000-0000-000000020905'),
  '{"quantity":2,"unit":"Meat pieces",
    "classifier_option_id":"00000000-0000-0000-0000-000000020302",
    "classifier_option_name":"Cheese","classifier_selected":true}'::jsonb,
  'B7 NOTHING client-supplied survives: quantity, unit and name are the server''s');

-- ============================================================================
-- C — invalid classifier configuration degrades to unsplit, never to nothing
-- ============================================================================
-- Point 240g at the CHICKEN's Cheese (a foreign product's option).
update public.modifier_options
   set kitchen_meat = '{"quantity":2,"unit":"Meat pieces",
                        "classifier_option_id":"00000000-0000-0000-0000-000000020304",
                        "classifier_option_name":"Cheese"}'::jsonb
 where id = '00000000-0000-0000-0000-000000020301';

select is(
  pg_temp.submit('00000000-0000-0000-0000-000000020906', 'op-C1',
                 '00000000-0000-0000-0000-000000020301', true, null) ->> 'ok',
  'true', 'C1 a foreign-product classifier does not break the submit');

select is(
  pg_temp.stored('00000000-0000-0000-0000-000000020906'),
  '{"quantity":2,"unit":"Meat pieces"}'::jsonb,
  'C2 a FOREIGN product classifier degrades to an UNSPLIT contribution');

-- Self-reference.
update public.modifier_options
   set kitchen_meat = '{"quantity":2,"unit":"Meat pieces",
                        "classifier_option_id":"00000000-0000-0000-0000-000000020301",
                        "classifier_option_name":"240g"}'::jsonb
 where id = '00000000-0000-0000-0000-000000020301';

select ok(
  (pg_temp.submit('00000000-0000-0000-0000-000000020907', 'op-C3',
                  '00000000-0000-0000-0000-000000020301', true, null) ->> 'ok')::boolean,
  'C3 a self-referencing classifier does not break the submit');

select is(
  pg_temp.stored('00000000-0000-0000-0000-000000020907'),
  '{"quantity":2,"unit":"Meat pieces"}'::jsonb,
  'C4 a SELF-REFERENCE degrades to an UNSPLIT contribution');

-- A nonexistent classifier id.
update public.modifier_options
   set kitchen_meat = '{"quantity":2,"unit":"Meat pieces",
                        "classifier_option_id":"00000000-0000-0000-0000-0000deadbeef",
                        "classifier_option_name":"Ghost"}'::jsonb
 where id = '00000000-0000-0000-0000-000000020301';
select is(
  (select pg_temp.submit('00000000-0000-0000-0000-000000020908', 'op-C5',
                         '00000000-0000-0000-0000-000000020301', true, null) ->> 'ok'),
  'true', 'C5 a deleted/nonexistent classifier does not break the submit');
select is(
  pg_temp.stored('00000000-0000-0000-0000-000000020908'),
  '{"quantity":2,"unit":"Meat pieces"}'::jsonb,
  'C6 a NONEXISTENT classifier degrades to an UNSPLIT contribution');

-- A malformed (non-string) classifier id in the stored configuration.
update public.modifier_options
   set kitchen_meat = '{"quantity":2,"unit":"Meat pieces",
                        "classifier_option_id":{"amount_minor":5}}'::jsonb
 where id = '00000000-0000-0000-0000-000000020301';
select is(
  (select pg_temp.submit('00000000-0000-0000-0000-000000020909', 'op-C7',
                         '00000000-0000-0000-0000-000000020301', true, null) ->> 'ok'),
  'true', 'C7 malformed classifier configuration does not break the submit');
select is(
  pg_temp.stored('00000000-0000-0000-0000-000000020909'),
  '{"quantity":2,"unit":"Meat pieces"}'::jsonb,
  'C8 MALFORMED classifier metadata keeps the valid quantity/unit, unsplit');

-- A non-positive configured quantity contributes nothing at all.
update public.modifier_options
   set kitchen_meat = '{"quantity":0,"unit":"Meat pieces"}'::jsonb
 where id = '00000000-0000-0000-0000-000000020301';
select is(
  (select pg_temp.submit('00000000-0000-0000-0000-00000002090a', 'op-C9',
                         '00000000-0000-0000-0000-000000020301', true, null) ->> 'ok'),
  'true', 'C9 a zero-quantity configuration does not break the submit');
select is(
  pg_temp.stored('00000000-0000-0000-0000-00000002090a'),
  null::jsonb,
  'C10 a ZERO configured quantity stores NO contribution (never a unit-only row)');

-- An option with NO configuration at all stores nothing (the historical shape).
select is(
  (select pg_temp.submit('00000000-0000-0000-0000-00000002090b', 'op-C11',
                         '00000000-0000-0000-0000-000000020303', false, null) ->> 'ok'),
  'true', 'C11 an unclassified 120g submit is accepted');
select is(
  pg_temp.stored('00000000-0000-0000-0000-00000002090b'),
  '{"quantity":1,"unit":"Meat pieces"}'::jsonb,
  'C12 an UNCLASSIFIED option stores its plain contribution');

-- ============================================================================
-- D — Add-items enforces the identical contract
-- ============================================================================
-- Restore the healthy 240g configuration first.
update public.modifier_options
   set kitchen_meat = '{"quantity":2,"unit":"Meat pieces",
                        "classifier_option_id":"00000000-0000-0000-0000-000000020302",
                        "classifier_option_name":"Cheese"}'::jsonb
 where id = '00000000-0000-0000-0000-000000020301';

-- A live parent order to add to.
select is(
  (pg_temp.submit('00000000-0000-0000-0000-00000002090c', 'op-D0',
                  '00000000-0000-0000-0000-000000020303', false, null) ->> 'ok')::text,
  'true', 'D0 the parent order for the Add-items round is accepted');

select is(
  (app.add_order_items(
     '00000000-0000-0000-0000-000000020c01',
     '00000000-0000-0000-0000-00000002090c',
     '00000000-0000-0000-0000-000000020d01', 'op-D1',
     pg_temp.body('00000000-0000-0000-0000-000000020301', true,
       '{"quantity":2,"unit":"Meat pieces",
         "classifier_option_id":"00000000-0000-0000-0000-000000020302",
         "classifier_option_name":"LIES","classifier_selected":false}'::jsonb),
     now()) ->> 'ok')::text,
  'true', 'D1 Add-items with a lying snapshot is accepted');

select is(
  (select om.meat_snapshot
     from public.order_item_modifiers om
     join public.order_items oi
       on oi.organization_id = om.organization_id and oi.id = om.order_item_id
    where oi.order_id = '00000000-0000-0000-0000-00000002090c'
      and oi.service_round_id is not null
      and om.modifier_option_id = '00000000-0000-0000-0000-000000020301'),
  '{"quantity":2,"unit":"Meat pieces",
    "classifier_option_id":"00000000-0000-0000-0000-000000020302",
    "classifier_option_name":"Cheese","classifier_selected":true}'::jsonb,
  'D2 Add-items ALSO derives the trusted snapshot: name fixed, selected=true');

select * from finish();
rollback;
