-- ============================================================================
-- KITCHEN-DISPATCH-ENFORCE-001 — pgTAP: the SERVER-SIDE dispatch-mode guard.
--
-- app.sync_push must validate the REQUESTED order.submit dispatch_mode against
-- the AUTHORITATIVE branches.kitchen_workflow_mode (session-derived scope,
-- never the payload) INSIDE the same transaction, BEFORE app.submit_order runs
-- — so a rejection creates NO business rows at all.
--
-- Approved compatibility matrix (KITCHEN-DISPATCH-ENFORCE-001 §7):
--   kds          + absent / 'kds'    -> accept (unchanged KDS lifecycle)
--   kds          + 'direct_print'    -> REJECT  dispatch_mode_not_allowed
--   printer_only + 'direct_print'    -> accept (unchanged verified lifecycle)
--   printer_only + absent / 'kds'    -> accept (deployed-client compatibility)
--   any          + unknown value     -> REJECT  invalid_payload / dispatch_mode
--
-- Before this phase the server routed purely on the client payload, so a
-- forged direct_print on a kds branch stamped the order `served`, dropped it
-- from the KDS feed and created NO kitchen print dispatch — the ticket reached
-- neither screen nor printer. Cases C/D/H/I/M are RED on the pre-migration
-- schema by construction.
--
-- Session pinned to UTC; hex-only UUIDs; PIN-session auth (GUC-free).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(52);

-- ===== fixture: ONE org, TWO branches (kds + printer_only) ===================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-00de0000aa00', 'Org DE', 'de-a', 'ILS');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa00', 'Rest DE', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, kitchen_workflow_mode) values
  ('00000000-0000-0000-0000-00de0000aa1a', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', 'Branch KDS', 'kds'),
  ('00000000-0000-0000-0000-00de0000aa1b', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', 'Branch PO',  'printer_only');
insert into printer_devices (id, organization_id, restaurant_id, branch_id, display_name, connection_type, role, paper_width, is_enabled) values
  ('00000000-0000-0000-0000-00de0000bb11', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa1b', 'DE Kitchen 80', 'network', 'kitchen', '80mm', true);
insert into tables (id, organization_id, restaurant_id, branch_id, label, seats, status, is_active) values
  ('00000000-0000-0000-0000-00de00007a01', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa1a', 'K1', 4, 'available', true),
  ('00000000-0000-0000-0000-00de00007b01', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa1b', 'P1', 4, 'available', true);

-- devices/sessions: one POS per branch (+ one KDS device on the kds branch to
-- prove the accepted order really reaches the KDS feed).
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00de000dd001', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa1a', 'pos'),
  ('00000000-0000-0000-0000-00de000dd002', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa1b', 'pos'),
  ('00000000-0000-0000-0000-00de000dd003', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa1a', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00de000cc001', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa1a', '00000000-0000-0000-0000-00de000dd001', 'active'),
  ('00000000-0000-0000-0000-00de000cc002', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa1b', '00000000-0000-0000-0000-00de000dd002', 'active'),
  ('00000000-0000-0000-0000-00de000cc003', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa1a', '00000000-0000-0000-0000-00de000dd003', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-00de000ee001', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa1a', '00000000-0000-0000-0000-00de000dd001', '00000000-0000-0000-0000-00de000cc001'),
  ('00000000-0000-0000-0000-00de000ee002', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa1b', '00000000-0000-0000-0000-00de000dd002', '00000000-0000-0000-0000-00de000cc002'),
  ('00000000-0000-0000-0000-00de000ee003', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa1a', '00000000-0000-0000-0000-00de000dd003', '00000000-0000-0000-0000-00de000cc003');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00de0000ff01', 'de-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00de00ab0001', '00000000-0000-0000-0000-00de0000ff01', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa1a', 'cashier'),
  ('00000000-0000-0000-0000-00de00ab0002', '00000000-0000-0000-0000-00de0000ff01', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa1b', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-00de00ef0001', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa1a', '00000000-0000-0000-0000-00de0000ff01', '00000000-0000-0000-0000-00de00ab0001', 'Cashier K'),
  ('00000000-0000-0000-0000-00de00ef0002', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa1b', '00000000-0000-0000-0000-00de0000ff01', '00000000-0000-0000-0000-00de00ab0002', 'Cashier P');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00de00c50001', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa1a', '00000000-0000-0000-0000-00de000ee001', '00000000-0000-0000-0000-00de00ef0001', '00000000-0000-0000-0000-00de00ab0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00de00c50002', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa1b', '00000000-0000-0000-0000-00de000ee002', '00000000-0000-0000-0000-00de00ef0002', '00000000-0000-0000-0000-00de00ab0002', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00de00c50003', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa1a', '00000000-0000-0000-0000-00de000ee003', '00000000-0000-0000-0000-00de00ef0001', '00000000-0000-0000-0000-00de00ab0001', now() + interval '1 hour');
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('00000000-0000-0000-0000-00de0000ca01', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', null, 'Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('00000000-0000-0000-0000-00de000000f0', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', null, '00000000-0000-0000-0000-00de0000ca01', 'Tap Water', 0, 'ILS', 1),
  ('00000000-0000-0000-0000-00de000000f5', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', null, '00000000-0000-0000-0000-00de0000ca01', 'Burger', 500, 'ILS', 2);

-- an OPEN shift + active cash drawer on the printer_only POS device, so the
-- NORMAL settlement path (app.record_payment) is reachable in cases E and G.
insert into shifts (id, organization_id, restaurant_id, branch_id, device_id, opened_by_employee_profile_id, resolved_membership_id, local_operation_id, status) values
  ('00000000-0000-0000-0000-00de00005f01', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa1b', '00000000-0000-0000-0000-00de000dd002', '00000000-0000-0000-0000-00de00ef0002', '00000000-0000-0000-0000-00de00ab0002', 'de-shift-open', 'open');
insert into cash_drawer_sessions (id, organization_id, restaurant_id, branch_id, device_id, shift_id, opened_by_employee_profile_id, opening_float_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00de00006d01', '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10', '00000000-0000-0000-0000-00de0000aa1b', '00000000-0000-0000-0000-00de000dd002', '00000000-0000-0000-0000-00de00005f01', '00000000-0000-0000-0000-00de00ef0002', 0, 'de-drawer-open');

-- a FOREIGN org with a printer_only branch — the spoof target for case I.
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-00de0000bb00', 'Org DE2', 'de-b', 'ILS');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-00de0000bb10', '00000000-0000-0000-0000-00de0000bb00', 'Rest DE2', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, kitchen_workflow_mode) values
  ('00000000-0000-0000-0000-00de0000bb1b', '00000000-0000-0000-0000-00de0000bb00', '00000000-0000-0000-0000-00de0000bb10', 'Foreign PO', 'printer_only');

-- Helper: ONE order.submit op through app.sync_push. p_mode NULL omits the
-- dispatch_mode key entirely (the deployed old-client payload shape).
-- p_extra merges hostile/spoof keys into the payload.
create or replace function pg_temp.de_submit(
  p_pin uuid, p_dev uuid, p_op text, p_order uuid, p_item uuid, p_price bigint,
  p_mode text, p_type text default 'takeaway', p_table uuid default null,
  p_extra jsonb default '{}'::jsonb)
  returns jsonb language sql as $$
  select app.sync_push(p_pin, p_dev,
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', p_op,
      'operation_type', 'order.submit',
      'target_entity', 'order',
      'target_id', p_order::text,
      'payload',
        jsonb_build_object(
          'order_id', p_order::text, 'order_type', p_type,
          'currency_code', 'ILS',
          'order_items', jsonb_build_array(jsonb_build_object(
            'menu_item_id', p_item::text, 'quantity', 1,
            'unit_price_minor_snapshot', p_price,
            'menu_item_name_snapshot', 'Item', 'modifiers', '[]'::jsonb)),
          'subtotal_minor', p_price, 'discount_total_minor', 0,
          'tax_total_minor', 0, 'grand_total_minor', p_price)
        || case when p_table is null then '{}'::jsonb
                else jsonb_build_object('table_id', p_table::text) end
        || case when p_mode is null then '{}'::jsonb
                else jsonb_build_object('dispatch_mode', p_mode) end
        || p_extra)));
$$;

-- derived occupancy = ACTIVE DINE-IN orders on a table (02 "Table occupancy").
create or replace function pg_temp.de_occupancy(p_table uuid)
  returns int language sql as $$
  select count(*)::int from public.orders o
   where o.table_id = p_table
     and o.order_type = 'dine_in'
     and o.status not in ('completed', 'cancelled', 'voided')
     and o.deleted_at is null;
$$;

-- ===== A. kds branch + OMITTED dispatch_mode -> accepted, KDS lifecycle ======
create temp table t_a as select pg_temp.de_submit(
  '00000000-0000-0000-0000-00de00c50001', '00000000-0000-0000-0000-00de000dd001',
  'de-a-omit', '00000000-0000-0000-0000-00de00000a01', '00000000-0000-0000-0000-00de000000f5', 500, null) as res;
select is((select res #>> '{results,0,status}' from t_a), 'applied',
  'A1: kds branch + OMITTED dispatch_mode is applied (deployed old-client shape)');
select ok((select o.status = 'submitted' and o.dispatch_mode = 'kds' and o.revision = 1
             from orders o where o.id = '00000000-0000-0000-0000-00de00000a01'),
  'A2: it rests submitted / dispatch_mode=kds / revision 1 — the KDS lifecycle');
select ok((select app.sync_pull('00000000-0000-0000-0000-00de00c50003', '00000000-0000-0000-0000-00de000dd003',
             array['orders'], '{}'::jsonb, 500)::text like '%00de00000a01%'),
  'A3: the accepted order IS visible in a KDS device sync_pull feed');

-- ===== B. kds branch + explicit 'kds' -> identical accept ====================
create temp table t_b as select pg_temp.de_submit(
  '00000000-0000-0000-0000-00de00c50001', '00000000-0000-0000-0000-00de000dd001',
  'de-b-kds', '00000000-0000-0000-0000-00de00000a02', '00000000-0000-0000-0000-00de000000f5', 500, 'kds') as res;
select is((select res #>> '{results,0,status}' from t_b), 'applied',
  'B1: kds branch + explicit ''kds'' is applied');
select ok((select o.status = 'submitted' and o.dispatch_mode = 'kds' and o.revision = 1
             from orders o where o.id = '00000000-0000-0000-0000-00de00000a02'),
  'B2: explicit ''kds'' is byte-identical to the omitted-key path');

-- ===== C. kds branch + 'direct_print' -> REJECTED, ZERO side effects =========
-- dine_in + a table so table occupancy is a meaningful assertion.
create temp table t_c_before as select pg_temp.de_occupancy('00000000-0000-0000-0000-00de00007a01') as n;
create temp table t_c as select pg_temp.de_submit(
  '00000000-0000-0000-0000-00de00c50001', '00000000-0000-0000-0000-00de000dd001',
  'de-c-forge', '00000000-0000-0000-0000-00de00000a03', '00000000-0000-0000-0000-00de000000f5', 500,
  'direct_print', 'dine_in', '00000000-0000-0000-0000-00de00007a01') as res;
select is((select res #>> '{results,0,status}' from t_c), 'rejected',
  'C1: a direct_print submit on a KDS branch is REJECTED');
select is((select res #>> '{results,0,error}' from t_c), 'dispatch_mode_not_allowed',
  'C2: the typed error is dispatch_mode_not_allowed (never a raw SQLSTATE)');
select is((select res #>> '{results,0,idempotency_replay}' from t_c), 'false',
  'C3: the first rejection is not an idempotency replay');
select ok(not exists (select 1 from orders where id = '00000000-0000-0000-0000-00de00000a03'),
  'C4: NO order row was created');
select ok(not exists (select 1 from order_items where order_id = '00000000-0000-0000-0000-00de00000a03'),
  'C5: NO order_items rows were created');
select ok(not exists (select 1 from kitchen_print_dispatches where order_id = '00000000-0000-0000-0000-00de00000a03'),
  'C6: NO kitchen_print_dispatches row was created');
select ok(not exists (select 1 from payments where order_id = '00000000-0000-0000-0000-00de00000a03'),
  'C7: NO payment row was created');
select is(pg_temp.de_occupancy('00000000-0000-0000-0000-00de00007a01'), (select n from t_c_before),
  'C8: table occupancy is unchanged by the rejected forgery');
select ok(not exists (select 1 from audit_events
    where action = 'order.status_updated'
      and (new_values ->> 'order_code') = '#' || upper(right(replace('00000000-0000-0000-0000-00de00000a03', '-', ''), 6))),
  'C9: NO order.status_updated audit — no submitted->served transition happened');
select is((select count(*)::int from audit_events
    where action = 'sync.operation_rejected'
      and new_values ->> 'local_operation_id' = 'de-c-forge'), 1,
  'C10: exactly ONE sync.operation_rejected audit for the forged op');
select ok((select so.status = 'rejected' and so.last_error_code = 'dispatch_mode_not_allowed'
             and so.last_error_class = 'permanent'
             from sync_operations so
             where so.organization_id = '00000000-0000-0000-0000-00de0000aa00'
               and so.device_id = '00000000-0000-0000-0000-00de000dd001'
               and so.local_operation_id = 'de-c-forge'),
  'C11: the ledger row is rejected/permanent with the typed error code');

-- ===== D. REPLAY of the rejection is verbatim and still creates nothing ======
create temp table t_d as select pg_temp.de_submit(
  '00000000-0000-0000-0000-00de00c50001', '00000000-0000-0000-0000-00de000dd001',
  'de-c-forge', '00000000-0000-0000-0000-00de00000a03', '00000000-0000-0000-0000-00de000000f5', 500,
  'direct_print', 'dine_in', '00000000-0000-0000-0000-00de00007a01') as res;
select is((select res #>> '{results,0,error}' from t_d), 'dispatch_mode_not_allowed',
  'D1: the replay returns the SAME typed rejection verbatim');
select is((select res #>> '{results,0,idempotency_replay}' from t_d), 'true',
  'D2: the replay is flagged idempotency_replay');
select ok(not exists (select 1 from orders where id = '00000000-0000-0000-0000-00de00000a03'),
  'D3: the replay still creates NO order');

-- ===== E. printer_only + 'direct_print' (chargeable dine-in) -> UNCHANGED ====
create temp table t_e as select pg_temp.de_submit(
  '00000000-0000-0000-0000-00de00c50002', '00000000-0000-0000-0000-00de000dd002',
  'de-e-dp', '00000000-0000-0000-0000-00de00000b01', '00000000-0000-0000-0000-00de000000f5', 500,
  'direct_print', 'dine_in', '00000000-0000-0000-0000-00de00007b01') as res;
select is((select res #>> '{results,0,status}' from t_e), 'applied',
  'E1: printer_only + direct_print is applied (unchanged verified lifecycle)');
select ok((select o.status = 'served' and o.dispatch_mode = 'direct_print' and o.revision = 2
             from orders o where o.id = '00000000-0000-0000-0000-00de00000b01'),
  'E2: it rests served / dispatch_mode=direct_print / revision 2');
select ok(exists (select 1 from kitchen_print_dispatches
                   where order_id = '00000000-0000-0000-0000-00de00000b01' and dispatch_type = 'initial_order'),
  'E3: its kitchen print dispatch EXISTS (printer_only branch gate)');
select ok(not exists (select 1 from payments where order_id = '00000000-0000-0000-0000-00de00000b01'),
  'E4: NOT completed and NO payment fabricated — settlement is never bypassed');
select is(pg_temp.de_occupancy('00000000-0000-0000-0000-00de00007b01'), 1,
  'E5: the served dine-in order still occupies its table');
select is((select app.sync_push('00000000-0000-0000-0000-00de00c50002', '00000000-0000-0000-0000-00de000dd002',
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', 'de-e-pay', 'operation_type', 'payment.create',
      'target_entity', 'payment', 'target_id', '00000000-0000-0000-0000-00de00000c01',
      'payload', jsonb_build_object(
        'payment_id', '00000000-0000-0000-0000-00de00000c01',
        'order_id', '00000000-0000-0000-0000-00de00000b01',
        'tender_type', 'cash', 'amount_tendered_minor', 500))))
    #>> '{results,0,status}'), 'applied',
  'E6: the NORMAL cash settlement is applied');
select ok((select o.status = 'completed' from orders o where o.id = '00000000-0000-0000-0000-00de00000b01'),
  'E7: settlement (not printing) completes the served direct_print order');
select is(pg_temp.de_occupancy('00000000-0000-0000-0000-00de00007b01'), 0,
  'E8: completion RELEASES the derived table occupancy');

-- ===== F. printer_only + 'direct_print' ZERO-TOTAL -> completes ==============
create temp table t_f as select pg_temp.de_submit(
  '00000000-0000-0000-0000-00de00c50002', '00000000-0000-0000-0000-00de000dd002',
  'de-f-zt', '00000000-0000-0000-0000-00de00000b02', '00000000-0000-0000-0000-00de000000f0', 0, 'direct_print') as res;
select is((select res #>> '{results,0,status}' from t_f), 'applied',
  'F1: printer_only + direct_print zero-total is applied');
select ok((select o.status = 'completed' from orders o where o.id = '00000000-0000-0000-0000-00de00000b02'),
  'F2: a ZERO-TOTAL order completes inside the submit transaction (nothing to pay)');
select ok(not exists (select 1 from payments where order_id = '00000000-0000-0000-0000-00de00000b02'),
  'F3: NO payment row is fabricated for the zero-total completion');

-- ===== G. printer_only + OMITTED key -> accepted (legacy compatibility) ======
create temp table t_g as select pg_temp.de_submit(
  '00000000-0000-0000-0000-00de00c50002', '00000000-0000-0000-0000-00de000dd002',
  'de-g-omit', '00000000-0000-0000-0000-00de00000b03', '00000000-0000-0000-0000-00de000000f5', 500, null) as res;
select is((select res #>> '{results,0,status}' from t_g), 'applied',
  'G1: printer_only + OMITTED key is ACCEPTED — deployed pilot APKs keep working');
select ok((select o.status = 'submitted' and o.dispatch_mode = 'kds'
             from orders o where o.id = '00000000-0000-0000-0000-00de00000b03'),
  'G2: the legacy path stays submitted (no served promotion without direct_print)');
select ok(exists (select 1 from kitchen_print_dispatches
                   where order_id = '00000000-0000-0000-0000-00de00000b03' and dispatch_type = 'initial_order'),
  'G3: its kitchen ticket dispatch STILL exists (submit_order branch-mode gate)');
select is((select app.sync_push('00000000-0000-0000-0000-00de00c50002', '00000000-0000-0000-0000-00de000dd002',
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', 'de-g-pay', 'operation_type', 'payment.create',
      'target_entity', 'payment', 'target_id', '00000000-0000-0000-0000-00de00000c02',
      'payload', jsonb_build_object(
        'payment_id', '00000000-0000-0000-0000-00de00000c02',
        'order_id', '00000000-0000-0000-0000-00de00000b03',
        'tender_type', 'cash', 'amount_tendered_minor', 500))))
    #>> '{results,0,status}'), 'applied',
  'G4: settlement of the legacy printer_only order is applied');
select ok((select o.status = 'completed' from orders o where o.id = '00000000-0000-0000-0000-00de00000b03'),
  'G5: settlement ALONE completes it (printer_only widened eligibility)');

-- ===== H. unknown dispatch value -> invalid_payload, no side effects =========
create temp table t_h as select pg_temp.de_submit(
  '00000000-0000-0000-0000-00de00c50002', '00000000-0000-0000-0000-00de000dd002',
  'de-h-bad', '00000000-0000-0000-0000-00de00000b04', '00000000-0000-0000-0000-00de000000f5', 500, 'both') as res;
select is((select res #>> '{results,0,error}' from t_h), 'invalid_payload',
  'H1: an unknown dispatch_mode value is rejected invalid_payload');
select is((select res #>> '{results,0,detail}' from t_h), 'dispatch_mode',
  'H2: the rejection names the offending field');
select ok(not exists (select 1 from orders where id = '00000000-0000-0000-0000-00de00000b04'),
  'H3: an unknown value creates NO order');

-- ===== I. payload SCOPE SPOOF is ignored — scope is session-derived ==========
-- a kds-branch device claims a printer_only branch (same org, then foreign org).
create temp table t_i1 as select pg_temp.de_submit(
  '00000000-0000-0000-0000-00de00c50001', '00000000-0000-0000-0000-00de000dd001',
  'de-i-spoof1', '00000000-0000-0000-0000-00de00000a04', '00000000-0000-0000-0000-00de000000f5', 500,
  'direct_print', 'takeaway', null,
  jsonb_build_object('branch_id', '00000000-0000-0000-0000-00de0000aa1b',
                     'organization_id', '00000000-0000-0000-0000-00de0000aa00')) as res;
select is((select res #>> '{results,0,error}' from t_i1), 'dispatch_mode_not_allowed',
  'I1: a payload branch_id claiming the printer_only branch is IGNORED — still rejected');
create temp table t_i2 as select pg_temp.de_submit(
  '00000000-0000-0000-0000-00de00c50001', '00000000-0000-0000-0000-00de000dd001',
  'de-i-spoof2', '00000000-0000-0000-0000-00de00000a05', '00000000-0000-0000-0000-00de000000f5', 500,
  'direct_print', 'takeaway', null,
  jsonb_build_object('branch_id', '00000000-0000-0000-0000-00de0000bb1b',
                     'organization_id', '00000000-0000-0000-0000-00de0000bb00')) as res;
select is((select res #>> '{results,0,error}' from t_i2), 'dispatch_mode_not_allowed',
  'I2: a FOREIGN org''s printer_only branch never authorizes this org''s op');
select ok(not exists (select 1 from orders where id in (
    '00000000-0000-0000-0000-00de00000a04', '00000000-0000-0000-0000-00de00000a05')),
  'I3: neither spoof created an order');

-- ===== J. an APPLIED direct_print replay stays idempotent ====================
create temp table t_j as select pg_temp.de_submit(
  '00000000-0000-0000-0000-00de00c50002', '00000000-0000-0000-0000-00de000dd002',
  'de-e-dp', '00000000-0000-0000-0000-00de00000b01', '00000000-0000-0000-0000-00de000000f5', 500,
  'direct_print', 'dine_in', '00000000-0000-0000-0000-00de00007b01') as res;
select is((select res #>> '{results,0,idempotency_replay}' from t_j), 'true',
  'J1: replaying the APPLIED direct_print submit is an idempotency replay');
select is((select count(*)::int from audit_events
    where action = 'order.status_updated'
      and (new_values ->> 'order_code') = '#' || upper(right(replace('00000000-0000-0000-0000-00de00000b01', '-', ''), 6))
      and new_values ->> 'to_status' = 'served'), 1,
  'J2: exactly ONE submitted->served dispatch audit — no duplicate transition');

-- ===== K. ACL posture is preserved (no new privileged surface) ===============
-- NOTE: app.sync_push carries a SHIPPED grant to `authenticated`
-- (20260802090000 :871). The regression that matters is that the re-emit
-- PRESERVES that posture exactly — not that it revokes it.
select ok(has_function_privilege('authenticated', 'app.sync_push(uuid, uuid, jsonb)', 'EXECUTE'),
  'K1: app.sync_push keeps its shipped EXECUTE grant to authenticated (ACL preserved)');
select ok(not has_function_privilege('anon', 'app.sync_push(uuid, uuid, jsonb)', 'EXECUTE'),
  'K2: app.sync_push is NOT executable by anon');
select ok(not has_function_privilege('authenticated',
    'app.apply_direct_print_dispatch(uuid, uuid, uuid, uuid, uuid, uuid, uuid, text)', 'EXECUTE'),
  'K3: the internal dispatch helper is NOT executable by authenticated');
select ok(not has_function_privilege('anon',
    'app.apply_direct_print_dispatch(uuid, uuid, uuid, uuid, uuid, uuid, uuid, text)', 'EXECUTE'),
  'K4: the internal dispatch helper is NOT executable by anon');
select ok(has_function_privilege('authenticated', 'public.sync_push(uuid, uuid, jsonb)', 'EXECUTE'),
  'K5: the public.sync_push wrapper stays executable by authenticated');

-- ===== L. the guard never mutates branch configuration ======================
select ok((select count(*) = 2 from branches
             where (id = '00000000-0000-0000-0000-00de0000aa1a' and kitchen_workflow_mode = 'kds')
                or (id = '00000000-0000-0000-0000-00de0000aa1b' and kitchen_workflow_mode = 'printer_only')),
  'L1: both branch kitchen_workflow_mode values are untouched by every case above');

-- ===== M. the defensive belt: dedicated SQLSTATE, no leaked detail ==========
-- A DIRECT call on a kds-branch order (bypassing sync_push) must raise the
-- internal RFDM0 and roll its own subtransaction back. Through app.sync_push
-- the belt is unreachable by construction (same transaction, same share-locked
-- branch row) — the client-visible typed code is proven by C2/C11.
create or replace function pg_temp.de_belt() returns text language plpgsql as $$
declare v jsonb;
begin
  v := app.apply_direct_print_dispatch(
    '00000000-0000-0000-0000-00de0000aa00', '00000000-0000-0000-0000-00de0000aa10',
    '00000000-0000-0000-0000-00de0000aa1a', '00000000-0000-0000-0000-00de00000a01',
    '00000000-0000-0000-0000-00de00ef0001', '00000000-0000-0000-0000-00de00ab0001',
    '00000000-0000-0000-0000-00de000dd001', 'de-belt-probe');
  return 'NO_RAISE:' || coalesce(v::text, '<null>');
exception when others then
  return SQLSTATE || '|' || SQLERRM;
end;
$$;
create temp table t_m as select pg_temp.de_belt() as r;
select is((select split_part(r, '|', 1) from t_m), 'RFDM0',
  'M1: a direct belt call on a kds-branch order raises the dedicated RFDM0');
select ok((select r not ilike '%printer_only%' and r not ilike '%kitchen_workflow%' from t_m),
  'M2: the belt message leaks NO branch-mode / internal detail');
select ok((select o.status = 'submitted' and o.dispatch_mode = 'kds' and o.revision = 1
             from orders o where o.id = '00000000-0000-0000-0000-00de00000a01'),
  'M3: the raised belt left the order completely unchanged (subtransaction rollback)');

select * from finish();
rollback;
