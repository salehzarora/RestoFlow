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
-- HOW IT IS ENFORCED NOW (021).
--
--   020 closed the hole by having the server DERIVE the snapshot and store its
--   own answer, discarding whatever the client sent. That silently replaced a
--   frozen operation's answer whenever the menu had moved on, so one accepted
--   order could carry two different preparation answers (POS vs KDS/spool).
--
--   021 keeps the identical trust boundary and changes only the VERDICT: the
--   server still derives its own snapshot from its own rows and still believes
--   nothing the client says — but it now COMPARES, and REFUSES the whole
--   operation (`modifier_prep_snapshot_stale`) instead of quietly overwriting.
--   A lying client therefore gets LESS than before: not a corrected row, but no
--   row at all.
--
--   These assertions are the same security cases, restated against that
--   verdict. The stale/replay/atomicity contract itself lives in
--   modifier_prep_stale_snapshot_021_test.sql.
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

select plan(30);

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

-- The exact frozen snapshot a CURRENT POS produces for the 240g option.
create or replace function pg_temp.frozen(p_selected boolean)
  returns jsonb language sql immutable as $fn$
  select jsonb_build_object(
    'quantity', 2, 'unit', 'Meat pieces',
    'classifier_option_id', '00000000-0000-0000-0000-000000020302',
    'classifier_option_name', 'Cheese',
    'classifier_selected', p_selected);
$fn$;

-- ============================================================================
-- A — the honest cases: a frozen snapshot that matches is accepted AS SUBMITTED
-- ============================================================================
select is(
  (pg_temp.submit('00000000-0000-0000-0000-000000020901', 'op-A1',
                  '00000000-0000-0000-0000-000000020301', true,
                  pg_temp.frozen(true)) ->> 'ok')::boolean,
  true, 'A1 a normal 240g + Cheese submit is accepted');

select is(
  pg_temp.stored('00000000-0000-0000-0000-000000020901'),
  pg_temp.frozen(true),
  'A2 the stored snapshot is the VALIDATED SUBMITTED value, unchanged');

select is(
  (pg_temp.submit('00000000-0000-0000-0000-000000020902', 'op-A3',
                  '00000000-0000-0000-0000-000000020301', false,
                  pg_temp.frozen(false)) -> 'ok')::text,
  'true', 'A3 the same order without Cheese is accepted');

select is(
  pg_temp.stored('00000000-0000-0000-0000-000000020902') -> 'classifier_selected',
  'false'::jsonb,
  'A4 without Cheese the stored answer is classifier_selected = false');

select is(
  pg_temp.stored('00000000-0000-0000-0000-000000020902') -> 'quantity',
  '2'::jsonb,
  'A5 the PER-UNIT quantity is stored (modifier units stay in their own column)');

-- ============================================================================
-- B — a lying client (the whole point of Codex MEDIUM #4) is now REFUSED
-- ============================================================================
select is(
  pg_temp.submit('00000000-0000-0000-0000-000000020903', 'op-B1',
     '00000000-0000-0000-0000-000000020301', false, pg_temp.frozen(true)) ->> 'error',
  'modifier_prep_snapshot_stale',
  'B1 claiming classifier_selected=true WITHOUT selecting Cheese is refused');

select is(
  (select count(*) from public.orders where id = '00000000-0000-0000-0000-000000020903'),
  0::bigint, 'B2 ...and no order exists: the lie was not corrected, it was rejected');

select is(
  pg_temp.submit('00000000-0000-0000-0000-000000020904', 'op-B3',
     '00000000-0000-0000-0000-000000020301', true, pg_temp.frozen(false)) ->> 'error',
  'modifier_prep_snapshot_stale',
  'B3 claiming classifier_selected=false WHILE selecting Cheese is refused');

select is(
  pg_temp.submit('00000000-0000-0000-0000-000000020905', 'op-B4',
     '00000000-0000-0000-0000-000000020301', true,
     '{"quantity":2,"unit":"Meat pieces",
       "classifier_option_id":"00000000-0000-0000-0000-000000020302",
       "classifier_option_name":"TOTALLY FAKE","classifier_selected":true}'::jsonb) ->> 'error',
  'modifier_prep_snapshot_stale',
  'B4 a FAKE classifier name is refused');

select is(
  pg_temp.stored('00000000-0000-0000-0000-000000020905'),
  null::jsonb, 'B5 ...and nothing at all was stored under that order');

select is(
  pg_temp.submit('00000000-0000-0000-0000-000000020906', 'op-B6',
     '00000000-0000-0000-0000-000000020301', true,
     '{"quantity":99,"unit":"Free Beer",
       "classifier_option_id":"00000000-0000-0000-0000-000000020302",
       "classifier_option_name":"Cheese","classifier_selected":true}'::jsonb) ->> 'error',
  'modifier_prep_snapshot_stale',
  'B6 an invented quantity and unit are refused');

select is(
  pg_temp.submit('00000000-0000-0000-0000-000000020907', 'op-B7',
     '00000000-0000-0000-0000-000000020301', true,
     '{"quantity":2,"unit":"Meat pieces",
       "classifier_option_id":"00000000-0000-0000-0000-000000020304",
       "classifier_option_name":"Cheese","classifier_selected":true}'::jsonb) ->> 'error',
  'modifier_prep_snapshot_stale',
  'B7 a classifier id belonging to ANOTHER product is refused');

select is(
  pg_temp.submit('00000000-0000-0000-0000-000000020908', 'op-B8',
     '00000000-0000-0000-0000-000000020301', true, null) ->> 'error',
  'modifier_prep_snapshot_stale',
  'B8 omitting the snapshot while the option IS configured is refused');

-- ============================================================================
-- C — invalid classifier configuration degrades to unsplit on BOTH sides
-- ============================================================================
-- The degradation rules are unchanged by 021; what changed is that the CLIENT
-- must arrive at the same canonical answer. A POS reading the same live menu
-- does, because it applies the same link rules to the same rows.
update public.modifier_options
   set kitchen_meat = '{"quantity":2,"unit":"Meat pieces",
                        "classifier_option_id":"00000000-0000-0000-0000-000000020304",
                        "classifier_option_name":"Cheese"}'::jsonb
 where id = '00000000-0000-0000-0000-000000020301';

select is(
  pg_temp.submit('00000000-0000-0000-0000-000000020909', 'op-C1',
                 '00000000-0000-0000-0000-000000020301', true,
                 '{"quantity":2,"unit":"Meat pieces"}'::jsonb) ->> 'ok',
  'true', 'C1 a foreign-product classifier config accepts an UNSPLIT snapshot');

select is(
  pg_temp.stored('00000000-0000-0000-0000-000000020909'),
  '{"quantity":2,"unit":"Meat pieces"}'::jsonb,
  'C2 a FOREIGN product classifier degrades to an UNSPLIT contribution');

update public.modifier_options
   set kitchen_meat = '{"quantity":2,"unit":"Meat pieces",
                        "classifier_option_id":"00000000-0000-0000-0000-000000020301",
                        "classifier_option_name":"240g"}'::jsonb
 where id = '00000000-0000-0000-0000-000000020301';

select ok(
  (pg_temp.submit('00000000-0000-0000-0000-00000002090a', 'op-C3',
                  '00000000-0000-0000-0000-000000020301', true,
                  '{"quantity":2,"unit":"Meat pieces"}'::jsonb) ->> 'ok')::boolean,
  'C3 a self-referencing classifier config accepts an UNSPLIT snapshot');

select is(
  pg_temp.stored('00000000-0000-0000-0000-00000002090a'),
  '{"quantity":2,"unit":"Meat pieces"}'::jsonb,
  'C4 a SELF-REFERENCE degrades to an UNSPLIT contribution');

update public.modifier_options
   set kitchen_meat = '{"quantity":2,"unit":"Meat pieces",
                        "classifier_option_id":"00000000-0000-0000-0000-0000deadbeef",
                        "classifier_option_name":"Ghost"}'::jsonb
 where id = '00000000-0000-0000-0000-000000020301';
select is(
  (select pg_temp.submit('00000000-0000-0000-0000-00000002090b', 'op-C5',
                         '00000000-0000-0000-0000-000000020301', true,
                         '{"quantity":2,"unit":"Meat pieces"}'::jsonb) ->> 'ok'),
  'true', 'C5 a deleted/nonexistent classifier config accepts an UNSPLIT snapshot');
select is(
  pg_temp.stored('00000000-0000-0000-0000-00000002090b'),
  '{"quantity":2,"unit":"Meat pieces"}'::jsonb,
  'C6 a NONEXISTENT classifier degrades to an UNSPLIT contribution');

update public.modifier_options
   set kitchen_meat = '{"quantity":2,"unit":"Meat pieces",
                        "classifier_option_id":{"amount_minor":5}}'::jsonb
 where id = '00000000-0000-0000-0000-000000020301';
select is(
  (select pg_temp.submit('00000000-0000-0000-0000-00000002090c', 'op-C7',
                         '00000000-0000-0000-0000-000000020301', true,
                         '{"quantity":2,"unit":"Meat pieces"}'::jsonb) ->> 'ok'),
  'true', 'C7 malformed classifier configuration accepts an UNSPLIT snapshot');
select is(
  pg_temp.stored('00000000-0000-0000-0000-00000002090c'),
  '{"quantity":2,"unit":"Meat pieces"}'::jsonb,
  'C8 MALFORMED classifier metadata keeps the valid quantity/unit, unsplit');

update public.modifier_options
   set kitchen_meat = '{"quantity":0,"unit":"Meat pieces"}'::jsonb
 where id = '00000000-0000-0000-0000-000000020301';
select is(
  (select pg_temp.submit('00000000-0000-0000-0000-00000002090d', 'op-C9',
                         '00000000-0000-0000-0000-000000020301', true, null) ->> 'ok'),
  'true', 'C9 a zero-quantity configuration accepts a snapshot-less line');
select is(
  pg_temp.stored('00000000-0000-0000-0000-00000002090d'),
  null::jsonb,
  'C10 a ZERO configured quantity stores NO contribution (never a unit-only row)');

select is(
  (select pg_temp.submit('00000000-0000-0000-0000-00000002090e', 'op-C11',
                         '00000000-0000-0000-0000-000000020303', false,
                         '{"quantity":1,"unit":"Meat pieces"}'::jsonb) ->> 'ok'),
  'true', 'C11 an unclassified 120g submit is accepted');
select is(
  pg_temp.stored('00000000-0000-0000-0000-00000002090e'),
  '{"quantity":1,"unit":"Meat pieces"}'::jsonb,
  'C12 an UNCLASSIFIED option stores its plain contribution');

-- ============================================================================
-- D — Add-items enforces the identical contract
-- ============================================================================
update public.modifier_options
   set kitchen_meat = '{"quantity":2,"unit":"Meat pieces",
                        "classifier_option_id":"00000000-0000-0000-0000-000000020302",
                        "classifier_option_name":"Cheese"}'::jsonb
 where id = '00000000-0000-0000-0000-000000020301';

select is(
  (pg_temp.submit('00000000-0000-0000-0000-00000002090f', 'op-D0',
                  '00000000-0000-0000-0000-000000020303', false,
                  '{"quantity":1,"unit":"Meat pieces"}'::jsonb) ->> 'ok')::text,
  'true', 'D0 the parent order for the Add-items round is accepted');

select is(
  app.add_order_items(
     '00000000-0000-0000-0000-000000020c01',
     '00000000-0000-0000-0000-00000002090f',
     '00000000-0000-0000-0000-000000020d01', 'op-D1',
     pg_temp.body('00000000-0000-0000-0000-000000020301', true,
       '{"quantity":2,"unit":"Meat pieces",
         "classifier_option_id":"00000000-0000-0000-0000-000000020302",
         "classifier_option_name":"LIES","classifier_selected":false}'::jsonb),
     now()) ->> 'error',
  'modifier_prep_snapshot_stale',
  'D1 Add-items with a lying snapshot is REFUSED');

select is(
  (select count(*) from public.order_service_rounds
    where order_id = '00000000-0000-0000-0000-00000002090f'),
  0::bigint, 'D2 ...and no service round was created');

select is(
  (app.add_order_items(
     '00000000-0000-0000-0000-000000020c01',
     '00000000-0000-0000-0000-00000002090f',
     '00000000-0000-0000-0000-000000020d01', 'op-D3',
     pg_temp.body('00000000-0000-0000-0000-000000020301', true, pg_temp.frozen(true)),
     now()) ->> 'ok')::boolean,
  true, 'D3 an HONEST Add-items round is accepted');

select is(
  (select om.meat_snapshot
     from public.order_item_modifiers om
     join public.order_items oi
       on oi.organization_id = om.organization_id and oi.id = om.order_item_id
    where oi.order_id = '00000000-0000-0000-0000-00000002090f'
      and oi.service_round_id is not null
      and om.modifier_option_id = '00000000-0000-0000-0000-000000020301'),
  pg_temp.frozen(true),
  'D4 Add-items stores the VALIDATED SUBMITTED snapshot');

select * from finish();
rollback;
