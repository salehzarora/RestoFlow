-- ============================================================================
-- RF-052 — pgTAP: order.submitted audit event (RF052-B1, D-013)
-- ============================================================================
-- A successful app.submit_order writes exactly ONE append-only audit_events row
-- (action order.submitted) scoped to the resolved tenant context, with the submit
-- snapshot summary in new_values. A clean idempotency replay writes NO second
-- audit row. The RF-017 append-only guarantee is untouched (no UPDATE/DELETE
-- grant added; the audit row cannot be updated/deleted). Fixtures inserted as the
-- BYPASSRLS connection role; the RPC is SECURITY DEFINER.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(25);

-- ---- valid PIN-session chain (cashier on a paired+active device) -----------
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf052au-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee0a', 'rf052au@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');

-- ---- submit: 2 x 500 + modifier 100 => subtotal/grand 1100 -----------------
select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1',
  '00000000-0000-0000-0000-00000000da11','op-audit','takeaway','00000000-0000-0000-0000-0000000ab1e1','00000000-0000-0000-0000-0000000585f1','USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":2,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Burger","modifiers":[{"modifier_option_id":"00000000-0000-0000-0000-0000000000f2","price_minor_snapshot":100,"quantity":1,"option_name_snapshot":"Extra"}]}]'::jsonb,
  1100, 0, 0, 1100, null);

-- exactly one audit row, action order.submitted ------------------------------ 1-2
select is((select count(*) from audit_events)::int, 1, 'submit_order wrote exactly one audit_events row');
select is((select action from audit_events)::text, 'order.submitted', 'audit action is order.submitted');

-- tenant context + device + actor -------------------------------------------- 3-7
select is((select organization_id from audit_events), '00000000-0000-0000-0000-0000000000a0'::uuid, 'audit organization_id = resolved org');
select is((select restaurant_id  from audit_events), '00000000-0000-0000-0000-0000000000a1'::uuid, 'audit restaurant_id = resolved restaurant');
select is((select branch_id      from audit_events), '00000000-0000-0000-0000-00000000a1b1'::uuid, 'audit branch_id = resolved branch');
select is((select device_id      from audit_events), '00000000-0000-0000-0000-00000000da11'::uuid, 'audit device_id = p_device_id');
select is((select actor_employee_profile_id from audit_events), '00000000-0000-0000-0000-0000000ef001'::uuid, 'audit actor_employee_profile_id = resolved employee (RF-017 actor present)');

-- new_values carries the submit snapshot summary ----------------------------- 8-13
select is((select new_values ->> 'order_id'             from audit_events), '00000000-0000-0000-0000-00000000a0d1', 'new_values.order_id');
select is((select (new_values ->> 'revision')::int      from audit_events), 1,        'new_values.revision');
select is((select new_values ->> 'currency_code'        from audit_events), 'USD',    'new_values.currency_code');
select is((select (new_values ->> 'subtotal_minor')::bigint     from audit_events), 1100::bigint, 'new_values.subtotal_minor');
select is((select (new_values ->> 'grand_total_minor')::bigint  from audit_events), 1100::bigint, 'new_values.grand_total_minor');
select is((select new_values ->> 'local_operation_id'   from audit_events), 'op-audit', 'new_values.local_operation_id');

-- new_values contains ALL 16 expected keys ----------------------------------- 14
select ok(
  (select new_values ?& array[
    'order_id','status','revision','currency_code','subtotal_minor','discount_total_minor',
    'tax_total_minor','grand_total_minor','device_id','local_operation_id','order_type',
    'table_id','shift_id','resolved_membership_id','item_count','modifier_count']
   from audit_events),
  'new_values contains all 16 expected keys');

-- and each remaining key carries the correct value --------------------------- 15-24
select is((select new_values ->> 'status'                      from audit_events), 'submitted',  'new_values.status');
select is((select (new_values ->> 'discount_total_minor')::bigint from audit_events), 0::bigint, 'new_values.discount_total_minor');
select is((select (new_values ->> 'tax_total_minor')::bigint    from audit_events), 0::bigint,    'new_values.tax_total_minor');
select is((select new_values ->> 'device_id'                   from audit_events), '00000000-0000-0000-0000-00000000da11', 'new_values.device_id');
select is((select new_values ->> 'order_type'                  from audit_events), 'takeaway',   'new_values.order_type');
select is((select new_values ->> 'table_id'                    from audit_events), '00000000-0000-0000-0000-0000000ab1e1', 'new_values.table_id');
select is((select new_values ->> 'shift_id'                    from audit_events), '00000000-0000-0000-0000-0000000585f1', 'new_values.shift_id');
select is((select new_values ->> 'resolved_membership_id'      from audit_events), '00000000-0000-0000-0000-00000000ab01', 'new_values.resolved_membership_id');
select is((select (new_values ->> 'item_count')::int           from audit_events), 1, 'new_values.item_count');
select is((select (new_values ->> 'modifier_count')::int       from audit_events), 1, 'new_values.modifier_count');

-- idempotent replay writes NO second audit row ------------------------------- 25
select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1',
  '00000000-0000-0000-0000-00000000da11','op-audit','takeaway','00000000-0000-0000-0000-0000000ab1e1','00000000-0000-0000-0000-0000000585f1','USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":2,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Burger","modifiers":[{"modifier_option_id":"00000000-0000-0000-0000-0000000000f2","price_minor_snapshot":100,"quantity":1,"option_name_snapshot":"Extra"}]}]'::jsonb,
  1100, 0, 0, 1100, null);
select is((select count(*) from audit_events)::int, 1, 'a clean idempotency replay does NOT write a second audit_events row');

select * from finish();
rollback;
