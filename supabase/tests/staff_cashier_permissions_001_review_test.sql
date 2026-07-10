-- ============================================================================
-- STAFF-CASHIER-PERMISSIONS-001 (Codex CHANGES-REQUESTED correction) — pgTAP
-- ============================================================================
-- Covers the correction findings:
--   * resolver fail-closed on every malformed permissions shape/value
--   * strict fail-closed create_staff_member p_capabilities validation (jsonb_each)
--   * legacy idempotency fingerprint replay (no capabilities appended for {})
--   * full-comp (100% / zero-out) discount manager gate (order + item)
--   * set_staff_capabilities membership-derived scope auth + scoped UPDATE +
--     no-oracle unified error + old/new audit payload
-- Fixtures as the BYPASSRLS connection role; PIN RPCs read the actor from the
-- session, management RPCs from app.current_app_user_id() (GUC test path).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(52);

-- ---- tenants + scopes ----------------------------------------------------
insert into organizations (id, name, slug, default_currency) values
  ('ea000000-0000-0000-0000-0000000000a0','Org A','scp-rev-a','USD'),
  ('eb000000-0000-0000-0000-0000000000b0','Org B','scp-rev-b','USD');
insert into restaurants (id, organization_id, name) values
  ('ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-0000000000a0','RA1'),
  ('eb000000-0000-0000-0000-0000000000b1','eb000000-0000-0000-0000-0000000000b0','RB1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('ea000000-0000-0000-0000-00000000a1b1','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','Branch A'),
  ('ea000000-0000-0000-0000-00000000a1b2','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','Branch B'),
  ('eb000000-0000-0000-0000-00000000b1b1','eb000000-0000-0000-0000-0000000000b0','eb000000-0000-0000-0000-0000000000b1','Branch BB');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('ea000000-0000-0000-0000-0000000d0a11','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b1','pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('ea000000-0000-0000-0000-0000000f0a11','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b1','ea000000-0000-0000-0000-0000000d0a11','active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('ea000000-0000-0000-0000-0000000500a1','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b1','ea000000-0000-0000-0000-0000000d0a11','ea000000-0000-0000-0000-0000000f0a11');
insert into app_users (id, email) values
  ('ea000000-0000-0000-0000-0000000000e1','rev-owner@x.test'),
  ('ea000000-0000-0000-0000-0000000000e2','rev-mgra@x.test'),
  ('ea000000-0000-0000-0000-0000000000e3','rev-cash-def@x.test'),
  ('ea000000-0000-0000-0000-0000000000e4','rev-cash-deny@x.test'),
  ('ea000000-0000-0000-0000-0000000000e6','rev-cash-b@x.test'),
  ('eb000000-0000-0000-0000-0000000000e1','rev-ownerb@x.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('ea000000-0000-0000-0000-00000000ab01','ea000000-0000-0000-0000-0000000000e1','ea000000-0000-0000-0000-0000000000a0',null,null,'org_owner','{}'::jsonb),
  ('ea000000-0000-0000-0000-00000000ab02','ea000000-0000-0000-0000-0000000000e2','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b1','manager','{}'::jsonb),
  ('ea000000-0000-0000-0000-00000000ab03','ea000000-0000-0000-0000-0000000000e3','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b1','cashier','{}'::jsonb),
  ('ea000000-0000-0000-0000-00000000ab04','ea000000-0000-0000-0000-0000000000e4','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b1','cashier','{"apply_discount":"false","void_order":"false"}'::jsonb),
  ('ea000000-0000-0000-0000-00000000ab06','ea000000-0000-0000-0000-0000000000e6','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b2','cashier','{}'::jsonb),
  ('eb000000-0000-0000-0000-00000000bb01','eb000000-0000-0000-0000-0000000000e1','eb000000-0000-0000-0000-0000000000b0','eb000000-0000-0000-0000-0000000000b1','eb000000-0000-0000-0000-00000000b1b1','org_owner','{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('ea000000-0000-0000-0000-00000000ef03','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b1','ea000000-0000-0000-0000-0000000000e3','ea000000-0000-0000-0000-00000000ab03','Def Cashier'),
  ('ea000000-0000-0000-0000-00000000ef04','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b1','ea000000-0000-0000-0000-0000000000e4','ea000000-0000-0000-0000-00000000ab04','Deny Cashier'),
  ('ea000000-0000-0000-0000-00000000ef02','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b1','ea000000-0000-0000-0000-0000000000e2','ea000000-0000-0000-0000-00000000ab02','Mgr A'),
  ('ea000000-0000-0000-0000-00000000ef06','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b2','ea000000-0000-0000-0000-0000000000e6','ea000000-0000-0000-0000-00000000ab06','Cashier B'),
  -- forged EP: scoped to Branch A but pointing at the Branch-B cashier membership.
  ('ea000000-0000-0000-0000-00000000ef09','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b1','ea000000-0000-0000-0000-0000000000e6','ea000000-0000-0000-0000-00000000ab06','Forged EP'),
  -- mismatch EP: app_user (e2/MgrA) does NOT match its membership's app_user (e3).
  ('ea000000-0000-0000-0000-00000000ef10','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b1','ea000000-0000-0000-0000-0000000000e2','ea000000-0000-0000-0000-00000000ab03','Mismatch EP');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('ea000000-0000-0000-0000-00000000c503','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b1','ea000000-0000-0000-0000-0000000500a1','ea000000-0000-0000-0000-00000000ef03','ea000000-0000-0000-0000-00000000ab03', now()+interval '1 hour'),
  ('ea000000-0000-0000-0000-00000000c504','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b1','ea000000-0000-0000-0000-0000000500a1','ea000000-0000-0000-0000-00000000ef04','ea000000-0000-0000-0000-00000000ab04', now()+interval '1 hour'),
  ('ea000000-0000-0000-0000-00000000c502','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b1','ea000000-0000-0000-0000-0000000500a1','ea000000-0000-0000-0000-00000000ef02','ea000000-0000-0000-0000-00000000ab02', now()+interval '1 hour');
-- two submitted orders (subtotal 1000, one item each) for discount tests.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id) values
  ('ea000000-0000-0000-0000-00000000a0d1','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b1','ea000000-0000-0000-0000-0000000d0a11','ea000000-0000-0000-0000-00000000c503','ea000000-0000-0000-0000-00000000ef03','ea000000-0000-0000-0000-00000000ab03','dine_in','submitted','USD',1000,0,0,1000,'od1'),
  ('ea000000-0000-0000-0000-00000000a0d2','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b1','ea000000-0000-0000-0000-0000000d0a11','ea000000-0000-0000-0000-00000000c503','ea000000-0000-0000-0000-00000000ef03','ea000000-0000-0000-0000-00000000ab03','dine_in','submitted','USD',1000,0,0,1000,'od2');
insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id, quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor) values
  ('ea000000-0000-0000-0000-00000000a1e2','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b1','ea000000-0000-0000-0000-00000000a0d2','ea000000-0000-0000-0000-0000000000f1',1,'Item',1000,1000);

-- ===== A. Resolver fail-closed (direct) ==================================== 1-13
select ok(app.cashier_capability_allowed('cashier','{}'::jsonb,'apply_discount'),                     'A1 default cashier: absent key => allowed');
select ok(not app.cashier_capability_allowed('cashier','{"void_order":"false"}'::jsonb,'void_order'), 'A2 present "false" => deny');
select ok(not app.cashier_capability_allowed('cashier','{"void_order":"true"}'::jsonb,'void_order'),  'A3 present "true" => deny (fail-closed)');
select ok(not app.cashier_capability_allowed('cashier','{"void_order":false}'::jsonb,'void_order'),   'A4 present boolean false => deny');
select ok(not app.cashier_capability_allowed('cashier','{"void_order":null}'::jsonb,'void_order'),    'A5 present JSON null => deny');
select ok(not app.cashier_capability_allowed('cashier','{"void_order":0}'::jsonb,'void_order'),       'A6 present number => deny');
select ok(not app.cashier_capability_allowed('cashier','{"void_order":[]}'::jsonb,'void_order'),      'A7 present array value => deny');
select ok(not app.cashier_capability_allowed('cashier','[]'::jsonb,'void_order'),                     'A8 array root => deny');
select ok(not app.cashier_capability_allowed('cashier','"x"'::jsonb,'void_order'),                    'A9 scalar root => deny');
select ok(not app.cashier_capability_allowed('cashier','null'::jsonb,'void_order'),                   'A10 JSON null root => deny');
select ok(not app.cashier_capability_allowed('cashier',null,'void_order'),                            'A11 SQL NULL => deny');
select ok(not app.cashier_capability_allowed('manager','{}'::jsonb,'void_order'),                     'A12 non-cashier => deny');
select ok(not app.cashier_capability_allowed('cashier','{}'::jsonb,'refund'),                         'A13 unrelated capability => deny');

-- ===== B. Strict create_staff_member p_capabilities validation ============ 14-27
set local app.current_app_user_id = 'ea000000-0000-0000-0000-0000000000e1';   -- org owner
create or replace function pg_temp.badcap(p jsonb) returns text language plpgsql as $f$
begin
  perform app.create_staff_member(gen_random_uuid(),'ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b1','Rej '||md5(coalesce(p::text,'x')),'cashier',p);
  return 'CREATED';
exception when sqlstate '42501' then return '42501';
end; $f$;
select is(pg_temp.badcap('{"void_order":false}'::jsonb),  '42501', 'B1 boolean false rejected');
select is(pg_temp.badcap('{"void_order":null}'::jsonb),   '42501', 'B2 JSON null value rejected');
select is(pg_temp.badcap('{"void_order":true}'::jsonb),   '42501', 'B3 boolean true rejected');
select is(pg_temp.badcap('{"void_order":"true"}'::jsonb), '42501', 'B4 string "true" rejected');
select is(pg_temp.badcap('{"void_order":0}'::jsonb),      '42501', 'B5 number rejected');
select is(pg_temp.badcap('{"void_order":[]}'::jsonb),     '42501', 'B6 array value rejected');
select is(pg_temp.badcap('{"void_order":{}}'::jsonb),     '42501', 'B7 nested object rejected');
select is(pg_temp.badcap('{"refund":"false"}'::jsonb),    '42501', 'B8 unknown key rejected');
select is(pg_temp.badcap('{"void_order":"false","refund":"false"}'::jsonb), '42501', 'B9 mixed valid+invalid rejected');
select is(pg_temp.badcap('[]'::jsonb),                    '42501', 'B10 array root rejected');
select is(pg_temp.badcap('"false"'::jsonb),               '42501', 'B11 scalar root rejected');
select is(pg_temp.badcap('null'::jsonb),                  '42501', 'B12 JSON null root rejected');
select is((select count(*)::int from employee_profiles where display_name like 'Rej %'), 0, 'B13 no rejected create left ANY staff row (atomic rollback)');
select is((app.create_staff_member(gen_random_uuid(),'ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b1','Valid Multi','cashier','{"apply_discount":"false","void_order":"false"}'::jsonb) ->> 'ok')::boolean, true, 'B14 valid deny-only object accepted');

-- ===== C. Legacy idempotency fingerprint (no capabilities appended for {}) = 28-30
select app.create_staff_member('ea000000-0000-0000-0000-0000000c1d01','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b1','Legacy One','cashier');
select is(
  (select request_fingerprint from management_request_results where client_request_id='ea000000-0000-0000-0000-0000000c1d01'),
  md5(jsonb_build_object('org','ea000000-0000-0000-0000-0000000000a0','restaurant','ea000000-0000-0000-0000-0000000000a1','branch','ea000000-0000-0000-0000-00000000a1b1','display_name','Legacy One','role','cashier')::text),
  'C1 no-deny create uses the EXACT legacy fingerprint (no capabilities appended)');
select is((app.create_staff_member('ea000000-0000-0000-0000-0000000c1d01','ea000000-0000-0000-0000-0000000000a0','ea000000-0000-0000-0000-0000000000a1','ea000000-0000-0000-0000-00000000a1b1','Legacy One','cashier') ->> 'idempotent_replay')::boolean,
  true, 'C2 retry with the same request id + no caps REPLAYS (idempotent)');
select is((select count(*)::int from employee_profiles where display_name='Legacy One'), 1, 'C3 the retried legacy create made NO duplicate');

-- ===== D. set_staff_capabilities scope + oracle + audit ==================== 31-42
-- manager A covers Branch A -> may edit the Branch-A default cashier.
set local app.current_app_user_id = 'ea000000-0000-0000-0000-0000000000e2';
select is((app.set_staff_capabilities(gen_random_uuid(),'ea000000-0000-0000-0000-00000000ef03', true, false, true) ->> 'ok')::boolean, true, 'D1 branch manager edits a cashier in its OWN covered branch');
-- manager A does NOT cover Branch B -> cannot edit the legit Branch-B cashier.
select throws_ok($$ select app.set_staff_capabilities(gen_random_uuid(),'ea000000-0000-0000-0000-00000000ef06', true, false, true) $$, '42501', NULL, 'D2 branch manager cannot edit a SIBLING branch cashier');
-- FORGED EP (branch A profile -> branch B membership): scope now derives from the
-- MEMBERSHIP (branch B) -> manager A is rejected AND the B membership is untouched.
select throws_ok($$ select app.set_staff_capabilities(gen_random_uuid(),'ea000000-0000-0000-0000-00000000ef09', true, false, true) $$, '42501', NULL, 'D3 forged profile->foreign-membership is rejected (scope from membership)');
select is((select permissions from memberships where id='ea000000-0000-0000-0000-00000000ab06'), '{}'::jsonb, 'D4 the Branch-B membership was NOT mutated by the forged edit');
-- app_user mismatch (ep.app_user_id <> m.app_user_id) -> join fails -> 42501.
set local app.current_app_user_id = 'ea000000-0000-0000-0000-0000000000e1';   -- org owner (would otherwise cover)
select throws_ok($$ select app.set_staff_capabilities(gen_random_uuid(),'ea000000-0000-0000-0000-00000000ef10', true, false, true) $$, '42501', NULL, 'D5 profile/membership app_user mismatch is rejected');
-- org owner may edit the Branch-B cashier (legitimate coverage).
select is((app.set_staff_capabilities(gen_random_uuid(),'ea000000-0000-0000-0000-00000000ef06', true, true, false) ->> 'ok')::boolean, true, 'D6 org owner edits a Branch-B cashier (coverage hierarchy preserved)');
-- ORACLE: manager A probing nonexistent / cross-tenant / sibling-branch / forged /
-- mismatch targets must all yield the IDENTICAL sqlstate + message.
set local app.current_app_user_id = 'ea000000-0000-0000-0000-0000000000e2';
create or replace function pg_temp.errof(emp uuid) returns text language plpgsql as $f$
begin
  perform app.set_staff_capabilities(gen_random_uuid(), emp, true, false, true);
  return 'OK';
exception when others then return sqlstate || '|' || sqlerrm;
end; $f$;
select is(pg_temp.errof('ea000000-0000-0000-0000-0000000dead1'::uuid),                pg_temp.errof('ea000000-0000-0000-0000-00000000ef06'::uuid), 'D7 nonexistent target == sibling-branch target (same error)');
select is(pg_temp.errof('ea000000-0000-0000-0000-00000000ef06'::uuid),                pg_temp.errof('ea000000-0000-0000-0000-00000000ef09'::uuid), 'D8 sibling-branch == forged (same error)');
select is(pg_temp.errof('ea000000-0000-0000-0000-00000000ef10'::uuid),                pg_temp.errof('ea000000-0000-0000-0000-0000000dead1'::uuid), 'D9 mismatch == nonexistent (same error)');
select ok(pg_temp.errof('ea000000-0000-0000-0000-0000000dead1'::uuid) like '42501|%not in caller scope', 'D10 the unified error is 42501 + a scope-neutral message (no existence/role/branch leak)');
-- audit old/new on a successful edit.
set local app.current_app_user_id = 'ea000000-0000-0000-0000-0000000000e2';
select app.set_staff_capabilities(gen_random_uuid(),'ea000000-0000-0000-0000-00000000ef03', true, true, true);  -- re-enable all (old had void deny from D1)
select ok(exists(select 1 from audit_events where action='staff.capabilities_updated'
   and (old_values->'permissions') is not null and (new_values->'permissions') is not null
   and (new_values->>'membership_id')='ea000000-0000-0000-0000-00000000ab03'),
  'D11 staff.capabilities_updated carries OLD and NEW permissions payloads');
select is((select permissions from memberships where id='ea000000-0000-0000-0000-00000000ab03'), '{}'::jsonb, 'D12 re-enable removed all deny keys (unrelated keys would be preserved)');

-- ===== E. Full-comp discount manager gate (order + item) =================== 43-52
-- order-level, base = subtotal 1000 (o0d1). Default cashier c503.
select is((app.apply_discount('ea000000-0000-0000-0000-00000000c503','ea000000-0000-0000-0000-00000000a0d1','ea000000-0000-0000-0000-0000000d0a11','e-p50','order',null,'percentage',5000,'half',null) ->> 'ok')::boolean, true, 'E1 default cashier 50% (partial) is allowed');
select is((app.apply_discount('ea000000-0000-0000-0000-00000000c503','ea000000-0000-0000-0000-00000000a0d1','ea000000-0000-0000-0000-0000000d0a11','e-p100','order',null,'percentage',10000,'comp',null) ->> 'error'), 'permission_denied', 'E2 default cashier 100% is DENIED (full comp)');
select is((app.apply_discount('ea000000-0000-0000-0000-00000000c503','ea000000-0000-0000-0000-00000000a0d1','ea000000-0000-0000-0000-0000000d0a11','e-fz','order',null,'fixed',1000,'zero',null) ->> 'error'), 'permission_denied', 'E3 default cashier fixed==subtotal (zero-out) is DENIED');
select is((app.apply_discount('ea000000-0000-0000-0000-00000000c503','ea000000-0000-0000-0000-00000000a0d1','ea000000-0000-0000-0000-0000000d0a11','e-fx','order',null,'fixed',9999,'big',null) ->> 'error'), 'permission_denied', 'E4 default cashier fixed>subtotal is DENIED');
select is((app.apply_discount('ea000000-0000-0000-0000-00000000c503','ea000000-0000-0000-0000-00000000a0d1','ea000000-0000-0000-0000-0000000d0a11','e-b1','order',null,'percentage',9990,'boundary',null) ->> 'ok')::boolean, true, 'E5 boundary: 99.90% leaves 1 minor -> allowed');
select is((app.apply_discount('ea000000-0000-0000-0000-00000000c503','ea000000-0000-0000-0000-00000000a0d1','ea000000-0000-0000-0000-0000000d0a11','e-b2','order',null,'percentage',9995,'boundary',null) ->> 'error'), 'permission_denied', 'E6 boundary: 99.95% rounds to full -> DENIED');
select is((app.apply_discount('ea000000-0000-0000-0000-00000000c502','ea000000-0000-0000-0000-00000000a0d1','ea000000-0000-0000-0000-0000000d0a11','e-mgr','order',null,'percentage',10000,'comp',null) ->> 'ok')::boolean, true, 'E7 a MANAGER may apply 100% (full comp allowed for manager+)');
select is((app.apply_discount('ea000000-0000-0000-0000-00000000c504','ea000000-0000-0000-0000-00000000a0d1','ea000000-0000-0000-0000-0000000d0a11','e-deny','order',null,'percentage',5000,'x',null) ->> 'error'), 'permission_denied', 'E8 explicit apply_discount=false cashier is denied even for a partial discount');
-- item-level, base = 1000 (item a1e2 on o0d2).
select is((app.apply_discount('ea000000-0000-0000-0000-00000000c503','ea000000-0000-0000-0000-00000000a0d2','ea000000-0000-0000-0000-0000000d0a11','e-i100','order_item','ea000000-0000-0000-0000-00000000a1e2','percentage',10000,'comp',null) ->> 'error'), 'permission_denied', 'E9 default cashier item-level 100% is DENIED');
select is((select grand_total_minor from orders where id='ea000000-0000-0000-0000-00000000a0d2'), 1000::bigint, 'E10 the item-denied order is UNCHANGED (no clamp-to-zero, no negative)');

select * from finish();
rollback;
