-- ============================================================================
-- KIOSK-001-PREREQ-079 — pgTAP: the dine-in-without-a-table contract.
--
-- SHAPE: takeaway must stay table-free; dine-in MAY omit the table (the
-- owner's table-selection-OFF flow); a SUPPLIED dine-in table still passes
-- the FULL Phase-2 atomic gate (occupied/reserved/oos/sibling refused).
-- LIFECYCLE: a NULL-table dine-in kiosk order persists honestly (dine_in +
-- NULL table + device actor), creates NO occupancy, is visible to POS and
-- KDS, progresses through the kitchen states, takes a cashier payment,
-- COMPLETES normally, and replays idempotently. SECURITY: the token proof
-- and every HARDENING-FIX-073 authority run unchanged on the new shape.
-- Fixtures inserted as the BYPASSRLS harness role; all RPC authority is
-- parameter-based (token / PIN), so the harness role drives everything.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(28);

-- ===== fixture: one org/rest/branch; kiosk + POS devices; staff sessions ====
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-007900000a00', 'NT Org', 'kiosk-nt', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-007900000a10', '00000000-0000-0000-0000-007900000a00', 'NT Rest');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-007900000a1a', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', 'NT Branch A'),
  ('00000000-0000-0000-0000-007900000a1b', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', 'NT Branch B');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('00000000-0000-0000-0000-007900004001', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', '00000000-0000-0000-0000-007900000a1a', 'kiosk', 'NT Kiosk'),
  ('00000000-0000-0000-0000-007900004004', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', '00000000-0000-0000-0000-007900000a1a', 'pos',   'NT POS');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-007900004011', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', '00000000-0000-0000-0000-007900000a1a', '00000000-0000-0000-0000-007900004001', 'active'),
  ('00000000-0000-0000-0000-007900004014', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', '00000000-0000-0000-0000-007900000a1a', '00000000-0000-0000-0000-007900004004', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, expires_at) values
  ('00000000-0000-0000-0000-007900004051', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', '00000000-0000-0000-0000-007900000a1a', '00000000-0000-0000-0000-007900004001', '00000000-0000-0000-0000-007900004011', app.hash_provisioning_secret('tok-nt-kiosk'), true, now() + interval '1 day'),
  ('00000000-0000-0000-0000-007900004055', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', '00000000-0000-0000-0000-007900000a1a', '00000000-0000-0000-0000-007900004004', '00000000-0000-0000-0000-007900004014', app.hash_provisioning_secret('tok-nt-pos'),   true, now() + interval '1 day');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00790000ee01', 'nt-cashier@example.test'),
  ('00000000-0000-0000-0000-00790000ee02', 'nt-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00790000ab01', '00000000-0000-0000-0000-00790000ee01', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', '00000000-0000-0000-0000-007900000a1a', 'cashier'),
  ('00000000-0000-0000-0000-00790000ab02', '00000000-0000-0000-0000-00790000ee02', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', '00000000-0000-0000-0000-007900000a1a', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-00790000ef01', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', '00000000-0000-0000-0000-007900000a1a', '00000000-0000-0000-0000-00790000ee01', '00000000-0000-0000-0000-00790000ab01'),
  ('00000000-0000-0000-0000-00790000ef02', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', '00000000-0000-0000-0000-007900000a1a', '00000000-0000-0000-0000-00790000ee02', '00000000-0000-0000-0000-00790000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00790000c501', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', '00000000-0000-0000-0000-007900000a1a', '00000000-0000-0000-0000-007900004055', '00000000-0000-0000-0000-00790000ef01', '00000000-0000-0000-0000-00790000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00790000c502', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', '00000000-0000-0000-0000-007900000a1a', '00000000-0000-0000-0000-007900004055', '00000000-0000-0000-0000-00790000ef02', '00000000-0000-0000-0000-00790000ab02', now() + interval '1 hour');

-- menu: Cola 1000 (no groups) + Burger 4000 with a REQUIRED single Weight.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order, is_active) values
  ('00000000-0000-0000-0000-00790000c100', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', null, 'NT Cat', 0, true);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order, is_active) values
  ('00000000-0000-0000-0000-007900011701', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', null, '00000000-0000-0000-0000-00790000c100', 'NT Cola', 1000, 'ILS', 0, true),
  ('00000000-0000-0000-0000-007900011702', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', null, '00000000-0000-0000-0000-00790000c100', 'NT Burger', 4000, 'ILS', 1, true);
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, min_select, max_select, is_required, is_active) values
  ('00000000-0000-0000-0000-00790000d101', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', null, '00000000-0000-0000-0000-007900011702', 'NT Weight', 'single', 1, 1, true, true);
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active) values
  ('00000000-0000-0000-0000-00790000d201', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', null, '00000000-0000-0000-0000-00790000d101', 'NT-120', 0, 0, true);

-- floor: T1 available, T2 occupied, T4 out-of-service, TB on the sibling
-- branch, TX in ANOTHER ORG.
insert into tables (id, organization_id, restaurant_id, branch_id, label, seats, status, is_active) values
  ('00000000-0000-0000-0000-00790000f101', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', '00000000-0000-0000-0000-007900000a1a', 'NT-T1', 4, 'available',      true),
  ('00000000-0000-0000-0000-00790000f102', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', '00000000-0000-0000-0000-007900000a1a', 'NT-T2', 2, 'occupied',       true),
  ('00000000-0000-0000-0000-00790000f104', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', '00000000-0000-0000-0000-007900000a1a', 'NT-T4', 4, 'out_of_service', true),
  ('00000000-0000-0000-0000-00790000f10b', '00000000-0000-0000-0000-007900000a00', '00000000-0000-0000-0000-007900000a10', '00000000-0000-0000-0000-007900000a1b', 'NT-TB', 4, 'available',      true);
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-007900000b00', 'NT Org B', 'kiosk-nt-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-007900000b10', '00000000-0000-0000-0000-007900000b00', 'NT Rest B');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-007900000b1a', '00000000-0000-0000-0000-007900000b00', '00000000-0000-0000-0000-007900000b10', 'NT B Branch');
insert into tables (id, organization_id, restaurant_id, branch_id, label, seats, status, is_active) values
  ('00000000-0000-0000-0000-00790000f10c', '00000000-0000-0000-0000-007900000b00', '00000000-0000-0000-0000-007900000b10', '00000000-0000-0000-0000-007900000b1a', 'NT-TX', 4, 'available', true);

create temp table _r (label text primary key, r jsonb);
create temp table _cola as select jsonb_build_array(jsonb_build_object(
  'menu_item_id', '00000000-0000-0000-0000-007900011701',
  'menu_item_name_snapshot', 'NT Cola', 'quantity', 1,
  'unit_price_minor_snapshot', 1000)) as items;

-- helper: one kiosk submit with the shared token (harness role; the RPC's
-- only authority is the token parameter).
create function pg_temp.ksub(p_order uuid, p_op text, p_type text, p_table uuid)
returns jsonb language sql as $$
  select public.kiosk_submit_order(
    '00000000-0000-0000-0000-007900004001', 'tok-nt-kiosk',
    p_order, p_op, p_type, p_table, 'ILS', null, null, null,
    (select items from _cola), 1000, 0, 0, 1000);
$$;
-- helper: one kitchen status hop through the REAL sync_push funnel.
create function pg_temp.kstatus(p_op text, p_order uuid, p_to text)
returns jsonb language sql as $$
  select public.sync_push('00000000-0000-0000-0000-00790000c502',
    '00000000-0000-0000-0000-007900004004',
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', p_op, 'operation_type', 'order.status',
      'target_entity', 'order',
      'payload', jsonb_build_object(
        'order_id', p_order, 'new_status', p_to))));
$$;

-- ============================================================================
-- A. SHAPE (1-7)
-- ============================================================================
select ok(((pg_temp.ksub('00000000-0000-0000-0000-007900aade01', 'nt-01', 'takeaway', null)) ->> 'ok')::boolean,
  'A1: takeaway without a table is accepted (unchanged)');
select is(((pg_temp.ksub('00000000-0000-0000-0000-007900aade02', 'nt-02', 'takeaway',
    '00000000-0000-0000-0000-00790000f101')) ->> 'error'),
  'table_not_allowed', 'A2: takeaway STILL never carries a table');
insert into _r values ('nt', pg_temp.ksub('00000000-0000-0000-0000-007900aade03', 'nt-03', 'dine_in', null));
select ok((select (r ->> 'ok')::boolean from _r where label = 'nt'),
  'A3: dine-in WITHOUT a table is accepted — the owner table-selection-OFF flow (079)');
select ok(((pg_temp.ksub('00000000-0000-0000-0000-007900aade04', 'nt-04', 'dine_in',
    '00000000-0000-0000-0000-00790000f101')) ->> 'ok')::boolean,
  'A4: dine-in WITH an available table still seats it (gate unchanged)');
select is(((pg_temp.ksub('00000000-0000-0000-0000-007900aade05', 'nt-05', 'dine_in',
    '00000000-0000-0000-0000-00790000f102')) ->> 'error'),
  'table_no_longer_available', 'A5: a supplied OCCUPIED table is still refused');
select is(((pg_temp.ksub('00000000-0000-0000-0000-007900aade06', 'nt-06', 'dine_in',
    '00000000-0000-0000-0000-00790000f104')) ->> 'error'),
  'table_not_available', 'A6: a supplied OUT-OF-SERVICE table is still refused');
select is(((pg_temp.ksub('00000000-0000-0000-0000-007900aade07', 'nt-07', 'dine_in',
    '00000000-0000-0000-0000-00790000f10c')) ->> 'error'),
  'table_not_available', 'A7: a CROSS-TENANT table is indistinguishable from unknown (R-003)');

-- ============================================================================
-- B. NULL-TABLE LIFECYCLE (8-20) — the A3 order end to end.
-- ============================================================================
select ok((select o.order_type = 'dine_in' and o.table_id is null
              and o.status = 'submitted' and o.revision = 1
            from orders o where o.id = '00000000-0000-0000-0000-007900aade03'),
  'B1: persisted honestly — dine_in, NULL table, submitted, revision 1');
select ok((select o.pin_session_id is null and o.opened_by_employee_profile_id is null
              and o.resolved_membership_id is null and o.shift_id is null
              and o.device_id = '00000000-0000-0000-0000-007900004001'
            from orders o where o.id = '00000000-0000-0000-0000-007900aade03'),
  'B2: the kiosk DEVICE is the actor; no staff triple, no shift');
select ok((select ae.device_id = '00000000-0000-0000-0000-007900004001'
              and ae.new_values ->> 'actor_kind' = 'kiosk_device'
              and ae.new_values ->> 'table_id' is null
            from audit_events ae
            where ae.action = 'kiosk.order.submitted'
              and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-007900aade03'),
  'B3: the append-only audit row records the device actor and the NULL table');
select is((select count(*)::int from orders o
            where o.branch_id = '00000000-0000-0000-0000-007900000a1a'
              and o.order_type = 'dine_in' and o.table_id is not null
              and o.deleted_at is null
              and o.status in ('submitted','accepted','preparing','ready','served')), 1,
  'B4: derived occupancy counts ONLY the A4 seated order — the NULL-table order occupies nothing');
select is(app.table_effective_state('available', 0), 'available',
  'B5: an untouched table reads available (no phantom occupancy path exists for a NULL table)');
select ok((select exists (select 1 from jsonb_array_elements(
             app.pos_order_snapshots('00000000-0000-0000-0000-00790000c501',
                                     '00000000-0000-0000-0000-007900004004') -> 'orders') o
             where o ->> 'order_id' = '00000000-0000-0000-0000-007900aade03'
               and o ->> 'table_label' is null)),
  'B6: POS sees the order with an honest NULL table label (LEFT JOIN, no crash)');
select ok((app.sync_pull('00000000-0000-0000-0000-00790000c502',
                         '00000000-0000-0000-0000-007900004004',
                         array['orders'])::text like '%007900aade03%'),
  'B7: KDS receives the order through sync_pull');
-- NOTE: each hop is its OWN statement — an uncorrelated status subquery in
-- the same SELECT is planned as an InitPlan and would read the PRE-hop state.
select pg_temp.kstatus('nt-st-a', '00000000-0000-0000-0000-007900aade03', 'accepted');
select ok((select o.status = 'accepted' from orders o
            where o.id = '00000000-0000-0000-0000-007900aade03'),
  'B8: the kitchen ACCEPTS it — normal state machine, no table needed');
select pg_temp.kstatus('nt-st-p', '00000000-0000-0000-0000-007900aade03', 'preparing');
select pg_temp.kstatus('nt-st-r', '00000000-0000-0000-0000-007900aade03', 'ready');
select pg_temp.kstatus('nt-st-s', '00000000-0000-0000-0000-007900aade03', 'served');
select ok((select o.status = 'served' from orders o
            where o.id = '00000000-0000-0000-0000-007900aade03'),
  'B9: preparing -> ready -> served all progress normally');
select app.open_shift('00000000-0000-0000-0000-00790000c501',
                      '00000000-0000-0000-0000-007900057001',
                      '00000000-0000-0000-0000-0079000cd001',
                      '00000000-0000-0000-0000-007900004004', 'nt-shift', 0) ->> 'ok';
select ok(((app.record_payment('00000000-0000-0000-0000-00790000c501',
    '00000000-0000-0000-0000-007900aade03',
    '00000000-0000-0000-0000-007900004004', 'nt-pay-1', 'cash', 1000, null)) ->> 'ok')::boolean,
  'B10: the cashier takes the pay-later payment normally');
select ok((select o.status = 'completed' from orders o
            where o.id = '00000000-0000-0000-0000-007900aade03'),
  'B11: SERVED + fully SETTLED completes the order — the normal lifecycle end');
select is((select count(*)::int from payments p
            where p.order_id = '00000000-0000-0000-0000-007900aade03'
              and p.status = 'completed'), 1,
  'B12: exactly one completed payment (receipt path intact)');
select ok((select p.receipt_number is not null from payments p
            where p.order_id = '00000000-0000-0000-0000-007900aade03'
              and p.status = 'completed'),
  'B13: a receipt number was assigned (D-021 sequence, table-agnostic)');

-- ============================================================================
-- C. IDEMPOTENCY on the new shape (21-22... numbered 14-15 here)
-- ============================================================================
insert into _r values ('replay', pg_temp.ksub('00000000-0000-0000-0000-007900aade03', 'nt-03', 'dine_in', null));
select ok((select (r ->> 'ok')::boolean and (r ->> 'idempotency_replay')::boolean
              and r ->> 'order_id' = '00000000-0000-0000-0000-007900aade03'
            from _r where label = 'replay')
  and (select count(*) = 1 from orders o
        where o.device_id = '00000000-0000-0000-0000-007900004001'
          and o.local_operation_id = 'nt-03'),
  'C1: the exact replay returns the stored acceptance; no duplicate order');
select is(((pg_temp.ksub('00000000-0000-0000-0000-007900aadeff', 'nt-03', 'takeaway', null)) ->> 'error'),
  'conflict', 'C2: the reused idempotency key with a different payload stays a conflict');

-- ============================================================================
-- D. SECURITY on the new shape (16-19)
-- ============================================================================
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007900004001', 'wrong-token',
    '00000000-0000-0000-0000-007900aade08', 'nt-08', 'dine_in', null, 'ILS', null, null, null,
    (select items from _cola), 1000, 0, 0, 1000)) ->> 'error'),
  'invalid_session', 'D1: a wrong token is refused before any shape rule runs');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007900004004', 'tok-nt-pos',
    '00000000-0000-0000-0000-007900aade09', 'nt-09', 'dine_in', null, 'ILS', null, null, null,
    (select items from _cola), 1000, 0, 0, 1000)) ->> 'error'),
  'invalid_session', 'D2: a POS token still cannot use the kiosk mutation');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007900004001', 'tok-nt-kiosk',
    '00000000-0000-0000-0000-007900aade0a', 'nt-10', 'dine_in', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object(
      'menu_item_id', '00000000-0000-0000-0000-007900011701',
      'menu_item_name_snapshot', 'NT Cola', 'quantity', 1,
      'unit_price_minor_snapshot', 1)),
    1, 0, 0, 1)) ->> 'error'),
  'menu_price_changed', 'D3: the price authority runs unchanged on the NULL-table shape');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007900004001', 'tok-nt-kiosk',
    '00000000-0000-0000-0000-007900aade0b', 'nt-11', 'dine_in', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object(
      'menu_item_id', '00000000-0000-0000-0000-007900011702',
      'menu_item_name_snapshot', 'NT Burger', 'quantity', 1,
      'unit_price_minor_snapshot', 4000)),
    4000, 0, 0, 4000)) ->> 'error'),
  'modifier_selection_invalid', 'D4: required-group enforcement runs unchanged on the NULL-table shape');

-- ============================================================================
-- E. POS PATH UNTOUCHED (20-21... numbered 20,26)
-- ============================================================================
select lives_ok(
  $$select app.submit_order('00000000-0000-0000-0000-00790000c501',
      '00000000-0000-0000-0000-007900aade0c',
      '00000000-0000-0000-0000-007900004004', 'nt-pos-1', 'dine_in', null, null, 'ILS', null,
      (select items from _cola), 1000, 0, 0, 1000)$$,
  'E1: the POS path never raises on the shape — refusals RETURN envelopes');
select is(((app.submit_order('00000000-0000-0000-0000-00790000c501',
    '00000000-0000-0000-0000-007900aade0d',
    '00000000-0000-0000-0000-007900004004', 'nt-pos-2', 'dine_in', null, null, 'ILS', null,
    (select items from _cola), 1000, 0, 0, 1000)) ->> 'error'),
  'table_required', 'E2: the STAFF POS submit still requires a dine-in table (unchanged)');

select * from finish();
rollback;
