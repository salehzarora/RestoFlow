-- ============================================================================
-- KITCHEN-PRINT-DUAL-001C (KDS-SYNC-FILTER) — pgTAP: app.sync_pull excludes the
-- COMPLETE graph of a direct_print order from a KDS DEVICE's changes feed, while
-- the cursor still advances over the EXAMINED rows and every non-KDS consumer is
-- unchanged. The trusted signal is devices.device_type='kds' (session-backing
-- device), never the role or the client device_id.
--
--   A. KDS + direct_print order  -> orders/order_items/order_item_modifiers/
--      order_service_rounds all absent; NO direct_print id leaks anywhere.
--   B. KDS + normal kds order    -> the complete graph is still returned.
--   C. POS (cashier) + direct_print -> still visible (POS/history unaffected).
--   D. All-filtered page          -> zero rows, cursor ADVANCES past them, a
--      second pull from that cursor does not replay them.
--   E. Mixed page                 -> only the normal row returned, cursor past both.
--   F. Pagination / child no-leak -> a filtered order's children never leak on a
--      later page; a single filtered row still advances the cursor (no starvation).
--   G. Restart/replay             -> a fresh pull never re-surfaces direct_print.
-- Session pinned to UTC; hex-only UUIDs; PIN-session auth (GUC-free).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(23);

-- ===== fixture: 1 org / 1 restaurant / 1 KDS-mode branch ====================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-00f11c000a00', 'Org F', 'f11c-a', 'ILS');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-00f11c000a10', '00000000-0000-0000-0000-00f11c000a00', 'Rest F1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00f11c000a1a', '00000000-0000-0000-0000-00f11c000a00', '00000000-0000-0000-0000-00f11c000a10', 'Branch F (kds)');
-- default kitchen_workflow_mode is 'kds' -> the KDS pulls the order graph.

-- POS + KDS device (both in the SAME kds branch), pairings, sessions.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00f11cd00001', '00000000-0000-0000-0000-00f11c000a00', '00000000-0000-0000-0000-00f11c000a10', '00000000-0000-0000-0000-00f11c000a1a', 'pos'),
  ('00000000-0000-0000-0000-00f11cd00002', '00000000-0000-0000-0000-00f11c000a00', '00000000-0000-0000-0000-00f11c000a10', '00000000-0000-0000-0000-00f11c000a1a', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00f11cc00001', '00000000-0000-0000-0000-00f11c000a00', '00000000-0000-0000-0000-00f11c000a10', '00000000-0000-0000-0000-00f11c000a1a', '00000000-0000-0000-0000-00f11cd00001', 'active'),
  ('00000000-0000-0000-0000-00f11cc00002', '00000000-0000-0000-0000-00f11c000a00', '00000000-0000-0000-0000-00f11c000a10', '00000000-0000-0000-0000-00f11c000a1a', '00000000-0000-0000-0000-00f11cd00002', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-00f11ce00001', '00000000-0000-0000-0000-00f11c000a00', '00000000-0000-0000-0000-00f11c000a10', '00000000-0000-0000-0000-00f11c000a1a', '00000000-0000-0000-0000-00f11cd00001', '00000000-0000-0000-0000-00f11cc00001'),
  ('00000000-0000-0000-0000-00f11ce00002', '00000000-0000-0000-0000-00f11c000a00', '00000000-0000-0000-0000-00f11c000a10', '00000000-0000-0000-0000-00f11c000a1a', '00000000-0000-0000-0000-00f11cd00002', '00000000-0000-0000-0000-00f11cc00002');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00f11c00f001', 'f11c-cashier@example.test'),
  ('00000000-0000-0000-0000-00f11c00f002', 'f11c-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00f11cab0001', '00000000-0000-0000-0000-00f11c00f001', '00000000-0000-0000-0000-00f11c000a00', '00000000-0000-0000-0000-00f11c000a10', '00000000-0000-0000-0000-00f11c000a1a', 'cashier'),
  ('00000000-0000-0000-0000-00f11cab0002', '00000000-0000-0000-0000-00f11c00f002', '00000000-0000-0000-0000-00f11c000a00', '00000000-0000-0000-0000-00f11c000a10', '00000000-0000-0000-0000-00f11c000a1a', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-00f11cef0001', '00000000-0000-0000-0000-00f11c000a00', '00000000-0000-0000-0000-00f11c000a10', '00000000-0000-0000-0000-00f11c000a1a', '00000000-0000-0000-0000-00f11c00f001', '00000000-0000-0000-0000-00f11cab0001', 'Cashier F'),
  ('00000000-0000-0000-0000-00f11cef0002', '00000000-0000-0000-0000-00f11c000a00', '00000000-0000-0000-0000-00f11c000a10', '00000000-0000-0000-0000-00f11c000a1a', '00000000-0000-0000-0000-00f11c00f002', '00000000-0000-0000-0000-00f11cab0002', 'Kitchen F');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00f11c5c0001', '00000000-0000-0000-0000-00f11c000a00', '00000000-0000-0000-0000-00f11c000a10', '00000000-0000-0000-0000-00f11c000a1a', '00000000-0000-0000-0000-00f11ce00001', '00000000-0000-0000-0000-00f11cef0001', '00000000-0000-0000-0000-00f11cab0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00f11c5c0002', '00000000-0000-0000-0000-00f11c000a00', '00000000-0000-0000-0000-00f11c000a10', '00000000-0000-0000-0000-00f11c000a1a', '00000000-0000-0000-0000-00f11ce00002', '00000000-0000-0000-0000-00f11cef0002', '00000000-0000-0000-0000-00f11cab0002', now() + interval '1 hour');

insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('00000000-0000-0000-0000-00f11cca0001', '00000000-0000-0000-0000-00f11c000a00', '00000000-0000-0000-0000-00f11c000a10', null, 'Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('00000000-0000-0000-0000-00f11c00e0f0', '00000000-0000-0000-0000-00f11c000a00', '00000000-0000-0000-0000-00f11c000a10', null, '00000000-0000-0000-0000-00f11cca0001', 'Burger', 500, 'ILS', 1);

-- ===== three orders in the kds branch, all created by the POS cashier =========
-- id order (same tx now(), so keyset falls to id):  0d01 < 0d02 < 0d03
--   DP1 (0d01) direct_print, DP2 (0d02) direct_print, KDS1 (0d03) normal kds.
-- A helper that submits one Burger order + attaches a modifier + a service round.
create or replace function pg_temp.mk_order(p_order uuid, p_localop text) returns void
  language plpgsql as $$
begin
  perform app.submit_order(
    '00000000-0000-0000-0000-00f11c5c0001', p_order, '00000000-0000-0000-0000-00f11cd00001',
    p_localop, 'takeaway', null, null, 'ILS', null,
    '[{"menu_item_id":"00000000-0000-0000-0000-00f11c00e0f0","quantity":1,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Burger","modifiers":[]}]'::jsonb,
    500, 0, 0, 500, null);
  -- one modifier snapshot on the (single) line
  insert into public.order_item_modifiers
    (organization_id, restaurant_id, branch_id, order_item_id, modifier_option_id, option_name_snapshot, price_minor_snapshot, quantity)
  select '00000000-0000-0000-0000-00f11c000a00', '00000000-0000-0000-0000-00f11c000a10', '00000000-0000-0000-0000-00f11c000a1a',
         oi.id, gen_random_uuid(), 'Extra cheese', 0, 1
    from public.order_items oi where oi.order_id = p_order;
  -- one service round (Round 2) on the order
  insert into public.order_service_rounds
    (organization_id, restaurant_id, branch_id, order_id, round_number, device_id, opened_by_employee_profile_id)
  values ('00000000-0000-0000-0000-00f11c000a00', '00000000-0000-0000-0000-00f11c000a10', '00000000-0000-0000-0000-00f11c000a1a',
          p_order, 2, '00000000-0000-0000-0000-00f11cd00001', '00000000-0000-0000-0000-00f11cef0001');
end $$;

select pg_temp.mk_order('00000000-0000-0000-0000-00f11c000d01', 'f11c-op1');
select pg_temp.mk_order('00000000-0000-0000-0000-00f11c000d02', 'f11c-op2');
select pg_temp.mk_order('00000000-0000-0000-0000-00f11c000d03', 'f11c-op3');

-- flip DP1 + DP2 to direct_print (status left 'submitted' on purpose: an
-- otherwise-active order must still be filtered — the gate is dispatch_mode).
update public.orders set dispatch_mode = 'direct_print'
  where id in ('00000000-0000-0000-0000-00f11c000d01', '00000000-0000-0000-0000-00f11c000d02');

-- =============================================================================
-- A. KDS DEVICE + direct_print: the COMPLETE graph is absent  (1-5)
-- =============================================================================
create temp table t_kds as
  select app.sync_pull('00000000-0000-0000-0000-00f11c5c0002', '00000000-0000-0000-0000-00f11cd00002',
                       null, '{}'::jsonb, 500) as res;
select ok(
  (select not exists (select 1 from jsonb_array_elements(res -> 'changes' -> 'orders' -> 'rows') r
     where r ->> 'id' in ('00000000-0000-0000-0000-00f11c000d01','00000000-0000-0000-0000-00f11c000d02'))
   from t_kds),
  'A1 KDS: no direct_print ORDER row is served');                                                    -- 1
select ok(
  (select not exists (select 1 from jsonb_array_elements(res -> 'changes' -> 'order_items' -> 'rows') r
     where r ->> 'order_id' in ('00000000-0000-0000-0000-00f11c000d01','00000000-0000-0000-0000-00f11c000d02'))
   from t_kds),
  'A2 KDS: no direct_print ORDER_ITEM row is served (child of a filtered order)');                    -- 2
select ok(
  (select not exists (
     select 1 from jsonb_array_elements(res -> 'changes' -> 'order_item_modifiers' -> 'rows') r
      join public.order_items oi on oi.id = (r ->> 'order_item_id')::uuid
     where oi.order_id in ('00000000-0000-0000-0000-00f11c000d01','00000000-0000-0000-0000-00f11c000d02'))
   from t_kds),
  'A3 KDS: no direct_print ORDER_ITEM_MODIFIER row is served (TRANSITIVE child)');                    -- 3
select ok(
  (select not exists (select 1 from jsonb_array_elements(res -> 'changes' -> 'order_service_rounds' -> 'rows') r
     where r ->> 'order_id' in ('00000000-0000-0000-0000-00f11c000d01','00000000-0000-0000-0000-00f11c000d02'))
   from t_kds),
  'A4 KDS: no direct_print ORDER_SERVICE_ROUND row is served');                                       -- 4
select ok(
  (select res::text not like '%00f11c000d01%' and res::text not like '%00f11c000d02%' from t_kds),
  'A5 KDS: neither direct_print order id leaks ANYWHERE in the serialized response');                 -- 5

-- =============================================================================
-- B. KDS DEVICE + normal kds order: the complete graph is still returned  (6-9)
-- =============================================================================
select ok(
  (select exists (select 1 from jsonb_array_elements(res -> 'changes' -> 'orders' -> 'rows') r
     where r ->> 'id' = '00000000-0000-0000-0000-00f11c000d03') from t_kds),
  'B6 KDS: the normal kds ORDER is present');                                                         -- 6
select ok(
  (select exists (select 1 from jsonb_array_elements(res -> 'changes' -> 'order_items' -> 'rows') r
     where r ->> 'order_id' = '00000000-0000-0000-0000-00f11c000d03') from t_kds),
  'B7 KDS: the normal kds ORDER_ITEM is present');                                                    -- 7
select ok(
  (select exists (
     select 1 from jsonb_array_elements(res -> 'changes' -> 'order_item_modifiers' -> 'rows') r
      join public.order_items oi on oi.id = (r ->> 'order_item_id')::uuid
     where oi.order_id = '00000000-0000-0000-0000-00f11c000d03') from t_kds),
  'B8 KDS: the normal kds ORDER_ITEM_MODIFIER is present');                                           -- 8
select ok(
  (select exists (select 1 from jsonb_array_elements(res -> 'changes' -> 'order_service_rounds' -> 'rows') r
     where r ->> 'order_id' = '00000000-0000-0000-0000-00f11c000d03') from t_kds),
  'B9 KDS: the normal kds ORDER_SERVICE_ROUND is present');                                           -- 9

-- =============================================================================
-- C. POS (cashier) DEVICE + direct_print: STILL VISIBLE (no regression)  (10-12)
-- =============================================================================
create temp table t_pos as
  select app.sync_pull('00000000-0000-0000-0000-00f11c5c0001', '00000000-0000-0000-0000-00f11cd00001',
                       null, '{}'::jsonb, 500) as res;
select ok(
  (select exists (select 1 from jsonb_array_elements(res -> 'changes' -> 'orders' -> 'rows') r
     where r ->> 'id' = '00000000-0000-0000-0000-00f11c000d01') from t_pos),
  'C10 POS: the direct_print ORDER is STILL served to the POS (history/reports unaffected)');         -- 10
select ok(
  (select exists (select 1 from jsonb_array_elements(res -> 'changes' -> 'order_items' -> 'rows') r
     where r ->> 'order_id' = '00000000-0000-0000-0000-00f11c000d01') from t_pos),
  'C11 POS: the direct_print ORDER_ITEM is STILL served to the POS');                                 -- 11
select ok(
  (select res::text like '%00f11c000d01%' from t_pos),
  'C12 POS: the direct_print order id IS present for the POS consumer');                              -- 12

-- =============================================================================
-- D. All-filtered page: zero rows, cursor ADVANCES, no replay  (13-17)
-- =============================================================================
create temp table t_d1 as
  select app.sync_pull('00000000-0000-0000-0000-00f11c5c0002', '00000000-0000-0000-0000-00f11cd00002',
                       array['orders'], '{}'::jsonb, 2) as res;   -- page covers DP1,DP2 (both filtered)
select is(
  (select jsonb_array_length(res -> 'changes' -> 'orders' -> 'rows') from t_d1), 0,
  'D13: an all-direct_print page returns ZERO visible order rows');                                   -- 13
select ok(
  (select (res -> 'changes' -> 'orders' -> 'next_cursor') is not null
      and (res -> 'changes' -> 'orders' -> 'next_cursor') <> 'null'::jsonb from t_d1),
  'D14: the cursor still ADVANCES past the filtered page (next_cursor is not null)');                 -- 14
select ok(
  (select (res -> 'changes' -> 'orders' ->> 'has_more')::boolean from t_d1),
  'D15: has_more is true (the normal order beyond the filtered page is reachable)');                  -- 15
create temp table t_d2 as
  select app.sync_pull('00000000-0000-0000-0000-00f11c5c0002', '00000000-0000-0000-0000-00f11cd00002',
                       array['orders'],
                       jsonb_build_object('orders', (select res -> 'changes' -> 'orders' -> 'next_cursor' from t_d1)),
                       2) as res;
select ok(
  (select exists (select 1 from jsonb_array_elements(res -> 'changes' -> 'orders' -> 'rows') r
     where r ->> 'id' = '00000000-0000-0000-0000-00f11c000d03') from t_d2),
  'D16: the second pull (from the advanced cursor) returns the normal order');                        -- 16
select ok(
  (select res::text not like '%00f11c000d01%' and res::text not like '%00f11c000d02%' from t_d2),
  'D17: the second pull does NOT replay the filtered direct_print rows');                             -- 17

-- =============================================================================
-- E. Mixed page: only the normal row returned  (18)
-- =============================================================================
create temp table t_e as
  select app.sync_pull('00000000-0000-0000-0000-00f11c5c0002', '00000000-0000-0000-0000-00f11cd00002',
                       array['orders'], '{}'::jsonb, 3) as res;   -- page covers DP1,DP2,KDS1
select ok(
  (select jsonb_array_length(res -> 'changes' -> 'orders' -> 'rows') = 1
      and (res -> 'changes' -> 'orders' -> 'rows' -> 0 ->> 'id') = '00000000-0000-0000-0000-00f11c000d03'
   from t_e),
  'E18: a mixed page returns ONLY the normal row; the direct_print rows are dropped');                -- 18

-- =============================================================================
-- F. Pagination: child no-leak + a single filtered row still advances  (19-21)
-- =============================================================================
create temp table t_items as
  select app.sync_pull('00000000-0000-0000-0000-00f11c5c0002', '00000000-0000-0000-0000-00f11cd00002',
                       array['order_items'], '{}'::jsonb, 1) as res;  -- first order_items page (limit 1)
select ok(
  (select not exists (select 1 from jsonb_array_elements(res -> 'changes' -> 'order_items' -> 'rows') r
     where r ->> 'order_id' in ('00000000-0000-0000-0000-00f11c000d01','00000000-0000-0000-0000-00f11c000d02'))
   from t_items),
  'F19: a paged order_items pull never leaks a filtered order''s child on the page');                 -- 19
create temp table t_f1 as
  select app.sync_pull('00000000-0000-0000-0000-00f11c5c0002', '00000000-0000-0000-0000-00f11cd00002',
                       array['orders'], '{}'::jsonb, 1) as res;   -- page is exactly [DP1] (filtered)
select is(
  (select jsonb_array_length(res -> 'changes' -> 'orders' -> 'rows') from t_f1), 0,
  'F20: a single-row filtered page emits zero rows...');                                              -- 20
select ok(
  (select (res -> 'changes' -> 'orders' -> 'next_cursor' ->> 'id') = '00000000-0000-0000-0000-00f11c000d01'
      and (res -> 'changes' -> 'orders' ->> 'has_more')::boolean
   from t_f1),
  'F21: ...yet the cursor advances by exactly that one examined row (no starvation, no stall)');      -- 21

-- =============================================================================
-- G. Restart/replay: a fresh KDS pull never re-surfaces direct_print  (22-23)
-- =============================================================================
create temp table t_g as
  select app.sync_pull('00000000-0000-0000-0000-00f11c5c0002', '00000000-0000-0000-0000-00f11cd00002',
                       null, '{}'::jsonb, 500) as res;
select ok(
  (select res::text not like '%00f11c000d01%' and res::text not like '%00f11c000d02%' from t_g),
  'G22: a restart-from-empty pull is idempotent — direct_print is still absent everywhere');          -- 22
select ok(
  (select exists (select 1 from jsonb_array_elements(res -> 'changes' -> 'orders' -> 'rows') r
     where r ->> 'id' = '00000000-0000-0000-0000-00f11c000d03') from t_g),
  'G23: ...and the normal kds order is still delivered on the fresh pull');                            -- 23

select * from finish();
rollback;
