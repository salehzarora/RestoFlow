-- ============================================================================
-- KIOSK-PRINT-114B.5B — pos_order_detail exposes the persisted ORDER-TIME
-- kitchen snapshots so a branch-discovered (kiosk / other-till) order can be
-- manually reprinted on the POS with the SAME whole-order counts the initial
-- ticket carried.
--
-- Contract under test (additive keys only, allowlisted projections only):
--   items[].prep_snapshot          = app.kitchen_prep_projection(order_items.prep_snapshot)
--   items[].modifiers[].meat_snapshot
--                                  = app.kitchen_modifier_prep_projection(order_item_modifiers.meat_snapshot)
--
-- PER-UNIT: the projected quantities are the stored per-unit values — never
-- multiplied by the line or modifier quantity here (the canonical client
-- aggregator applies those factors exactly once).
-- NULL history: a NULL stored snapshot projects to JSON null — nothing is
-- re-derived from the live menu (D-008). Money contract and every existing
-- key are byte-unchanged; auth/scoping envelopes unchanged (R-003).
-- ============================================================================
begin;

set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(30);

-- ===== fixture (privileged seed, mirrors modifier_prep_classifier_019) ======
insert into organizations (id, name, slug, default_currency) values
  ('b5b00000-0000-0000-0000-0000000000a0', 'Org 5B', 'org-5b', 'ILS'),
  ('b5b00000-0000-0000-0000-0000000000b0', 'Org 5B foreign', 'org-5b-foreign', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('b5b00000-0000-0000-0000-0000000000a1', 'b5b00000-0000-0000-0000-0000000000a0', 'Rest 5B'),
  ('b5b00000-0000-0000-0000-0000000000b1', 'b5b00000-0000-0000-0000-0000000000b0', 'Rest 5B foreign');
insert into branches (id, organization_id, restaurant_id, name) values
  ('b5b00000-0000-0000-0000-0000000000ab', 'b5b00000-0000-0000-0000-0000000000a0', 'b5b00000-0000-0000-0000-0000000000a1', 'Branch 5B'),
  ('b5b00000-0000-0000-0000-0000000000bb', 'b5b00000-0000-0000-0000-0000000000b0', 'b5b00000-0000-0000-0000-0000000000b1', 'Branch 5B foreign');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('b5b00000-0000-0000-0000-0000000000d1', 'b5b00000-0000-0000-0000-0000000000a0', 'b5b00000-0000-0000-0000-0000000000a1', 'b5b00000-0000-0000-0000-0000000000ab', 'pos'),
  ('b5b00000-0000-0000-0000-0000000000d2', 'b5b00000-0000-0000-0000-0000000000a0', 'b5b00000-0000-0000-0000-0000000000a1', 'b5b00000-0000-0000-0000-0000000000ab', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('b5b00000-0000-0000-0000-0000000000f1', 'b5b00000-0000-0000-0000-0000000000a0', 'b5b00000-0000-0000-0000-0000000000a1', 'b5b00000-0000-0000-0000-0000000000ab', 'b5b00000-0000-0000-0000-0000000000d1', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('b5b00000-0000-0000-0000-00000000005a', 'b5b00000-0000-0000-0000-0000000000a0', 'b5b00000-0000-0000-0000-0000000000a1', 'b5b00000-0000-0000-0000-0000000000ab', 'b5b00000-0000-0000-0000-0000000000d1', 'b5b00000-0000-0000-0000-0000000000f1');
insert into app_users (id, email) values
  ('b5b00000-0000-0000-0000-00000000006a', 'pos-detail-5b@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('b5b00000-0000-0000-0000-00000000007a', 'b5b00000-0000-0000-0000-00000000006a', 'b5b00000-0000-0000-0000-0000000000a0', 'b5b00000-0000-0000-0000-0000000000a1', 'b5b00000-0000-0000-0000-0000000000ab', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('b5b00000-0000-0000-0000-00000000008a', 'b5b00000-0000-0000-0000-0000000000a0', 'b5b00000-0000-0000-0000-0000000000a1', 'b5b00000-0000-0000-0000-0000000000ab', 'b5b00000-0000-0000-0000-00000000006a', 'b5b00000-0000-0000-0000-00000000007a');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('b5b00000-0000-0000-0000-00000000009a', 'b5b00000-0000-0000-0000-0000000000a0', 'b5b00000-0000-0000-0000-0000000000a1', 'b5b00000-0000-0000-0000-0000000000ab', 'b5b00000-0000-0000-0000-00000000005a', 'b5b00000-0000-0000-0000-00000000008a', 'b5b00000-0000-0000-0000-00000000007a', now() + interval '1 hour');

-- The OWNER FIXTURE as persisted after 114B.1: 2 × Classic Burger 240g with a
-- PER-UNIT bun prep (1) and the 240g option's PER-MODIFIER-UNIT meat (2).
-- Both stored snapshots carry an EXTRA non-money key the projection must drop.
insert into orders (
  id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
  opened_by_employee_profile_id, resolved_membership_id, order_type,
  currency_code, subtotal_minor, grand_total_minor, local_operation_id, status)
values (
  'b5b00000-0000-0000-0000-00000000010a', 'b5b00000-0000-0000-0000-0000000000a0',
  'b5b00000-0000-0000-0000-0000000000a1', 'b5b00000-0000-0000-0000-0000000000ab',
  'b5b00000-0000-0000-0000-0000000000d1', 'b5b00000-0000-0000-0000-00000000009a',
  'b5b00000-0000-0000-0000-00000000008a', 'b5b00000-0000-0000-0000-00000000007a',
  'takeaway', 'ILS', 9000, 9000, 'op-5b-initial', 'submitted');

insert into order_items (
  id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
  quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor,
  notes, line_position, prep_snapshot)
values
  ('b5b00000-0000-0000-0000-0000000100a1', 'b5b00000-0000-0000-0000-0000000000a0',
   'b5b00000-0000-0000-0000-0000000000a1', 'b5b00000-0000-0000-0000-0000000000ab',
   'b5b00000-0000-0000-0000-00000000010a', 'b5b00000-0000-0000-0000-000000001001',
   2, 'Classic Burger', 4500, 9000, 'well done', 1,
   '[{"name":"Bun","quantity":1,"unit":"pcs","internal_note":"never-exposed"}]'::jsonb),
  -- A PRE-114B.1 (historical) line: NULL prep, no modifiers.
  ('b5b00000-0000-0000-0000-0000000100a2', 'b5b00000-0000-0000-0000-0000000000a0',
   'b5b00000-0000-0000-0000-0000000000a1', 'b5b00000-0000-0000-0000-0000000000ab',
   'b5b00000-0000-0000-0000-00000000010a', 'b5b00000-0000-0000-0000-000000001002',
   1, 'Legacy Fries', 0, 0, null, 2, null);

insert into order_item_modifiers (
  id, organization_id, restaurant_id, branch_id, order_item_id,
  modifier_option_id, option_name_snapshot, price_minor_snapshot, quantity,
  meat_snapshot, created_at)
values
  ('b5b00000-0000-0000-0000-000000010101', 'b5b00000-0000-0000-0000-0000000000a0',
   'b5b00000-0000-0000-0000-0000000000a1', 'b5b00000-0000-0000-0000-0000000000ab',
   'b5b00000-0000-0000-0000-0000000100a1', 'b5b00000-0000-0000-0000-000000001240',
   '240g', 0, 1,
   '{"quantity":2,"unit":"meat","secret":"never-exposed"}'::jsonb,
   now() - interval '2 minutes'),
  ('b5b00000-0000-0000-0000-000000010102', 'b5b00000-0000-0000-0000-0000000000a0',
   'b5b00000-0000-0000-0000-0000000000a1', 'b5b00000-0000-0000-0000-0000000000ab',
   'b5b00000-0000-0000-0000-0000000100a1', 'b5b00000-0000-0000-0000-0000000001cc',
   'Cheese', 300, 1, null, now() - interval '1 minute');

create temp table _d as
  select app.pos_order_detail('b5b00000-0000-0000-0000-00000000009a',
                              'b5b00000-0000-0000-0000-0000000000d1',
                              'b5b00000-0000-0000-0000-00000000010a') as res;

-- ===== A. item prep_snapshot is projected (per unit, allowlisted) ==========
select is((select res ->> 'ok' from _d), 'true', '01 the authorized detail read succeeds');
select is((select res #> '{items,0,prep_snapshot}' from _d),
  '[{"name":"Bun","quantity":1,"unit":"pcs"}]'::jsonb,
  '02 A. items[0].prep_snapshot is the ALLOWLISTED projection of the stored snapshot');
select is((select res #>> '{items,0,quantity}' from _d), '2',
  '03 the line quantity is carried separately (2)');
select is((select res #> '{items,0,prep_snapshot,0,quantity}' from _d), '1'::jsonb,
  '04 the prep quantity stays PER UNIT (1, not 2) — no multiplication in the detail');
select ok((select (res #> '{items,0,prep_snapshot,0}') ? 'internal_note' from _d) is false,
  '05 C. an extra stored key is REDACTED by the projection');

-- ===== B. modifier meat_snapshot is projected =============================
select is((select res #> '{items,0,modifiers,0,meat_snapshot}' from _d),
  '{"quantity":2,"unit":"meat"}'::jsonb,
  '06 B. modifiers[0].meat_snapshot is the allowlisted projection (per modifier unit)');
select is((select res #>> '{items,0,modifiers,0,quantity}' from _d), '1',
  '07 the modifier quantity is carried separately');
select ok((select (res #> '{items,0,modifiers,0,meat_snapshot}') ? 'secret' from _d) is false,
  '08 C. an extra stored meat key is REDACTED');
select is((select jsonb_typeof(res #> '{items,0,modifiers,1,meat_snapshot}') from _d), 'null',
  '09 an option with NO meat snapshot projects to JSON null');

-- ===== D. NULL historical snapshots stay NULL (never re-derived) ==========
select is((select jsonb_typeof(res #> '{items,1,prep_snapshot}') from _d), 'null',
  '10 D. a NULL stored prep_snapshot projects to JSON null');
select is((select res #> '{items,1,modifiers}' from _d), '[]'::jsonb,
  '11 D. the historical line has no modifiers');
select is((select res #>> '{items,1,menu_item_name_snapshot}' from _d), 'Legacy Fries',
  '12 D. the historical line still prints its name');

-- ===== E. every existing key is unchanged; the new keys are ADDITIVE ======
select is(
  (select array_agg(k order by k) from _d, jsonb_object_keys(res #> '{items,0}') k),
  array['category_display_order_snapshot','item_display_order_snapshot','item_size_snapshot',
        'item_variant_snapshot','line_discount_minor','line_position','line_total_minor',
        'menu_item_id','menu_item_name_snapshot','modifiers','notes','order_item_id',
        'prep_snapshot','quantity','round_number','service_round_id','status',
        'unit_price_minor_snapshot'],
  '13 E. items[] carries exactly the shipped keys + prep_snapshot');
select is(
  (select array_agg(k order by k) from _d, jsonb_object_keys(res #> '{items,0,modifiers,0}') k),
  array['meat_snapshot','modifier_name_snapshot','option_name_snapshot','price_minor_snapshot','quantity'],
  '14 E. modifiers[] carries exactly the shipped keys + meat_snapshot');
select is(
  (select array_agg(k order by k) from _d, jsonb_object_keys(res -> 'order') k),
  array['created_at','currency_code','customer_name','customer_phone','discount_total_minor',
        'grand_total_minor','order_code','order_id','order_type','receipt_number','revision',
        'status','subtotal_minor','table_label','tax_total_minor','updated_at'],
  '15 E. the order header keys are byte-unchanged');
select is(
  (select array_agg(k order by k) from _d, jsonb_object_keys(res) k),
  array['entity','items','ok','order','payment','rounds','server_ts'],
  '16 E. the envelope keys are unchanged');
select is((select res #>> '{items,0,notes}' from _d), 'well done', '17 E. notes still carried');
select is((select res #>> '{items,0,modifiers,0,option_name_snapshot}' from _d), '240g',
  '18 E. modifier option name still carried');
select is((select res #>> '{items,0,line_position}' from _d), '1', '19 E. ordering snapshots still carried');
select is((select res #>> '{items,1,line_position}' from _d), '2', '20 E. items stay in print order');

-- ===== G. money contract unchanged (integer minor units, same keys) =======
select is((select res #>> '{items,0,line_total_minor}' from _d), '9000', '21 G. line_total_minor unchanged');
select is((select res #>> '{items,0,unit_price_minor_snapshot}' from _d), '4500', '22 G. unit price unchanged');
select is((select res #>> '{order,grand_total_minor}' from _d), '9000', '23 G. grand total unchanged');
select ok((select not (res::text ~* 'amount_minor|internal_note|secret') from _d),
  '24 G. no stored internal/hostile key leaks anywhere in the envelope');

-- ===== F. authorization / scoping envelopes unchanged =====================
select is((select app.pos_order_detail('b5b00000-0000-0000-0000-00000000009a',
                                       'b5b00000-0000-0000-0000-0000000000d2',
                                       'b5b00000-0000-0000-0000-00000000010a') ->> 'error'),
  'invalid_session', '25 F. a session bound to another device is refused');
select is((select app.pos_order_detail('b5b00000-0000-0000-0000-00000000009a',
                                       'b5b00000-0000-0000-0000-0000000000d1',
                                       'b5b00000-0000-0000-0000-0000000000ff') ->> 'error'),
  'order_not_found', '26 F. an unknown order collapses to order_not_found');
select ok(not has_function_privilege('anon', 'public.pos_order_detail(uuid, uuid, uuid)', 'execute'),
  '27 F. anon cannot execute the public wrapper');
select ok(has_function_privilege('authenticated', 'public.pos_order_detail(uuid, uuid, uuid)', 'execute'),
  '28 F. authenticated keeps execute on the public wrapper');
select ok(exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'pos_order_detail'
      and p.prosecdef and p.provolatile = 's'
      and array_to_string(p.proconfig, ',') like '%search_path=%'),
  '29 F. app.pos_order_detail stays SECURITY DEFINER, STABLE, with a pinned search_path');
select ok(exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'pos_order_detail'
      and pg_get_function_identity_arguments(p.oid) = 'p_pin_session_id uuid, p_device_id uuid, p_order_id uuid'),
  '30 F. the signature is unchanged (no new standalone RPC)');

select * from finish();
rollback;
