-- ============================================================================
-- POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 — pgTAP: the optional order-time customer
-- phone contract + the printer_only dine-in CLOSE lifecycle.
--
-- Part A/B (customer phone):
--   * app.is_valid_customer_phone predicate (local / +intl / punctuation valid;
--     letters / newline / <5 digits / >32 chars / empty / null invalid).
--   * app.sync_push order.submit: a valid phone persists (trimmed display form);
--     blank -> null (order still submits); an old payload WITHOUT the key still
--     submits; an INVALID non-empty phone REJECTS the whole op (typed
--     invalid_payload) and creates NO order; a replay preserves the value.
--   * the four authorized reads (pos_order_detail / owner_order_detail /
--     owner_order_history / owner_active_orders) return customer_phone; a
--     cross-tenant actor is denied; anon has no execute.
--   * PRIVACY: the phone is NOT in pos_order_snapshots, NOT in the kitchen
--     dispatch generic ledger, NOT in any audit_events row.
--
-- Part C (dine-in close, printer_only): a dine_in direct_print order rests at
--   `served` on submit, COMPLETES on the UNCHANGED cash settlement, and frees its
--   table (no active order remains) — no KDS acknowledgement required.
--
-- Synthetic phone numbers only. Session pinned to UTC; hex-only UUIDs;
-- PIN-session auth (GUC-free) for POS; actor GUC for the owner reads.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(41);

-- ===== fixture ==============================================================
-- Org A: Rest A1 with Branch K (kds) + Branch P (printer_only, flipped below).
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-00cf0000aa00', 'Org CP-A', 'cp-a', 'ILS');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-00cf0000aa10', '00000000-0000-0000-0000-00cf0000aa00', 'Rest A1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00cf0000aa1a', '00000000-0000-0000-0000-00cf0000aa00', '00000000-0000-0000-0000-00cf0000aa10', 'Branch K (kds)'),
  ('00000000-0000-0000-0000-00cf0000aa2b', '00000000-0000-0000-0000-00cf0000aa00', '00000000-0000-0000-0000-00cf0000aa10', 'Branch P (printer_only)');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00cf00d0aa01', '00000000-0000-0000-0000-00cf0000aa00', '00000000-0000-0000-0000-00cf0000aa10', '00000000-0000-0000-0000-00cf0000aa1a', 'pos'),
  ('00000000-0000-0000-0000-00cf00d0aa02', '00000000-0000-0000-0000-00cf0000aa00', '00000000-0000-0000-0000-00cf0000aa10', '00000000-0000-0000-0000-00cf0000aa2b', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00cf00c0aa01', '00000000-0000-0000-0000-00cf0000aa00', '00000000-0000-0000-0000-00cf0000aa10', '00000000-0000-0000-0000-00cf0000aa1a', '00000000-0000-0000-0000-00cf00d0aa01', 'active'),
  ('00000000-0000-0000-0000-00cf00c0aa02', '00000000-0000-0000-0000-00cf0000aa00', '00000000-0000-0000-0000-00cf0000aa10', '00000000-0000-0000-0000-00cf0000aa2b', '00000000-0000-0000-0000-00cf00d0aa02', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-00cf00e0aa01', '00000000-0000-0000-0000-00cf0000aa00', '00000000-0000-0000-0000-00cf0000aa10', '00000000-0000-0000-0000-00cf0000aa1a', '00000000-0000-0000-0000-00cf00d0aa01', '00000000-0000-0000-0000-00cf00c0aa01'),
  ('00000000-0000-0000-0000-00cf00e0aa02', '00000000-0000-0000-0000-00cf0000aa00', '00000000-0000-0000-0000-00cf0000aa10', '00000000-0000-0000-0000-00cf0000aa2b', '00000000-0000-0000-0000-00cf00d0aa02', '00000000-0000-0000-0000-00cf00c0aa02');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00cf0000af01', 'cp-cashier-k@example.test'),
  ('00000000-0000-0000-0000-00cf0000af02', 'cp-cashier-p@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00cf00ab0a01', '00000000-0000-0000-0000-00cf0000af01', '00000000-0000-0000-0000-00cf0000aa00', '00000000-0000-0000-0000-00cf0000aa10', '00000000-0000-0000-0000-00cf0000aa1a', 'cashier'),
  ('00000000-0000-0000-0000-00cf00ab0a02', '00000000-0000-0000-0000-00cf0000af02', '00000000-0000-0000-0000-00cf0000aa00', '00000000-0000-0000-0000-00cf0000aa10', '00000000-0000-0000-0000-00cf0000aa2b', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-00cf00ef0a01', '00000000-0000-0000-0000-00cf0000aa00', '00000000-0000-0000-0000-00cf0000aa10', '00000000-0000-0000-0000-00cf0000aa1a', '00000000-0000-0000-0000-00cf0000af01', '00000000-0000-0000-0000-00cf00ab0a01', 'Cashier K'),
  ('00000000-0000-0000-0000-00cf00ef0a02', '00000000-0000-0000-0000-00cf0000aa00', '00000000-0000-0000-0000-00cf0000aa10', '00000000-0000-0000-0000-00cf0000aa2b', '00000000-0000-0000-0000-00cf0000af02', '00000000-0000-0000-0000-00cf00ab0a02', 'Cashier P');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00cf00c50a01', '00000000-0000-0000-0000-00cf0000aa00', '00000000-0000-0000-0000-00cf0000aa10', '00000000-0000-0000-0000-00cf0000aa1a', '00000000-0000-0000-0000-00cf00e0aa01', '00000000-0000-0000-0000-00cf00ef0a01', '00000000-0000-0000-0000-00cf00ab0a01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00cf00c50a02', '00000000-0000-0000-0000-00cf0000aa00', '00000000-0000-0000-0000-00cf0000aa10', '00000000-0000-0000-0000-00cf0000aa2b', '00000000-0000-0000-0000-00cf00e0aa02', '00000000-0000-0000-0000-00cf00ef0a02', '00000000-0000-0000-0000-00cf00ab0a02', now() + interval '1 hour');
insert into tables (id, organization_id, restaurant_id, branch_id, label) values
  ('00000000-0000-0000-0000-00cf00fb0a01', '00000000-0000-0000-0000-00cf0000aa00', '00000000-0000-0000-0000-00cf0000aa10', '00000000-0000-0000-0000-00cf0000aa2b', 'P-7');
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('00000000-0000-0000-0000-00cf0000ca01', '00000000-0000-0000-0000-00cf0000aa00', '00000000-0000-0000-0000-00cf0000aa10', null, 'Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('00000000-0000-0000-0000-00cf0000dd01', '00000000-0000-0000-0000-00cf0000aa00', '00000000-0000-0000-0000-00cf0000aa10', null, '00000000-0000-0000-0000-00cf0000ca01', 'Burger', 500, 'ILS', 1);

-- Flip Branch P to printer_only (PRIVILEGED SQL; there is no client setter).
update public.branches set kitchen_workflow_mode = 'printer_only'
  where id = '00000000-0000-0000-0000-00cf0000aa2b';

-- Open a shift + bound drawer on Branch P so app.record_payment can settle (RF-055).
select app.open_shift('00000000-0000-0000-0000-00cf00c50a02', '00000000-0000-0000-0000-00cf00fa0a01',
                      '00000000-0000-0000-0000-00cf00fd0a01', '00000000-0000-0000-0000-00cf00d0aa02', 'cp-sh-p', 0);

-- Helper: one order.submit through app.sync_push. p_phone NULL omits the key
-- entirely (the old-client payload); a non-null p_phone includes it verbatim.
create or replace function pg_temp.cp_submit(
  p_pin uuid, p_dev uuid, p_op text, p_order uuid, p_price bigint,
  p_type text, p_table uuid, p_mode text, p_phone text)
  returns jsonb language sql as $$
  select app.sync_push(p_pin, p_dev,
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', p_op,
      'operation_type', 'order.submit',
      'target_entity', 'order',
      'target_id', p_order::text,
      'payload',
        jsonb_build_object(
          'order_id', p_order::text, 'order_type', p_type, 'currency_code', 'ILS',
          'table_id', p_table,
          'order_items', jsonb_build_array(jsonb_build_object(
            'menu_item_id', '00000000-0000-0000-0000-00cf0000dd01', 'quantity', 1,
            'unit_price_minor_snapshot', p_price,
            'menu_item_name_snapshot', 'Burger', 'modifiers', '[]'::jsonb)),
          'subtotal_minor', p_price, 'discount_total_minor', 0,
          'tax_total_minor', 0, 'grand_total_minor', p_price,
          'dispatch_mode', p_mode)
        || case when p_phone is null then '{}'::jsonb
                else jsonb_build_object('customer_phone', p_phone) end)));
$$;

create or replace function pg_temp.cp_pay(p_pin uuid, p_dev uuid, p_op text, p_order uuid, p_amt bigint)
  returns jsonb language sql as $$
  select app.sync_push(p_pin, p_dev,
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', p_op, 'operation_type', 'payment.create',
      'target_entity', 'payment', 'target_id', p_order::text,
      'payload', jsonb_build_object(
        'order_id', p_order::text, 'tender_type', 'cash', 'amount_tendered_minor', p_amt))));
$$;

-- ===== 1. app.is_valid_customer_phone predicate =============================
select ok(app.is_valid_customer_phone('054-1234567'),        '01 local number valid');
select ok(app.is_valid_customer_phone('+972 54 987 6543'),   '02 international + valid');
select ok(app.is_valid_customer_phone('+1 (555) 019-2837'),  '03 spaces/parens/hyphens valid');
select ok(not app.is_valid_customer_phone('054-ABC-1234'),   '04 letters rejected');
select ok(not app.is_valid_customer_phone(E'054\n12345'),    '05 newline rejected');
select ok(not app.is_valid_customer_phone('12 34'),          '06 fewer than 5 digits rejected');
select ok(not app.is_valid_customer_phone(repeat('1', 33)),  '07 over 32 chars rejected');
select ok(not app.is_valid_customer_phone(''),               '08 empty rejected');

-- ===== 2. schema =============================================================
select col_type_is('public', 'orders', 'customer_phone', 'text', '09 customer_phone is text');
select col_is_null('public', 'orders', 'customer_phone', '10 customer_phone is nullable');
select col_hasnt_default('public', 'orders', 'customer_phone', '11 customer_phone has no default');
select ok(exists (select 1 from pg_constraint where conname = 'orders_customer_phone_valid_chk'),
  '12 defensive CHECK constraint exists');

-- ===== 3. submission through app.sync_push ===================================
-- valid local number persists on a kds takeaway order (Branch K).
select is((select pg_temp.cp_submit(
    '00000000-0000-0000-0000-00cf00c50a01', '00000000-0000-0000-0000-00cf00d0aa01',
    'cp-loc', '00000000-0000-0000-0000-00cf00000d01', 500, 'takeaway', null, 'kds', '  054-1234567  ')
    #>> '{results,0,status}'), 'applied', '13 a valid phone order.submit is applied');
select is((select customer_phone from orders where id = '00000000-0000-0000-0000-00cf00000d01'),
  '054-1234567', '14 the TRIMMED display form is persisted');

-- international + punctuation persists verbatim (trimmed).
select is((select pg_temp.cp_submit(
    '00000000-0000-0000-0000-00cf00c50a01', '00000000-0000-0000-0000-00cf00d0aa01',
    'cp-intl', '00000000-0000-0000-0000-00cf00000d02', 500, 'takeaway', null, 'kds', '+972 54 987 6543')
    #>> '{results,0,status}'), 'applied', '15 an international + phone order.submit is applied');
select is((select customer_phone from orders where id = '00000000-0000-0000-0000-00cf00000d02'),
  '+972 54 987 6543', '16 the international display form (spaces + leading +) is preserved');

-- blank/whitespace phone -> NULL, but the order STILL submits.
select is((select pg_temp.cp_submit(
    '00000000-0000-0000-0000-00cf00c50a01', '00000000-0000-0000-0000-00cf00d0aa01',
    'cp-blank', '00000000-0000-0000-0000-00cf00000d03', 500, 'takeaway', null, 'kds', '    ')
    #>> '{results,0,status}'), 'applied', '17 a blank phone does NOT block submit');
select ok((select customer_phone is null from orders where id = '00000000-0000-0000-0000-00cf00000d03'),
  '18 a blank/whitespace phone is stored as NULL');

-- old-client payload with NO customer_phone key still submits (null-safe).
select is((select pg_temp.cp_submit(
    '00000000-0000-0000-0000-00cf00c50a01', '00000000-0000-0000-0000-00cf00d0aa01',
    'cp-omit', '00000000-0000-0000-0000-00cf00000d04', 500, 'takeaway', null, 'kds', null)
    #>> '{results,0,status}'), 'applied', '19 an old payload without the phone key still submits');
select ok((select customer_phone is null from orders where id = '00000000-0000-0000-0000-00cf00000d04'),
  '20 the phone is NULL when the key is absent');

-- INVALID non-empty phones REJECT the whole op (invalid_payload) + NO order.
select is((select pg_temp.cp_submit(
    '00000000-0000-0000-0000-00cf00c50a01', '00000000-0000-0000-0000-00cf00d0aa01',
    'cp-letters', '00000000-0000-0000-0000-00cf00000d05', 500, 'takeaway', null, 'kds', '054-ABC-1234')
    #>> '{results,0,error}'), 'invalid_payload', '21 letters -> invalid_payload');
select ok(not exists (select 1 from orders where id = '00000000-0000-0000-0000-00cf00000d05'),
  '22 an invalid-letters phone creates NO order');
select is((select pg_temp.cp_submit(
    '00000000-0000-0000-0000-00cf00c50a01', '00000000-0000-0000-0000-00cf00d0aa01',
    'cp-nl', '00000000-0000-0000-0000-00cf00000d06', 500, 'takeaway', null, 'kds', E'054\n12345')
    #>> '{results,0,error}'), 'invalid_payload', '23 a newline -> invalid_payload');
select is((select pg_temp.cp_submit(
    '00000000-0000-0000-0000-00cf00c50a01', '00000000-0000-0000-0000-00cf00d0aa01',
    'cp-short', '00000000-0000-0000-0000-00cf00000d07', 500, 'takeaway', null, 'kds', '12 34')
    #>> '{results,0,error}'), 'invalid_payload', '24 fewer than 5 digits -> invalid_payload');
select is((select pg_temp.cp_submit(
    '00000000-0000-0000-0000-00cf00c50a01', '00000000-0000-0000-0000-00cf00d0aa01',
    'cp-long', '00000000-0000-0000-0000-00cf00000d08', 500, 'takeaway', null, 'kds', '+' || repeat('9', 40))
    #>> '{results,0,error}'), 'invalid_payload', '25 over 32 chars -> invalid_payload');
select ok(not exists (select 1 from orders where id in (
    '00000000-0000-0000-0000-00cf00000d06','00000000-0000-0000-0000-00cf00000d07','00000000-0000-0000-0000-00cf00000d08')),
  '26 newline / short / long invalid phones create NO order');

-- idempotent replay preserves the original value exactly once.
create temp table _cp_replay as select pg_temp.cp_submit(
  '00000000-0000-0000-0000-00cf00c50a01', '00000000-0000-0000-0000-00cf00d0aa01',
  'cp-loc', '00000000-0000-0000-0000-00cf00000d01', 500, 'takeaway', null, 'kds', '999-999-9999') as res;
select is((select customer_phone from orders where id = '00000000-0000-0000-0000-00cf00000d01'),
  '054-1234567', '27 a replay never overwrites the stored phone');

-- ===== 4. authorized reads return customer_phone ============================
select is((select app.pos_order_detail('00000000-0000-0000-0000-00cf00c50a01',
    '00000000-0000-0000-0000-00cf00d0aa01', '00000000-0000-0000-0000-00cf00000d01')
    #>> '{order,customer_phone}'), '054-1234567', '28 pos_order_detail returns the phone');

set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00cf0000af01';
select is((select app.owner_order_detail('00000000-0000-0000-0000-00cf0000aa00',
    '00000000-0000-0000-0000-00cf0000aa10', '00000000-0000-0000-0000-00cf0000aa1a',
    '00000000-0000-0000-0000-00cf00000d01') #>> '{order,customer_phone}'),
  '054-1234567', '29 owner_order_detail returns the phone');
select is((select o ->> 'customer_phone'
    from jsonb_array_elements(app.owner_order_history('00000000-0000-0000-0000-00cf0000aa00',
      '00000000-0000-0000-0000-00cf0000aa10', '00000000-0000-0000-0000-00cf0000aa1a') -> 'orders') o
    where o ->> 'order_id' = '00000000-0000-0000-0000-00cf00000d01'),
  '054-1234567', '30 owner_order_history returns the phone');
select is((select o ->> 'customer_phone'
    from jsonb_array_elements(app.owner_active_orders('00000000-0000-0000-0000-00cf0000aa00',
      '00000000-0000-0000-0000-00cf0000aa10', '00000000-0000-0000-0000-00cf0000aa1a') -> 'orders') o
    where o ->> 'order_id' = '00000000-0000-0000-0000-00cf00000d01'),
  '054-1234567', '31 owner_active_orders returns the phone');
reset role;

-- cross-tenant actor (Org B member) is denied a read of an Org A order.
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-00cf0000bb00', 'Org CP-B', 'cp-b', 'ILS');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00cf0000bf01', 'cp-outsider@example.test');
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-00cf00bb0b01', '00000000-0000-0000-0000-00cf0000bf01', '00000000-0000-0000-0000-00cf0000bb00', 'org_owner');
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00cf0000bf01';
select throws_ok($$ select app.owner_order_detail('00000000-0000-0000-0000-00cf0000aa00',
    '00000000-0000-0000-0000-00cf0000aa10', '00000000-0000-0000-0000-00cf0000aa1a',
    '00000000-0000-0000-0000-00cf00000d01') $$,
  '42501', null, '32 a cross-tenant actor cannot read another org''s order');
reset role;

-- anon has no execute on the public read wrapper / the phone predicate.
select ok(not has_function_privilege('anon', 'public.pos_order_detail(uuid, uuid, uuid)', 'execute'),
  '33 anon cannot execute public.pos_order_detail');
select ok(not has_function_privilege('anon', 'app.is_valid_customer_phone(text)', 'execute'),
  '34 anon cannot execute the phone predicate');

-- ===== 5. dine-in printer_only CLOSE + table release ========================
-- submit a dine_in direct_print order on Branch P (printer_only) with a phone.
select is((select pg_temp.cp_submit(
    '00000000-0000-0000-0000-00cf00c50a02', '00000000-0000-0000-0000-00cf00d0aa02',
    'cp-dine', '00000000-0000-0000-0000-00cf00000e01', 500, 'dine_in',
    '00000000-0000-0000-0000-00cf00fb0a01', 'direct_print', '050-7654321')
    #>> '{results,0,order_status}'), 'served',
  '35 a dine_in direct_print order rests at served on submit (no KDS)');
select ok((select status = 'served' from orders where id = '00000000-0000-0000-0000-00cf00000e01'),
  '36 the dine-in order is persisted served, not stuck at submitted');
-- the table is OCCUPIED while the order is open.
select ok(exists (select 1 from orders where table_id = '00000000-0000-0000-0000-00cf00fb0a01'
    and status not in ('completed','cancelled','voided') and deleted_at is null),
  '37 the table is occupied while the order is open');
-- settle in full -> COMPLETES on the UNCHANGED rule.
create temp table _cp_pay as select pg_temp.cp_pay('00000000-0000-0000-0000-00cf00c50a02',
    '00000000-0000-0000-0000-00cf00d0aa02', 'cp-dine-pay', '00000000-0000-0000-0000-00cf00000e01', 500) as res;
select ok((select status = 'completed' from orders where id = '00000000-0000-0000-0000-00cf00000e01'),
  '38 the settled dine-in order auto-completes (no KDS ack)');
-- the table is now FREE (no active order holds it) -> reusable.
select ok(not exists (select 1 from orders where table_id = '00000000-0000-0000-0000-00cf00fb0a01'
    and status not in ('completed','cancelled','voided') and deleted_at is null),
  '39 completion frees the table (no active order remains)');

-- ===== 6. privacy: the phone is not in the ledger / snapshots / audit =======
-- the dine-in order's phone must NOT appear in the kitchen dispatch generic
-- ledger (money_free_payload) for that order.
select ok(not exists (select 1 from kitchen_print_dispatches kd
    where kd.order_id = '00000000-0000-0000-0000-00cf00000e01'
      and (kd.money_free_payload::text like '%7654321%' or kd.money_free_payload ? 'customer_phone')),
  '40 the phone is absent from the kitchen dispatch generic ledger');
-- and NOT in any audit_events row, and pos_order_snapshots never selects it.
select ok(
  not exists (select 1 from audit_events
      where organization_id = '00000000-0000-0000-0000-00cf0000aa00'
        and (coalesce(old_values::text,'') || coalesce(new_values::text,'') || coalesce(reason,'')) like '%7654321%')
  and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app' and p.proname = 'pos_order_snapshots'
        and pg_get_functiondef(p.oid) like '%customer_phone%'),
  '41 the phone is not in audit free-text and not in pos_order_snapshots');

select * from finish();
rollback;
