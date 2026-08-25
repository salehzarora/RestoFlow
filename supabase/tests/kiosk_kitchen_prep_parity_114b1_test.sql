-- ============================================================================
-- KIOSK-PRINT-114B.1 — pgTAP: kiosk kitchen PREP PARITY (migration 1).
--
-- Kiosk-originated order_items.prep_snapshot must be SERVER-DERIVED from the
-- trusted menu_items.attributes.prep_components (the POS parity gap: the
-- kiosk client cannot and must not send prep metadata — kiosk_menu redacts
-- it by design). Contract:
--   * the persisted snapshot is the POS wire shape [{name, quantity, unit,
--     classifier_option_id?, classifier_option_name?, classifier_selected?}];
--   * classifier names come from the option's OWN row (never config text);
--   * classifier_selected derives from the submitted modifier selection;
--   * unknown/foreign classifier ids degrade to UNSPLIT resources;
--   * blank-name / non-positive / non-object entries are dropped;
--   * client-supplied item prep_snapshot is IGNORED (never persisted);
--   * the printer_only kitchen dispatch payload now carries item prep;
--   * meat gate (021), display-order snapshots, kiosk_menu redaction and
--     submit idempotency are byte-unchanged.
-- Fixtures inserted as the BYPASSRLS harness role; RPC authority is the
-- kiosk device token parameter.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(14);

-- ===== fixture: org / restaurant / printer_only branch / kiosk device =======
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-b114-0000000000a0', 'B114 Org', 'b114-prep', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-b114-0000000000a1', '00000000-0000-0000-b114-0000000000a0', 'B114 Rest');
insert into branches (id, organization_id, restaurant_id, name, kitchen_workflow_mode, kitchen_workflow_mode_revision) values
  ('00000000-0000-0000-b114-0000000000aa', '00000000-0000-0000-b114-0000000000a0', '00000000-0000-0000-b114-0000000000a1', 'B114 Branch P', 'printer_only', 1);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('00000000-0000-0000-b114-0000000d1001', '00000000-0000-0000-b114-0000000000a0', '00000000-0000-0000-b114-0000000000a1', '00000000-0000-0000-b114-0000000000aa', 'kiosk', 'B114 Kiosk');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-b114-0000000d2001', '00000000-0000-0000-b114-0000000000a0', '00000000-0000-0000-b114-0000000000a1', '00000000-0000-0000-b114-0000000000aa', '00000000-0000-0000-b114-0000000d1001', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, expires_at) values
  ('00000000-0000-0000-b114-0000000d3001', '00000000-0000-0000-b114-0000000000a0', '00000000-0000-0000-b114-0000000000a1', '00000000-0000-0000-b114-0000000000aa', '00000000-0000-0000-b114-0000000d1001', '00000000-0000-0000-b114-0000000d2001', app.hash_provisioning_secret('tok-b114-kiosk'), true, now() + interval '1 day');

-- menu: Burger (prep_components configured, Size group with the classifier
-- target) + Cola (no prep at all). display orders are DISTINCT on purpose so
-- the trigger-populated snapshots are observable.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order, is_active) values
  ('00000000-0000-0000-b114-0000000c1000', '00000000-0000-0000-b114-0000000000a0', '00000000-0000-0000-b114-0000000000a1', null, 'B114 Cat', 5, true);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order, is_active, attributes) values
  ('00000000-0000-0000-b114-000000110000'::uuid, '00000000-0000-0000-b114-0000000000a0', '00000000-0000-0000-b114-0000000000a1', null, '00000000-0000-0000-b114-0000000c1000', 'B114 Burger', 4000, 'ILS', 3, true,
   jsonb_build_object('prep_components', jsonb_build_array(
     jsonb_build_object('name', 'Patty', 'quantity', 1, 'unit', 'pc',
                        'classifier_option_id', '00000000-0000-0000-b114-0000000d0201',
                        'classifier_option_name', 'Stale Large Label'),
     jsonb_build_object('name', 'Bun', 'quantity', 2, 'unit', 'pc'),
     jsonb_build_object('name', 'Sauce', 'quantity', 1, 'unit', 'g',
                        'classifier_option_id', '00000000-0000-0000-b114-00000000dead'),
     jsonb_build_object('name', '', 'quantity', 1, 'unit', 'x'),
     jsonb_build_object('name', 'NegQ', 'quantity', -2, 'unit', 'x'),
     to_jsonb('junk-entry'::text)))),
  ('00000000-0000-0000-b114-000000110002'::uuid, '00000000-0000-0000-b114-0000000000a0', '00000000-0000-0000-b114-0000000000a1', null, '00000000-0000-0000-b114-0000000c1000', 'B114 Cola', 1000, 'ILS', 7, true, null);
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, min_select, max_select, is_required, is_active) values
  ('00000000-0000-0000-b114-0000000d0101', '00000000-0000-0000-b114-0000000000a0', '00000000-0000-0000-b114-0000000000a1', null, '00000000-0000-0000-b114-000000110000', 'Size', 'single', 1, 1, true, true);
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active, kitchen_meat) values
  ('00000000-0000-0000-b114-0000000d0201', '00000000-0000-0000-b114-0000000000a0', '00000000-0000-0000-b114-0000000000a1', null, '00000000-0000-0000-b114-0000000d0101', 'Large', 0, 0, true,
   jsonb_build_object('quantity', 1, 'unit', 'patty')),
  ('00000000-0000-0000-b114-0000000d0202', '00000000-0000-0000-b114-0000000000a0', '00000000-0000-0000-b114-0000000000a1', null, '00000000-0000-0000-b114-0000000d0101', 'Small', 0, 1, true, null);

-- helper: burger submit (qty 2) with a chosen Size option and OPTIONAL extra
-- item-level payload keys (the malicious-prep probe).
create function pg_temp.bsub(p_order uuid, p_op text, p_option uuid, p_option_name text,
                             p_meat jsonb, p_extra jsonb default '{}'::jsonb)
returns jsonb language sql as $$
  select public.kiosk_submit_order(
    '00000000-0000-0000-b114-0000000d1001', 'tok-b114-kiosk',
    p_order, p_op, 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array((jsonb_build_object(
      'menu_item_id', '00000000-0000-0000-b114-000000110000',
      'menu_item_name_snapshot', 'B114 Burger', 'quantity', 2,
      'unit_price_minor_snapshot', 4000,
      'modifiers', jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'modifier_option_id', p_option,
        'option_name_snapshot', p_option_name,
        'price_minor_snapshot', 0, 'quantity', 1,
        'meat_snapshot', p_meat)))) || p_extra)),
    8000, 0, 0, 8000);
$$;

create temp table _r (label text primary key, r jsonb);

-- ============================================================================
-- P1-P3: server-derived snapshot, exact POS wire shape, canonical names.
-- ============================================================================
insert into _r values ('large', pg_temp.bsub('00000000-0000-0000-b114-00000aade001', 'b114-01',
  '00000000-0000-0000-b114-0000000d0201', 'Large', jsonb_build_object('quantity', 1, 'unit', 'patty')));
select ok((select (r ->> 'ok')::boolean from _r where label = 'large'),
  'P1: the fixture kiosk submit is accepted (control)');
select ok((select oi.prep_snapshot is not null
             from order_items oi where oi.order_id = '00000000-0000-0000-b114-00000aade001'),
  'P2: the kiosk order item persists a NON-NULL prep_snapshot (the 114B.1 parity fix)');
select is(
  (select oi.prep_snapshot from order_items oi where oi.order_id = '00000000-0000-0000-b114-00000aade001'),
  jsonb_build_array(
    jsonb_build_object('name', 'Patty', 'quantity', 1, 'unit', 'pc',
                       'classifier_option_id', '00000000-0000-0000-b114-0000000d0201',
                       'classifier_option_name', 'Large',
                       'classifier_selected', true),
    jsonb_build_object('name', 'Bun', 'quantity', 2, 'unit', 'pc'),
    jsonb_build_object('name', 'Sauce', 'quantity', 1, 'unit', 'g')),
  'P3: EXACT POS wire shape — canonical classifier name from the option row, '
  'selected=true for the chosen Large, unknown classifier degrades to '
  'unsplit, blank/non-positive/non-object config entries dropped');

-- ============================================================================
-- P4: classifier_selected derives from the SELECTION (Small => false).
-- ============================================================================
select pg_temp.bsub('00000000-0000-0000-b114-00000aade002', 'b114-02',
  '00000000-0000-0000-b114-0000000d0202', 'Small', null);
select is(
  (select oi.prep_snapshot -> 0 -> 'classifier_selected'
     from order_items oi where oi.order_id = '00000000-0000-0000-b114-00000aade002'),
  'false'::jsonb,
  'P4: with Small selected the Patty classifier answers selected=false');

-- ============================================================================
-- P5: a malicious client prep_snapshot can NEVER override the derivation.
-- ============================================================================
select pg_temp.bsub('00000000-0000-0000-b114-00000aade003', 'b114-03',
  '00000000-0000-0000-b114-0000000d0201', 'Large', jsonb_build_object('quantity', 1, 'unit', 'patty'),
  jsonb_build_object('prep_snapshot', jsonb_build_array(
    jsonb_build_object('name', 'HACK', 'quantity', 99, 'unit', 'x'))));
select ok((select oi.prep_snapshot::text not like '%HACK%'
              and oi.prep_snapshot -> 0 ->> 'name' = 'Patty'
             from order_items oi where oi.order_id = '00000000-0000-0000-b114-00000aade003'),
  'P5: a client-submitted item prep_snapshot is IGNORED — the persisted '
  'snapshot is the server derivation');

-- ============================================================================
-- P6: an item with no configured prep persists NULL (never a fake []).
-- ============================================================================
select public.kiosk_submit_order(
  '00000000-0000-0000-b114-0000000d1001', 'tok-b114-kiosk',
  '00000000-0000-0000-b114-00000aade004', 'b114-04', 'takeaway', null, 'ILS', null, null, null,
  jsonb_build_array(jsonb_build_object(
    'menu_item_id', '00000000-0000-0000-b114-000000110002',
    'menu_item_name_snapshot', 'B114 Cola', 'quantity', 1,
    'unit_price_minor_snapshot', 1000)),
  1000, 0, 0, 1000);
select ok((select oi.prep_snapshot is null
             from order_items oi where oi.order_id = '00000000-0000-0000-b114-00000aade004'),
  'P6: a prep-less item still persists prep_snapshot NULL');

-- ============================================================================
-- P7-P8: the printer_only kitchen dispatch payload now carries item prep.
-- ============================================================================
select ok((select d.money_free_payload -> 'items' -> 0 ? 'prep'
              and d.money_free_payload -> 'items' -> 0 -> 'prep' -> 0 ->> 'name' = 'Patty'
             from kitchen_print_dispatches d
             where d.order_id = '00000000-0000-0000-b114-00000aade001'),
  'P7: the kiosk order''s kitchen dispatch payload projects the item prep '
  '(Patty reaches the paper path)');
select ok((select d.money_free_payload::text not like '%HACK%'
             from kitchen_print_dispatches d
             where d.order_id = '00000000-0000-0000-b114-00000aade003'),
  'P8: no client-invented prep can reach a dispatch payload');

-- ============================================================================
-- P9-P10: the 021 modifier meat path is BYTE-UNCHANGED.
-- ============================================================================
select is(((pg_temp.bsub('00000000-0000-0000-b114-00000aade005', 'b114-05',
    '00000000-0000-0000-b114-0000000d0201', 'Large',
    jsonb_build_object('quantity', 9, 'unit', 'patty'))) ->> 'error'),
  'modifier_prep_snapshot_stale',
  'P9: a WRONG client meat_snapshot is still refused (021 gate unchanged)');
select is(
  (select om.meat_snapshot from order_item_modifiers om
     join order_items oi on oi.id = om.order_item_id
     where oi.order_id = '00000000-0000-0000-b114-00000aade001'),
  jsonb_build_object('quantity', 1, 'unit', 'patty'),
  'P10: the persisted modifier meat_snapshot equals the trusted derivation '
  '(unchanged path)');

-- ============================================================================
-- P11: display-order / line-position snapshots stay server-populated.
-- ============================================================================
select ok((select oi.category_display_order_snapshot = 5
              and oi.item_display_order_snapshot = 3
              and oi.line_position >= 1
             from order_items oi where oi.order_id = '00000000-0000-0000-b114-00000aade001'),
  'P11: trigger-populated display-order snapshots + line_position unchanged');

-- ============================================================================
-- P12: kiosk_menu still redacts every prep/attributes detail.
-- ============================================================================
select ok((select (public.kiosk_menu('00000000-0000-0000-b114-0000000d1001', 'tok-b114-kiosk'))::text
             not like all (array['%prep_components%', '%Patty%', '%attributes%'])),
  'P12: kiosk_menu exposes NO prep_components / attributes / prep names');

-- ============================================================================
-- P13-P14: idempotent replay unchanged — one order, one dispatch.
-- ============================================================================
insert into _r values ('replay', pg_temp.bsub('00000000-0000-0000-b114-00000aade001', 'b114-01',
  '00000000-0000-0000-b114-0000000d0201', 'Large', jsonb_build_object('quantity', 1, 'unit', 'patty')));
select ok((select (r ->> 'ok')::boolean and (r ->> 'idempotency_replay')::boolean
             from _r where label = 'replay'),
  'P13: the identical resubmit replays idempotently');
select is((select count(*)::int from kitchen_print_dispatches d
             where d.order_id = '00000000-0000-0000-b114-00000aade001'), 1,
  'P14: the replay created no second dispatch');

select * from finish();
rollback;
