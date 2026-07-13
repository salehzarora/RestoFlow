-- ============================================================================
-- ORDER-AUTO-COMPLETION-001 — pgTAP: the AUDIT record of an automatic completion.
--
-- An automatic completion must be as legible in the Activity Log as a manual one,
-- and must be DISTINGUISHABLE from it. There is NO new action key: the canonical
-- `order.status_updated` is reused (it already classifies as ORDERS and already
-- carries a safe payload projection) and gains two SAFE scalar fields:
--     completion_mode     'automatic' | 'manual'
--     completion_trigger  'order_served' | 'payment_recorded'   (automatic only)
--
-- Fixture: Org A / Rest A1 / Branch A1a, a POS device (cashier PIN session), a KDS
-- device (kitchen_staff PIN session), and an org_owner for the manual path.
--   #0AC101  ready,  PAID 1000 -> the KDS bump AUTO-COMPLETES it  (direction A)
--   #0AC102  served, UNPAID    -> the KDS bump leaves it served   (no completion event)
--   #0AC103  served, UNPAID    -> the POS payment AUTO-COMPLETES it (direction B)
--   #0AC104  served, PAID  400 -> the org_owner MANUALLY completes it (the recovery path)
--
-- Asserts: direction A writes TWO honest events (the kitchen's ready->served AND the
-- automatic served->completed) and NOT a denial, even though kitchen_staff is barred
-- from the MANUAL completion; direction B writes ONE completion event alongside the
-- untouched payment audit trail; every automatic event names the REAL initiating
-- actor + device (no invented "system" principal) and carries completion_mode +
-- completion_trigger; the manual recovery path is stamped completion_mode=manual and
-- carries NO trigger; audit_safe_detail exposes both new fields and still drops the
-- identifiers; the payload stays MONEY-FREE (T-003); and nothing is ever duplicated.
-- Session pinned to UTC; hex-only UUIDs.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(25);

-- ===== fixture ===============================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000001ac0a0', 'Org A', 'acaud-a', 'ILS');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0000001ac1a0', '00000000-0000-0000-0000-0000001ac0a0', 'Rest A1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000001acaa0', '00000000-0000-0000-0000-0000001ac0a0', '00000000-0000-0000-0000-0000001ac1a0', 'Branch A1a');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-0000001acd01', '00000000-0000-0000-0000-0000001ac0a0', '00000000-0000-0000-0000-0000001ac1a0', '00000000-0000-0000-0000-0000001acaa0', 'pos'),
  ('00000000-0000-0000-0000-0000001acd02', '00000000-0000-0000-0000-0000001ac0a0', '00000000-0000-0000-0000-0000001ac1a0', '00000000-0000-0000-0000-0000001acaa0', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-0000001acc01', '00000000-0000-0000-0000-0000001ac0a0', '00000000-0000-0000-0000-0000001ac1a0', '00000000-0000-0000-0000-0000001acaa0', '00000000-0000-0000-0000-0000001acd01', 'active'),
  ('00000000-0000-0000-0000-0000001acc02', '00000000-0000-0000-0000-0000001ac0a0', '00000000-0000-0000-0000-0000001ac1a0', '00000000-0000-0000-0000-0000001acaa0', '00000000-0000-0000-0000-0000001acd02', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000001aced1', '00000000-0000-0000-0000-0000001ac0a0', '00000000-0000-0000-0000-0000001ac1a0', '00000000-0000-0000-0000-0000001acaa0', '00000000-0000-0000-0000-0000001acd01', '00000000-0000-0000-0000-0000001acc01'),
  ('00000000-0000-0000-0000-0000001aced2', '00000000-0000-0000-0000-0000001ac0a0', '00000000-0000-0000-0000-0000001ac1a0', '00000000-0000-0000-0000-0000001acaa0', '00000000-0000-0000-0000-0000001acd02', '00000000-0000-0000-0000-0000001acc02');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000001acf01', 'acaud-cashier@example.test'),
  ('00000000-0000-0000-0000-0000001acf02', 'acaud-kitchen@example.test'),
  ('00000000-0000-0000-0000-0000001acf03', 'acaud-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000001acb11', '00000000-0000-0000-0000-0000001acf01', '00000000-0000-0000-0000-0000001ac0a0', '00000000-0000-0000-0000-0000001ac1a0', '00000000-0000-0000-0000-0000001acaa0', 'cashier'),
  ('00000000-0000-0000-0000-0000001acb12', '00000000-0000-0000-0000-0000001acf02', '00000000-0000-0000-0000-0000001ac0a0', '00000000-0000-0000-0000-0000001ac1a0', '00000000-0000-0000-0000-0000001acaa0', 'kitchen_staff'),
  ('00000000-0000-0000-0000-0000001acb13', '00000000-0000-0000-0000-0000001acf03', '00000000-0000-0000-0000-0000001ac0a0', null, null, 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-0000001acea1', '00000000-0000-0000-0000-0000001ac0a0', '00000000-0000-0000-0000-0000001ac1a0', '00000000-0000-0000-0000-0000001acaa0', '00000000-0000-0000-0000-0000001acf01', '00000000-0000-0000-0000-0000001acb11', 'Cashier C.'),
  ('00000000-0000-0000-0000-0000001acea2', '00000000-0000-0000-0000-0000001ac0a0', '00000000-0000-0000-0000-0000001ac1a0', '00000000-0000-0000-0000-0000001acaa0', '00000000-0000-0000-0000-0000001acf02', '00000000-0000-0000-0000-0000001acb12', 'Kitchen K.');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0000001acc51', '00000000-0000-0000-0000-0000001ac0a0', '00000000-0000-0000-0000-0000001ac1a0', '00000000-0000-0000-0000-0000001acaa0', '00000000-0000-0000-0000-0000001aced1', '00000000-0000-0000-0000-0000001acea1', '00000000-0000-0000-0000-0000001acb11', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000001acc52', '00000000-0000-0000-0000-0000001ac0a0', '00000000-0000-0000-0000-0000001ac1a0', '00000000-0000-0000-0000-0000001acaa0', '00000000-0000-0000-0000-0000001aced2', '00000000-0000-0000-0000-0000001acea2', '00000000-0000-0000-0000-0000001acb12', now() + interval '1 hour');

insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, customer_name, local_operation_id, revision) values
  ('00000000-0000-0000-0000-0000001ac101', '00000000-0000-0000-0000-0000001ac0a0', '00000000-0000-0000-0000-0000001ac1a0', '00000000-0000-0000-0000-0000001acaa0', '00000000-0000-0000-0000-0000001acd01', '00000000-0000-0000-0000-0000001acc51', '00000000-0000-0000-0000-0000001acea1', '00000000-0000-0000-0000-0000001acb11', 'dine_in', 'ready',  'ILS', 1000, 0, 0, 1000, 'Layla', 'acaud-o1', 1),
  ('00000000-0000-0000-0000-0000001ac102', '00000000-0000-0000-0000-0000001ac0a0', '00000000-0000-0000-0000-0000001ac1a0', '00000000-0000-0000-0000-0000001acaa0', '00000000-0000-0000-0000-0000001acd01', '00000000-0000-0000-0000-0000001acc51', '00000000-0000-0000-0000-0000001acea1', '00000000-0000-0000-0000-0000001acb11', 'dine_in', 'ready',  'ILS',  900, 0, 0,  900, null, 'acaud-o2', 1),
  ('00000000-0000-0000-0000-0000001ac103', '00000000-0000-0000-0000-0000001ac0a0', '00000000-0000-0000-0000-0000001ac1a0', '00000000-0000-0000-0000-0000001acaa0', '00000000-0000-0000-0000-0000001acd01', '00000000-0000-0000-0000-0000001acc51', '00000000-0000-0000-0000-0000001acea1', '00000000-0000-0000-0000-0000001acb11', 'dine_in', 'served', 'ILS',  800, 0, 0,  800, null, 'acaud-o3', 1),
  ('00000000-0000-0000-0000-0000001ac104', '00000000-0000-0000-0000-0000001ac0a0', '00000000-0000-0000-0000-0000001ac1a0', '00000000-0000-0000-0000-0000001acaa0', '00000000-0000-0000-0000-0000001acd01', '00000000-0000-0000-0000-0000001acc51', '00000000-0000-0000-0000-0000001acea1', '00000000-0000-0000-0000-0000001acb11', 'dine_in', 'served', 'ILS',  400, 0, 0,  400, null, 'acaud-o4', 1);

insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id) values
  ('00000000-0000-0000-0000-0000001acaf1', '00000000-0000-0000-0000-0000001ac0a0', '00000000-0000-0000-0000-0000001ac1a0', '00000000-0000-0000-0000-0000001acaa0', '00000000-0000-0000-0000-0000001ac101', '00000000-0000-0000-0000-0000001acd01', '00000000-0000-0000-0000-0000001acea1', '00000000-0000-0000-0000-0000001acb11', 'cash', 'completed', 1000, 1000, 0, 'ILS', 'acaud-p1'),
  ('00000000-0000-0000-0000-0000001acaf4', '00000000-0000-0000-0000-0000001ac0a0', '00000000-0000-0000-0000-0000001ac1a0', '00000000-0000-0000-0000-0000001acaa0', '00000000-0000-0000-0000-0000001ac104', '00000000-0000-0000-0000-0000001acd01', '00000000-0000-0000-0000-0000001acea1', '00000000-0000-0000-0000-0000001acb11', 'cash', 'completed',  400,  400, 0, 'ILS', 'acaud-p4');

select app.open_shift('00000000-0000-0000-0000-0000001acc51', '00000000-0000-0000-0000-0000001acff1',
                      '00000000-0000-0000-0000-0000001acdd1', '00000000-0000-0000-0000-0000001acd01', 'acaud-sh', 0);

-- ===== drive the three paths =================================================
-- A: the KDS bumps a PAID order to served  -> auto-completes
select app.update_order_status('00000000-0000-0000-0000-0000001acc52', '00000000-0000-0000-0000-0000001acd02',
                               '00000000-0000-0000-0000-0000001ac101', 'served', 'acaud-bump-1');
-- A-unpaid: the KDS bumps an UNPAID order to served -> stays served
select app.update_order_status('00000000-0000-0000-0000-0000001acc52', '00000000-0000-0000-0000-0000001acd02',
                               '00000000-0000-0000-0000-0000001ac102', 'served', 'acaud-bump-2');
-- B: the POS pays a SERVED order -> auto-completes
select app.record_payment('00000000-0000-0000-0000-0000001acc51', '00000000-0000-0000-0000-0000001ac103',
                          '00000000-0000-0000-0000-0000001acd01', 'acaud-pay-3', 'cash', 800, null);
-- the MANUAL recovery path: the org_owner completes a served+paid order by hand
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000001acf03';
select app.owner_complete_order('00000000-0000-0000-0000-0000001ac0a0', '00000000-0000-0000-0000-0000001ac104');
reset role;

-- =============================================================================
-- A. DIRECTION A — TWO honest events, and NOT a denial  (1-10)
-- =============================================================================
select is((select count(*)::int from audit_events
            where action = 'order.status_updated'
              and new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac101'), 2,
  'A: a KDS bump of a PAID order writes exactly TWO events — two real transitions happened');       -- 1
select ok(
  (select count(*) = 1 from audit_events
    where action = 'order.status_updated'
      and new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac101'
      and old_values ->> 'status' = 'ready' and new_values ->> 'status' = 'served'),
  'A: event 1 is the kitchen''s own ready -> served (it is not swallowed by the automation)');      -- 2
select ok(
  (select count(*) = 1 from audit_events
    where action = 'order.status_updated'
      and new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac101'
      and old_values ->> 'status' = 'served' and new_values ->> 'status' = 'completed'),
  'A: event 2 is the automatic served -> completed');                                               -- 3
select is(
  (select ae.new_values ->> 'completion_mode' from audit_events ae
    where ae.action = 'order.status_updated'
      and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac101'
      and ae.new_values ->> 'status' = 'completed'),
  'automatic',
  'A: the completion event is stamped completion_mode = automatic');                                -- 4
select is(
  (select ae.new_values ->> 'completion_trigger' from audit_events ae
    where ae.action = 'order.status_updated'
      and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac101'
      and ae.new_values ->> 'status' = 'completed'),
  'order_served',
  'A: ...and names WHY it fired (completion_trigger = order_served)');                              -- 5
select is(
  (select ae.new_values ->> 'payment_status' from audit_events ae
    where ae.action = 'order.status_updated'
      and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac101'
      and ae.new_values ->> 'status' = 'completed'),
  'paid',
  'A: ...and records that the order was paid (payment_status = paid)');                             -- 6
select ok(
  (select ae.actor_employee_profile_id = '00000000-0000-0000-0000-0000001acea2'  -- Kitchen K.
      and ae.actor_app_user_id is null
      and ae.device_id = '00000000-0000-0000-0000-0000001acd02'                  -- the KDS
      and ae.new_values ->> 'role' = 'kitchen_staff'
   from audit_events ae
   where ae.action = 'order.status_updated'
     and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac101'
     and ae.new_values ->> 'status' = 'completed'),
  'A: the automatic event names the REAL initiating actor + device — no invented "system" principal, no null actor'); -- 7
select ok(
  (select ae.organization_id = '00000000-0000-0000-0000-0000001ac0a0'
      and ae.restaurant_id   = '00000000-0000-0000-0000-0000001ac1a0'
      and ae.branch_id       = '00000000-0000-0000-0000-0000001acaa0'
      and ae.occurred_at    <= now()
   from audit_events ae
   where ae.action = 'order.status_updated'
     and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac101'
     and ae.new_values ->> 'status' = 'completed'),
  'A: the automatic event carries the full org/restaurant/branch scope + authoritative server UTC time');  -- 8
select is((select count(*)::int from audit_events
            where action = 'order.status_update_denied'
              and new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac101'), 0,
  'A: NO order.status_update_denied — the automatic rule does not re-run the role gate and does not spuriously deny the kitchen'); -- 9
select ok(
  (select not exists (
     select 1 from audit_events ae,
       lateral jsonb_object_keys(ae.new_values || coalesce(ae.old_values, '{}'::jsonb)) k
     where ae.action = 'order.status_updated'
       and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac101'
       and (k like '%_minor' or k in ('customer_name','notes','phone','email','address','pin','token')))),
  'A: the automatic payload is MONEY-FREE (T-003) and carries no customer/private key');            -- 10

-- =============================================================================
-- B. DIRECTION A, UNPAID — the served event only, no completion  (11-12)
-- =============================================================================
select is((select count(*)::int from audit_events
            where action = 'order.status_updated'
              and new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac102'), 1,
  'A-unpaid: exactly ONE event (the served transition) — nothing was auto-completed');              -- 11
select ok(
  (select ae.new_values ->> 'status' = 'served' and not (ae.new_values ? 'completion_mode')
   from audit_events ae
   where ae.action = 'order.status_updated'
     and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac102'),
  'A-unpaid: the served event carries NO completion_mode (nothing completed)');                     -- 12

-- =============================================================================
-- C. DIRECTION B — ONE completion event beside an intact payment trail  (13-17)
-- =============================================================================
select is((select count(*)::int from audit_events
            where action = 'order.status_updated'
              and new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac103'), 1,
  'B: paying a SERVED order writes exactly ONE order.status_updated (the completion)');             -- 13
select ok(
  (select ae.old_values ->> 'status' = 'served'
      and ae.new_values ->> 'status' = 'completed'
      and ae.new_values ->> 'completion_mode' = 'automatic'
      and ae.new_values ->> 'completion_trigger' = 'payment_recorded'
      and ae.new_values ->> 'order_code' = '#1AC103'
   from audit_events ae
   where ae.action = 'order.status_updated'
     and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac103'),
  'B: served -> completed, mode=automatic, trigger=payment_recorded, with the SAFE order_code');    -- 14
select ok(
  (select ae.actor_employee_profile_id = '00000000-0000-0000-0000-0000001acea1'  -- Cashier C.
      and ae.device_id = '00000000-0000-0000-0000-0000001acd01'                  -- the POS
      and ae.new_values ->> 'role' = 'cashier'
   from audit_events ae
   where ae.action = 'order.status_updated'
     and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac103'),
  'B: the completion names the CASHIER who took the payment, on the POS device that took it');      -- 15
select ok(
  (select count(*) = 1 from audit_events
    where action = 'payment.recorded' and new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac103')
  and (select count(*) = 1 from audit_events
        where action = 'receipt_number.assigned' and new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac103'),
  'B: the payment''s OWN audit trail is intact (payment.recorded + receipt_number.assigned — D-013)'); -- 16
select ok(
  (select not exists (
     select 1 from audit_events ae,
       lateral jsonb_object_keys(ae.new_values || coalesce(ae.old_values, '{}'::jsonb)) k
     where ae.action = 'order.status_updated'
       and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac103'
       and k like '%_minor')),
  'B: the completion event is MONEY-FREE even though a payment triggered it (T-003)');              -- 17

-- =============================================================================
-- D. THE MANUAL RECOVERY PATH stays distinguishable  (18-19)
-- =============================================================================
select is(
  (select ae.new_values ->> 'completion_mode' from audit_events ae
    where ae.action = 'order.status_updated'
      and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac104'
      and ae.new_values ->> 'status' = 'completed'),
  'manual',
  'the MANUAL recovery completion is stamped completion_mode = manual (never confused with the rule)');  -- 18
select ok(
  (select not (ae.new_values ? 'completion_trigger') and ae.actor_app_user_id = '00000000-0000-0000-0000-0000001acf03'
   from audit_events ae
   where ae.action = 'order.status_updated'
     and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac104'
     and ae.new_values ->> 'status' = 'completed'),
  'the manual completion carries NO trigger (a human chose it) and names the JWT owner who did');   -- 19

-- =============================================================================
-- E. THE SAFE PROJECTION the Dashboard actually receives  (20-22)
-- =============================================================================
select ok(
  (select app.audit_safe_detail('order.status_updated', ae.new_values)
            ?& array['status','order_code','payment_status','role','completion_mode','completion_trigger']
   from audit_events ae
   where ae.action = 'order.status_updated'
     and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac103'),
  'audit_safe_detail EXPOSES completion_mode + completion_trigger (the Activity Log can render them)');  -- 20
select ok(
  (select not (app.audit_safe_detail('order.status_updated', ae.new_values)
                 ?| array['order_id','revision','resolved_membership_id','local_operation_id'])
   from audit_events ae
   where ae.action = 'order.status_updated'
     and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac103'),
  'audit_safe_detail STILL drops the order UUID, revision, membership id and op id (allowlist unchanged)'); -- 21
select ok(
  (select not exists (
     select 1 from audit_events ae,
       lateral jsonb_object_keys(app.audit_safe_detail('order.status_updated', ae.new_values)) k
     where ae.action = 'order.status_updated'
       and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac101'
       and k like '%_minor')),
  'the projected detail carries NO money key (T-003 holds through the projection)');                 -- 22

-- =============================================================================
-- F. CLASSIFICATION — the reused action still lands in ORDERS, never Other  (23)
-- =============================================================================
select ok(
  app.audit_category('order.status_updated') = 'orders'
  and app.audit_action_has_detail('order.status_updated'),
  'order.status_updated still classifies as ORDERS and still renders detail (no new action key was needed)'); -- 23

-- =============================================================================
-- G. THE AUDIT MUST NOT LIE ABOUT MONEY  (24-25)
--    A ZERO-TOTAL (comped) order completes with NO payment row. Writing
--    payment_status='paid' would assert a payment that was NEVER taken, into an
--    APPEND-ONLY trail that can never be corrected (D-013, invariant 8) — and the
--    owner would see the SAME order as `unpaid` in the Orders list, which derives
--    payment status from the existence of a payments row. It says `not_chargeable`.
-- =============================================================================
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, revision) values
  ('00000000-0000-0000-0000-0000001ac105', '00000000-0000-0000-0000-0000001ac0a0', '00000000-0000-0000-0000-0000001ac1a0', '00000000-0000-0000-0000-0000001acaa0', '00000000-0000-0000-0000-0000001acd01', '00000000-0000-0000-0000-0000001acc51', '00000000-0000-0000-0000-0000001acea1', '00000000-0000-0000-0000-0000001acb11', 'dine_in', 'ready', 'ILS', 0, 0, 0, 0, 'acaud-o5', 1);

select app.update_order_status('00000000-0000-0000-0000-0000001acc52', '00000000-0000-0000-0000-0000001acd02',
                               '00000000-0000-0000-0000-0000001ac105', 'served', 'acaud-bump-5');

select ok(
  (select ae.new_values ->> 'status' = 'completed'
      and ae.new_values ->> 'completion_mode' = 'automatic'
      and ae.new_values ->> 'payment_status' = 'not_chargeable'
      and ae.new_values ->> 'payment_status' <> 'paid'
   from audit_events ae
   where ae.action = 'order.status_updated'
     and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac105'
     and ae.new_values ->> 'status' = 'completed')
  and (select count(*) = 0 from payments where order_id = '00000000-0000-0000-0000-0000001ac105'),
  'a ZERO-TOTAL completion audits payment_status = NOT_CHARGEABLE — it never claims a payment that was not taken');  -- 24
-- ...and the SAFE projection carries the honest value through to the Activity Log.
select is(
  (select app.audit_safe_detail('order.status_updated', ae.new_values) ->> 'payment_status'
   from audit_events ae
   where ae.action = 'order.status_updated'
     and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000001ac105'
     and ae.new_values ->> 'status' = 'completed'),
  'not_chargeable',
  'audit_safe_detail projects not_chargeable through to the Dashboard (the owner is told the truth)');  -- 25

select * from finish();
rollback;
