-- ============================================================================
-- ORDER-EDIT-001G — pgTAP: app.owner_order_edits / public.owner_order_edits,
-- the read-only "Order edits" report (API_CONTRACT §4.47; MONEY §9.2 M12 / M13,
-- §13; DECISION D-043). Every edit is a REAL edit sent through public.sync_push
-- (order.edit -> app.edit_order); every read runs AS the authenticated role
-- (the REPORT-123 lesson), with the identity GUC only.
--   A. catalog and ACL (both layers)
--   B. authorization (42501 / permission_denied / who sees staff names)
--   C. validation (22023, limit clamp, custom echo)
--   D. M13 figures AS WRITTEN (worked example, set_quantity, split modify,
--      edit chain, add-only then void, item discount, audit identity, sums,
--      integers)
--   E. window (M12 order bucket, Asia/Jerusalem, custom, last60/90, tz-less)
--   F. tenant isolation
--   G. breakdowns (null reason, ordering, overlapping staff rows)
--   H. reason filter and keyset paging
--   I. privacy (no reason_text, no ids, exact key sets)
--   J. envelope (no audit, effective currency, currency_codes, the switch,
--      empty window)
--   K. a later item discount on the rows an edit wrote (fixed and 100 %)
--      never rewrites that edit's figures
-- Session pinned to UTC; hex-only UUIDs.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(73);

-- ===== fixture ===============================================================
-- Org A, restaurant A1 (no zone, no currency override), three branches:
--   B1 'UTC' (KDS, editing ON), B2 'Asia/Jerusalem' (editing ON),
--   B3 no zone (editing ON; must contribute NOTHING to the report).
-- Org B: one UTC branch (isolation).
insert into organizations (id, name, slug, default_currency) values
  ('9e0a0000-0000-0000-0000-0000000000a0', 'Org Edits A', 'org-edits-001g-a', 'ILS'),
  ('9e0b0000-0000-0000-0000-0000000000a0', 'Org Edits B', 'org-edits-001g-b', 'ILS');
insert into restaurants (id, organization_id, name, timezone) values
  ('9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000a0', 'Rest A1', null),
  ('9e0b0000-0000-0000-0000-0000000000a1', '9e0b0000-0000-0000-0000-0000000000a0', 'Rest B1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone, order_edit_enabled) values
  ('9e0a0000-0000-0000-0000-0000000000b1', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', 'Branch UTC', 'UTC', true),
  ('9e0a0000-0000-0000-0000-0000000000b2', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', 'Branch Jerusalem', 'Asia/Jerusalem', true),
  ('9e0a0000-0000-0000-0000-0000000000b3', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', 'Branch No Zone', null, true),
  ('9e0b0000-0000-0000-0000-0000000000b1', '9e0b0000-0000-0000-0000-0000000000a0', '9e0b0000-0000-0000-0000-0000000000a1', 'Branch Other', null, true);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('9e0a0000-0000-0000-0000-0000000000d1', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'pos'),
  ('9e0a0000-0000-0000-0000-0000000000d2', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b2', 'pos'),
  ('9e0a0000-0000-0000-0000-0000000000d3', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b3', 'pos'),
  ('9e0b0000-0000-0000-0000-0000000000d1', '9e0b0000-0000-0000-0000-0000000000a0', '9e0b0000-0000-0000-0000-0000000000a1', '9e0b0000-0000-0000-0000-0000000000b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status)
  select replace(d.id::text, '00000000d', '00000000f')::uuid, d.organization_id, d.restaurant_id, d.branch_id, d.id, 'active'
    from devices d where d.id::text like '9e0_0000-0000-0000-0000-0000000000d_';
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id)
  select replace(d.id::text, '00000000d', '000000005')::uuid, d.organization_id, d.restaurant_id, d.branch_id, d.id,
         replace(d.id::text, '00000000d', '00000000f')::uuid
    from devices d where d.id::text like '9e0_0000-0000-0000-0000-0000000000d_';
insert into app_users (id, email) values
  ('9e0a0000-0000-0000-0000-00000000006a', 'g-cashier@example.test'),
  ('9e0a0000-0000-0000-0000-00000000006b', 'g-manager-b1@example.test'),
  ('9e0a0000-0000-0000-0000-00000000006c', 'g-kitchen@example.test'),
  ('9e0a0000-0000-0000-0000-00000000006d', 'g-manager-rest@example.test'),
  ('9e0a0000-0000-0000-0000-00000000006e', 'g-owner@example.test'),
  ('9e0a0000-0000-0000-0000-00000000006f', 'g-accountant@example.test'),
  ('9e0b0000-0000-0000-0000-00000000006a', 'g-other-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('9e0a0000-0000-0000-0000-00000000007a', '9e0a0000-0000-0000-0000-00000000006a', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'cashier', '{}'::jsonb),
  ('9e0a0000-0000-0000-0000-00000000007b', '9e0a0000-0000-0000-0000-00000000006b', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'manager', '{}'::jsonb),
  ('9e0a0000-0000-0000-0000-00000000007c', '9e0a0000-0000-0000-0000-00000000006c', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'kitchen_staff', '{}'::jsonb),
  ('9e0a0000-0000-0000-0000-00000000007d', '9e0a0000-0000-0000-0000-00000000006d', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', null, 'manager', '{}'::jsonb),
  ('9e0a0000-0000-0000-0000-00000000007e', '9e0a0000-0000-0000-0000-00000000006e', '9e0a0000-0000-0000-0000-0000000000a0', null, null, 'org_owner', '{}'::jsonb),
  ('9e0a0000-0000-0000-0000-00000000007f', '9e0a0000-0000-0000-0000-00000000006f', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', null, 'accountant', '{}'::jsonb),
  ('9e0b0000-0000-0000-0000-00000000007a', '9e0b0000-0000-0000-0000-00000000006a', '9e0b0000-0000-0000-0000-0000000000a0', null, null, 'org_owner', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('9e0a0000-0000-0000-0000-00000000008a', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', '9e0a0000-0000-0000-0000-00000000006a', '9e0a0000-0000-0000-0000-00000000007a', 'Cara Cashier'),
  ('9e0a0000-0000-0000-0000-00000000008b', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', '9e0a0000-0000-0000-0000-00000000006b', '9e0a0000-0000-0000-0000-00000000007b', 'Max Manager'),
  ('9e0a0000-0000-0000-0000-00000000008c', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', '9e0a0000-0000-0000-0000-00000000006c', '9e0a0000-0000-0000-0000-00000000007c', 'Kai Kitchen'),
  ('9e0a0000-0000-0000-0000-00000000008d', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', null, '9e0a0000-0000-0000-0000-00000000006d', '9e0a0000-0000-0000-0000-00000000007d', 'Rita Manager'),
  ('9e0a0000-0000-0000-0000-00000000008e', '9e0a0000-0000-0000-0000-0000000000a0', null, null, '9e0a0000-0000-0000-0000-00000000006e', '9e0a0000-0000-0000-0000-00000000007e', 'Olga Owner'),
  ('9e0a0000-0000-0000-0000-00000000008f', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', null, '9e0a0000-0000-0000-0000-00000000006f', '9e0a0000-0000-0000-0000-00000000007f', 'Ana Accountant'),
  ('9e0b0000-0000-0000-0000-00000000008a', '9e0b0000-0000-0000-0000-0000000000a0', null, null, '9e0b0000-0000-0000-0000-00000000006a', '9e0b0000-0000-0000-0000-00000000007a', 'Bob Other');
-- PIN sessions: Cara and Max on the B1 till; Rita on the B2 and B3 tills; Bob on Org B's.
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('9e0a0000-0000-0000-0000-00000000009a', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', '9e0a0000-0000-0000-0000-000000000051', '9e0a0000-0000-0000-0000-00000000008a', '9e0a0000-0000-0000-0000-00000000007a', now() + interval '1 hour'),
  ('9e0a0000-0000-0000-0000-00000000009b', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', '9e0a0000-0000-0000-0000-000000000051', '9e0a0000-0000-0000-0000-00000000008b', '9e0a0000-0000-0000-0000-00000000007b', now() + interval '1 hour'),
  ('9e0a0000-0000-0000-0000-00000000009d', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b2', '9e0a0000-0000-0000-0000-000000000052', '9e0a0000-0000-0000-0000-00000000008d', '9e0a0000-0000-0000-0000-00000000007d', now() + interval '1 hour'),
  ('9e0a0000-0000-0000-0000-00000000009e', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b3', '9e0a0000-0000-0000-0000-000000000053', '9e0a0000-0000-0000-0000-00000000008d', '9e0a0000-0000-0000-0000-00000000007d', now() + interval '1 hour'),
  ('9e0b0000-0000-0000-0000-00000000009a', '9e0b0000-0000-0000-0000-0000000000a0', '9e0b0000-0000-0000-0000-0000000000a1', '9e0b0000-0000-0000-0000-0000000000b1', '9e0b0000-0000-0000-0000-000000000051', '9e0b0000-0000-0000-0000-00000000008a', '9e0b0000-0000-0000-0000-00000000007a', now() + interval '1 hour');

-- Menu (restaurant-wide). Org A: Burger 4000 {Extras: tomato +0, cucumber +0},
-- Fries 1500, Cola 800, Lemonade 900, Salad 2000. Org B: Soup 1200.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('9e0a0000-0000-0000-0000-0000000000c1', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', null, 'Mains', 1),
  ('9e0b0000-0000-0000-0000-0000000000c1', '9e0b0000-0000-0000-0000-0000000000a0', '9e0b0000-0000-0000-0000-0000000000a1', null, 'Soups', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('9e0a0000-0000-0000-0000-000000001001', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', null, '9e0a0000-0000-0000-0000-0000000000c1', 'Burger',   4000, 'ILS', 1),
  ('9e0a0000-0000-0000-0000-000000001002', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', null, '9e0a0000-0000-0000-0000-0000000000c1', 'Fries',    1500, 'ILS', 2),
  ('9e0a0000-0000-0000-0000-000000001003', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', null, '9e0a0000-0000-0000-0000-0000000000c1', 'Cola',      800, 'ILS', 3),
  ('9e0a0000-0000-0000-0000-000000001004', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', null, '9e0a0000-0000-0000-0000-0000000000c1', 'Lemonade',  900, 'ILS', 4),
  ('9e0a0000-0000-0000-0000-000000001005', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', null, '9e0a0000-0000-0000-0000-0000000000c1', 'Salad',    2000, 'ILS', 5),
  ('9e0b0000-0000-0000-0000-000000001001', '9e0b0000-0000-0000-0000-0000000000a0', '9e0b0000-0000-0000-0000-0000000000a1', null, '9e0b0000-0000-0000-0000-0000000000c1', 'Soup',     1200, 'ILS', 1);
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, min_select, max_select, is_required, is_active, display_order) values
  ('9e0a0000-0000-0000-0000-00000000d101', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', null, '9e0a0000-0000-0000-0000-000000001001', 'Extras', 'multiple', 0, null, false, true, 1);
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active) values
  ('9e0a0000-0000-0000-0000-00000000e001', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', null, '9e0a0000-0000-0000-0000-00000000d101', 'tomato',   0, 1, true),
  ('9e0a0000-0000-0000-0000-00000000e002', '9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', null, '9e0a0000-0000-0000-0000-00000000d101', 'cucumber', 0, 2, true);

-- Builders (direct inserts as the fixture role; the insert triggers still fire).
-- An order belongs to the PIN session's org / restaurant / branch / till.
create function pg_temp.mk_order(p_id uuid, p_pin uuid, p_created timestamptz default now(),
  p_currency text default 'ILS') returns void
language sql as $$
  insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
    opened_by_employee_profile_id, resolved_membership_id, order_type, currency_code,
    subtotal_minor, grand_total_minor, local_operation_id, status, created_at)
  select p_id, ps.organization_id, ps.restaurant_id, ps.branch_id, ds.device_id, ps.id,
         ps.employee_profile_id, ps.resolved_membership_id, 'dine_in', p_currency, 0, 0,
         'submit-' || p_id::text, 'submitted', p_created
    from pin_sessions ps join device_sessions ds on ds.id = ps.device_session_id
   where ps.id = p_pin;
$$;
create function pg_temp.mk_item(p_id uuid, p_order uuid, p_menu uuid, p_name text, p_qty int,
  p_unit bigint, p_disc bigint default 0) returns void
language sql as $$
  insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
    quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_discount_minor, line_total_minor)
  select p_id, o.organization_id, o.restaurant_id, o.branch_id, o.id, p_menu, p_qty, p_name, p_unit,
         p_disc, p_qty * p_unit - p_disc
    from orders o where o.id = p_order;
$$;
create function pg_temp.mk_mod(p_item uuid, p_opt uuid, p_name text) returns void
language sql as $$
  insert into order_item_modifiers (organization_id, restaurant_id, branch_id, order_item_id,
    modifier_option_id, modifier_name_snapshot, option_name_snapshot, price_minor_snapshot, quantity)
  select oi.organization_id, oi.restaurant_id, oi.branch_id, oi.id, p_opt, 'Extras', p_name, 0, 1
    from order_items oi where oi.id = p_item;
$$;
-- stored totals: subtotal = live lines; no discount; tax off.
create function pg_temp.settle(p_order uuid) returns void
language sql as $$
  update orders o set subtotal_minor = s.t, discount_total_minor = 0, tax_total_minor = 0,
                      grand_total_minor = s.t
    from (select coalesce(sum(line_total_minor), 0) as t from order_items
           where order_id = p_order and status not in ('voided', 'cancelled')) s
   where o.id = p_order;
$$;
-- one order.edit through public.sync_push from the PIN session's own till;
-- the op result is kept under p_k.
create temp table t_ed (k text primary key, r jsonb);
create function pg_temp.edit(p_k text, p_pin uuid, p_order uuid, p_payload jsonb) returns void
language sql as $$
  insert into t_ed
  select p_k, public.sync_push(p_pin, ds.device_id, jsonb_build_array(jsonb_build_object(
           'local_operation_id', 'g-' || p_k, 'operation_type', 'order.edit', 'target_entity', 'order',
           'target_id', p_order, 'payload', p_payload || jsonb_build_object('order_id', p_order)))) -> 'results' -> 0
    from pin_sessions ps join device_sessions ds on ds.id = ps.device_session_id
   where ps.id = p_pin;
$$;
create function pg_temp.eid(p_k text) returns text language sql as $$
  select r ->> 'order_edit_id' from t_ed where k = p_k;
$$;
-- the six figures of one listed edit, as text (missing -> NULL)
create function pg_temp.figs(p_res jsonb, p_k text) returns text language sql as $$
  select concat_ws('/', e ->> 'removed_minor', e ->> 'replaced_out_minor', e ->> 'replaced_in_minor',
                   e ->> 'added_minor', e ->> 'net_change_minor', e ->> 'gross_retired_minor')
    from jsonb_array_elements(p_res -> 'edits') e
   where e ->> 'order_edit_id' = pg_temp.eid(p_k);
$$;
-- every key anywhere in a document
create function pg_temp.jkeys(p jsonb) returns setof text language sql as $$
  with recursive w(v) as (
    select p
    union all
    select c.v from w cross join lateral (
      select x.value as v from jsonb_each(case when jsonb_typeof(w.v) = 'object' then w.v else '{}'::jsonb end) x
      union all
      select y.value from jsonb_array_elements(case when jsonb_typeof(w.v) = 'array' then w.v else '[]'::jsonb end) y
    ) c
  )
  select k from w cross join lateral jsonb_object_keys(case when jsonb_typeof(w.v) = 'object' then w.v else '{}'::jsonb end) k;
$$;
-- every (key, value) pair anywhere whose key ends in _minor
create function pg_temp.minors(p jsonb) returns table (k text, v jsonb) language sql as $$
  with recursive w(v) as (
    select p
    union all
    select c.v from w cross join lateral (
      select x.value as v from jsonb_each(case when jsonb_typeof(w.v) = 'object' then w.v else '{}'::jsonb end) x
      union all
      select y.value from jsonb_array_elements(case when jsonb_typeof(w.v) = 'array' then w.v else '[]'::jsonb end) y
    ) c
  )
  select x.key, x.value from w cross join lateral jsonb_each(case when jsonb_typeof(w.v) = 'object' then w.v else '{}'::jsonb end) x
   where x.key like '%\_minor';
$$;

-- ---- B1 orders, all created now (branch-local today in UTC) -----------------
-- O1 the MONEY §9.2 worked example: Burger (+tomato, +cucumber) 4000, Fries
-- 1500, Cola 800 -> burger without tomato, fries removed, + Lemonade 900.
select pg_temp.mk_order('9e0a0000-0000-0000-0000-00000000a001', '9e0a0000-0000-0000-0000-00000000009a');
select pg_temp.mk_item('9e0a0000-0000-0000-0000-0000000a1001', '9e0a0000-0000-0000-0000-00000000a001', '9e0a0000-0000-0000-0000-000000001001', 'Burger', 1, 4000);
select pg_temp.mk_mod('9e0a0000-0000-0000-0000-0000000a1001', '9e0a0000-0000-0000-0000-00000000e001', 'tomato');
select pg_temp.mk_mod('9e0a0000-0000-0000-0000-0000000a1001', '9e0a0000-0000-0000-0000-00000000e002', 'cucumber');
select pg_temp.mk_item('9e0a0000-0000-0000-0000-0000000a1002', '9e0a0000-0000-0000-0000-00000000a001', '9e0a0000-0000-0000-0000-000000001002', 'Fries', 1, 1500);
select pg_temp.mk_item('9e0a0000-0000-0000-0000-0000000a1003', '9e0a0000-0000-0000-0000-00000000a001', '9e0a0000-0000-0000-0000-000000001003', 'Cola', 1, 800);
select pg_temp.settle('9e0a0000-0000-0000-0000-00000000a001');
select pg_temp.edit('e1', '9e0a0000-0000-0000-0000-00000000009a', '9e0a0000-0000-0000-0000-00000000a001',
  '{"reason_code": "customer_changed_mind",
    "expected": {"subtotal_minor": 5700, "tax_total_minor": 0, "grand_total_minor": 5700},
    "changes": [
      {"op": "modify", "order_item_id": "9e0a0000-0000-0000-0000-0000000a1001",
       "replacements": [{"quantity": 1, "modifiers": [{"modifier_option_id": "9e0a0000-0000-0000-0000-00000000e002"}]}]},
      {"op": "remove", "order_item_id": "9e0a0000-0000-0000-0000-0000000a1002"},
      {"op": "add", "item": {"menu_item_id": "9e0a0000-0000-0000-0000-000000001004", "quantity": 1,
        "unit_price_minor_snapshot": 900, "menu_item_name_snapshot": "Lemonade", "modifiers": []}}]}'::jsonb);

-- O2 set_quantity: Cola 3 -> 2 (a reduction: remainder row replaces it) and
-- Fries 1 -> 3 (an increase: a +2 delta row). reason 'other' with free text.
select pg_temp.mk_order('9e0a0000-0000-0000-0000-00000000a002', '9e0a0000-0000-0000-0000-00000000009a');
select pg_temp.mk_item('9e0a0000-0000-0000-0000-0000000a2001', '9e0a0000-0000-0000-0000-00000000a002', '9e0a0000-0000-0000-0000-000000001003', 'Cola', 3, 800);
select pg_temp.mk_item('9e0a0000-0000-0000-0000-0000000a2002', '9e0a0000-0000-0000-0000-00000000a002', '9e0a0000-0000-0000-0000-000000001002', 'Fries', 1, 1500);
select pg_temp.settle('9e0a0000-0000-0000-0000-00000000a002');
select pg_temp.edit('e2', '9e0a0000-0000-0000-0000-00000000009a', '9e0a0000-0000-0000-0000-00000000a002',
  '{"reason_code": "other", "reason_text": "SECRET-REASON-TEXT-001G",
    "expected": {"subtotal_minor": 6100, "tax_total_minor": 0, "grand_total_minor": 6100},
    "changes": [
      {"op": "set_quantity", "order_item_id": "9e0a0000-0000-0000-0000-0000000a2001", "quantity": 2},
      {"op": "set_quantity", "order_item_id": "9e0a0000-0000-0000-0000-0000000a2002", "quantity": 3}]}'::jsonb);

-- O3 a modify split into two replacements (one unchanged continuation, one
-- changed): the retired Burger x2 (8000) is ONE line, however many rows name it.
select pg_temp.mk_order('9e0a0000-0000-0000-0000-00000000a003', '9e0a0000-0000-0000-0000-00000000009b');
select pg_temp.mk_item('9e0a0000-0000-0000-0000-0000000a3001', '9e0a0000-0000-0000-0000-00000000a003', '9e0a0000-0000-0000-0000-000000001001', 'Burger', 2, 4000);
select pg_temp.mk_mod('9e0a0000-0000-0000-0000-0000000a3001', '9e0a0000-0000-0000-0000-00000000e001', 'tomato');
select pg_temp.mk_mod('9e0a0000-0000-0000-0000-0000000a3001', '9e0a0000-0000-0000-0000-00000000e002', 'cucumber');
select pg_temp.mk_item('9e0a0000-0000-0000-0000-0000000a3002', '9e0a0000-0000-0000-0000-00000000a003', '9e0a0000-0000-0000-0000-000000001003', 'Cola', 1, 800);
select pg_temp.settle('9e0a0000-0000-0000-0000-00000000a003');
select pg_temp.edit('e3', '9e0a0000-0000-0000-0000-00000000009b', '9e0a0000-0000-0000-0000-00000000a003',
  '{"reason_code": "entry_mistake",
    "expected": {"subtotal_minor": 8800, "tax_total_minor": 0, "grand_total_minor": 8800},
    "changes": [
      {"op": "modify", "order_item_id": "9e0a0000-0000-0000-0000-0000000a3001",
       "replacements": [
         {"quantity": 1, "modifiers": [{"modifier_option_id": "9e0a0000-0000-0000-0000-00000000e001"},
                                       {"modifier_option_id": "9e0a0000-0000-0000-0000-00000000e002"}]},
         {"quantity": 1, "modifiers": [{"modifier_option_id": "9e0a0000-0000-0000-0000-00000000e002"}]}]}]}'::jsonb);

-- O4 an edit chain: edit 1 (Cara) changes the burger; edit 2 (Max) removes the
-- replacement edit 1 wrote. Subtotal 4800 -> 4800 -> 800.
select pg_temp.mk_order('9e0a0000-0000-0000-0000-00000000a004', '9e0a0000-0000-0000-0000-00000000009a');
select pg_temp.mk_item('9e0a0000-0000-0000-0000-0000000a4001', '9e0a0000-0000-0000-0000-00000000a004', '9e0a0000-0000-0000-0000-000000001001', 'Burger', 1, 4000);
select pg_temp.mk_mod('9e0a0000-0000-0000-0000-0000000a4001', '9e0a0000-0000-0000-0000-00000000e001', 'tomato');
select pg_temp.mk_mod('9e0a0000-0000-0000-0000-0000000a4001', '9e0a0000-0000-0000-0000-00000000e002', 'cucumber');
select pg_temp.mk_item('9e0a0000-0000-0000-0000-0000000a4002', '9e0a0000-0000-0000-0000-00000000a004', '9e0a0000-0000-0000-0000-000000001003', 'Cola', 1, 800);
select pg_temp.settle('9e0a0000-0000-0000-0000-00000000a004');
select pg_temp.edit('e4a', '9e0a0000-0000-0000-0000-00000000009a', '9e0a0000-0000-0000-0000-00000000a004',
  '{"reason_code": "customer_changed_mind",
    "expected": {"subtotal_minor": 4800, "tax_total_minor": 0, "grand_total_minor": 4800},
    "changes": [
      {"op": "modify", "order_item_id": "9e0a0000-0000-0000-0000-0000000a4001",
       "replacements": [{"quantity": 1, "modifiers": [{"modifier_option_id": "9e0a0000-0000-0000-0000-00000000e002"}]}]}]}'::jsonb);
select pg_temp.edit('e4b', '9e0a0000-0000-0000-0000-00000000009b', '9e0a0000-0000-0000-0000-00000000a004',
  jsonb_build_object('reason_code', 'entry_mistake',
    'expected', jsonb_build_object('subtotal_minor', 800, 'tax_total_minor', 0, 'grand_total_minor', 800),
    'changes', jsonb_build_array(jsonb_build_object('op', 'remove', 'order_item_id',
       (select r -> 'changes' -> 0 -> 'new_order_item_ids' ->> 0 from t_ed where k = 'e4a')))));

-- O5 an ADD-ONLY edit (no reason) — then the whole order is voided.
select pg_temp.mk_order('9e0a0000-0000-0000-0000-00000000a005', '9e0a0000-0000-0000-0000-00000000009a');
select pg_temp.mk_item('9e0a0000-0000-0000-0000-0000000a5001', '9e0a0000-0000-0000-0000-00000000a005', '9e0a0000-0000-0000-0000-000000001005', 'Salad', 1, 2000);
select pg_temp.mk_item('9e0a0000-0000-0000-0000-0000000a5002', '9e0a0000-0000-0000-0000-00000000a005', '9e0a0000-0000-0000-0000-000000001002', 'Fries', 1, 1500);
select pg_temp.settle('9e0a0000-0000-0000-0000-00000000a005');
select pg_temp.edit('e5', '9e0a0000-0000-0000-0000-00000000009a', '9e0a0000-0000-0000-0000-00000000a005',
  '{"expected": {"subtotal_minor": 4400, "tax_total_minor": 0, "grand_total_minor": 4400},
    "changes": [{"op": "add", "item": {"menu_item_id": "9e0a0000-0000-0000-0000-000000001004", "quantity": 1,
        "unit_price_minor_snapshot": 900, "menu_item_name_snapshot": "Lemonade", "modifiers": []}}]}'::jsonb);
create temp table t_void as
  select app.void_order('9e0a0000-0000-0000-0000-00000000009b', '9e0a0000-0000-0000-0000-00000000a005',
                        '9e0a0000-0000-0000-0000-0000000000d1', 'g-void-o5', 'guest left') as r;

-- O6 (taken in USD) removes a line that carries an ITEM discount: Salad 2000
-- with 300 off = 1700 net.
select pg_temp.mk_order('9e0a0000-0000-0000-0000-00000000a006', '9e0a0000-0000-0000-0000-00000000009a', now(), 'USD');
select pg_temp.mk_item('9e0a0000-0000-0000-0000-0000000a6001', '9e0a0000-0000-0000-0000-00000000a006', '9e0a0000-0000-0000-0000-000000001005', 'Salad', 1, 2000, 300);
select pg_temp.mk_item('9e0a0000-0000-0000-0000-0000000a6002', '9e0a0000-0000-0000-0000-00000000a006', '9e0a0000-0000-0000-0000-000000001003', 'Cola', 1, 800);
select pg_temp.settle('9e0a0000-0000-0000-0000-00000000a006');
select pg_temp.edit('e6', '9e0a0000-0000-0000-0000-00000000009a', '9e0a0000-0000-0000-0000-00000000a006',
  '{"reason_code": "item_unavailable",
    "expected": {"subtotal_minor": 800, "tax_total_minor": 0, "grand_total_minor": 800},
    "changes": [{"op": "remove", "order_item_id": "9e0a0000-0000-0000-0000-0000000a6001"}]}'::jsonb);

-- O7 created YESTERDAY (branch-local, UTC), edited today (M12: yesterday's bucket).
select pg_temp.mk_order('9e0a0000-0000-0000-0000-00000000a007', '9e0a0000-0000-0000-0000-00000000009a',
  (current_date - 1 + time '12:00') at time zone 'UTC');
select pg_temp.mk_item('9e0a0000-0000-0000-0000-0000000a7001', '9e0a0000-0000-0000-0000-00000000a007', '9e0a0000-0000-0000-0000-000000001005', 'Salad', 1, 2000);
select pg_temp.settle('9e0a0000-0000-0000-0000-00000000a007');
select pg_temp.edit('e7', '9e0a0000-0000-0000-0000-00000000009a', '9e0a0000-0000-0000-0000-00000000a007',
  '{"expected": {"subtotal_minor": 2900, "tax_total_minor": 0, "grand_total_minor": 2900},
    "changes": [{"op": "add", "item": {"menu_item_id": "9e0a0000-0000-0000-0000-000000001004", "quantity": 1,
        "unit_price_minor_snapshot": 900, "menu_item_name_snapshot": "Lemonade", "modifiers": []}}]}'::jsonb);

-- O8 on B2 (Asia/Jerusalem): created at 22:30 UTC the day BEFORE Jerusalem's
-- local today, i.e. 00:30 / 01:30 of Jerusalem's local today.
create temp table t_jlm as select (now() at time zone 'Asia/Jerusalem')::date as local_today;
select pg_temp.mk_order('9e0a0000-0000-0000-0000-00000000a008', '9e0a0000-0000-0000-0000-00000000009d',
  ((select local_today from t_jlm) - 1 + time '22:30') at time zone 'UTC');
select pg_temp.mk_item('9e0a0000-0000-0000-0000-0000000a8001', '9e0a0000-0000-0000-0000-00000000a008', '9e0a0000-0000-0000-0000-000000001003', 'Cola', 1, 800);
select pg_temp.mk_item('9e0a0000-0000-0000-0000-0000000a8002', '9e0a0000-0000-0000-0000-00000000a008', '9e0a0000-0000-0000-0000-000000001002', 'Fries', 1, 1500);
select pg_temp.settle('9e0a0000-0000-0000-0000-00000000a008');
select pg_temp.edit('e8', '9e0a0000-0000-0000-0000-00000000009d', '9e0a0000-0000-0000-0000-00000000a008',
  '{"reason_code": "kitchen_issue",
    "expected": {"subtotal_minor": 800, "tax_total_minor": 0, "grand_total_minor": 800},
    "changes": [{"op": "remove", "order_item_id": "9e0a0000-0000-0000-0000-0000000a8002"}]}'::jsonb);

-- O9 on B3 (no zone at branch or restaurant): an edit the report must never count.
select pg_temp.mk_order('9e0a0000-0000-0000-0000-00000000a009', '9e0a0000-0000-0000-0000-00000000009e');
select pg_temp.mk_item('9e0a0000-0000-0000-0000-0000000a9001', '9e0a0000-0000-0000-0000-00000000a009', '9e0a0000-0000-0000-0000-000000001005', 'Salad', 1, 2000);
select pg_temp.mk_item('9e0a0000-0000-0000-0000-0000000a9002', '9e0a0000-0000-0000-0000-00000000a009', '9e0a0000-0000-0000-0000-000000001003', 'Cola', 1, 800);
select pg_temp.settle('9e0a0000-0000-0000-0000-00000000a009');
select pg_temp.edit('e9', '9e0a0000-0000-0000-0000-00000000009e', '9e0a0000-0000-0000-0000-00000000a009',
  '{"reason_code": "customer_changed_mind",
    "expected": {"subtotal_minor": 2000, "tax_total_minor": 0, "grand_total_minor": 2000},
    "changes": [{"op": "remove", "order_item_id": "9e0a0000-0000-0000-0000-0000000a9002"}]}'::jsonb);

-- OB Org B (restaurant zone UTC): Soup x2 -> 1 by Bob.
select pg_temp.mk_order('9e0b0000-0000-0000-0000-00000000a001', '9e0b0000-0000-0000-0000-00000000009a');
select pg_temp.mk_item('9e0b0000-0000-0000-0000-0000000a1001', '9e0b0000-0000-0000-0000-00000000a001', '9e0b0000-0000-0000-0000-000000001001', 'Soup', 2, 1200);
select pg_temp.settle('9e0b0000-0000-0000-0000-00000000a001');
select pg_temp.edit('eb', '9e0b0000-0000-0000-0000-00000000009a', '9e0b0000-0000-0000-0000-00000000a001',
  '{"reason_code": "customer_changed_mind",
    "expected": {"subtotal_minor": 1200, "tax_total_minor": 0, "grand_total_minor": 1200},
    "changes": [{"op": "set_quantity", "order_item_id": "9e0b0000-0000-0000-0000-0000000a1001", "quantity": 1}]}'::jsonb);

-- ===== the reads, AS the authenticated role ==================================
set local role authenticated;
create temp table t_r (k text primary key, r jsonb);
reset role;
create temp table t_audit0 as select count(*) as n from audit_events;
set local role authenticated;

-- B1 by Max (branch manager): the main read.
set local app.current_app_user_id = '9e0a0000-0000-0000-0000-00000000006b';
insert into t_r values
  ('mgr',      app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today')),
  ('mgr_pub',  public.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today')),
  ('mgr_yday', app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'yesterday')),
  ('mgr_cust', app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today', current_date, current_date)),
  ('mgr_l60',  app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'last60')),
  ('mgr_l90',  app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'last90')),
  ('mgr_lim0', app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today', p_limit => 0)),
  ('mgr_lim1k', app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today', p_limit => 1000)),
  ('mgr_rsn',  app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today', p_reason_code => 'entry_mistake')),
  ('mgr_none', app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today', p_reason_code => 'none')),
  ('mgr_empty', app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today', current_date - 40, current_date - 40)),
  ('p1',       app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today', p_limit => 2));
insert into t_r values ('p2', app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today', p_limit => 2, p_cursor => (select r ->> 'next_cursor' from t_r where k = 'p1')));
insert into t_r values ('p3', app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today', p_limit => 2, p_cursor => (select r ->> 'next_cursor' from t_r where k = 'p2')));
insert into t_r values ('p4', app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today', p_limit => 2, p_cursor => (select r ->> 'next_cursor' from t_r where k = 'p3')));

-- B1 by Cara (cashier) and Kai (kitchen); the restaurant by Ana (accountant)
set local app.current_app_user_id = '9e0a0000-0000-0000-0000-00000000006a';
insert into t_r values ('cash', app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today'));
set local app.current_app_user_id = '9e0a0000-0000-0000-0000-00000000006c';
insert into t_r values ('kitchen', app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today'));
set local app.current_app_user_id = '9e0a0000-0000-0000-0000-00000000006f';
insert into t_r values ('acct', app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', null, 'today'));

-- Olga (org_owner): org-wide, per branch, the restaurant, last7, and the report range
set local app.current_app_user_id = '9e0a0000-0000-0000-0000-00000000006e';
insert into t_r values
  ('own_org',  app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', null, null, 'today')),
  ('own_rest', app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', null, 'today')),
  ('own_b2',   app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b2', 'today')),
  ('own_b2y',  app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b2', 'yesterday')),
  ('own_b3',   app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b3', 'last7')),
  ('own_l7',   app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', null, null, 'last7', p_limit => 100)),
  ('rr_b1',    app.owner_report_range('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today'));
-- Bob (Org B owner) reads his own organization
set local app.current_app_user_id = '9e0b0000-0000-0000-0000-00000000006a';
insert into t_r values ('orgb', app.owner_order_edits('9e0b0000-0000-0000-0000-0000000000a0', null, null, 'today'));
reset role;

-- the effective currency under a restaurant override; the switch turned off
update restaurants set currency_override = 'USD' where id = '9e0a0000-0000-0000-0000-0000000000a1';
update branches set order_edit_enabled = false where id = '9e0a0000-0000-0000-0000-0000000000b1';
set local role authenticated;
set local app.current_app_user_id = '9e0a0000-0000-0000-0000-00000000006e';
insert into t_r values
  ('own_ovr',  app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today')),
  ('own_ovr_org', app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', null, null, 'today')),
  ('own_off_b1e', app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today', current_date - 40, current_date - 40));
reset role;
update restaurants set currency_override = null where id = '9e0a0000-0000-0000-0000-0000000000a1';
update branches set order_edit_enabled = true where id = '9e0a0000-0000-0000-0000-0000000000b1';

-- fixture sanity: every edit applied, the void applied
select ok((select bool_and(r ->> 'status' = 'applied') and count(*) = 11 from t_ed)
      and (select (r ->> 'ok')::boolean from t_void),
  '00 fixture: all eleven edits were applied through sync_push, and O5 was voided');

-- ===== A. catalog and ACL ====================================================
select is((select string_agg(pg_get_function_identity_arguments(p.oid), ' ; ' order by n.nspname)
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where p.proname = 'owner_order_edits'),
  'p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_range text, p_start date, p_end date, p_reason_code text, p_limit integer, p_cursor text'
  || ' ; ' ||
  'p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_range text, p_start date, p_end date, p_reason_code text, p_limit integer, p_cursor text',
  'A1 app. and public.owner_order_edits exist with the exact nine-argument identity');
select ok((select p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""']
             from pg_proc p where p.oid = 'app.owner_order_edits(uuid,uuid,uuid,text,date,date,text,integer,text)'::regprocedure),
  'A2 app.owner_order_edits: SECURITY DEFINER, STABLE, search_path pinned empty');
select ok((select not p.prosecdef and l.lanname = 'sql' and p.proconfig = array['search_path=""']
             from pg_proc p join pg_language l on l.oid = p.prolang
            where p.oid = 'public.owner_order_edits(uuid,uuid,uuid,text,date,date,text,integer,text)'::regprocedure),
  'A3 public.owner_order_edits: a SECURITY INVOKER sql wrapper, search_path pinned empty');
select ok(has_function_privilege('authenticated', 'app.owner_order_edits(uuid,uuid,uuid,text,date,date,text,integer,text)', 'EXECUTE')
      and has_function_privilege('authenticated', 'public.owner_order_edits(uuid,uuid,uuid,text,date,date,text,integer,text)', 'EXECUTE'),
  'A4 authenticated may EXECUTE both layers');
select ok(not has_function_privilege('anon', 'app.owner_order_edits(uuid,uuid,uuid,text,date,date,text,integer,text)', 'EXECUTE')
      and not has_function_privilege('anon', 'public.owner_order_edits(uuid,uuid,uuid,text,date,date,text,integer,text)', 'EXECUTE')
      and not has_function_privilege('public', 'app.owner_order_edits(uuid,uuid,uuid,text,date,date,text,integer,text)', 'EXECUTE')
      and not has_function_privilege('public', 'public.owner_order_edits(uuid,uuid,uuid,text,date,date,text,integer,text)', 'EXECUTE'),
  'A5 anon and PUBLIC may execute neither layer (D-037)');
select ok((select p.proacl is not null from pg_proc p
            where p.oid = 'public.owner_order_edits(uuid,uuid,uuid,text,date,date,text,integer,text)'::regprocedure)
      and position('actor_read_rank_in_scope' in pg_get_functiondef('app.owner_order_edits(uuid,uuid,uuid,text,date,date,text,integer,text)'::regprocedure)) = 0,
  'A6 the wrapper carries an explicit ACL, and the reader uses the MEMBER rank only (never the support read rank)');

-- ===== B. authorization ======================================================
set local role authenticated;
reset app.current_app_user_id;
select throws_ok(
  $$ select app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', null, null, 'today') $$,
  '42501', 'owner_order_edits: authentication required', 'B1 no identity -> 42501');
set local app.current_app_user_id = '9e0a0000-0000-0000-0000-00000000006e';
select throws_ok(
  $$ select public.owner_order_edits(null, null, null, 'today') $$,
  '42501', 'owner_order_edits: organization_id is required', 'B2 a null organization -> 42501');
set local app.current_app_user_id = '9e0b0000-0000-0000-0000-00000000006a';
select throws_ok(
  $$ select public.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', null, null, 'today') $$,
  '42501', 'owner_order_edits: caller has no active membership covering the requested scope',
  'B3 another organization''s owner -> 42501 (RISK R-003)');
set local app.current_app_user_id = '9e0a0000-0000-0000-0000-00000000006b';
select throws_ok(
  $$ select app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b2', 'today') $$,
  '42501', 'owner_order_edits: caller has no active membership covering the requested scope',
  'B4 a branch manager asking for a sibling branch -> 42501');
select throws_ok(
  $$ select app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000fffff', 'today') $$,
  '42501', 'owner_order_edits: caller has no active membership covering the requested scope',
  'B5 a nonexistent branch gives the SAME 42501 (no existence oracle)');
select throws_ok(
  $$ select app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', null, 'today') $$,
  '42501', 'owner_order_edits: caller has no active membership covering the requested scope',
  'B6 a branch manager asking restaurant-wide -> 42501 (downward-only)');
reset role;
select is((select r from t_r where k = 'kitchen'),
  '{"ok": false, "error": "permission_denied", "entity": "owner_order_edits"}'::jsonb,
  'B7 kitchen_staff -> {ok:false, error:permission_denied} (the figures are money)');
select ok((select (r ->> 'ok')::boolean and (r ->> 'staff_visible')::boolean = false
                  and r -> 'by_staff' = '[]'::jsonb
                  and (select bool_and(e -> 'staff_name' = 'null'::jsonb) and count(*) = 7
                         from jsonb_array_elements(r -> 'edits') e)
             from t_r where k = 'cash'),
  'B8 a cashier reads the block with staff_visible false, by_staff [] and every staff_name null');
select ok((select (r ->> 'ok')::boolean and (r ->> 'staff_visible')::boolean = false
                  and r -> 'by_staff' = '[]'::jsonb
                  and not exists (select 1 from jsonb_array_elements(r -> 'edits') e where e -> 'staff_name' <> 'null'::jsonb)
             from t_r where k = 'acct'),
  'B9 an accountant likewise reads it without staff names');
select ok((select (c.r - 'by_staff' - 'staff_visible' - 'edits') = (m.r - 'by_staff' - 'staff_visible' - 'edits')
             from t_r c, t_r m where c.k = 'cash' and m.k = 'mgr')
      and (select array_agg(e - 'staff_name' order by o) from t_r, jsonb_array_elements(r -> 'edits') with ordinality x(e, o) where k = 'cash')
        = (select array_agg(e - 'staff_name' order by o) from t_r, jsonb_array_elements(r -> 'edits') with ordinality x(e, o) where k = 'mgr'),
  'B10 apart from the staff names, the cashier''s result is the manager''s, byte for byte');
select ok((select (r ->> 'staff_visible')::boolean
                  and (select bool_and(e ->> 'staff_name' in ('Cara Cashier', 'Max Manager')) from jsonb_array_elements(r -> 'edits') e)
             from t_r where k = 'mgr')
      and (select (r ->> 'staff_visible')::boolean and jsonb_array_length(r -> 'by_staff') = 3 from t_r where k = 'own_org'),
  'B11 a manager and an org_owner see staff names (Rita''s Jerusalem edit too, org-wide)');
select is((select r from t_r where k = 'mgr_pub'), (select r from t_r where k = 'mgr'),
  'B12 AS authenticated the public wrapper returns exactly what the implementation does (REPORT-123)');

-- ===== C. validation =========================================================
set local role authenticated;
set local app.current_app_user_id = '9e0a0000-0000-0000-0000-00000000006b';
select throws_ok(
  $$ select app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'last365') $$,
  '22023', null, 'C1 an unknown range -> 22023');
select throws_ok(
  $$ select app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today', current_date, null) $$,
  '22023', null, 'C2 p_start without p_end -> 22023');
select throws_ok(
  $$ select app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today', current_date, current_date - 1) $$,
  '22023', null, 'C3 p_end before p_start -> 22023');
select throws_ok(
  $$ select app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today', current_date - 92, current_date) $$,
  '22023', null, 'C4 a 93-day window -> 22023');
select lives_ok(
  $$ select app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today', current_date - 91, current_date) $$,
  'C5 a 92-day window is accepted');
select throws_ok(
  $$ select app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today', p_reason_code => 'void') $$,
  '22023', null, 'C6 an unknown reason filter -> 22023');
select throws_ok(
  $$ select app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today', p_cursor => 'x|y') $$,
  '22023', 'owner_order_edits: invalid cursor', 'C7 a malformed cursor -> 22023');
reset role;
select ok((select (r ->> 'limit')::int = 1 and jsonb_array_length(r -> 'edits') = 1 from t_r where k = 'mgr_lim0')
      and (select (r ->> 'limit')::int = 100 and jsonb_array_length(r -> 'edits') = 7 from t_r where k = 'mgr_lim1k')
      and (select (r ->> 'limit')::int = 25 from t_r where k = 'mgr'),
  'C8 p_limit is clamped to 1..100 (default 25) and echoed');
select ok((select r ->> 'range' = 'custom' from t_r where k = 'mgr_cust')
      and (select r ->> 'range' = 'today' from t_r where k = 'mgr'),
  'C9 a custom pair echoes range custom; a preset echoes itself');

-- ===== D. M13 figures AS WRITTEN =============================================
select is(pg_temp.figs((select r from t_r where k = 'mgr'), 'e1'), '1500/4000/4000/900/-600/5500',
  'D1 the MONEY worked example: removed 1500, replaced_out 4000, replaced_in 4000, added 900, net -600, gross 5500');
select is(pg_temp.figs((select r from t_r where k = 'mgr'), 'e2'), '0/2400/1600/3000/2200/2400',
  'D2 set_quantity 3 -> 2 plus 1 -> 3: replaced 2400 -> 1600, added 3000, net +2200');
select is(pg_temp.figs((select r from t_r where k = 'mgr'), 'e3'), '0/8000/8000/0/0/8000',
  'D3 a modify split into two replacements: the retired 8000 line counts ONCE');
select ok(pg_temp.figs((select r from t_r where k = 'mgr'), 'e4a') = '0/4000/4000/0/0/4000'
      and pg_temp.figs((select r from t_r where k = 'mgr'), 'e4b') = '4000/0/0/0/-4000/4000',
  'D4 an edit chain: edit 1 keeps its 0 (its replacement retired later is NOT re-judged), edit 2 reports -4000');
select ok((select sum((e ->> 'net_change_minor')::bigint) from t_r, jsonb_array_elements(r -> 'edits') e
            where k = 'mgr' and e ->> 'order_id' = '9e0a0000-0000-0000-0000-00000000a004')
          = (select subtotal_minor from orders where id = '9e0a0000-0000-0000-0000-00000000a004') - 4800,
  'D5 the chain''s edits sum to the order''s subtotal now minus before (800 - 4800)');
select ok(pg_temp.figs((select r from t_r where k = 'mgr'), 'e5') = '0/0/0/900/900/0'
      and (select e ->> 'order_status' from t_r, jsonb_array_elements(r -> 'edits') e
            where k = 'mgr' and e ->> 'order_edit_id' = pg_temp.eid('e5')) = 'voided',
  'D6 an add-only edit of an order voided since keeps +900 and is listed with order_status voided');
select ok((select (r -> 'current' ->> 'void_total_minor')::bigint = 4400 and (r -> 'current' ->> 'void_count')::int = 1
             from t_r where k = 'rr_b1')
      and (select grand_total_minor = 4400 from orders where id = '9e0a0000-0000-0000-0000-00000000a005'),
  'D7 Voids reports the voided order''s post-edit grand total (4400) and no edit-retired line of any other order');
select is(pg_temp.figs((select r from t_r where k = 'mgr'), 'e6'), '1700/0/0/0/-1700/1700',
  'D8 removing a line with an item discount reports its NET line_total_minor (1700)');
select ok((select count(*) = 9 and bool_and((e ->> 'net_change_minor')::bigint
                   = (a.new_values ->> 'subtotal_minor')::bigint - (a.old_values ->> 'subtotal_minor')::bigint)
             from t_r, jsonb_array_elements(r -> 'edits') e
             join audit_events a on a.action = 'order.edited' and a.new_values ->> 'order_edit_id' = e ->> 'order_edit_id'
            where k = 'own_l7'),
  'D9 for every listed edit (9 in the org, last7), net_change_minor = the order.edited audit''s new - old subtotal');
select ok((select (s ->> 'edit_count')::bigint = (select count(*) from jsonb_array_elements(m.r -> 'edits'))
                  and (s ->> 'edited_order_count')::bigint = (select count(distinct e ->> 'order_id') from jsonb_array_elements(m.r -> 'edits') e)
                  and (s ->> 'removed_minor')::bigint      = (select sum((e ->> 'removed_minor')::bigint) from jsonb_array_elements(m.r -> 'edits') e)
                  and (s ->> 'replaced_out_minor')::bigint = (select sum((e ->> 'replaced_out_minor')::bigint) from jsonb_array_elements(m.r -> 'edits') e)
                  and (s ->> 'replaced_in_minor')::bigint  = (select sum((e ->> 'replaced_in_minor')::bigint) from jsonb_array_elements(m.r -> 'edits') e)
                  and (s ->> 'added_minor')::bigint        = (select sum((e ->> 'added_minor')::bigint) from jsonb_array_elements(m.r -> 'edits') e)
                  and (s ->> 'net_change_minor')::bigint   = (select sum((e ->> 'net_change_minor')::bigint) from jsonb_array_elements(m.r -> 'edits') e)
                  and (s ->> 'gross_retired_minor')::bigint = (s ->> 'removed_minor')::bigint + (s ->> 'replaced_out_minor')::bigint
             from t_r m, lateral (select m.r -> 'summary' as s) x where m.k = 'mgr'),
  'D10 the summary is the sum of the listed edits, and gross_retired = removed + replaced_out');
select is((select r -> 'summary' from t_r where k = 'mgr'),
  '{"edit_count": 7, "edited_order_count": 6, "removed_minor": 7200, "replaced_out_minor": 18400, "replaced_in_minor": 17600, "added_minor": 4800, "net_change_minor": -3200, "gross_retired_minor": 25600}'::jsonb,
  'D11 the B1 summary for today, exactly');
select ok((select count(*) > 0 and bool_and(jsonb_typeof(m.v) = 'number' and m.v::text ~ '^-?[0-9]+$')
             from t_r, pg_temp.minors(r) m where t_r.k in ('mgr', 'own_l7', 'acct', 'orgb')),
  'D12 every *_minor value anywhere in the results is an integral JSON number (D-007)');

-- ===== E. window =============================================================
select ok((select not exists (select 1 from jsonb_array_elements(r -> 'edits') e where e ->> 'order_edit_id' = pg_temp.eid('e7'))
             from t_r where k = 'mgr')
      and (select (r -> 'summary' ->> 'edit_count')::int = 1
                  and r -> 'edits' -> 0 ->> 'order_edit_id' = pg_temp.eid('e7')
                  and r -> 'edits' -> 0 ->> 'business_day' = to_char(current_date - 1, 'YYYY-MM-DD')
             from t_r where k = 'mgr_yday'),
  'E1 an order created yesterday and edited today counts only under yesterday (M12)');
select ok((select (r -> 'summary' ->> 'edit_count')::int = 1
                  and r -> 'edits' -> 0 ->> 'order_edit_id' = pg_temp.eid('e8')
                  and r -> 'edits' -> 0 ->> 'business_day' = to_char((select local_today from t_jlm), 'YYYY-MM-DD')
                  and r -> 'edits' -> 0 ->> 'timezone' = 'Asia/Jerusalem'
             from t_r where k = 'own_b2')
      and (select (created_at at time zone 'UTC')::date = (select local_today from t_jlm) - 1
             from orders where id = '9e0a0000-0000-0000-0000-00000000a008')
      and (select (r -> 'summary' ->> 'edit_count')::int = 0 from t_r where k = 'own_b2y'),
  'E2 Asia/Jerusalem: an order at 22:30 UTC falls on the NEXT local day');
select ok((select (select array_agg(e ->> 'order_edit_id' order by e ->> 'order_edit_id') from jsonb_array_elements(c.r -> 'edits') e)
                = (select array_agg(e ->> 'order_edit_id' order by e ->> 'order_edit_id') from jsonb_array_elements(t.r -> 'edits') e)
                  and c.r -> 'summary' = t.r -> 'summary'
             from t_r c, t_r t where c.k = 'mgr_cust' and t.k = 'mgr'),
  'E3 a custom pair (today, today) selects exactly the today preset''s edits');
select ok((select (r -> 'summary' ->> 'edit_count')::int = 8 and r ->> 'range' = 'last60' from t_r where k = 'mgr_l60')
      and (select (r -> 'summary' ->> 'edit_count')::int = 8 and r ->> 'range' = 'last90' from t_r where k = 'mgr_l90'),
  'E4 last60 and last90 are accepted (today''s seven plus yesterday''s one)');
select ok((select (r -> 'summary' ->> 'edit_count')::int = 0 and r -> 'edits' = '[]'::jsonb from t_r where k = 'own_b3')
      and exists (select 1 from order_edits where id = pg_temp.eid('e9')::uuid)
      and not exists (select 1 from t_r, jsonb_array_elements(r -> 'edits') e
                       where e ->> 'order_edit_id' = pg_temp.eid('e9')),
  'E5 a branch with no time zone contributes nothing, in any read');

-- ===== F. tenant isolation ===================================================
select ok((select (r -> 'summary' ->> 'edit_count')::int = 8 from t_r where k = 'own_org')
      and (select (r -> 'summary' ->> 'edit_count')::int = 8 from t_r where k = 'own_rest')
      and (select (r -> 'summary' ->> 'edit_count')::int = 7 from t_r where k = 'mgr'),
  'F1 the org-wide owner sees both zoned branches (7 + 1); a branch filter narrows to its own');
select ok(not exists (select 1 from t_r, jsonb_array_elements(r -> 'edits') e
                       where k <> 'orgb' and (e ->> 'order_edit_id' = pg_temp.eid('eb')
                                              or e ->> 'order_id' like '9e0b%'))
      and not exists (select 1 from t_r where k <> 'orgb' and r::text like '%Bob Other%')
      and not exists (select 1 from t_r where k = 'orgb' and r::text ~ '(Cara|Max|Rita|Olga|Ana) ')
      and (select (r -> 'summary' ->> 'edit_count')::int = 1
                  and r -> 'edits' -> 0 ->> 'order_edit_id' = pg_temp.eid('eb')
                  and r -> 'by_staff' -> 0 ->> 'staff_name' = 'Bob Other'
             from t_r where k = 'orgb'),
  'F2 another organization''s edits and staff never appear, and its owner sees only its own');

-- ===== G. breakdowns =========================================================
select is((select array_agg(coalesce(b ->> 'reason_code', '<none>') order by o)
             from t_r, jsonb_array_elements(r -> 'by_reason') with ordinality x(b, o) where k = 'mgr'),
  array['entry_mistake', 'customer_changed_mind', 'other', 'item_unavailable', '<none>'],
  'G1 by_reason is ordered by gross retired desc and keeps the no-reason row (null) last here');
select ok((select b -> 'reason_code' = 'null'::jsonb and (b ->> 'edit_count')::int = 1 and (b ->> 'added_minor')::bigint = 900
             from t_r, jsonb_array_elements(r -> 'by_reason') b where k = 'mgr' and b ->> 'reason_code' is null)
      and (select (b ->> 'edit_count')::int = 2 and (b ->> 'gross_retired_minor')::bigint = 12000
             from t_r, jsonb_array_elements(r -> 'by_reason') b where k = 'mgr' and b ->> 'reason_code' = 'entry_mistake'),
  'G2 the null-reason row carries the add-only edit; entry_mistake sums two edits (12000)');
select is((select jsonb_agg(jsonb_build_object('n', b ->> 'staff_name', 'e', (b ->> 'edit_count')::int,
                                               'o', (b ->> 'edited_order_count')::int, 'g', (b ->> 'gross_retired_minor')::bigint) order by o)
             from t_r, jsonb_array_elements(r -> 'by_staff') with ordinality x(b, o) where k = 'mgr'),
  '[{"n": "Cara Cashier", "e": 5, "o": 5, "g": 13600}, {"n": "Max Manager", "e": 2, "o": 2, "g": 12000}]'::jsonb,
  'G3 by_staff: grouped by the person who made the edit, ordered by gross retired desc');
select ok((select sum((b ->> 'edited_order_count')::int) from t_r, jsonb_array_elements(r -> 'by_staff') b where k = 'mgr')
          > (select (r -> 'summary' ->> 'edited_order_count')::int from t_r where k = 'mgr'),
  'G4 edited_order_count overlaps across staff rows (O4 was edited by both) and need not sum to the summary');

-- ===== H. reason filter and keyset paging ====================================
select ok((select (r ->> 'matching')::int = 2 and jsonb_array_length(r -> 'edits') = 2
                  and (select bool_and(e ->> 'reason_code' = 'entry_mistake') from jsonb_array_elements(r -> 'edits') e)
             from t_r where k = 'mgr_rsn')
      and (select f.r -> 'summary' = m.r -> 'summary' and f.r -> 'by_reason' = m.r -> 'by_reason'
                  and f.r -> 'by_staff' = m.r -> 'by_staff'
             from t_r f, t_r m where f.k = 'mgr_rsn' and m.k = 'mgr'),
  'H1 the reason filter narrows only edits[] / matching; summary, by_reason and by_staff do not move');
select ok((select (r ->> 'matching')::int = 1 and r -> 'edits' -> 0 ->> 'order_edit_id' = pg_temp.eid('e5')
                  and r -> 'edits' -> 0 -> 'reason_code' = 'null'::jsonb
             from t_r where k = 'mgr_none'),
  'H2 the filter none selects the edits with no reason');
select ok((select (r ->> 'count')::int = 2 and (r ->> 'has_more')::boolean and r ->> 'next_cursor' is not null
                  and (r ->> 'matching')::int = 7 from t_r where k = 'p1')
      and (select (r ->> 'count')::int = 2 and (r ->> 'has_more')::boolean from t_r where k = 'p2')
      and (select (r ->> 'count')::int = 2 and (r ->> 'has_more')::boolean from t_r where k = 'p3')
      and (select (r ->> 'count')::int = 1 and not (r ->> 'has_more')::boolean and r -> 'next_cursor' = 'null'::jsonb
             from t_r where k = 'p4'),
  'H3 limit 2 pages 7 edits as 2 / 2 / 2 / 1; the last page has has_more false and a null next_cursor');
select is((select array_agg(e ->> 'order_edit_id' order by k, o)
             from t_r, jsonb_array_elements(r -> 'edits') with ordinality x(e, o) where k in ('p1', 'p2', 'p3', 'p4')),
          (select array_agg(e ->> 'order_edit_id' order by o)
             from t_r, jsonb_array_elements(r -> 'edits') with ordinality x(e, o) where k = 'mgr'),
  'H4 the pages concatenate to the unpaged list, in order: no duplicate, no gap');
select is((select array_agg(e ->> 'order_edit_id' order by o)
             from t_r, jsonb_array_elements(r -> 'edits') with ordinality x(e, o) where k = 'mgr'),
          (select array_agg(id::text order by created_at desc, id desc) from order_edits
            where branch_id = '9e0a0000-0000-0000-0000-0000000000b1'
              and order_id <> '9e0a0000-0000-0000-0000-00000000a007'),
  'H5 edits[] is newest first (created_at desc, id desc)');

-- ===== I. privacy ============================================================
select is((select count(*)::int from t_r, pg_temp.jkeys(r) j(key)
            where t_r.k <> 'rr_b1'
              and (j.key in ('reason_text', 'device_id', 'pin_session_id', 'membership_id', 'employee_profile_id',
                         'local_operation_id', 'resolved_membership_id', 'kitchen_ack_device_id',
                         'kitchen_ack_by_employee_profile_id', 'order_item_id')
                   or j.key like 'customer\_%')),
  0, 'I1 no result anywhere carries reason_text, a device / session / membership / employee / line id, or customer data');
select ok(not exists (select 1 from t_r where k <> 'rr_b1' and r::text like '%SECRET-REASON-TEXT-001G%'),
  'I2 the free reason text appears nowhere in the report');
select is((select array_agg(j.key order by j.key collate "C") from t_r, jsonb_object_keys(r) j(key) where t_r.k = 'mgr'),
  array['by_reason', 'by_staff', 'count', 'currency_code', 'currency_codes', 'edits', 'entity', 'has_more', 'limit',
        'matching', 'next_cursor', 'ok', 'order_edit_enabled_in_scope', 'range', 'staff_visible', 'summary'],
  'I3 the envelope key set is exactly the contract''s');
select is((select array_agg(j.key order by j.key collate "C") from t_r, jsonb_object_keys(r -> 'edits' -> 0) j(key) where t_r.k = 'mgr'),
  array['added_minor', 'branch_name', 'business_day', 'created_at', 'created_at_utc', 'currency_code', 'edit_number',
        'gross_retired_minor', 'kitchen_channel', 'net_change_minor', 'order_code', 'order_edit_id', 'order_id',
        'order_status', 'order_type', 'reason_code', 'removed_minor', 'replaced_in_minor', 'replaced_out_minor',
        'staff_name', 'timezone'],
  'I4 an edits[] element''s key set is exactly the contract''s');
select ok((select bool_and(e ->> 'created_at' ~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$'
                           and e ->> 'created_at_utc' ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
                           and e ->> 'order_code' ~ '^#[0-9A-F]{6}$'
                           and e ->> 'branch_name' = 'Branch UTC' and e ->> 'kitchen_channel' = 'kds')
             from t_r, jsonb_array_elements(r -> 'edits') e where k = 'mgr'),
  'I5 display fields: branch-local created_at, ISO-8601 Z instant, #XXXXXX order code, branch name, channel');

-- ===== J. envelope ===========================================================
select is((select count(*) from audit_events), (select n from t_audit0),
  'J1 the reads wrote no audit_events row (D-013)');
select ok((select r ->> 'currency_code' = 'USD' from t_r where k = 'own_ovr')
      and (select r ->> 'currency_code' = 'ILS' from t_r where k = 'own_ovr_org')
      and (select r ->> 'currency_code' = 'ILS' from t_r where k = 'mgr'),
  'J2 currency_code is the EFFECTIVE currency: the restaurant override when a restaurant is in scope, else the org default');
select ok((select r -> 'currency_codes' = '["ILS", "USD"]'::jsonb from t_r where k = 'mgr')
      and (select bool_and(e ->> 'currency_code' = case when e ->> 'order_id' = '9e0a0000-0000-0000-0000-00000000a006' then 'USD' else 'ILS' end)
             from t_r, jsonb_array_elements(r -> 'edits') e where k = 'mgr'),
  'J3 currency_codes lists the counted orders'' currencies, sorted and distinct; each row carries its order''s');
select ok((select (r ->> 'order_edit_enabled_in_scope')::boolean from t_r where k = 'mgr')
      and (select not (r ->> 'order_edit_enabled_in_scope')::boolean and (r -> 'summary' ->> 'edit_count')::int = 7
             from t_r where k = 'own_ovr')
      and (select (r ->> 'order_edit_enabled_in_scope')::boolean from t_r where k = 'own_ovr_org'),
  'J4 order_edit_enabled_in_scope follows the branch switch; edits made stay listed after it is turned off');
select is((select r - 'currency_code' - 'range' - 'limit' - 'staff_visible' - 'order_edit_enabled_in_scope' from t_r where k = 'mgr_empty'),
  '{"ok": true, "entity": "owner_order_edits", "currency_codes": [], "summary": {"edit_count": 0, "edited_order_count": 0, "removed_minor": 0, "replaced_out_minor": 0, "replaced_in_minor": 0, "added_minor": 0, "net_change_minor": 0, "gross_retired_minor": 0}, "by_reason": [], "by_staff": [], "edits": [], "count": 0, "matching": 0, "has_more": false, "next_cursor": null}'::jsonb,
  'J5 an empty window returns honest zeros and empty arrays');
select ok((select not (r ->> 'order_edit_enabled_in_scope')::boolean and (r -> 'summary' ->> 'edit_count')::int = 0
             from t_r where k = 'own_off_b1e'),
  'J6 a scope with the switch off and no edits in the window reads hidden (enabled false, zero edits)');

-- ===== K. a LATER item discount never rewrites an edit's figures =============
-- Built after every assertion above, so none of their counts move. A row an
-- edit wrote is valued as written (line_total_minor + line_discount_minor):
-- app.apply_discount (scope order_item) later lowers its line_total_minor, and
-- that discount belongs to Discounts, not to the edit.
-- O10 add-only: Salad 2000, + Lemonade 900, + Cola 800 (subtotal 2000 -> 3700).
select pg_temp.mk_order('9e0a0000-0000-0000-0000-00000000a010', '9e0a0000-0000-0000-0000-00000000009a');
select pg_temp.mk_item('9e0a0000-0000-0000-0000-0000000c0001', '9e0a0000-0000-0000-0000-00000000a010', '9e0a0000-0000-0000-0000-000000001005', 'Salad', 1, 2000);
select pg_temp.settle('9e0a0000-0000-0000-0000-00000000a010');
select pg_temp.edit('e10', '9e0a0000-0000-0000-0000-00000000009a', '9e0a0000-0000-0000-0000-00000000a010',
  '{"expected": {"subtotal_minor": 3700, "tax_total_minor": 0, "grand_total_minor": 3700},
    "changes": [
      {"op": "add", "item": {"menu_item_id": "9e0a0000-0000-0000-0000-000000001004", "quantity": 1,
        "unit_price_minor_snapshot": 900, "menu_item_name_snapshot": "Lemonade", "modifiers": []}},
      {"op": "add", "item": {"menu_item_id": "9e0a0000-0000-0000-0000-000000001003", "quantity": 1,
        "unit_price_minor_snapshot": 800, "menu_item_name_snapshot": "Cola", "modifiers": []}}]}'::jsonb);
-- O11 a reduction and an increase: Cola 3 -> 2 (remainder row 1600 replaces
-- the 2400 line), Fries 1 -> 2 (a +1 delta row 1500). Subtotal 3900 -> 4600.
select pg_temp.mk_order('9e0a0000-0000-0000-0000-00000000a011', '9e0a0000-0000-0000-0000-00000000009a');
select pg_temp.mk_item('9e0a0000-0000-0000-0000-0000000c1001', '9e0a0000-0000-0000-0000-00000000a011', '9e0a0000-0000-0000-0000-000000001003', 'Cola', 3, 800);
select pg_temp.mk_item('9e0a0000-0000-0000-0000-0000000c1002', '9e0a0000-0000-0000-0000-00000000a011', '9e0a0000-0000-0000-0000-000000001002', 'Fries', 1, 1500);
select pg_temp.settle('9e0a0000-0000-0000-0000-00000000a011');
select pg_temp.edit('e11', '9e0a0000-0000-0000-0000-00000000009a', '9e0a0000-0000-0000-0000-00000000a011',
  '{"reason_code": "customer_changed_mind",
    "expected": {"subtotal_minor": 4600, "tax_total_minor": 0, "grand_total_minor": 4600},
    "changes": [
      {"op": "set_quantity", "order_item_id": "9e0a0000-0000-0000-0000-0000000c1001", "quantity": 2},
      {"op": "set_quantity", "order_item_id": "9e0a0000-0000-0000-0000-0000000c1002", "quantity": 2}]}'::jsonb);

-- the rows each edit wrote
create temp table t_k_rows as
  select 'lemonade'::text as k, id from order_items
   where edit_id = pg_temp.eid('e10')::uuid and menu_item_id = '9e0a0000-0000-0000-0000-000000001004'
  union all
  select 'cola_added', id from order_items
   where edit_id = pg_temp.eid('e10')::uuid and menu_item_id = '9e0a0000-0000-0000-0000-000000001003'
  union all
  select 'cola_remainder', id from order_items
   where edit_id = pg_temp.eid('e11')::uuid and replaces_order_item_id = '9e0a0000-0000-0000-0000-0000000c1001'
  union all
  select 'fries_delta', id from order_items
   where edit_id = pg_temp.eid('e11')::uuid and replaces_order_item_id is null;

-- before: Max (B1 manager) reads the block and the report range
set local role authenticated;
set local app.current_app_user_id = '9e0a0000-0000-0000-0000-00000000006b';
insert into t_r values
  ('k_before',    app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today')),
  ('k_rr_before', app.owner_report_range('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today'));
reset role;

-- Max discounts every written row at ITEM scope: fixed 100 and a 100 %
-- percentage on O10's added lines; a 100 % percentage on O11's remainder row
-- and fixed 200 on its +1 delta row.
create temp table t_disc (k text primary key, r jsonb);
insert into t_disc values ('lemonade', app.apply_discount('9e0a0000-0000-0000-0000-00000000009b', '9e0a0000-0000-0000-0000-00000000a010',
  '9e0a0000-0000-0000-0000-0000000000d1', 'g-k-disc-1', 'order_item', (select id from t_k_rows where k = 'lemonade'), 'fixed', 100, 'loyalty'));
insert into t_disc values ('cola_added', app.apply_discount('9e0a0000-0000-0000-0000-00000000009b', '9e0a0000-0000-0000-0000-00000000a010',
  '9e0a0000-0000-0000-0000-0000000000d1', 'g-k-disc-2', 'order_item', (select id from t_k_rows where k = 'cola_added'), 'percentage', 10000, 'on the house'));
insert into t_disc values ('cola_remainder', app.apply_discount('9e0a0000-0000-0000-0000-00000000009b', '9e0a0000-0000-0000-0000-00000000a011',
  '9e0a0000-0000-0000-0000-0000000000d1', 'g-k-disc-3', 'order_item', (select id from t_k_rows where k = 'cola_remainder'), 'percentage', 10000, 'on the house'));
insert into t_disc values ('fries_delta', app.apply_discount('9e0a0000-0000-0000-0000-00000000009b', '9e0a0000-0000-0000-0000-00000000a011',
  '9e0a0000-0000-0000-0000-0000000000d1', 'g-k-disc-4', 'order_item', (select id from t_k_rows where k = 'fries_delta'), 'fixed', 200, 'loyalty'));

-- after: the same reads
set local role authenticated;
set local app.current_app_user_id = '9e0a0000-0000-0000-0000-00000000006b';
insert into t_r values
  ('k_after',    app.owner_order_edits('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today')),
  ('k_rr_after', app.owner_report_range('9e0a0000-0000-0000-0000-0000000000a0', '9e0a0000-0000-0000-0000-0000000000a1', '9e0a0000-0000-0000-0000-0000000000b1', 'today'));
reset role;

select ok((select bool_and(r ->> 'status' = 'applied') from t_ed where k in ('e10', 'e11'))
      and (select count(*) = 4 and bool_and((r ->> 'ok')::boolean) from t_disc)
      and (select count(*) = 4 from t_k_rows)
      and (select string_agg(t.k || '=' || oi.line_total_minor || '+' || oi.line_discount_minor, ',' order by t.k)
             from t_k_rows t join order_items oi on oi.id = t.id)
          = 'cola_added=0+800,cola_remainder=0+1600,fries_delta=1300+200,lemonade=800+100'
      and (select array_agg(subtotal_minor order by id) from orders
            where id in ('9e0a0000-0000-0000-0000-00000000a010', '9e0a0000-0000-0000-0000-00000000a011')) = array[2800::bigint, 2800::bigint],
  'K0 fixture: both edits applied, then four item discounts landed on the rows they wrote (fixed and 100 %)');
select ok(pg_temp.figs((select r from t_r where k = 'k_before'), 'e10') = '0/0/0/1700/1700/0'
      and pg_temp.figs((select r from t_r where k = 'k_after'), 'e10') = '0/0/0/1700/1700/0',
  'K1 an add-only edit keeps added 1700 / net +1700 after a fixed and a 100 % item discount on the lines it added');
select ok(pg_temp.figs((select r from t_r where k = 'k_before'), 'e11') = '0/2400/1600/1500/700/2400'
      and pg_temp.figs((select r from t_r where k = 'k_after'), 'e11') = '0/2400/1600/1500/700/2400',
  'K2 a reduction + increase keeps replaced_in 1600 / added 1500 / net +700 after a 100 % and a fixed item discount on its rows');
select ok((select count(*) = 2 and bool_and((e ->> 'net_change_minor')::bigint
                   = (a.new_values ->> 'subtotal_minor')::bigint - (a.old_values ->> 'subtotal_minor')::bigint)
             from t_r, jsonb_array_elements(r -> 'edits') e
             join audit_events a on a.action = 'order.edited' and a.new_values ->> 'order_edit_id' = e ->> 'order_edit_id'
            where k = 'k_after' and e ->> 'order_edit_id' in (pg_temp.eid('e10'), pg_temp.eid('e11'))),
  'K3 after the discounts, each edit''s net_change_minor still equals its order.edited audit''s new - old subtotal');
select ok((select a.r -> 'summary' = b.r -> 'summary' and a.r -> 'by_reason' = b.r -> 'by_reason'
                  and a.r -> 'by_staff' = b.r -> 'by_staff'
             from t_r a, t_r b where a.k = 'k_after' and b.k = 'k_before'),
  'K4 summary, by_reason and by_staff do not move when a later item discount lands on an edit''s rows');
select is((select (a.r -> 'current' ->> 'discount_minor')::bigint - (b.r -> 'current' ->> 'discount_minor')::bigint
             from t_r a, t_r b where a.k = 'k_rr_after' and b.k = 'k_rr_before'),
  2700::bigint,
  'K5 the 2700 of item discounts is reported once, under Discounts (owner_report_range)');

select * from finish();
rollback;
