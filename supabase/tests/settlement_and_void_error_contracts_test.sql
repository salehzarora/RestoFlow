-- ============================================================================
-- MONEY-SETTLEMENT-CONSISTENCY-001 (corrective) — pgTAP: the domain error contract
-- SURVIVES app.sync_push.
--
-- THE BUG THIS PINS. app.sync_push finalizes a dispatched op two ways:
--   * the RPC RETURNS {ok:false,...} -> the RPC's OWN envelope is merged through VERBATIM
--     (`error` and `detail` survive) -- this is how order_has_completed_payment already
--     reaches the POS;
--   * the RPC RAISES              -> the envelope is REBUILT FROM SCRATCH: `error`
--     collapses to the generic literal 'rejected' and the domain code is LOST.
-- Two refusals were on the RAISE side, so the POS could not see them:
--   record_payment's zero-total refusal, and void_order's terminal-order refusal.
-- Both now RETURN. sync_push is NOT modified.
--
-- Every test below drives the REAL client path (public.sync_push), not the RPC directly.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(16);

-- ===== fixture ===============================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000ec0a0', 'Org A', 'ec-a', 'ILS');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000ec1a0', '00000000-0000-0000-0000-0000000ec0a0', 'Rest A1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000ecaa0', '00000000-0000-0000-0000-0000000ec0a0', '00000000-0000-0000-0000-0000000ec1a0', 'Branch A1a', 'UTC');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-0000000ecd01', '00000000-0000-0000-0000-0000000ec0a0', '00000000-0000-0000-0000-0000000ec1a0', '00000000-0000-0000-0000-0000000ecaa0', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-0000000ecc01', '00000000-0000-0000-0000-0000000ec0a0', '00000000-0000-0000-0000-0000000ec1a0', '00000000-0000-0000-0000-0000000ecaa0', '00000000-0000-0000-0000-0000000ecd01', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000ece01', '00000000-0000-0000-0000-0000000ec0a0', '00000000-0000-0000-0000-0000000ec1a0', '00000000-0000-0000-0000-0000000ecaa0', '00000000-0000-0000-0000-0000000ecd01', '00000000-0000-0000-0000-0000000ecc01');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000ecf01', 'ec-manager@example.test'),
  ('00000000-0000-0000-0000-0000000ecf02', 'ec-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000ecb11', '00000000-0000-0000-0000-0000000ecf01', '00000000-0000-0000-0000-0000000ec0a0', '00000000-0000-0000-0000-0000000ec1a0', '00000000-0000-0000-0000-0000000ecaa0', 'manager'),
  ('00000000-0000-0000-0000-0000000ecb12', '00000000-0000-0000-0000-0000000ecf02', '00000000-0000-0000-0000-0000000ec0a0', '00000000-0000-0000-0000-0000000ec1a0', '00000000-0000-0000-0000-0000000ecaa0', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-0000000ecea1', '00000000-0000-0000-0000-0000000ec0a0', '00000000-0000-0000-0000-0000000ec1a0', '00000000-0000-0000-0000-0000000ecaa0', '00000000-0000-0000-0000-0000000ecf01', '00000000-0000-0000-0000-0000000ecb11', 'Manager M.'),
  ('00000000-0000-0000-0000-0000000ecea2', '00000000-0000-0000-0000-0000000ec0a0', '00000000-0000-0000-0000-0000000ec1a0', '00000000-0000-0000-0000-0000000ecaa0', '00000000-0000-0000-0000-0000000ecf02', '00000000-0000-0000-0000-0000000ecb12', 'Kitchen K.');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0000000ecc51', '00000000-0000-0000-0000-0000000ec0a0', '00000000-0000-0000-0000-0000000ec1a0', '00000000-0000-0000-0000-0000000ecaa0', '00000000-0000-0000-0000-0000000ece01', '00000000-0000-0000-0000-0000000ecea1', '00000000-0000-0000-0000-0000000ecb11', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000ecc52', '00000000-0000-0000-0000-0000000ec0a0', '00000000-0000-0000-0000-0000000ec1a0', '00000000-0000-0000-0000-0000000ecaa0', '00000000-0000-0000-0000-0000000ece01', '00000000-0000-0000-0000-0000000ecea2', '00000000-0000-0000-0000-0000000ecb12', now() + interval '1 hour');

-- #EC0001 ZERO-TOTAL (non-chargeable) | #EC0002 positive, payable | #EC0003 TERMINAL
-- #EC0004 positive + already PAID (the void payment-block) | #EC0005 positive, voidable
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, revision) values
  ('00000000-0000-0000-0000-0000000ec001', '00000000-0000-0000-0000-0000000ec0a0', '00000000-0000-0000-0000-0000000ec1a0', '00000000-0000-0000-0000-0000000ecaa0', '00000000-0000-0000-0000-0000000ecd01', '00000000-0000-0000-0000-0000000ecc51', '00000000-0000-0000-0000-0000000ecea1', '00000000-0000-0000-0000-0000000ecb11', 'dine_in', 'served',    'ILS',    0, 0, 0,    0, 'ec-1', 1),
  ('00000000-0000-0000-0000-0000000ec002', '00000000-0000-0000-0000-0000000ec0a0', '00000000-0000-0000-0000-0000000ec1a0', '00000000-0000-0000-0000-0000000ecaa0', '00000000-0000-0000-0000-0000000ecd01', '00000000-0000-0000-0000-0000000ecc51', '00000000-0000-0000-0000-0000000ecea1', '00000000-0000-0000-0000-0000000ecb11', 'dine_in', 'submitted', 'ILS', 1000, 0, 0, 1000, 'ec-2', 1),
  ('00000000-0000-0000-0000-0000000ec003', '00000000-0000-0000-0000-0000000ec0a0', '00000000-0000-0000-0000-0000000ec1a0', '00000000-0000-0000-0000-0000000ecaa0', '00000000-0000-0000-0000-0000000ecd01', '00000000-0000-0000-0000-0000000ecc51', '00000000-0000-0000-0000-0000000ecea1', '00000000-0000-0000-0000-0000000ecb11', 'dine_in', 'completed', 'ILS',    0, 0, 0,    0, 'ec-3', 1),
  ('00000000-0000-0000-0000-0000000ec004', '00000000-0000-0000-0000-0000000ec0a0', '00000000-0000-0000-0000-0000000ec1a0', '00000000-0000-0000-0000-0000000ecaa0', '00000000-0000-0000-0000-0000000ecd01', '00000000-0000-0000-0000-0000000ecc51', '00000000-0000-0000-0000-0000000ecea1', '00000000-0000-0000-0000-0000000ecb11', 'dine_in', 'submitted', 'ILS',  800, 0, 0,  800, 'ec-4', 1),
  ('00000000-0000-0000-0000-0000000ec005', '00000000-0000-0000-0000-0000000ec0a0', '00000000-0000-0000-0000-0000000ec1a0', '00000000-0000-0000-0000-0000000ecaa0', '00000000-0000-0000-0000-0000000ecd01', '00000000-0000-0000-0000-0000000ecc51', '00000000-0000-0000-0000-0000000ecea1', '00000000-0000-0000-0000-0000000ecb11', 'dine_in', 'submitted', 'ILS',  600, 0, 0,  600, 'ec-5', 1);
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id) values
  ('00000000-0000-0000-0000-0000000ecfa4', '00000000-0000-0000-0000-0000000ec0a0', '00000000-0000-0000-0000-0000000ec1a0', '00000000-0000-0000-0000-0000000ecaa0', '00000000-0000-0000-0000-0000000ec004', '00000000-0000-0000-0000-0000000ecd01', '00000000-0000-0000-0000-0000000ecea1', '00000000-0000-0000-0000-0000000ecb11', 'cash', 'completed', 800, 800, 0, 'ILS', 'ec-p4');

select app.open_shift('00000000-0000-0000-0000-0000000ecc51', '00000000-0000-0000-0000-0000000ecff1',
                      '00000000-0000-0000-0000-0000000ecdd1', '00000000-0000-0000-0000-0000000ecd01', 'ec-sh', 0);

-- The ONE op result from a real public.sync_push call (the client's actual path).
create or replace function pg_temp.push(p_pin uuid, p_op jsonb) returns jsonb
language sql as $fn$
  select (r -> 'results' -> 0)
  from public.sync_push(p_pin, '00000000-0000-0000-0000-0000000ecd01'::uuid,
                        jsonb_build_array(p_op)) as r;
$fn$;

create or replace function pg_temp.pay_op(p_op text, p_order uuid, p_tendered bigint) returns jsonb
language sql as $fn$
  select jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'payment.create',
    'target_entity', 'order', 'target_id', p_order,
    'client_created_at', now(),
    'payload', jsonb_build_object('order_id', p_order, 'tender_type', 'cash',
                                  'amount_tendered_minor', p_tendered));
$fn$;

create or replace function pg_temp.void_op(p_op text, p_order uuid) returns jsonb
language sql as $fn$
  select jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.void',
    'target_entity', 'order', 'target_id', p_order,
    'client_created_at', now(),
    'payload', jsonb_build_object('order_id', p_order, 'reason', 'wrong order'));
$fn$;

-- =============================================================================
-- A. record_payment: order_not_chargeable SURVIVES sync_push  (1-8)
-- =============================================================================
create temp table t_receipt_before as
  select coalesce((select last_issued_value from branch_receipt_counters
                    where branch_id = '00000000-0000-0000-0000-0000000ecaa0'), 0) as v;
create temp table t_zero as
  select pg_temp.push('00000000-0000-0000-0000-0000000ecc51',
                      pg_temp.pay_op('ec-pay-z', '00000000-0000-0000-0000-0000000ec001', 0)) as r;

select is((select r ->> 'error' from t_zero), 'order_not_chargeable',
  'THE FIX: a zero-total payment through the REAL sync_push path returns order_not_chargeable');  -- 1
select ok(
  (select r ->> 'error' <> 'rejected' and (r ->> 'ok')::boolean = false
      and r ->> 'status' = 'rejected' from t_zero),
  'the domain code is NOT collapsed to the generic `rejected` — but it is still classed as a permanent rejection, not a transport failure');  -- 2
select ok(
  (select not (r ? 'sqlstate') from t_zero)
  and (select r::text not ilike '%grand_total_minor%' and r::text not ilike '%record_payment:%'
       from t_zero),
  'NO raw database message and NO SQLSTATE leaks into the envelope (the RAISE path used to expose both)');  -- 3
select is((select count(*)::int from payments where order_id = '00000000-0000-0000-0000-0000000ec001'), 0,
  'NO payment row was inserted');                                                            -- 4
select ok(
  (select coalesce((select last_issued_value from branch_receipt_counters
                     where branch_id = '00000000-0000-0000-0000-0000000ecaa0'), 0)
          = (select v from t_receipt_before)),
  'the gapless per-branch receipt counter did NOT move — no receipt number was burned');     -- 5
select ok(
  (select o.status = 'served' and o.revision = 1 and o.receipt_number is null
   from orders o where o.id = '00000000-0000-0000-0000-0000000ec001')
  and (select s.status = 'open' from shifts s where s.id = '00000000-0000-0000-0000-0000000ecff1')
  and (select c.status = 'active' from cash_drawer_sessions c where c.id = '00000000-0000-0000-0000-0000000ecdd1')
  and (select count(*) = 0 from order_operations
        where order_id = '00000000-0000-0000-0000-0000000ec001' and action = 'record_payment'),
  'NO order revision bump, NO shift change, NO cash-drawer change, NO success ledger entry'); -- 6

-- A NORMAL positive payment through the same path is untouched.
create temp table t_pos as
  select pg_temp.push('00000000-0000-0000-0000-0000000ecc51',
                      pg_temp.pay_op('ec-pay-2', '00000000-0000-0000-0000-0000000ec002', 1500)) as r;
select ok(
  (select r ->> 'status' = 'applied' and (r ->> 'ok')::boolean = true
      and (r ->> 'change_due_minor')::bigint = 500
      and r ->> 'receipt_number' is not null from t_pos)
  and (select count(*) = 1 and max(amount_minor) = 1000
       from payments where order_id = '00000000-0000-0000-0000-0000000ec002'),
  'a NORMAL positive cash payment through sync_push is UNCHANGED (applied, amount 1000, change 500, receipt assigned)');  -- 7
select ok(
  (select (pg_temp.push('00000000-0000-0000-0000-0000000ecc51',
                        pg_temp.pay_op('ec-pay-2', '00000000-0000-0000-0000-0000000ec002', 1500))
           ->> 'idempotency_replay')::boolean)
  and (select count(*) = 1 from payments where order_id = '00000000-0000-0000-0000-0000000ec002'),
  'the idempotent replay of a normal payment is UNCHANGED (replay flagged, no duplicate payment)');  -- 8

-- =============================================================================
-- B. void_order: the TERMINAL refusal is TYPED and DISTINGUISHABLE  (9-13)
-- =============================================================================
create temp table t_term as
  select pg_temp.push('00000000-0000-0000-0000-0000000ecc51',
                      pg_temp.void_op('ec-void-t', '00000000-0000-0000-0000-0000000ec003')) as r;
select ok(
  (select r ->> 'error' = 'invalid_transition'
      and r ->> 'detail' = 'order_not_voidable'
      and r ->> 'order_status' = 'completed'
      and (r ->> 'ok')::boolean = false from t_term),
  'THE FIX: a TERMINAL order returns the exact typed code (invalid_transition / order_not_voidable) through sync_push');  -- 9
select ok(
  (select o.status = 'completed' from orders o where o.id = '00000000-0000-0000-0000-0000000ec003'),
  'VOID ELIGIBILITY IS UNCHANGED: the completed order is NOT voided (D-024 terminal, no completed -> void path)');  -- 10

-- The PAID-order block stays a DIFFERENT, distinguishable outcome.
create temp table t_paid as
  select pg_temp.push('00000000-0000-0000-0000-0000000ecc51',
                      pg_temp.void_op('ec-void-p', '00000000-0000-0000-0000-0000000ec004')) as r;
select ok(
  (select r ->> 'error' = 'permission_denied'
      and r ->> 'detail' = 'order_has_completed_payment'
      and r ->> 'detail' <> 'order_not_voidable' from t_paid),
  'the PAID-order void block remains DISTINGUISHABLE from the terminal refusal');            -- 11

-- An AUTHORIZATION denial stays a DIFFERENT, distinguishable outcome.
create temp table t_role as
  select pg_temp.push('00000000-0000-0000-0000-0000000ecc52',   -- kitchen_staff
                      pg_temp.void_op('ec-void-r', '00000000-0000-0000-0000-0000000ec005')) as r;
select ok(
  (select r ->> 'error' = 'permission_denied'
      and coalesce(r ->> 'detail', '') <> 'order_not_voidable'
      and coalesce(r ->> 'detail', '') <> 'order_has_completed_payment' from t_role),
  'an AUTHORIZATION denial remains DISTINGUISHABLE (permission_denied, no terminal/paid detail)');  -- 12

-- A GENERIC rejection must NOT masquerade as terminal. A void with an EMPTY reason still
-- RAISES (unchanged), so sync_push produces the generic `rejected` — and it must carry
-- NEITHER of the typed detail codes.
select ok(
  (select r ->> 'error' = 'rejected'
      and coalesce(r ->> 'detail', '') <> 'order_not_voidable'
      and coalesce(r ->> 'detail', '') <> 'order_not_chargeable'
   from pg_temp.push('00000000-0000-0000-0000-0000000ecc51',
     jsonb_build_object('local_operation_id', 'ec-void-x', 'operation_type', 'order.void',
       'target_entity', 'order', 'target_id', '00000000-0000-0000-0000-0000000ec005',
       'client_created_at', now(),
       'payload', jsonb_build_object('order_id', '00000000-0000-0000-0000-0000000ec005', 'reason', ''))) as r),
  'a GENERIC rejection does NOT masquerade as terminal (no order_not_voidable detail)');     -- 13

-- =============================================================================
-- C. AUDIT + ACL  (14-16)
-- =============================================================================
select ok(
  (select count(*) = 1 from audit_events ae
    where ae.action = 'order.void_denied'
      and ae.new_values ->> 'order_id'      = '00000000-0000-0000-0000-0000000ec003'
      and ae.new_values ->> 'denied_reason' = 'order_not_voidable'
      and ae.new_values ->> 'order_status'  = 'completed'
      and ae.new_values ->> 'order_code'    = '#0EC003'
      and ae.actor_employee_profile_id = '00000000-0000-0000-0000-0000000ecea1')
  and app.audit_category('order.void_denied') = 'voids'
  and app.audit_category('order.void_denied') <> 'other'
  and app.audit_action_has_detail('order.void_denied')
  -- ...and the SAFE projection exposes WHY, while still dropping every identifier.
  and (select app.audit_safe_detail('order.void_denied', ae.new_values)
              ?& array['denied_reason', 'order_code', 'attempted_action']
       from audit_events ae
       where ae.action = 'order.void_denied'
         and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000000ec003')
  and (select not (app.audit_safe_detail('order.void_denied', ae.new_values) ? 'order_id')
       from audit_events ae
       where ae.action = 'order.void_denied'
         and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000000ec003'),
  'the TERMINAL void denial is audited on the EXISTING order.void_denied action (category `voids`, never Other) with a safe denied_reason, and NO identifier is projected');  -- 14
-- The zero-total PAYMENT refusal writes NO new audit action — record_payment's refusal
-- policy is unchanged (only the AUTHORIZATION denial is audited, as payment.denied).
-- sync_push still records it, now with the HONEST error instead of a generic one.
select ok(
  (select count(*) = 0 from audit_events
    where action = 'payment.denied' and new_values ->> 'order_id' = '00000000-0000-0000-0000-0000000ec001')
  and (select count(*) = 1 from audit_events
        where action = 'sync.operation_rejected'
          and new_values ->> 'local_operation_id' = 'ec-pay-z'
          and new_values ->> 'error' = 'order_not_chargeable'),
  'the zero-total refusal adds NO new audit action; sync.operation_rejected now records the HONEST error (order_not_chargeable), not a generic one');  -- 15
select ok(
  not has_function_privilege('anon',   'app.record_payment(uuid,uuid,uuid,text,text,bigint,text,integer)', 'execute')
  and not has_function_privilege('public', 'app.record_payment(uuid,uuid,uuid,text,text,bigint,text,integer)', 'execute')
  and not has_function_privilege('anon',   'app.void_order(uuid,uuid,uuid,text,text,integer)', 'execute')
  and not has_function_privilege('public', 'app.void_order(uuid,uuid,uuid,text,text,integer)', 'execute')
  and not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                   and proname in ('record_payment', 'void_order'))
  and has_function_privilege('authenticated', 'public.sync_push(uuid,uuid,jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.sync_push(uuid,uuid,jsonb)', 'execute'),
  'ACL unchanged: both writers keep NO anon/PUBLIC grant and NO public wrapper; the sync_push wrapper stays authenticated-only');  -- 16

select * from finish();
rollback;
