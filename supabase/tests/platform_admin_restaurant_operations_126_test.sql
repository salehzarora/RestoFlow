-- ============================================================================
-- ADMIN-126 — pgTAP: app/public.platform_admin_restaurant_operations.
--
-- THE ASSERTION THIS FILE EXISTS FOR is group P: the number the platform
-- console shows a RestoFlow operator and the number the restaurant owner sees
-- on their own Dashboard are read out of the SAME function and compared
-- field-by-field here. If a future change makes the console compute revenue
-- itself, group P fails — which is the only durable way to keep one revenue
-- formula in a system that now has two audiences for it.
--
-- Fixture (session pinned to UTC; hex-only UUIDs; GUC-free except the identity
-- GUC the harness sets):
--   Org A  active, ILS
--     Rest A1  tz UTC, inherits ILS. TODAY: 1000 completed, 500 served,
--              700 with a 200 discount (net 500), 300 VOIDED, 400 CANCELLED,
--              250 DRAFT, 900 tombstoned. YESTERDAY: 5000.
--              => today net = 1000 + 500 + 500 = 2000 over 3 counted orders.
--     Rest A2  tz UTC, currency_override USD. TODAY: 1500 completed.
--     Owners: TWO active org_owners, ONE revoked org_owner, ONE manager,
--             ONE inactive-app_user org_owner. Only the two active ones count.
--   Org B  SUSPENDED, EUR. Rest B1, no orders at all.
--
-- Money is integer minor units throughout; nothing here is a float.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(55);

-- ===== fixture ==============================================================
insert into organizations (id, name, slug, default_currency, status) values
  ('c2000000-0000-0000-0000-0000000000a0', 'Alpha Group', 'ops126-a', 'ILS', 'active'),
  ('c2000000-0000-0000-0000-0000000000b0', 'Bravo Ltd',   'ops126-b', 'EUR', 'suspended');

insert into restaurants (id, organization_id, name, timezone, currency_override) values
  ('c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000a0', 'Alpha One', 'UTC', null),
  ('c2000000-0000-0000-0000-0000000000a2', 'c2000000-0000-0000-0000-0000000000a0', 'Alpha Two', 'UTC', 'USD'),
  ('c2000000-0000-0000-0000-0000000000b1', 'c2000000-0000-0000-0000-0000000000b0', 'Bravo One', 'UTC', null);

insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('c2000000-0000-0000-0000-0000000000c1', 'c2000000-0000-0000-0000-0000000000a0', 'c2000000-0000-0000-0000-0000000000a1', 'A1 Main', null),
  ('c2000000-0000-0000-0000-0000000000c2', 'c2000000-0000-0000-0000-0000000000a0', 'c2000000-0000-0000-0000-0000000000a2', 'A2 Main', null),
  ('c2000000-0000-0000-0000-0000000000c3', 'c2000000-0000-0000-0000-0000000000b0', 'c2000000-0000-0000-0000-0000000000b1', 'B1 Main', null);

insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('c2000000-0000-0000-0000-0000000000d1', 'c2000000-0000-0000-0000-0000000000a0', 'c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000c1', 'pos'),
  ('c2000000-0000-0000-0000-0000000000d2', 'c2000000-0000-0000-0000-0000000000a0', 'c2000000-0000-0000-0000-0000000000a2', 'c2000000-0000-0000-0000-0000000000c2', 'pos');

-- Identities. Two ACTIVE org owners, one REVOKED owner, one manager, and one
-- owner whose app_user is INACTIVE — the contact list must contain exactly the
-- first two.
insert into app_users (id, email, is_active) values
  ('c2000000-0000-0000-0000-00000000e001', 'owner.one@example.test',      true),
  ('c2000000-0000-0000-0000-00000000e002', 'owner.two@example.test',      true),
  ('c2000000-0000-0000-0000-00000000e003', 'revoked.owner@example.test',  true),
  ('c2000000-0000-0000-0000-00000000e004', 'manager@example.test',        true),
  ('c2000000-0000-0000-0000-00000000e005', 'inactive.owner@example.test', false),
  ('c2000000-0000-0000-0000-00000000e006', 'bravo.owner@example.test',    true),
  ('c2000000-0000-0000-0000-00000000adf0', 'operator@example.test',       true),
  ('c2000000-0000-0000-0000-00000000adf1', 'tenant.owner@example.test',   true);
-- app_users.auth_user_id carries an FK to auth.users, so a principal that must
-- resolve through auth.uid() needs a real auth row first.
insert into auth.users (id, email) values
  ('c2000000-0000-0000-0000-00000000adf0', 'operator@example.test'),
  ('c2000000-0000-0000-0000-00000000adf1', 'tenant.owner@example.test'),
  ('c2000000-0000-0000-0000-00000000e001', 'owner.one@example.test');
update app_users set auth_user_id = id
 where id in ('c2000000-0000-0000-0000-00000000adf0',
              'c2000000-0000-0000-0000-00000000adf1',
              'c2000000-0000-0000-0000-00000000e001');

insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, status) values
  ('c2000000-0000-0000-0000-0000000f0001', 'c2000000-0000-0000-0000-00000000e001', 'c2000000-0000-0000-0000-0000000000a0', null, null, 'org_owner', 'active'),
  ('c2000000-0000-0000-0000-0000000f0002', 'c2000000-0000-0000-0000-00000000e002', 'c2000000-0000-0000-0000-0000000000a0', null, null, 'org_owner', 'active'),
  ('c2000000-0000-0000-0000-0000000f0003', 'c2000000-0000-0000-0000-00000000e003', 'c2000000-0000-0000-0000-0000000000a0', null, null, 'org_owner', 'revoked'),
  ('c2000000-0000-0000-0000-0000000f0004', 'c2000000-0000-0000-0000-00000000e004', 'c2000000-0000-0000-0000-0000000000a0', null, null, 'manager',   'active'),
  ('c2000000-0000-0000-0000-0000000f0005', 'c2000000-0000-0000-0000-00000000e005', 'c2000000-0000-0000-0000-0000000000a0', null, null, 'org_owner', 'active'),
  ('c2000000-0000-0000-0000-0000000f0006', 'c2000000-0000-0000-0000-00000000e006', 'c2000000-0000-0000-0000-0000000000b0', null, null, 'org_owner', 'active'),
  ('c2000000-0000-0000-0000-0000000f0007', 'c2000000-0000-0000-0000-00000000adf1', 'c2000000-0000-0000-0000-0000000000a0', null, null, 'org_owner', 'active');

-- The platform operator: a grant and NO membership anywhere (D-026).
insert into platform_admin_grants (id, app_user_id, status, granted_by) values
  ('c2000000-0000-0000-0000-0000000ad001', 'c2000000-0000-0000-0000-00000000adf0', 'active',
   'c2000000-0000-0000-0000-00000000adf0');

-- The order actor chain the POS really creates. orders_actor_all_or_none makes
-- pin_session_id / opened_by_employee_profile_id / resolved_membership_id
-- all-or-none, so a billed order cannot be seeded without it.
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('c2000000-0000-0000-0000-00000000d0a1', 'c2000000-0000-0000-0000-0000000000a0', 'c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000c1', 'c2000000-0000-0000-0000-0000000000d1', 'active'),
  ('c2000000-0000-0000-0000-00000000d0a2', 'c2000000-0000-0000-0000-0000000000a0', 'c2000000-0000-0000-0000-0000000000a2', 'c2000000-0000-0000-0000-0000000000c2', 'c2000000-0000-0000-0000-0000000000d2', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('c2000000-0000-0000-0000-00000000d0b1', 'c2000000-0000-0000-0000-0000000000a0', 'c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000c1', 'c2000000-0000-0000-0000-0000000000d1', 'c2000000-0000-0000-0000-00000000d0a1'),
  ('c2000000-0000-0000-0000-00000000d0b2', 'c2000000-0000-0000-0000-0000000000a0', 'c2000000-0000-0000-0000-0000000000a2', 'c2000000-0000-0000-0000-0000000000c2', 'c2000000-0000-0000-0000-0000000000d2', 'c2000000-0000-0000-0000-00000000d0a2');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('c2000000-0000-0000-0000-0000000000ef', 'c2000000-0000-0000-0000-0000000000a0', null, null, 'c2000000-0000-0000-0000-00000000e001', 'c2000000-0000-0000-0000-0000000f0001', 'Owner One');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('c2000000-0000-0000-0000-00000000d0c1', 'c2000000-0000-0000-0000-0000000000a0', 'c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000c1', 'c2000000-0000-0000-0000-00000000d0b1', 'c2000000-0000-0000-0000-0000000000ef', 'c2000000-0000-0000-0000-0000000f0001', now() + interval '1 hour'),
  ('c2000000-0000-0000-0000-00000000d0c2', 'c2000000-0000-0000-0000-0000000000a0', 'c2000000-0000-0000-0000-0000000000a2', 'c2000000-0000-0000-0000-0000000000c2', 'c2000000-0000-0000-0000-00000000d0b2', 'c2000000-0000-0000-0000-0000000000ef', 'c2000000-0000-0000-0000-0000000f0001', now() + interval '1 hour');

-- ---- Alpha One, TODAY. net = 1000 + 500 + (700-200) = 2000 over 3 orders.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id,
                    pin_session_id, opened_by_employee_profile_id, resolved_membership_id,
                    order_type, status,
                    currency_code, subtotal_minor, discount_total_minor, tax_total_minor,
                    grand_total_minor, local_operation_id, created_at, deleted_at) values
  ('c2000000-0000-0000-0000-000000010001', 'c2000000-0000-0000-0000-0000000000a0', 'c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000c1', 'c2000000-0000-0000-0000-0000000000d1', 'c2000000-0000-0000-0000-00000000d0c1', 'c2000000-0000-0000-0000-0000000000ef', 'c2000000-0000-0000-0000-0000000f0001', 'dine_in',  'completed', 'ILS', 1000,   0, 170, 1170, 'ops126-1', (current_date + interval '10 hours') at time zone 'UTC', null),
  ('c2000000-0000-0000-0000-000000010002', 'c2000000-0000-0000-0000-0000000000a0', 'c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000c1', 'c2000000-0000-0000-0000-0000000000d1', 'c2000000-0000-0000-0000-00000000d0c1', 'c2000000-0000-0000-0000-0000000000ef', 'c2000000-0000-0000-0000-0000000f0001', 'takeaway', 'served',    'ILS',  500,   0,   0,  500, 'ops126-2', (current_date + interval '11 hours') at time zone 'UTC', null),
  ('c2000000-0000-0000-0000-000000010003', 'c2000000-0000-0000-0000-0000000000a0', 'c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000c1', 'c2000000-0000-0000-0000-0000000000d1', 'c2000000-0000-0000-0000-00000000d0c1', 'c2000000-0000-0000-0000-0000000000ef', 'c2000000-0000-0000-0000-0000000f0001', 'dine_in',  'completed', 'ILS',  700, 200,   0,  500, 'ops126-3', (current_date + interval '12 hours') at time zone 'UTC', null),
  ('c2000000-0000-0000-0000-000000010004', 'c2000000-0000-0000-0000-0000000000a0', 'c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000c1', 'c2000000-0000-0000-0000-0000000000d1', 'c2000000-0000-0000-0000-00000000d0c1', 'c2000000-0000-0000-0000-0000000000ef', 'c2000000-0000-0000-0000-0000000f0001', 'dine_in',  'voided',    'ILS',  300,   0,   0,  300, 'ops126-4', (current_date + interval '13 hours') at time zone 'UTC', null),
  ('c2000000-0000-0000-0000-000000010005', 'c2000000-0000-0000-0000-0000000000a0', 'c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000c1', 'c2000000-0000-0000-0000-0000000000d1', 'c2000000-0000-0000-0000-00000000d0c1', 'c2000000-0000-0000-0000-0000000000ef', 'c2000000-0000-0000-0000-0000000f0001', 'dine_in',  'cancelled', 'ILS',  400,   0,   0,  400, 'ops126-5', (current_date + interval '14 hours') at time zone 'UTC', null),
  ('c2000000-0000-0000-0000-000000010006', 'c2000000-0000-0000-0000-0000000000a0', 'c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000c1', 'c2000000-0000-0000-0000-0000000000d1', 'c2000000-0000-0000-0000-00000000d0c1', 'c2000000-0000-0000-0000-0000000000ef', 'c2000000-0000-0000-0000-0000000f0001', 'dine_in',  'draft',     'ILS',  250,   0,   0,  250, 'ops126-6', (current_date + interval '15 hours') at time zone 'UTC', null),
  ('c2000000-0000-0000-0000-000000010007', 'c2000000-0000-0000-0000-0000000000a0', 'c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000c1', 'c2000000-0000-0000-0000-0000000000d1', 'c2000000-0000-0000-0000-00000000d0c1', 'c2000000-0000-0000-0000-0000000000ef', 'c2000000-0000-0000-0000-0000000f0001', 'dine_in',  'completed', 'ILS',  900,   0,   0,  900, 'ops126-7', (current_date + interval '16 hours') at time zone 'UTC', now()),
  ('c2000000-0000-0000-0000-000000010008', 'c2000000-0000-0000-0000-0000000000a0', 'c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000c1', 'c2000000-0000-0000-0000-0000000000d1', 'c2000000-0000-0000-0000-00000000d0c1', 'c2000000-0000-0000-0000-0000000000ef', 'c2000000-0000-0000-0000-0000000f0001', 'dine_in',  'completed', 'ILS', 5000,   0,   0, 5000, 'ops126-8', (current_date - 1 + interval '12 hours') at time zone 'UTC', null);

-- ---- Alpha Two, TODAY: 1500 in its OVERRIDDEN currency (USD).
insert into orders (id, organization_id, restaurant_id, branch_id, device_id,
                    pin_session_id, opened_by_employee_profile_id, resolved_membership_id,
                    order_type, status,
                    currency_code, subtotal_minor, discount_total_minor, tax_total_minor,
                    grand_total_minor, local_operation_id, created_at) values
  ('c2000000-0000-0000-0000-000000020001', 'c2000000-0000-0000-0000-0000000000a0', 'c2000000-0000-0000-0000-0000000000a2', 'c2000000-0000-0000-0000-0000000000c2', 'c2000000-0000-0000-0000-0000000000d2', 'c2000000-0000-0000-0000-00000000d0c2', 'c2000000-0000-0000-0000-0000000000ef', 'c2000000-0000-0000-0000-0000000f0001', 'dine_in', 'completed', 'USD', 1500, 0, 0, 1500, 'ops126-9', (current_date + interval '10 hours') at time zone 'UTC');

-- ===== the platform read ====================================================
set local role authenticated;
set local request.jwt.claim.sub = 'c2000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"c2000000-0000-0000-0000-00000000adf0","aal":"aal2"}';

create temp table ops as select public.platform_admin_restaurant_operations(
  'RestoFlow admin: restaurant operations (read-only)', 50, 0) as res;

create temp table ops_a1 as
  select r as row
    from ops, lateral jsonb_array_elements(res -> 'rows') r
   where r ->> 'restaurant_name' = 'Alpha One';

-- The OWNER's own view of the very same restaurant, through the tenant path.
reset role;
set local role authenticated;
set local request.jwt.claim.sub = 'c2000000-0000-0000-0000-00000000e001';
set local request.jwt.claims = '{"sub":"c2000000-0000-0000-0000-00000000e001","aal":"aal1"}';
create temp table tenant_a1 as select app.owner_report_range(
  'c2000000-0000-0000-0000-0000000000a0', 'c2000000-0000-0000-0000-0000000000a1', null, 'today') as res;
reset role;

-- ===========================================================================
-- P. REVENUE PARITY — the reason this file exists
-- ===========================================================================
select is(
  (select (row ->> 'today_revenue_minor')::bigint from ops_a1),
  (select (res -> 'current' ->> 'net_minor')::bigint from tenant_a1),
  'P1. platform revenue == the OWNER''S OWN Dashboard revenue, same restaurant, same day');
select is(
  (select (row ->> 'today_orders_count')::bigint from ops_a1),
  (select (res -> 'current' ->> 'order_count')::bigint from tenant_a1),
  'P2. platform order count == the owner''s order count');
select is(
  (select row ->> 'currency_code' from ops_a1),
  (select res ->> 'currency_code' from tenant_a1),
  'P3. platform currency == the owner''s currency');
select is(
  (select row ->> 'reporting_date' from ops_a1),
  (select res ->> 'range_end' from tenant_a1),
  'P4. platform reporting date == the owner''s report day');
select is((select (row ->> 'today_revenue_minor')::bigint from ops_a1), 2000::bigint,
  'P5. and that shared number is the hand-computed 1000 + 500 + (700-200)');
select is((select (row ->> 'today_orders_count')::bigint from ops_a1), 3::bigint,
  'P6. over exactly three counted orders');

-- ===========================================================================
-- A. REVENUE SEMANTICS — what the shared formula does and does not count
-- ===========================================================================
select ok((select (row ->> 'today_revenue_minor')::bigint from ops_a1) < 2300,
  'A1. the VOIDED 300 order is excluded');
select ok((select (row ->> 'today_revenue_minor')::bigint from ops_a1) < 2400,
  'A2. the CANCELLED 400 order is excluded');
select ok((select (row ->> 'today_revenue_minor')::bigint from ops_a1) < 2250,
  'A3. the DRAFT 250 order is excluded');
select ok((select (row ->> 'today_revenue_minor')::bigint from ops_a1) < 2900,
  'A4. the TOMBSTONED 900 order is excluded');
select ok((select (row ->> 'today_revenue_minor')::bigint from ops_a1) < 7000,
  'A5. YESTERDAY''S 5000 is not in today''s figure');
select is((select (row ->> 'today_revenue_minor')::bigint from ops_a1), 2000::bigint,
  'A6. the 200 discount is netted off (700 contributes 500, not 700)');
-- Tax: order 1 carries 170 tax on a 1000 subtotal. The headline is NET OF
-- DISCOUNT and EXCLUDES TAX, so 170 must not appear.
select ok((select (row ->> 'today_revenue_minor')::bigint from ops_a1) <> 2170,
  'A7. tax is not added on top — the figure is subtotal-minus-discount (this fixture uses exclusive tax), not grand total');

-- ===========================================================================
-- B. CURRENCY — effective per restaurant, and NEVER summed across currencies
-- ===========================================================================
select is(
  (select r ->> 'currency_code' from ops, lateral jsonb_array_elements(res -> 'rows') r
    where r ->> 'restaurant_name' = 'Alpha Two'),
  'USD', 'B1. a restaurant''s currency_override wins over the organization default');
select is((select row ->> 'currency_code' from ops_a1), 'ILS',
  'B2. a restaurant without an override inherits the organization currency');
select is(
  (select array(select (t ->> 'currency_code') from ops, lateral jsonb_array_elements(res -> 'totals_by_currency') t order by 1)),
  array['EUR', 'ILS', 'USD'],
  'B3. totals are GROUPED BY CURRENCY');
select is(
  (select (t ->> 'today_revenue_minor')::bigint from ops, lateral jsonb_array_elements(res -> 'totals_by_currency') t where t ->> 'currency_code' = 'ILS'),
  2000::bigint, 'B4. the ILS total is the ILS restaurants only');
select is(
  (select (t ->> 'today_revenue_minor')::bigint from ops, lateral jsonb_array_elements(res -> 'totals_by_currency') t where t ->> 'currency_code' = 'USD'),
  1500::bigint, 'B5. the USD total is the USD restaurant only');
select ok(
  (select not (res ? 'total_revenue_minor' or res ? 'today_revenue_minor') from ops),
  'B6. there is NO cross-currency grand total — adding ILS to USD is wrong in both');

-- ===========================================================================
-- C. OWNER CONTACTS — the signatory, and nobody else
-- ===========================================================================
select is(
  (select array(select jsonb_array_elements_text(row -> 'owner_contacts') order by 1) from ops_a1),
  array['owner.one@example.test', 'owner.two@example.test', 'tenant.owner@example.test'],
  'C1. every ACTIVE org_owner email is returned');
select ok(
  (select not exists (select 1 from ops_a1 where (row -> 'owner_contacts')::text like '%revoked.owner%')),
  'C2. a REVOKED org_owner is excluded');
select ok(
  (select not exists (select 1 from ops_a1 where (row -> 'owner_contacts')::text like '%manager@%')),
  'C3. a MANAGER is not a contact — only the organization owner is');
select ok(
  (select not exists (select 1 from ops_a1 where (row -> 'owner_contacts')::text like '%inactive.owner%')),
  'C4. an org_owner whose app_user is INACTIVE is excluded');
select ok(
  (select not (res::text like '%operator@example.test%') from ops),
  'C5. the platform operator''s own email never leaks into tenant contact data');
select is(
  (select jsonb_array_length(r -> 'owner_contacts') from ops, lateral jsonb_array_elements(res -> 'rows') r
    where r ->> 'restaurant_name' = 'Bravo One'),
  1, 'C6. a different organization gets ITS own owner, not Alpha''s');

-- ===========================================================================
-- D. PROJECTION — no unrelated PII and no order detail
-- ===========================================================================
select is(
  (select array(select jsonb_object_keys(row) order by 1) from ops_a1),
  array['branches_count', 'currency_code', 'organization_id', 'organization_name',
        'organization_status', 'owner_contacts', 'reporting_date', 'restaurant_id',
        'restaurant_name', 'restaurant_status', 'today_orders_count', 'today_revenue_minor'],
  'D1. exact row projection — nothing more');
select ok((select res::text not like '%local_operation_id%' from ops),
  'D2. no order identifiers');
select ok((select res::text not like '%ops126-%' from ops),
  'D3. no per-order detail of any kind');
select ok((select res::text not like '%pin_session%' and res::text not like '%device_id%' from ops),
  'D4. no device or PIN-session data');

-- ===========================================================================
-- E. FILTERS, SORTS, PAGING
-- ===========================================================================
set local role authenticated;
set local request.jwt.claim.sub = 'c2000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"c2000000-0000-0000-0000-00000000adf0","aal":"aal2"}';

select is((select (res ->> 'total_count')::int from ops), 3, 'E1. all three live restaurants');
select is(
  ((public.platform_admin_restaurant_operations('r', 50, 0, null, 'suspended')) ->> 'total_count')::int,
  1, 'E2. the organization-status filter narrows to the suspended tenant');
select is(
  ((public.platform_admin_restaurant_operations('r', 50, 0, 'Alpha')) ->> 'total_count')::int,
  2, 'E3. search matches the organization name across its restaurants');
select is(
  ((public.platform_admin_restaurant_operations('r', 50, 0, 'Bravo One')) ->> 'total_count')::int,
  1, 'E4. search also matches a restaurant name');
select is(
  (public.platform_admin_restaurant_operations('r', 50, 0, null, null, 'sales_desc') -> 'rows' -> 0 ->> 'restaurant_name'),
  'Alpha One', 'E5. sales_desc puts the highest-selling restaurant first');
select is(
  (public.platform_admin_restaurant_operations('r', 50, 0, null, null, 'sales_asc') -> 'rows' -> 0 ->> 'today_revenue_minor'),
  '0', 'E6. sales_asc puts a restaurant with no sales first');
select is(
  (public.platform_admin_restaurant_operations('r', 50, 0, null, null, 'orders_desc') -> 'rows' -> 0 ->> 'restaurant_name'),
  'Alpha One', 'E7. orders_desc ranks by order count');
select is(
  ((public.platform_admin_restaurant_operations('r', 50, 0, null, null, 'name_asc', true)) ->> 'total_count')::int,
  2, 'E8. with_sales=true keeps only restaurants that took money today');
select is(
  ((public.platform_admin_restaurant_operations('r', 50, 0, null, null, 'name_asc', false)) ->> 'total_count')::int,
  1, 'E9. with_sales=false keeps only the quiet ones');
select is(
  jsonb_array_length(public.platform_admin_restaurant_operations('r', 2, 0) -> 'rows'),
  2, 'E10. the page size is honoured');
select is(
  ((public.platform_admin_restaurant_operations('r', 2, 2)) ->> 'offset')::int,
  2, 'E11. the offset is echoed for the pager');
select is(
  ((public.platform_admin_restaurant_operations('r', 9999, 0)) ->> 'limit')::int,
  200, 'E12. the page size is clamped');
select throws_ok(
  $$ select public.platform_admin_restaurant_operations('r', 50, 0, null, null, 'nope') $$,
  '22023', NULL, 'E13. an unknown sort is a bad request, not a silent default');
select throws_ok(
  $$ select public.platform_admin_restaurant_operations('r', 50, 0, null, 'nope') $$,
  '22023', NULL, 'E14. an unknown organization status is refused');
reset role;

-- ===========================================================================
-- F. ACCESS CONTROL
-- ===========================================================================
select throws_ok(
  $$ select public.platform_admin_restaurant_operations('   ') $$,
  '42501', NULL, 'F1. a blank reason is refused — platform reads are reason-tagged');

set local role authenticated;
set local request.jwt.claim.sub = 'c2000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"c2000000-0000-0000-0000-00000000adf0","aal":"aal1"}';
select throws_ok(
  $$ select public.platform_admin_restaurant_operations('probe') $$,
  '42501', NULL, 'F2. a platform admin WITHOUT aal2 is refused');
reset role;

set local role authenticated;
set local request.jwt.claim.sub = 'c2000000-0000-0000-0000-00000000adf1';
set local request.jwt.claims = '{"sub":"c2000000-0000-0000-0000-00000000adf1","aal":"aal2"}';
select throws_ok(
  $$ select public.platform_admin_restaurant_operations('probe') $$,
  '42501', NULL, 'F3. an ORG OWNER with aal2 is refused — a membership is never platform access');
-- And the tenant path is unchanged for that same owner: they still read their
-- own restaurant exactly as before this migration.
select is(
  (app.owner_report_range('c2000000-0000-0000-0000-0000000000a0', 'c2000000-0000-0000-0000-0000000000a1', null, 'today') -> 'current' ->> 'net_minor')::bigint,
  2000::bigint, 'F4. the OWNER''S OWN report still works — the tenant gate is untouched');
-- The platform branch must not be reachable by setting the marker: the grant
-- and aal2 are the real boundary.
select set_config('app.platform_report_read', 'on', true) is not null as _;
select throws_ok(
  $$ select app.owner_report_range('c2000000-0000-0000-0000-0000000000b0', 'c2000000-0000-0000-0000-0000000000b1', null, 'today') $$,
  '42501', NULL,
  'F5. a tenant who forges the platform marker STILL cannot read another tenant');
select set_config('app.platform_report_read', '', true) is not null as _;
reset role;

set local role anon;
select throws_ok(
  $$ select public.platform_admin_restaurant_operations('probe') $$,
  '42501', NULL, 'F6. anon is refused');
reset role;

select ok(not has_function_privilege('anon', 'public.platform_admin_restaurant_operations(text,integer,integer,text,text,text,boolean)', 'EXECUTE'),
  'F7. anon holds no EXECUTE on the wrapper (explicitly revoked, not merely absent)');
select ok(not has_schema_privilege('anon', 'app', 'USAGE'),
  'F8. and anon cannot reach schema app at all');
select ok(has_function_privilege('authenticated', 'public.platform_admin_restaurant_operations(text,integer,integer,text,text,text,boolean)', 'EXECUTE'),
  'F9. authenticated holds EXECUTE on the wrapper');
select ok(has_function_privilege('authenticated', 'app.platform_admin_restaurant_operations(text,integer,integer,text,text,text,boolean)', 'EXECUTE'),
  'F10. and on the inner function — a wrapper-only grant would 42501 (REPORT-123)');

-- ===========================================================================
-- G. AUDIT
-- ===========================================================================
select is(
  (select count(*)::int from platform_admin_audit_events
    where action = 'platform.restaurant.operations.read'
      and reason = 'RestoFlow admin: restaurant operations (read-only)'),
  1, 'G1. the console read is audited under its own action and reason');
select is(
  (select actor_app_user_id from platform_admin_audit_events
    where action = 'platform.restaurant.operations.read'
      and reason = 'RestoFlow admin: restaurant operations (read-only)'),
  'c2000000-0000-0000-0000-00000000adf0'::uuid,
  'G2. attributed to the PLATFORM operator, never to a tenant');

select * from finish();
rollback;
