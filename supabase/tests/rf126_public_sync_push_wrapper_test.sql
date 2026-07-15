-- ============================================================================
-- RF-126 — pgTAP: public.sync_push is a SAFE, narrow POS WRITE wrapper over
-- app.sync_push (PROPOSED DECISION D-036, API_CONTRACT §4.14, R-002/R-007/R-003).
-- ============================================================================
-- public.sync_push exists with the (uuid,uuid,jsonb) signature, returns jsonb, is
-- SECURITY INVOKER, search_path-locked, VOLATILE (so PostgREST POST-routes the
-- write), and is callable by `authenticated` but NOT by public/anon. The narrowness
-- guard proves RF-126 exposed ONLY sync_push: none of the dispatched mutators
-- (submit_order/record_payment/apply_discount/open_shift/close_shift) gained a public
-- sibling, so the `app` schema stays unexposed and the wrapper is not a broad write
-- proxy. The full batch gate is PRESERVED through the wrapper (bogus PIN session,
-- device mismatch, and a non-array batch all raise the SAME 42501 as app.sync_push).
-- Behaviourally it delegates VERBATIM: a real shift.open -> order.submit ->
-- payment.create POS flow pushed THROUGH public.sync_push applies for real (one
-- payment, server-authoritative receipt number, integer-minor money), a replay
-- returns idempotency_replay without a duplicate, malformed/unknown/unauthorized ops
-- are per-op rejected while the batch envelope stays ok:true, and an op applied via
-- app.sync_push replayed via public.sync_push returns idempotency_replay (proving a
-- SHARED ledger => the public wrapper delegates to the app source of truth).
--
-- Fixtures inserted as the BYPASSRLS connection role; the sync_push calls run as the
-- connection role (the owner has EXECUTE on app.sync_push, and app.sync_push +
-- dispatched RPCs are SECURITY DEFINER) — the RF-056/RF-064 pattern.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(36);

-- ===== fixture: org A + restaurant + branch + a paired/active POS device + a ===
-- ===== valid cashier PIN session (the RF-056 exactly-once fixture) =============
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf126w-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11');
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee01', 'rf126w-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');
-- a live, active dining table in the SAME org/restaurant/branch (dine_in submits
-- now REQUIRE a valid table — RESTAURANT-OPERATIONS-V1-001 order-type/table rules)
insert into tables (id, organization_id, restaurant_id, branch_id, label, is_active) values
  ('00000000-0000-0000-0000-00000000ab1e', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'T1', true);

-- ===== (1-8) introspection: existence / type / INVOKER / search_path / VOLATILE /
-- ===== grants ================================================================
select has_function('public', 'sync_push', array['uuid','uuid','jsonb'], 'public.sync_push(uuid, uuid, jsonb) exists');
select is(
  (select format_type(prorettype, null) from pg_proc where proname='sync_push' and pronamespace='public'::regnamespace),
  'jsonb', 'public.sync_push returns jsonb');
select is(
  (select prosecdef from pg_proc where proname='sync_push' and pronamespace='public'::regnamespace),
  false, 'public.sync_push is SECURITY INVOKER (not definer)');
select ok(
  (select exists(
     select 1 from pg_proc p
     cross join lateral unnest(coalesce(p.proconfig, '{}'::text[])) as cfg
     where p.proname='sync_push' and p.pronamespace='public'::regnamespace
       and cfg like 'search_path=%')),
  'public.sync_push has a locked search_path');
select is(
  (select provolatile from pg_proc where proname='sync_push' and pronamespace='public'::regnamespace),
  'v', 'public.sync_push is VOLATILE (PostgREST POST-routes the write; the delegate writes in a writable context)');
select ok(
  not has_function_privilege('public', 'public.sync_push(uuid, uuid, jsonb)', 'execute'),
  'PUBLIC may NOT execute public.sync_push (revoked)');
select ok(
  not has_function_privilege('anon', 'public.sync_push(uuid, uuid, jsonb)', 'execute'),
  'anon may NOT execute public.sync_push (no anon writes)');
select ok(
  has_function_privilege('authenticated', 'public.sync_push(uuid, uuid, jsonb)', 'execute'),
  'authenticated MAY execute public.sync_push');

-- ===== (9-13) narrowness: NO dispatched mutator got a public sibling — the app =
-- ===== schema stays unexposed; the wrapper is not a broad write proxy =========
select hasnt_function('public', 'submit_order',   'no public.submit_order wrapper (reachable ONLY via the sync_push dispatcher)');
select hasnt_function('public', 'record_payment', 'no public.record_payment wrapper (dispatcher-only)');
select hasnt_function('public', 'apply_discount', 'no public.apply_discount wrapper (dispatcher-only)');
select hasnt_function('public', 'open_shift',     'no public.open_shift wrapper (dispatcher-only)');
select hasnt_function('public', 'close_shift',    'no public.close_shift wrapper (dispatcher-only)');

-- ===== (14-17) the WHOLE-BATCH gate is preserved through the wrapper ===========
-- a non-existent PIN session: same 42501 through the wrapper AND through app (parity)
select throws_ok(
  $$ select public.sync_push('00000000-0000-0000-0000-0000000000ff','00000000-0000-0000-0000-00000000da11','[]'::jsonb) $$,
  '42501', NULL, 'a bogus PIN session through public.sync_push raises 42501 (gate preserved)');
select throws_ok(
  $$ select app.sync_push('00000000-0000-0000-0000-0000000000ff','00000000-0000-0000-0000-00000000da11','[]'::jsonb) $$,
  '42501', NULL, 'parity: the SAME bogus PIN session raises 42501 through app.sync_push (verbatim delegation)');
-- a device_id not bound to the PIN session (cross-device/cross-branch) is rejected
select throws_ok(
  $$ select public.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000000ff','[]'::jsonb) $$,
  '42501', NULL, 'a device_id not matching the PIN session device is rejected through the wrapper (no cross-tenant push)');
-- a malformed batch (not a JSON array) is rejected
select throws_ok(
  $$ select public.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11','{}'::jsonb) $$,
  '42501', NULL, 'a non-array p_operations is rejected through the wrapper (malformed batch)');

-- ===== (18-23) a REAL POS flow pushed THROUGH public.sync_push applies =========
-- shift.open
select is(
  (public.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
    '[{"local_operation_id":"op-shift","operation_type":"shift.open","payload":{"shift_id":"00000000-0000-0000-0000-00000000a5f1","cash_drawer_session_id":"00000000-0000-0000-0000-00000000acd1","opening_float_minor":0}}]'::jsonb)
   -> 'results' -> 0 ->> 'status'), 'applied', 'shift.open via public.sync_push is applied');
-- order.submit (1 item @ 1000 minor)
select is(
  (public.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
    '[{"local_operation_id":"op-order","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","order_type":"dine_in","table_id":"00000000-0000-0000-0000-00000000ab1e","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb)
   -> 'results' -> 0 ->> 'status'), 'applied', 'order.submit via public.sync_push is applied');
select is((select count(*) from orders where id='00000000-0000-0000-0000-00000000a0d1')::int, 1, 'the order submitted through the wrapper exists');
-- payment.create (cash, 1000 tendered)
select is(
  (public.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
    '[{"local_operation_id":"op-pay","operation_type":"payment.create","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","tender_type":"cash","amount_tendered_minor":1000}}]'::jsonb)
   -> 'results' -> 0 ->> 'status'), 'applied', 'payment.create via public.sync_push is applied');
select is((select count(*) from payments)::int, 1, 'exactly one payment row created through the wrapper');
select is((select receipt_number from orders where id='00000000-0000-0000-0000-00000000a0d1'), '1', 'server-authoritative receipt number 1 assigned (D-021)');

-- ===== (24-27) integer-minor money preserved end-to-end through the wrapper ====
select is((select grand_total_minor from orders where id='00000000-0000-0000-0000-00000000a0d1')::bigint, 1000::bigint, 'orders.grand_total_minor = 1000 (server-recomputed from snapshots)');
select is((select pg_typeof(grand_total_minor)::text from orders where id='00000000-0000-0000-0000-00000000a0d1'), 'bigint', 'orders.grand_total_minor is bigint (integer minor, no float — D-007)');
select ok(
  (select amount_minor=1000 and tendered_minor=1000 and change_minor=0 from payments where order_id='00000000-0000-0000-0000-00000000a0d1'),
  'payment money is integer minor: amount=1000, tendered=1000, change=0');
select is((select pg_typeof(amount_minor)::text from payments where order_id='00000000-0000-0000-0000-00000000a0d1'), 'bigint', 'payments.amount_minor is bigint (no float money)');

-- ===== (28-31) idempotency: replaying the SAME payment.create via the wrapper ==
-- ===== returns the stored result without re-dispatching =======================
select is(
  (public.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
    '[{"local_operation_id":"op-pay","operation_type":"payment.create","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","tender_type":"cash","amount_tendered_minor":1000}}]'::jsonb)
   -> 'results' -> 0 ->> 'idempotency_replay')::boolean, true, 'replaying op-pay through the wrapper is flagged idempotency_replay');
select is((select count(*) from payments)::int, 1, 'replay through the wrapper created NO second payment');
select is((select last_issued_value from branch_receipt_counters where branch_id='00000000-0000-0000-0000-00000000a1b1')::bigint, 1::bigint, 'replay did NOT advance the per-branch receipt counter');
select is((select count(*) from sync_operations where local_operation_id='op-pay')::int, 1, 'exactly one ledger row for op-pay (shared sync_operations inbox)');

-- ===== (32-35) a mixed batch via the wrapper: the envelope is ok:true, each ====
-- ===== malformed / unknown / unauthorized op is INDIVIDUALLY rejected =========
-- op0: payload not an object; op1: unknown operation_type; op2: payment on a NON-existent order
select is(
  (public.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
    '[{"local_operation_id":"op-bad1","operation_type":"order.submit","payload":42},
      {"local_operation_id":"op-bad2","operation_type":"bogus.type","payload":{}},
      {"local_operation_id":"op-bad3","operation_type":"payment.create","payload":{"order_id":"00000000-0000-0000-0000-00000000dead","tender_type":"cash","amount_tendered_minor":500}}]'::jsonb)
   ->> 'ok')::boolean, true, 'a mixed reject batch still returns a well-formed envelope (ok:true; per-op rejected)');
select is(
  (public.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
    '[{"local_operation_id":"op-bad1b","operation_type":"order.submit","payload":42}]'::jsonb)
   -> 'results' -> 0 ->> 'error'), 'invalid_payload', 'a malformed payload (not an object) is rejected through the wrapper');
select is(
  (public.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
    '[{"local_operation_id":"op-bad2b","operation_type":"bogus.type","payload":{}}]'::jsonb)
   -> 'results' -> 0 ->> 'error'), 'unknown_operation_type', 'an unknown operation_type is rejected through the wrapper');
select is(
  (public.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
    '[{"local_operation_id":"op-bad3b","operation_type":"payment.create","payload":{"order_id":"00000000-0000-0000-0000-00000000dead","tender_type":"cash","amount_tendered_minor":500}}]'::jsonb)
   -> 'results' -> 0 ->> 'status'), 'rejected', 'a payment.create on a non-existent/unauthorized order is rejected through the wrapper (no arbitrary write)');

-- ===== (36) cross-delegation: an op applied via app.sync_push, then replayed ===
-- ===== via public.sync_push, returns idempotency_replay — they share ONE =======
-- ===== sync_operations ledger, proving public.sync_push delegates to app =======
select app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
  '[{"local_operation_id":"op-xdel","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d2","order_type":"dine_in","table_id":"00000000-0000-0000-0000-00000000ab1e","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb);
select is(
  (public.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
    '[{"local_operation_id":"op-xdel","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d2","order_type":"dine_in","table_id":"00000000-0000-0000-0000-00000000ab1e","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb)
   -> 'results' -> 0 ->> 'idempotency_replay')::boolean, true, 'an app.sync_push-applied op replayed via public.sync_push returns idempotency_replay (shared ledger => verbatim delegation)');

select * from finish();
rollback;
