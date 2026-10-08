-- ORDER-EDIT-001A — the SURFACE of sent-order editing: the owner setter of the
-- two branch switches (API_CONTRACT §4.45.8, the RF-113 template), the D-037
-- ACL of every new function (and the unchanged T-016 global surface), the
-- kitchen_workflow_mode single-writer guard, public.order_edits RLS, the
-- sync_operations CHECK + the revoked-device path, the §4.33 audit coverage
-- (category, has_detail, safe projections of REAL writer payloads) and the
-- Dashboard item-count readers (§4.45.10: retired lines excluded; unedited and
-- voided orders unchanged).
begin;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(64);

-- ===== fixture ==============================================================
-- Org A: one KDS-mode branch, order editing OFF (the setter turns it on); a
-- POS, a KDS and a second POS that is revoked later. Org F: another tenant.
insert into organizations (id, name, slug, default_currency) values
  ('e3ed0000-0000-0000-0000-0000000000a0', 'Org Surface A', 'org-edit-surface-a', 'ILS'),
  ('e3ed0000-0000-0000-0000-0000000000b0', 'Org Surface F', 'org-edit-surface-f', 'ILS');
insert into restaurants (id, organization_id, name, timezone) values
  ('e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000a0', 'Rest A', 'UTC'),
  ('e3ed0000-0000-0000-0000-0000000000b1', 'e3ed0000-0000-0000-0000-0000000000b0', 'Rest F', 'UTC');
insert into branches (id, organization_id, restaurant_id, name) values
  ('e3ed0000-0000-0000-0000-0000000000ab', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', 'Branch A'),
  ('e3ed0000-0000-0000-0000-0000000000bb', 'e3ed0000-0000-0000-0000-0000000000b0', 'e3ed0000-0000-0000-0000-0000000000b1', 'Branch F');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('e3ed0000-0000-0000-0000-0000000000d1', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', 'pos'),
  ('e3ed0000-0000-0000-0000-0000000000d2', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', 'kds'),
  ('e3ed0000-0000-0000-0000-0000000000d3', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('e3ed0000-0000-0000-0000-0000000000f1', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', 'e3ed0000-0000-0000-0000-0000000000d1', 'active'),
  ('e3ed0000-0000-0000-0000-0000000000f2', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', 'e3ed0000-0000-0000-0000-0000000000d2', 'active'),
  ('e3ed0000-0000-0000-0000-0000000000f3', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', 'e3ed0000-0000-0000-0000-0000000000d3', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('e3ed0000-0000-0000-0000-00000000005a', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', 'e3ed0000-0000-0000-0000-0000000000d1', 'e3ed0000-0000-0000-0000-0000000000f1'),
  ('e3ed0000-0000-0000-0000-00000000005b', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', 'e3ed0000-0000-0000-0000-0000000000d2', 'e3ed0000-0000-0000-0000-0000000000f2'),
  ('e3ed0000-0000-0000-0000-00000000005c', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', 'e3ed0000-0000-0000-0000-0000000000d3', 'e3ed0000-0000-0000-0000-0000000000f3');
insert into app_users (id, email) values
  ('e3ed0000-0000-0000-0000-00000000006a', 'surface-orgowner@example.test'),
  ('e3ed0000-0000-0000-0000-00000000006b', 'surface-restowner@example.test'),
  ('e3ed0000-0000-0000-0000-00000000006c', 'surface-manager@example.test'),
  ('e3ed0000-0000-0000-0000-00000000006d', 'surface-cashier@example.test'),
  ('e3ed0000-0000-0000-0000-00000000006e', 'surface-kitchen@example.test'),
  ('e3ed0000-0000-0000-0000-00000000006f', 'surface-other-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('e3ed0000-0000-0000-0000-00000000007a', 'e3ed0000-0000-0000-0000-00000000006a', 'e3ed0000-0000-0000-0000-0000000000a0', null, null, 'org_owner', '{}'::jsonb),
  ('e3ed0000-0000-0000-0000-00000000007b', 'e3ed0000-0000-0000-0000-00000000006b', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', null, 'restaurant_owner', '{}'::jsonb),
  ('e3ed0000-0000-0000-0000-00000000007c', 'e3ed0000-0000-0000-0000-00000000006c', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', 'manager', '{}'::jsonb),
  ('e3ed0000-0000-0000-0000-00000000007d', 'e3ed0000-0000-0000-0000-00000000006d', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', 'cashier', '{}'::jsonb),
  ('e3ed0000-0000-0000-0000-00000000007e', 'e3ed0000-0000-0000-0000-00000000006e', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', 'kitchen_staff', '{}'::jsonb),
  ('e3ed0000-0000-0000-0000-00000000007f', 'e3ed0000-0000-0000-0000-00000000006f', 'e3ed0000-0000-0000-0000-0000000000b0', null, null, 'org_owner', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('e3ed0000-0000-0000-0000-00000000008d', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', 'e3ed0000-0000-0000-0000-00000000006d', 'e3ed0000-0000-0000-0000-00000000007d', 'Sara Cashier'),
  ('e3ed0000-0000-0000-0000-00000000008e', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', 'e3ed0000-0000-0000-0000-00000000006e', 'e3ed0000-0000-0000-0000-00000000007e', 'Kai Kitchen');
-- 9d: cashier on the POS; 9e: kitchen on the KDS; 9f: cashier on the POS that is revoked later.
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('e3ed0000-0000-0000-0000-00000000009d', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', 'e3ed0000-0000-0000-0000-00000000005a', 'e3ed0000-0000-0000-0000-00000000008d', 'e3ed0000-0000-0000-0000-00000000007d', now() + interval '1 hour'),
  ('e3ed0000-0000-0000-0000-00000000009e', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', 'e3ed0000-0000-0000-0000-00000000005b', 'e3ed0000-0000-0000-0000-00000000008e', 'e3ed0000-0000-0000-0000-00000000007e', now() + interval '1 hour'),
  ('e3ed0000-0000-0000-0000-00000000009f', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', 'e3ed0000-0000-0000-0000-00000000005c', 'e3ed0000-0000-0000-0000-00000000008d', 'e3ed0000-0000-0000-0000-00000000007d', now() + interval '1 hour');

-- Menu: Fries 1500, Cola 800, Burger 4000.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('e3ed0000-0000-0000-0000-0000000000c1', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', null, 'Mains', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('e3ed0000-0000-0000-0000-000000001001', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', null, 'e3ed0000-0000-0000-0000-0000000000c1', 'Fries',  1500, 'ILS', 1),
  ('e3ed0000-0000-0000-0000-000000001002', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', null, 'e3ed0000-0000-0000-0000-0000000000c1', 'Cola',    800, 'ILS', 2),
  ('e3ed0000-0000-0000-0000-000000001003', 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1', null, 'e3ed0000-0000-0000-0000-0000000000c1', 'Burger', 4000, 'ILS', 3);

-- Orders (direct inserts as the fixture role). X is edited, Y stays unedited,
-- Z is VOIDED (its lines voided too).
create function pg_temp.mk_order(p_id uuid, p_status text, p_sub bigint) returns void
language sql as $$
  insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
    opened_by_employee_profile_id, resolved_membership_id, order_type, currency_code,
    subtotal_minor, grand_total_minor, local_operation_id, status, voided_at, voided_from_status)
  values (p_id, 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1',
    'e3ed0000-0000-0000-0000-0000000000ab', 'e3ed0000-0000-0000-0000-0000000000d1',
    'e3ed0000-0000-0000-0000-00000000009d', 'e3ed0000-0000-0000-0000-00000000008d',
    'e3ed0000-0000-0000-0000-00000000007d', 'dine_in', 'ILS', p_sub, p_sub, 'submit-' || p_id::text, p_status,
    case when p_status = 'voided' then now() end,
    case when p_status = 'voided' then 'submitted' end);
$$;
create function pg_temp.mk_item(p_id uuid, p_order uuid, p_menu uuid, p_name text, p_qty int,
  p_unit bigint, p_status text default 'pending') returns void
language sql as $$
  insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id, status,
    quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_discount_minor, line_total_minor)
  values (p_id, 'e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1',
    'e3ed0000-0000-0000-0000-0000000000ab', p_order, p_menu, p_status, p_qty, p_name, p_unit, 0, p_qty * p_unit);
$$;
select pg_temp.mk_order('e3ed0000-0000-0000-0000-00000000a001', 'submitted', 3800);
select pg_temp.mk_item('e3ed0000-0000-0000-0000-0000000a1001', 'e3ed0000-0000-0000-0000-00000000a001', 'e3ed0000-0000-0000-0000-000000001001', 'Fries', 2, 1500);
select pg_temp.mk_item('e3ed0000-0000-0000-0000-0000000a1002', 'e3ed0000-0000-0000-0000-00000000a001', 'e3ed0000-0000-0000-0000-000000001002', 'Cola', 1, 800);
select pg_temp.mk_order('e3ed0000-0000-0000-0000-00000000a002', 'submitted', 12000);
select pg_temp.mk_item('e3ed0000-0000-0000-0000-0000000a2001', 'e3ed0000-0000-0000-0000-00000000a002', 'e3ed0000-0000-0000-0000-000000001003', 'Burger', 3, 4000);
select pg_temp.mk_order('e3ed0000-0000-0000-0000-00000000a003', 'voided', 3800);
select pg_temp.mk_item('e3ed0000-0000-0000-0000-0000000a3001', 'e3ed0000-0000-0000-0000-00000000a003', 'e3ed0000-0000-0000-0000-000000001001', 'Fries', 2, 1500, 'voided');
select pg_temp.mk_item('e3ed0000-0000-0000-0000-0000000a3002', 'e3ed0000-0000-0000-0000-00000000a003', 'e3ed0000-0000-0000-0000-000000001002', 'Cola', 1, 800, 'voided');

-- one sync_push op; returns the op's result
create function pg_temp.push(p_pin uuid, p_dev uuid, p_op text, p_type text, p_order uuid, p_payload jsonb)
returns jsonb language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', p_type, 'target_entity', 'order',
    'target_id', p_order, 'payload', p_payload || jsonb_build_object('order_id', p_order)))) -> 'results' -> 0;
$$;
-- the safe order code of an order id
create function pg_temp.code(p_id uuid) returns text language sql immutable as $$
  select '#' || upper(right(replace(p_id::text, '-', ''), 6));
$$;

-- ===== A. app.set_branch_order_edit_settings (API §4.45.8; RF-113 template) ==
set local role authenticated;
set local app.current_app_user_id = 'e3ed0000-0000-0000-0000-00000000006a';  -- org_owner
create temp table t_s1 as select public.set_branch_order_edit_settings(
  'e3ed0000-0000-0000-0000-0000000c0001', 'e3ed0000-0000-0000-0000-0000000000a0',
  'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', true, false) as r;
create temp table t_s2 as select app.set_branch_order_edit_settings(
  'e3ed0000-0000-0000-0000-0000000c0001', 'e3ed0000-0000-0000-0000-0000000000a0',
  'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', true, false) as r;

select is((select r from t_s1),
  jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'branch',
    'branch_id', 'e3ed0000-0000-0000-0000-0000000000ab',
    'order_edit_enabled', true, 'order_edit_finished_food_manager_only', false),
  '01 org_owner (public wrapper): the exact success envelope');
select is((select r from t_s2), (select r || '{"idempotent_replay": true}'::jsonb from t_s1),
  '02 an exact replay (same p_client_request_id + input) returns the stored envelope with idempotent_replay true');
select throws_ok($$ select app.set_branch_order_edit_settings(
  'e3ed0000-0000-0000-0000-0000000c0001', 'e3ed0000-0000-0000-0000-0000000000a0',
  'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', false, false) $$,
  '42501', null, '03 the same p_client_request_id with DIFFERENT input RAISES 42501');
select throws_ok($$ select public.set_branch_order_edit_settings(
  null, 'e3ed0000-0000-0000-0000-0000000000a0',
  'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', true, false) $$,
  '42501', null, '04 a null p_client_request_id RAISES 42501');
select throws_ok($$ select app.set_branch_order_edit_settings(
  'e3ed0000-0000-0000-0000-0000000c00e1', 'e3ed0000-0000-0000-0000-0000000000a0',
  'e3ed0000-0000-0000-0000-0000000000a1', null, true, false) $$,
  '42501', null, '05 a null branch id RAISES 42501');
select throws_ok($$ select app.set_branch_order_edit_settings(
  'e3ed0000-0000-0000-0000-0000000c00e2', 'e3ed0000-0000-0000-0000-0000000000a0',
  'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', true, null) $$,
  '42501', null, '06 a null setting RAISES 42501');
set local app.current_app_user_id = '';
select throws_ok($$ select app.set_branch_order_edit_settings(
  'e3ed0000-0000-0000-0000-0000000c00e3', 'e3ed0000-0000-0000-0000-0000000000a0',
  'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', true, false) $$,
  '42501', null, '07 no authenticated actor RAISES 42501');

set local app.current_app_user_id = 'e3ed0000-0000-0000-0000-00000000006b';  -- restaurant_owner
create temp table t_s3 as select app.set_branch_order_edit_settings(
  'e3ed0000-0000-0000-0000-0000000c0002', 'e3ed0000-0000-0000-0000-0000000000a0',
  'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', true, true) as r;
select ok((select (r ->> 'ok')::boolean and not (r ->> 'idempotent_replay')::boolean
                  and r ->> 'entity' = 'branch'
                  and (r ->> 'order_edit_enabled')::boolean
                  and (r ->> 'order_edit_finished_food_manager_only')::boolean from t_s3),
  '08 restaurant_owner of the branch''s restaurant may write both switches');

set local app.current_app_user_id = 'e3ed0000-0000-0000-0000-00000000006c';  -- manager (rank 2)
create temp table t_s4 as select public.set_branch_order_edit_settings(
  'e3ed0000-0000-0000-0000-0000000c0003', 'e3ed0000-0000-0000-0000-0000000000a0',
  'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', false, false) as r;
select ok((select r ->> 'ok' = 'false' and r ->> 'error' = 'permission_denied' from t_s4),
  '09 a manager gets {ok:false, error:permission_denied} (no raise)');

set local app.current_app_user_id = 'e3ed0000-0000-0000-0000-00000000006f';  -- Org F's org_owner
select throws_ok($$ select app.set_branch_order_edit_settings(
  'e3ed0000-0000-0000-0000-0000000c0004', 'e3ed0000-0000-0000-0000-0000000000a0',
  'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', false, false) $$,
  '42501', null, '10 another tenant''s owner RAISES 42501 (no covering membership)');
reset role;
set local app.current_app_user_id = '';

select ok((select order_edit_enabled and order_edit_finished_food_manager_only
             from branches where id = 'e3ed0000-0000-0000-0000-0000000000ab')
      and (select not order_edit_enabled and not order_edit_finished_food_manager_only
             from branches where id = 'e3ed0000-0000-0000-0000-0000000000bb'),
  '11 both columns persisted (restaurant_owner''s write last); denials and raises wrote nothing; Org F untouched');
select is((select count(*)::int from audit_events
            where action = 'settings.branch.order_edit_updated'
              and branch_id = 'e3ed0000-0000-0000-0000-0000000000ab'),
  2, '12 exactly two settings.branch.order_edit_updated audits (the replay wrote no second one)');
select ok((select actor_app_user_id = 'e3ed0000-0000-0000-0000-00000000006a'
                  and organization_id = 'e3ed0000-0000-0000-0000-0000000000a0'
                  and restaurant_id = 'e3ed0000-0000-0000-0000-0000000000a1'
                  and old_values = '{"branch_id": "e3ed0000-0000-0000-0000-0000000000ab", "order_edit_enabled": false, "order_edit_finished_food_manager_only": false}'::jsonb
                  and new_values = '{"branch_id": "e3ed0000-0000-0000-0000-0000000000ab", "order_edit_enabled": true, "order_edit_finished_food_manager_only": false}'::jsonb
             from audit_events where action = 'settings.branch.order_edit_updated'
              and actor_app_user_id = 'e3ed0000-0000-0000-0000-00000000006a'),
  '13 the org_owner audit carries old/new values of the two booleans (false,false -> true,false)');
select ok((select old_values ->> 'order_edit_enabled' = 'true' and old_values ->> 'order_edit_finished_food_manager_only' = 'false'
                  and new_values ->> 'order_edit_enabled' = 'true' and new_values ->> 'order_edit_finished_food_manager_only' = 'true'
             from audit_events where action = 'settings.branch.order_edit_updated'
              and actor_app_user_id = 'e3ed0000-0000-0000-0000-00000000006b'),
  '14 the restaurant_owner audit: (true,false) -> (true,true)');
select ok((select count(*) = 1 and bool_and(old_values is null
                  and new_values = '{"branch_id": "e3ed0000-0000-0000-0000-0000000000ab", "setting": "order_edit"}'::jsonb)
             from audit_events where action = 'settings.branch.update_denied'
              and actor_app_user_id = 'e3ed0000-0000-0000-0000-00000000006c'),
  '15 the manager''s denial is audited settings.branch.update_denied with setting order_edit');
select ok((select app.audit_category(action) = 'settings'
                  and app.audit_safe_detail(action, new_values)
                      = '{"order_edit_enabled": true, "order_edit_finished_food_manager_only": false}'::jsonb
                  and app.audit_safe_detail(action, old_values)
                      = '{"order_edit_enabled": false, "order_edit_finished_food_manager_only": false}'::jsonb
             from audit_events where action = 'settings.branch.order_edit_updated'
              and actor_app_user_id = 'e3ed0000-0000-0000-0000-00000000006a'),
  '16 settings category; the safe detail projects EXACTLY the two booleans (branch_id dropped)');

-- ===== B. ACL (D-037) and the global public surface (T-016) ==================
select ok(not (select prosecdef from pg_proc where oid = 'public.set_branch_order_edit_settings(uuid,uuid,uuid,uuid,boolean,boolean)'::regprocedure)
          and not has_function_privilege('anon', 'public.set_branch_order_edit_settings(uuid,uuid,uuid,uuid,boolean,boolean)', 'EXECUTE')
          and has_function_privilege('authenticated', 'public.set_branch_order_edit_settings(uuid,uuid,uuid,uuid,boolean,boolean)', 'EXECUTE'),
  '17 public.set_branch_order_edit_settings: SECURITY INVOKER, anon denied, authenticated granted');
select ok((select prosecdef and proconfig @> array['search_path=""'] from pg_proc
            where oid = 'app.set_branch_order_edit_settings(uuid,uuid,uuid,uuid,boolean,boolean)'::regprocedure)
          and not has_function_privilege('anon', 'app.set_branch_order_edit_settings(uuid,uuid,uuid,uuid,boolean,boolean)', 'EXECUTE')
          and has_function_privilege('authenticated', 'app.set_branch_order_edit_settings(uuid,uuid,uuid,uuid,boolean,boolean)', 'EXECUTE'),
  '18 app.set_branch_order_edit_settings: SECURITY DEFINER with search_path pinned, anon denied, authenticated granted');
select is((select count(*)::int from pg_proc p
            where p.oid in ('public.set_branch_order_edit_settings(uuid,uuid,uuid,uuid,boolean,boolean)'::regprocedure,
                            'app.set_branch_order_edit_settings(uuid,uuid,uuid,uuid,boolean,boolean)'::regprocedure)
              and p.proacl is not null
              and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE')),
  2, '19 PUBLIC holds no EXECUTE on either setter (explicit ACL, no grantee 0)');
select ok((select count(*) = 1 from pg_proc where pronamespace = 'app'::regnamespace and proname = 'set_branch_order_edit_settings')
          and (select count(*) = 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'set_branch_order_edit_settings'),
  '20 exactly one overload of each setter');

create temp table t_internal (sig regprocedure, writes boolean);
insert into t_internal values
  ('app.edit_order(uuid,uuid,uuid,text,jsonb,timestamptz)', true),
  ('app.kitchen_ack_order_edit(uuid,uuid,uuid,text,integer)', true),
  ('app.create_order_edit_dispatch(uuid,uuid,uuid,uuid,uuid,jsonb,uuid,uuid,uuid)', true),
  ('app.edit_order_deny(uuid,uuid,uuid,uuid,uuid,uuid,text,text,text,text,text,text,jsonb,jsonb)', true),
  ('app.kitchen_dispatch_payload_order_edit(uuid,uuid,uuid,jsonb)', false),
  ('app.order_item_is_legacy_priced(uuid,uuid)', false),
  ('app.edit_tax_minor(bigint,boolean,integer,text)', false),
  ('app.edit_reanswer_prep(jsonb,jsonb)', false),
  ('app.edit_validate_new_line(jsonb)', false),
  ('app.edit_json_int(jsonb,bigint,bigint)', false),
  ('app.edit_try_uuid(text)', false),
  ('app.kitchen_dispatch_item_projection(uuid,uuid)', false);
select is((select string_agg(sig::text, ', ' order by sig::text) from t_internal
            where has_function_privilege('anon', sig, 'EXECUTE')
               or has_function_privilege('authenticated', sig, 'EXECUTE')),
  null, '21 no internal edit function is executable by anon or authenticated (culprits listed)');
select is((select string_agg(t.sig::text, ', ' order by t.sig::text) from t_internal t join pg_proc p on p.oid = t.sig
            where p.proacl is null
               or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE')),
  null, '22 no internal edit function leaves EXECUTE to PUBLIC');
select is((select string_agg(p.proname, ', ' order by p.proname) from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in (select p2.proname from t_internal t join pg_proc p2 on p2.oid = t.sig)),
  null, '23 no internal edit function has a public wrapper');
select is((select string_agg(t.sig::text, ', ' order by t.sig::text) from t_internal t join pg_proc p on p.oid = t.sig
            where (t.writes and not p.prosecdef)
               or not coalesce(p.proconfig @> array['search_path=""'], false)),
  null, '24 the four writers are SECURITY DEFINER and every internal edit function pins search_path');
select ok((select count(*) = 1 from pg_proc where pronamespace = 'app'::regnamespace and proname = 'edit_order')
          and (select count(*) = 1 from pg_proc where pronamespace = 'app'::regnamespace and proname = 'kitchen_ack_order_edit'),
  '25 exactly one overload of app.edit_order and app.kitchen_ack_order_edit');
select is((select string_agg(regexp_replace(p.oid::regprocedure::text, '^public\.', ''), ', '
                    order by regexp_replace(p.oid::regprocedure::text, '^public\.', ''))
             from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
              and has_function_privilege('anon', p.oid, 'EXECUTE')),
  'storefront_menu(text)', '26 T-016: the anon-executable public surface is still exactly storefront_menu(text)');
select is((select string_agg(regexp_replace(p.oid::regprocedure::text, '^public\.', ''), ', '
                    order by regexp_replace(p.oid::regprocedure::text, '^public\.', ''))
             from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') and p.prosecdef),
  'storefront_menu(text)', '27 T-016: the public SECURITY DEFINER surface is still exactly storefront_menu(text)');
select ok(not has_schema_privilege('anon', 'app', 'USAGE'), '28 anon still has no USAGE on schema app');

-- ===== C. the kitchen_workflow_mode single-writer guard (KITCHEN-MODE #45) ====
select ok(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('app', 'public')
      and p.prosrc ~* 'update\s+(public\.)?branches\y'
      and p.prosrc ilike '%kitchen_workflow_mode%') = 1
  and exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'app' and p.proname = 'set_kitchen_workflow_mode'
                 and p.prosrc ~* 'update\s+(public\.)?branches\y'
                 and p.prosrc ilike '%kitchen_workflow_mode%'),
  '29 ONLY app.set_kitchen_workflow_mode UPDATEs branches and mentions kitchen_workflow_mode (the new setter does not)');

-- ===== D. public.order_edits: RLS and table privileges ======================
select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.order_edits'::regclass),
  '30 order_edits: RLS enabled AND forced');
select ok(has_table_privilege('authenticated', 'public.order_edits', 'SELECT')
          and not has_table_privilege('authenticated', 'public.order_edits', 'INSERT')
          and not has_table_privilege('authenticated', 'public.order_edits', 'UPDATE')
          and not has_table_privilege('authenticated', 'public.order_edits', 'DELETE'),
  '31 authenticated: SELECT only (no INSERT / UPDATE / DELETE privilege)');
select ok(not has_table_privilege('anon', 'public.order_edits', 'SELECT')
          and not has_table_privilege('anon', 'public.order_edits', 'INSERT')
          and not has_table_privilege('anon', 'public.order_edits', 'UPDATE')
          and not has_table_privilege('anon', 'public.order_edits', 'DELETE')
          and not exists (select 1 from pg_class c, aclexplode(c.relacl) a
                           where c.oid = 'public.order_edits'::regclass
                             and a.grantee in (0, 'anon'::regrole)),
  '32 anon (and PUBLIC) hold no privilege on order_edits');

-- ===== E. sync: the CHECK, the end-to-end edit + ack, the revoked device =====
select ok((select pg_get_constraintdef(c.oid) like '%''order.edit''%'
                  and pg_get_constraintdef(c.oid) like '%''order.edit_ack''%'
             from pg_constraint c
            where c.conrelid = 'public.sync_operations'::regclass
              and c.conname = 'sync_operations_operation_type_check'),
  '33 the sync_operations CHECK admits order.edit and order.edit_ack');

-- The switch is ON (section A). Order X: Fries x2 (3000) + Cola x1 (800) =
-- 3800 -> Fries reduced to 1 -> 2300. The reduce retires the qty-2 line and
-- writes a qty-1 remainder.
create temp table t_edit as select pg_temp.push('e3ed0000-0000-0000-0000-00000000009d',
  'e3ed0000-0000-0000-0000-0000000000d1', 'surface-edit-1', 'order.edit', 'e3ed0000-0000-0000-0000-00000000a001',
  '{"reason_code": "entry_mistake",
    "expected": {"subtotal_minor": 2300, "tax_total_minor": 0, "grand_total_minor": 2300},
    "changes": [{"op": "set_quantity", "order_item_id": "e3ed0000-0000-0000-0000-0000000a1001", "quantity": 1}]}'::jsonb) as r;
select ok((select r ->> 'status' = 'applied' and (r ->> 'edit_number')::int = 1
                  and r ->> 'kitchen_channel' = 'kds' and (r ->> 'kitchen_ack_required')::boolean from t_edit),
  '34 the switch the owner turned on lets the edit apply through public.sync_push (edit 1, KDS, confirmation required)');
select ok((select count(*) = 1 and bool_and(status = 'applied' and operation_type = 'order.edit'
                  and target_id = 'e3ed0000-0000-0000-0000-00000000a001')
             from sync_operations where organization_id = 'e3ed0000-0000-0000-0000-0000000000a0'
              and local_operation_id = 'surface-edit-1')
      and (select status = 'cancelled' and removed_by_edit_id is not null and quantity = 2
             from order_items where id = 'e3ed0000-0000-0000-0000-0000000a1001')
      and (select count(*) = 1 from order_items
            where replaces_order_item_id = 'e3ed0000-0000-0000-0000-0000000a1001' and quantity = 1),
  '35 the op is ledgered applied as order.edit; the qty-2 line is retired and a qty-1 remainder written');

-- a refused edit (order.edit_denied writer) on the unedited order Y
create temp table t_deny as select pg_temp.push('e3ed0000-0000-0000-0000-00000000009d',
  'e3ed0000-0000-0000-0000-0000000000d1', 'surface-edit-deny', 'order.edit', 'e3ed0000-0000-0000-0000-00000000a002',
  '{"expected": {"subtotal_minor": 1, "tax_total_minor": 0, "grand_total_minor": 1},
    "changes": [{"op": "set_quantity", "order_item_id": "e3ed0000-0000-0000-0000-0000000a2001", "quantity": 4}]}'::jsonb) as r;
select ok((select r ->> 'status' = 'rejected' and r ->> 'error' = 'totals_mismatch' from t_deny)
      and (select edit_count = 0 and revision = 1 from orders where id = 'e3ed0000-0000-0000-0000-00000000a002'),
  '36 a refused edit is RETURNed rejected (totals_mismatch) and writes nothing to the order');

-- the kitchen's "Got it" (order.edit_acknowledged writer) and a POS ack (order.edit_ack_denied writer)
create temp table t_ack as select pg_temp.push('e3ed0000-0000-0000-0000-00000000009e',
  'e3ed0000-0000-0000-0000-0000000000d2', 'surface-ack-1', 'order.edit_ack', 'e3ed0000-0000-0000-0000-00000000a001',
  '{"up_to_edit_number": 1}'::jsonb) as r;
select ok((select r ->> 'status' = 'applied' and (r ->> 'acknowledged_count')::int = 1 from t_ack)
      and (select kitchen_ack_at is not null and kitchen_ack_device_id = 'e3ed0000-0000-0000-0000-0000000000d2'
             from order_edits where order_id = 'e3ed0000-0000-0000-0000-00000000a001'),
  '37 the KDS acknowledges edit 1 through public.sync_push (order.edit_ack)');
create temp table t_ack_deny as select pg_temp.push('e3ed0000-0000-0000-0000-00000000009d',
  'e3ed0000-0000-0000-0000-0000000000d1', 'surface-ack-pos', 'order.edit_ack', 'e3ed0000-0000-0000-0000-00000000a001',
  '{"up_to_edit_number": 1}'::jsonb) as r;
select ok((select r ->> 'status' = 'rejected' and r ->> 'error' = 'invalid_device_type' from t_ack_deny),
  '38 a POS acknowledging is refused invalid_device_type');

-- revoked device: both new ops are still ledgered + audited (revoked-path allowlist)
update device_sessions set revoked_at = now(), is_active = false where id = 'e3ed0000-0000-0000-0000-00000000005c';
create temp table t_rev as select public.sync_push('e3ed0000-0000-0000-0000-00000000009f', 'e3ed0000-0000-0000-0000-0000000000d3',
  jsonb_build_array(
    jsonb_build_object('local_operation_id', 'surface-rev-edit', 'operation_type', 'order.edit', 'target_entity', 'order',
      'target_id', 'e3ed0000-0000-0000-0000-00000000a001',
      'payload', '{"order_id": "e3ed0000-0000-0000-0000-00000000a001", "reason_code": "entry_mistake",
                   "expected": {"subtotal_minor": 800, "tax_total_minor": 0, "grand_total_minor": 800},
                   "changes": [{"op": "remove", "order_item_id": "e3ed0000-0000-0000-0000-0000000a1002"}]}'::jsonb),
    jsonb_build_object('local_operation_id', 'surface-rev-ack', 'operation_type', 'order.edit_ack', 'target_entity', 'order',
      'target_id', 'e3ed0000-0000-0000-0000-00000000a001',
      'payload', '{"order_id": "e3ed0000-0000-0000-0000-00000000a001", "up_to_edit_number": 1}'::jsonb))) as res;
select is((select string_agg(r ->> 'local_operation_id' || '=' || (r ->> 'status') || ':' || (r ->> 'error') || ':' || (r ->> 'detail'),
                             ',' order by r ->> 'local_operation_id')
             from t_rev, jsonb_array_elements(res -> 'results') r),
  'surface-rev-ack=rejected:rejected:revoked_device,surface-rev-edit=rejected:rejected:revoked_device',
  '39 a revoked till''s order.edit / order.edit_ack are rejected as revoked_device, never unknown_operation_type');
select is((select string_agg(operation_type || '=' || status || ':' || rejection_reason, ',' order by operation_type)
             from sync_operations where organization_id = 'e3ed0000-0000-0000-0000-0000000000a0'
              and local_operation_id in ('surface-rev-edit', 'surface-rev-ack')),
  'order.edit=rejected:revoked_device,order.edit_ack=rejected:revoked_device',
  '40 both are LEDGERED as rejected (revoked_device)');
select ok((select count(*) = 2 from audit_events where organization_id = 'e3ed0000-0000-0000-0000-0000000000a0'
             and action = 'sync.operation_rejected' and reason = 'revoked_device'
             and new_values ->> 'operation_type' in ('order.edit', 'order.edit_ack'))
      and (select edit_count = 1 and revision = 2 from orders where id = 'e3ed0000-0000-0000-0000-00000000a001'),
  '41 ... each audited sync.operation_rejected, and the order is untouched (edit_count 1)');

-- ===== F. order_edits RLS visibility ========================================
set local role authenticated;
set local app.current_app_user_id = 'e3ed0000-0000-0000-0000-00000000006d';  -- branch cashier of Org A
set local app.current_organization_id = 'e3ed0000-0000-0000-0000-0000000000a0';
create temp table t_rls_member as select count(*)::int as n from order_edits
  where order_id = 'e3ed0000-0000-0000-0000-00000000a001';
select throws_ok($$ insert into order_edits (organization_id, restaurant_id, branch_id, order_id, edit_number,
    device_id, local_operation_id, pin_session_id, employee_profile_id, membership_id, kitchen_channel)
  values ('e3ed0000-0000-0000-0000-0000000000a0', 'e3ed0000-0000-0000-0000-0000000000a1',
    'e3ed0000-0000-0000-0000-0000000000ab', 'e3ed0000-0000-0000-0000-00000000a002', 1,
    'e3ed0000-0000-0000-0000-0000000000d1', 'surface-forged', 'e3ed0000-0000-0000-0000-00000000009d',
    'e3ed0000-0000-0000-0000-00000000008d', 'e3ed0000-0000-0000-0000-00000000007d', 'kds') $$,
  '42501', null, '42 an authenticated client cannot INSERT an order_edits row (42501)');
set local app.current_app_user_id = 'e3ed0000-0000-0000-0000-00000000006f';  -- Org F's owner
set local app.current_organization_id = 'e3ed0000-0000-0000-0000-0000000000b0';
create temp table t_rls_other as select count(*)::int as n from order_edits;
set local app.current_organization_id = 'e3ed0000-0000-0000-0000-0000000000a0';  -- spoofed org selection
create temp table t_rls_spoof as select count(*)::int as n from order_edits;
reset role;
set local app.current_app_user_id = '';
set local app.current_organization_id = '';
select is((select n from t_rls_member), 1, '43 a member of the order''s branch sees the order_edits row');
select ok((select n = 0 from t_rls_other) and (select n = 0 from t_rls_spoof),
  '44 a member of ANOTHER organization sees nothing (also when selecting Org A''s id)');

-- ===== G. audit coverage (API §4.33) =========================================
select is((select string_agg(a || '=' || app.audit_category(a), ',' order by o)
             from unnest(array['order.edited', 'order.edit_denied', 'order.edit_acknowledged', 'order.edit_ack_denied',
                               'kitchen.dispatch_created', 'settings.branch.order_edit_updated']) with ordinality as x(a, o)),
  'order.edited=orders,order.edit_denied=orders,order.edit_acknowledged=orders,order.edit_ack_denied=orders,kitchen.dispatch_created=orders,settings.branch.order_edit_updated=settings',
  '45 app.audit_category: the four edit actions and kitchen.dispatch_created -> orders, the setter -> settings');
select ok((select bool_and(app.audit_action_has_detail(a))
             from unnest(array['order.edited', 'order.edit_denied', 'order.edit_acknowledged', 'order.edit_ack_denied',
                               'kitchen.dispatch_created', 'settings.branch.order_edit_updated']) a),
  '46 app.audit_action_has_detail is true for all six');

-- order.edited — the REAL writer payload of the edit above
create temp table t_ed as select old_values, new_values,
  app.audit_safe_detail(action, new_values) as dn, app.audit_safe_detail(action, old_values) as dold
  from audit_events where action = 'order.edited'
   and organization_id = 'e3ed0000-0000-0000-0000-0000000000a0';
select ok((select count(*) = 1 from t_ed)
      and (select new_values ? 'order_id' and new_values ? 'revision' and new_values ? 'local_operation_id'
                  and new_values ? 'order_edit_id' and new_values ? 'changes' and new_values ? 'resolved_membership_id'
             from t_ed),
  '47 the order.edited payload really carries the ids, revision, op id and changes[] (the projection has something to drop)');
select is((select dn - 'role' - 'device_type' - 'order_status' - 'kitchen_ack_required' from t_ed),
  jsonb_build_object('order_code', pg_temp.code('e3ed0000-0000-0000-0000-00000000a001'),
    'edit_number', 1, 'kitchen_channel', 'kds', 'reason_code', 'entry_mistake',
    'removed_item_count', 0, 'modified_item_count', 1, 'added_item_count', 0,
    'subtotal_minor', 2300, 'discount_total_minor', 0, 'grand_total_minor', 2300),
  '48 order.edited safe detail keeps order_code / edit_number / kitchen_channel / reason_code / counts / totals');
select ok((select not (dn ?| array['order_id', 'revision', 'local_operation_id', 'order_edit_id', 'changes',
                                   'resolved_membership_id'])
                  and dn ->> 'role' = 'cashier' and dn ->> 'device_type' = 'pos'
             from t_ed),
  '49 order.edited safe detail DROPS order_id, revision, local_operation_id, order_edit_id, changes[], resolved_membership_id');
select ok((select not (dold ?| array['order_id', 'revision']) and (dold ->> 'grand_total_minor')::bigint = 3800
             from t_ed),
  '50 order.edited old values: totals before kept (3800), order_id / revision dropped');

create temp table t_dn as select app.audit_safe_detail(action, new_values) as d
  from audit_events where action = 'order.edit_denied'
   and organization_id = 'e3ed0000-0000-0000-0000-0000000000a0';
select is((select d - 'order_status' from t_dn),
  jsonb_build_object('attempted_action', 'edit_order', 'order_code', pg_temp.code('e3ed0000-0000-0000-0000-00000000a002'),
    'role', 'cashier', 'device_type', 'pos', 'denied_reason', 'totals_mismatch'),
  '51 order.edit_denied keeps denied_reason / attempted_action / order_code / role / device_type (order_id dropped)');

create temp table t_ak as select new_values, app.audit_safe_detail(action, new_values) as d
  from audit_events where action = 'order.edit_acknowledged'
   and organization_id = 'e3ed0000-0000-0000-0000-0000000000a0';
select ok((select count(*) = 1 from t_ak)
      and (select (d ->> 'up_to_edit_number')::int = 1 and (d ->> 'acknowledged_count')::int = 1
                  and d ->> 'order_code' = pg_temp.code('e3ed0000-0000-0000-0000-00000000a001')
                  and new_values ? 'order_id' and new_values ? 'local_operation_id'
                  and not (d ?| array['order_id', 'local_operation_id', 'resolved_membership_id'])
             from t_ak),
  '52 order.edit_acknowledged keeps up_to_edit_number / acknowledged_count / order_code; ids and op id dropped');

create temp table t_akd as select app.audit_safe_detail(action, new_values) as d
  from audit_events where action = 'order.edit_ack_denied'
   and organization_id = 'e3ed0000-0000-0000-0000-0000000000a0';
select ok((select count(*) = 1 from t_akd)
      and (select d ->> 'denied_reason' = 'invalid_device_type' and d ->> 'attempted_action' = 'kitchen_ack_order_edit'
                  and d ->> 'device_type' = 'pos' and not (d ? 'order_id') from t_akd),
  '53 order.edit_ack_denied keeps denied_reason / attempted_action / device_type; order_id dropped');

select is(app.audit_safe_detail('kitchen.dispatch_created', jsonb_build_object(
            'order_code', '#00A001', 'dispatch_type', 'order_edit',
            'resolved_membership_id', 'e3ed0000-0000-0000-0000-00000000007d', 'grand_total_minor', 2300)),
  '{"order_code": "#00A001", "dispatch_type": "order_edit"}'::jsonb,
  '54 kitchen.dispatch_created (order_edit): order_code + dispatch_type only (membership id and any *_minor dropped)');
select is(app.audit_safe_detail('order.items_added', '{"order_code": "#00A001", "round_number": 2, "added_item_count": 1,
            "subtotal_minor": 500, "grand_total_minor": 500, "order_id": "e3ed0000-0000-0000-0000-00000000a001"}'::jsonb),
  '{"order_code": "#00A001", "round_number": 2, "added_item_count": 1}'::jsonb,
  '55 unchanged: order.items_added still drops every *_minor key and the id');
select ok(app.audit_safe_detail('order.voided', '{"voided_item_count": 2, "grand_total_minor": 900, "order_id": "x"}'::jsonb)
            = '{"voided_item_count": 2, "grand_total_minor": 900}'::jsonb
          and app.audit_safe_detail('order.some_unknown_action', '{"edit_number": 1}'::jsonb) = '{}'::jsonb,
  '56 unchanged: order.voided keeps its money keys; an action without detail projects nothing');

-- ===== H. readers: item counts exclude edit-retired lines =====================
set local role authenticated;
set local app.current_app_user_id = 'e3ed0000-0000-0000-0000-00000000006a';  -- org_owner
create temp table t_hist as select app.owner_order_history('e3ed0000-0000-0000-0000-0000000000a0',
  'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab', 'today') as res;
create temp table t_act as select app.owner_active_orders('e3ed0000-0000-0000-0000-0000000000a0',
  'e3ed0000-0000-0000-0000-0000000000a1', 'e3ed0000-0000-0000-0000-0000000000ab') as res;
reset role;
set local app.current_app_user_id = '';

create function pg_temp.hist_count(p_order uuid) returns int language sql as $$
  select (o ->> 'item_count')::int from t_hist, jsonb_array_elements(res -> 'orders') o
   where o ->> 'order_code' = pg_temp.code(p_order);
$$;
create function pg_temp.act_count(p_order uuid) returns int language sql as $$
  select (o ->> 'item_count')::int from t_act, jsonb_array_elements(res -> 'orders') o
   where o ->> 'order_code' = pg_temp.code(p_order);
$$;
select ok((select (res ->> 'ok')::boolean from t_hist) and (select (res ->> 'ok')::boolean from t_act),
  '57 both readers answer the owner ok');
select is(pg_temp.hist_count('e3ed0000-0000-0000-0000-00000000a001'), 2,
  '58 owner_order_history: the edited order counts LIVE quantity only (remainder 1 + cola 1; the retired qty-2 line excluded)');
select is(pg_temp.hist_count('e3ed0000-0000-0000-0000-00000000a002'), 3,
  '59 owner_order_history: an unedited order keeps its full count');
select is(pg_temp.hist_count('e3ed0000-0000-0000-0000-00000000a003'), 3,
  '60 owner_order_history: a VOIDED order keeps its full count (voided lines still counted, unchanged)');
select is(pg_temp.act_count('e3ed0000-0000-0000-0000-00000000a001'), 2,
  '61 owner_active_orders: the edited order counts LIVE quantity only');
select is(pg_temp.act_count('e3ed0000-0000-0000-0000-00000000a002'), 3,
  '62 owner_active_orders: an unedited order keeps its full count');
select is(pg_temp.act_count('e3ed0000-0000-0000-0000-00000000a003'), null,
  '63 owner_active_orders: the voided order is not active (unchanged)');
select is((select sum(quantity)::int from order_items where order_id = 'e3ed0000-0000-0000-0000-00000000a001'), 4,
  '64 control: without the provenance filter the edited order would count 4 (2 retired + 1 + 1)');

select * from finish();
rollback;
