-- ============================================================================
-- AUDIT-LOG-DASHBOARD-001 — pgTAP: app.owner_audit_events (read-only audit
-- timeline) + app.audit_redact_values (secret scrubber).
--
-- Org A (Rest A1 tz=UTC; Branch A1a + Branch A1b) with a set of TODAY audit
-- events on A1a, one org/restaurant-level event, one on A1b, plus a YESTERDAY
-- event; Org B carries one event to prove cross-tenant isolation. Callers:
-- org_owner (Amira K.), manager@A1a (Mona M.), cashier / kitchen_staff /
-- accountant (denied), manager@A1b, org B owner.
--
-- Covers: authorization (unauth / cashier / kitchen / accountant DENIED;
-- manager + org_owner ALLOWED; out-of-scope branch + cross-org -> 42501 with NO
-- existence oracle; downward branch narrowing); keyset pagination (limit clamp,
-- newest-first, occurred_at|id tie-break, next_cursor continuation, malformed
-- cursor -> 22023); filters (range today/yesterday, category, exact action,
-- sensitive_only, actor; unknown range/category -> 22023); PRIVACY (recursive
-- secret-key redaction top-level + nested; safe keys preserved; RPC never emits
-- an injected secret; actor shown as display_name, no email leak); READ-ONLY
-- (row count unchanged); wrapper hygiene (DEFINER/INVOKER; authenticated-only,
-- no anon). Table-level append-only immutability is owned by rf017_immutability.
-- Session pinned to UTC; hex-only UUIDs; GUC-free (identity GUC only).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(67);

-- ===== fixture: Org A (Rest A1 tz=UTC; Branch A1a, A1b) and Org B =============
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000a0000', 'Org A', 'al-a', 'ILS'),
  ('00000000-0000-0000-0000-0000000b0000', 'Org B', 'al-b', 'EUR');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a0000', 'Rest A1', 'UTC'),
  ('00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b0000', 'Rest B1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', 'Branch A1a', null),
  ('00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', 'Branch A1b', null),
  ('00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', 'Branch B1a', null);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'pos', 'POS-1');

insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000f001', 'al-owner@example.test'),
  ('00000000-0000-0000-0000-00000000f002', 'al-mgr-a@example.test'),
  ('00000000-0000-0000-0000-00000000f003', 'al-cashier@example.test'),
  ('00000000-0000-0000-0000-00000000f004', 'al-kitchen@example.test'),
  ('00000000-0000-0000-0000-00000000f005', 'al-accountant@example.test'),
  ('00000000-0000-0000-0000-00000000f006', 'al-orgb-owner@example.test'),
  ('00000000-0000-0000-0000-00000000f007', 'al-mgr-b@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0000', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000a0002', '00000000-0000-0000-0000-00000000f002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'manager'),
  ('00000000-0000-0000-0000-0000000a0003', '00000000-0000-0000-0000-00000000f003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'cashier'),
  ('00000000-0000-0000-0000-0000000a0004', '00000000-0000-0000-0000-00000000f004', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'kitchen_staff'),
  ('00000000-0000-0000-0000-0000000a0005', '00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-0000000a0000', null, null, 'accountant'),
  ('00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-00000000f006', '00000000-0000-0000-0000-0000000b0000', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000a0007', '00000000-0000-0000-0000-00000000f007', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', 'manager');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0000', null, null, '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0001', 'Amira K.'),
  ('00000000-0000-0000-0000-0000000e0f02', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000f002', '00000000-0000-0000-0000-0000000a0002', 'Mona M.'),
  ('00000000-0000-0000-0000-0000000e0f03', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000f003', '00000000-0000-0000-0000-0000000a0003', 'Cara C.');

-- ===== fixture: audit events =================================================
-- TODAY on Branch A1a (7 rows): 2 voids at 14:00 (tie-break pair), 1 void 10:00,
-- 1 discount, 1 shift.closed, 1 order.submitted (non-sensitive), 1 staff.pin_set
-- (with INJECTED secrets to prove redaction).
insert into audit_events
  (id, organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values, occurred_at) values
  ('00000000-0000-0000-0000-0000000ae001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', null, '00000000-0000-0000-0000-0000000e0f03', '00000000-0000-0000-0000-00000000d001', 'order.voided', 'wrong table', '{"status":"submitted","revision":1}'::jsonb, '{"status":"voided","revision":2,"void_reason":"wrong table","voided_item_count":2}'::jsonb, (current_date + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-0000000ae002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', null, '00000000-0000-0000-0000-0000000e0f03', '00000000-0000-0000-0000-00000000d001', 'order.discount_applied', null, '{"scope":"order","discount_total_minor":0,"grand_total_minor":1000}'::jsonb, '{"scope":"order","discount_type":"percent","value":10,"discount_total_minor":100,"grand_total_minor":900,"internal_worker_id":"w-42","access_token":"tok_leak_disc","audit_meta":{"session_token":"nested_secret"}}'::jsonb, (current_date + interval '11 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-0000000ae005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', null, '00000000-0000-0000-0000-0000000e0f02', '00000000-0000-0000-0000-00000000d001', 'shift.closed', null, null, '{"shift_id":"00000000-0000-0000-0000-0000000abc01","status":"closed"}'::jsonb, (current_date + interval '8 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-0000000ae006', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', null, '00000000-0000-0000-0000-0000000e0f03', '00000000-0000-0000-0000-00000000d001', 'order.submitted', null, null, '{"status":"submitted"}'::jsonb, (current_date + interval '9 hours 30 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0000-0000000ae007', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000f001', null, null, 'staff.pin_set', null, null, '{"employee_profile_id":"00000000-0000-0000-0000-0000000e0f03","pin_set":true,"pin_hash":"$2b$SUPERSECRET","access_token":"tok_leak","nested":{"session_token":"s3cr3t_val","display_name":"safe"}}'::jsonb, (current_date + interval '7 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-0000000ae008', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', null, '00000000-0000-0000-0000-0000000e0f03', '00000000-0000-0000-0000-00000000d001', 'order.voided', null, null, '{"status":"voided"}'::jsonb, (current_date + interval '14 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-0000000ae009', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', null, '00000000-0000-0000-0000-0000000e0f03', '00000000-0000-0000-0000-00000000d001', 'order.voided', null, null, '{"status":"voided"}'::jsonb, (current_date + interval '14 hours') at time zone 'UTC');
-- TODAY org/restaurant-level (branch NULL): capabilities + membership grant, actor=app_user.
insert into audit_events
  (id, organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values, occurred_at) values
  ('00000000-0000-0000-0000-0000000ae003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', null, '00000000-0000-0000-0000-00000000f001', null, null, 'staff.capabilities_updated', null, '{"permissions":{}}'::jsonb, '{"employee_profile_id":"00000000-0000-0000-0000-0000000e0f03","permissions":{"void_order":"false"},"capabilities":{"apply_discount":true,"void_order":false,"close_shift":true}}'::jsonb, (current_date + interval '12 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-0000000ae004', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', null, '00000000-0000-0000-0000-00000000f001', null, null, 'membership.granted', null, null, '{"target_app_user_id":"00000000-0000-0000-0000-00000000f003","role":"cashier"}'::jsonb, (current_date + interval '13 hours') at time zone 'UTC');
-- TODAY on Branch A1b (must NOT be visible to a manager@A1a).
insert into audit_events
  (id, organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values, occurred_at) values
  ('00000000-0000-0000-0000-0000000ae030', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-00000000f007', null, null, 'order.discount_applied', null, null, '{"scope":"order","discount_type":"amount","value":50}'::jsonb, (current_date + interval '10 hours') at time zone 'UTC');
-- YESTERDAY on Branch A1a (range filter).
insert into audit_events
  (id, organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values, occurred_at) values
  ('00000000-0000-0000-0000-0000000ae020', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', null, '00000000-0000-0000-0000-0000000e0f03', '00000000-0000-0000-0000-00000000d001', 'order.voided', 'late night', null, '{"status":"voided"}'::jsonb, (current_date - 1 + interval '22 hours') at time zone 'UTC');
-- Org B TODAY (cross-tenant isolation).
insert into audit_events
  (id, organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values, occurred_at) values
  ('00000000-0000-0000-0000-0000000ae0b0', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000f006', null, null, 'order.voided', null, null, '{"status":"voided"}'::jsonb, (current_date + interval '10 hours') at time zone 'UTC');

-- ===== result sets computed under role authenticated ==========================
set local role authenticated;

set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';  -- org_owner (Amira K.)
create temp table t_owner_org  as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', null, null, 'today') as res;
create temp table t_owner_a1a  as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today') as res;
create temp table t_owner_hi   as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', null, null, 'today', null, null, false, null, null, 999) as res;
create temp table t_owner_lo   as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', null, null, 'today', null, null, false, null, null, 0) as res;
create temp table t_owner_pin  as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', null, null, 'today', null, 'staff.pin_set') as res;
create temp table t_owner_grant as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', null, null, 'today', null, 'membership.granted') as res;
create temp table t_owner_disc as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', null, null, 'today', null, 'order.discount_applied') as res;
create temp table t_owner_caps as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', null, null, 'today', null, 'staff.capabilities_updated') as res;
create temp table t_owner_shift as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', null, null, 'today', null, 'shift.closed') as res;
create temp table t_owner_void as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', null, null, 'today', null, 'order.voided') as res;

set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f002';  -- manager @ A1a (Mona M.)
create temp table t_mgr_today  as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today') as res;
create temp table t_mgr_yest   as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'yesterday') as res;
create temp table t_mgr_voids  as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today', 'voids') as res;
create temp table t_mgr_disc   as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today', 'discounts') as res;
create temp table t_mgr_sub    as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today', null, 'order.submitted') as res;
create temp table t_mgr_sens   as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today', null, null, true) as res;
create temp table t_mgr_actor  as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today', null, null, false, null, '00000000-0000-0000-0000-0000000e0f03') as res;
create temp table t_mgr_p1     as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today', null, null, false, null, null, 1) as res;
create temp table t_mgr_p2     as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today', null, null, false, null, null, 1, (select res->>'next_cursor' from t_mgr_p1)) as res;

set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f003';  -- cashier
create temp table t_cashier as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today') as res;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f004';  -- kitchen_staff
create temp table t_kitchen as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today') as res;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f005';  -- accountant
create temp table t_acct as select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', null, null, 'today') as res;

reset role;

-- ===== AUTHORIZATION (1-9) ====================================================
set local role authenticated;
set local app.current_app_user_id = '';  -- unauthenticated
select throws_ok(
  $$ select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', null, null, 'today') $$,
  '42501', null, 'unauthenticated caller is denied (42501)');
reset role;

select is((select res->>'error' from t_cashier), 'permission_denied', 'a cashier is denied (permission_denied)');
select is((select res->>'error' from t_kitchen), 'permission_denied', 'kitchen_staff is denied (permission_denied)');
select is((select res->>'error' from t_acct),    'permission_denied', 'an accountant is denied (permission_denied)');
select is((select (res->>'ok')::boolean from t_mgr_today), true, 'a manager over the scope is allowed');
select is((select (res->'count')::int from t_mgr_today), 7, 'manager@A1a sees the 7 TODAY A1a events (org/branch-null events excluded)');
select is((select (res->>'ok')::boolean from t_owner_org), true, 'an org_owner is allowed');
select is((select (res->'count')::int from t_owner_org), 10, 'org_owner org-wide sees all 10 TODAY Org-A events (never Org B)');
select is((select (res->'count')::int from t_owner_a1a), 7, 'org_owner narrowed to A1a sees only the 7 A1a events (downward scope)');

-- out-of-scope + cross-org -> identical 42501 (no existence oracle)
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f002';  -- manager @ A1a
select throws_ok(
  $$ select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', 'today') $$,
  '42501', null, 'manager@A1a asking for A1b is denied (42501; no cross-branch leak)');
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';  -- org A owner
select throws_ok(
  $$ select app.owner_audit_events('00000000-0000-0000-0000-0000000b0000', null, null, 'today') $$,
  '42501', null, 'Org A owner asking for Org B is denied (42501; no cross-tenant oracle)');
reset role;

-- ===== PAGINATION (10-16) =====================================================
select is((select (res->>'limit')::int from t_owner_hi), 100, 'p_limit above 100 clamps to 100');
select is((select (res->>'limit')::int from t_owner_lo), 1,   'p_limit below 1 clamps to 1');
select is((select (res->'count')::int from t_mgr_p1), 1, 'first page (limit 1) returns 1 event');
select is((select (res->>'has_more')::boolean from t_mgr_p1), true, 'first page reports has_more when more remain');
select isnt((select res->>'next_cursor' from t_mgr_p1), null, 'first page returns a next_cursor');
-- newest-first + occurred_at|id tie-break: the two 14:00 voids sort by id DESC,
-- so ae009 is page 1 and ae008 is page 2.
select is((select res->'events'->0->>'event_id' from t_mgr_p1), '00000000-0000-0000-0000-0000000ae009', 'newest-first: highest-id event at the 14:00 tie is first');
select is((select res->'events'->0->>'event_id' from t_mgr_p2), '00000000-0000-0000-0000-0000000ae008', 'keyset continues to the tie-break partner on page 2 (no dup, no skip)');

set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f002';
select throws_ok(
  $$ select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today', null, null, false, null, null, 25, 'not-a-cursor') $$,
  '22023', null, 'a malformed cursor is a bad request (22023)');
reset role;

-- ===== FILTERS (17-24) ========================================================
select is((select (res->'count')::int from t_mgr_yest), 1, 'range=yesterday returns only the yesterday event');
select is((select (res->'count')::int from t_mgr_voids), 3, 'category=voids returns the 3 void events');
select is((select (res->'count')::int from t_mgr_disc), 1, 'category=discounts returns the 1 discount event');
select is((select (res->'count')::int from t_mgr_sub), 1, 'p_action=order.submitted returns exactly that event');
select is((select (res->'count')::int from t_mgr_sens), 6, 'sensitive_only excludes the non-sensitive order.submitted (7 -> 6)');
select is((select (res->'count')::int from t_mgr_actor), 5, 'actor filter returns only the cashier-profile events');

set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f002';
select throws_ok(
  $$ select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'quarter') $$,
  '22023', null, 'an unknown range is a bad request (22023)');
select throws_ok(
  $$ select app.owner_audit_events('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today', 'nonsense') $$,
  '22023', null, 'an unknown category is a bad request (22023)');
reset role;

-- ===== PRIVACY: SERVER-SIDE ALLOWLIST PROJECTION ==============================
-- The RPC must NEVER return raw payload JSON: app.audit_safe_detail is an
-- action-gated field ALLOWLIST (not a secret-key denylist). Function-level first.

-- (req1) a supported action keeps its expected safe field.
select is((app.audit_safe_detail('order.discount_applied', '{"discount_total_minor":100}'::jsonb)->>'discount_total_minor'), '100', 'safe_detail keeps an allowlisted field for a supported action');
-- (req2) a non-secret but UNKNOWN key is not returned.
select is((app.audit_safe_detail('order.discount_applied', '{"discount_total_minor":100,"internal_worker_id":"w"}'::jsonb) ? 'internal_worker_id'), false, 'safe_detail drops an unknown NON-secret key');
-- (req3) an UNKNOWN NESTED object is not returned.
select is((app.audit_safe_detail('order.discount_applied', '{"discount_total_minor":100,"audit_meta":{"session_token":"s"}}'::jsonb) ? 'audit_meta'), false, 'safe_detail drops an unknown nested object');
-- (req4) a secret-looking key is not returned.
select is((app.audit_safe_detail('order.discount_applied', '{"access_token":"x","discount_total_minor":100}'::jsonb) ? 'access_token'), false, 'safe_detail drops a secret-looking key');
-- (req5) a mixed payload returns ONLY the allowlisted subset.
select is((select count(*)::int from jsonb_object_keys(app.audit_safe_detail('order.discount_applied', '{"scope":"order","discount_type":"percent","value":10,"discount_total_minor":100,"grand_total_minor":900,"internal_worker_id":"w","access_token":"x"}'::jsonb))), 5, 'safe_detail returns only the 5 allowlisted keys from a mixed payload');
-- (req6) an UNKNOWN action returns no payload details, even for allowlisted keys.
select is((app.audit_safe_detail('menu.menu_item.updated', '{"status":"active","name":"Burger"}'::jsonb)), '{}'::jsonb, 'safe_detail returns {} for an unsupported action (no payload details)');
-- (req7) malformed / non-object payloads produce an empty safe object, never crash.
select is((app.audit_safe_detail('order.voided', '"a string"'::jsonb)), '{}'::jsonb, 'safe_detail: a scalar payload -> {} (no crash)');
select is((app.audit_safe_detail('order.voided', null)), '{}'::jsonb, 'safe_detail: NULL payload -> {} (no crash)');
select is((app.audit_safe_detail('order.voided', '[1,2,3]'::jsonb)), '{}'::jsonb, 'safe_detail: an array payload -> {} (no crash)');
-- capabilities nested object is kept to ONLY its 3 canonical booleans.
select is((app.audit_safe_detail('staff.capabilities_updated', '{"capabilities":{"apply_discount":true,"void_order":false,"evil":"x"},"permissions":{"y":1}}'::jsonb)->'capabilities'->>'void_order'), 'false', 'safe_detail keeps the canonical capability booleans');
select is((app.audit_safe_detail('staff.capabilities_updated', '{"capabilities":{"apply_discount":true,"evil":"x"}}'::jsonb)->'capabilities' ? 'evil'), false, 'safe_detail drops an unknown nested capability key');
select is((app.audit_safe_detail('staff.capabilities_updated', '{"capabilities":{"apply_discount":true},"permissions":{"y":1}}'::jsonb) ? 'permissions'), false, 'safe_detail drops the whole non-allowlisted permissions object');
-- the action-support predicate itself.
select is((app.audit_action_has_detail('order.voided')), true, 'has_detail: order.voided is supported');
select is((app.audit_action_has_detail('menu.menu_item.updated')), false, 'has_detail: menu.* is unsupported');
select is((app.audit_action_has_detail('device.created')), false, 'has_detail: device.created is unsupported (to_jsonb(device) never projected)');

-- (req8/req10) SAME at the RPC boundary: a direct authenticated caller cannot
-- retrieve the raw payload; supported presentations retain their safe data.
select is((select res->'events'->0->'new_values'->>'discount_total_minor' from t_owner_disc), '100', 'RPC: a supported discount retains its safe money-minor field');
select is((select res->'events'->0->'new_values' ? 'internal_worker_id' from t_owner_disc), false, 'RPC: an injected unknown NON-secret key is not returned');
select is((select res->'events'->0->'new_values' ? 'access_token' from t_owner_disc), false, 'RPC: an injected secret key is not returned');
select is((select res->'events'->0->'new_values' ? 'audit_meta' from t_owner_disc), false, 'RPC: an injected unknown nested object is not returned');
select is((select count(*)::int from jsonb_object_keys((select res->'events'->0->'new_values' from t_owner_disc))), 5, 'RPC: a mixed supported payload returns only its 5 allowlisted keys');
select is((select position('tok_leak_disc' in res::text)::int from t_owner_disc), 0, 'RPC: the injected raw secret value never appears anywhere');
select is((select position('nested_secret' in res::text)::int from t_owner_disc), 0, 'RPC: the injected nested secret value never appears anywhere');
-- an UNSUPPORTED action (staff.pin_set) returns NO payload at the RPC boundary.
select is((select jsonb_typeof(res->'events'->0->'new_values') from t_owner_pin), 'object', 'RPC: an unsupported action still returns a (safe) object payload');
select is((select count(*)::int from jsonb_object_keys((select res->'events'->0->'new_values' from t_owner_pin))), 0, 'RPC: an unsupported action returns an EMPTY payload (no details)');
select is((select position('SUPERSECRET' in res::text)::int from t_owner_pin), 0, 'RPC: no secret from an unsupported action ever appears');
-- supported presentations retain their required safe data.
-- t_owner_void returns the 3 voids newest-first [ae009, ae008, ae001]; ae001
-- (10:00) is the rich row carrying old+new status + the item count -> index 2.
select is((select res->'events'->2->'old_values'->>'status' from t_owner_void), 'submitted', 'RPC: void retains the safe BEFORE status');
select is((select res->'events'->2->'new_values'->>'status' from t_owner_void), 'voided', 'RPC: void retains the safe AFTER status');
select is((select res->'events'->2->'new_values'->>'voided_item_count' from t_owner_void), '2', 'RPC: void retains the safe item count');
select is((select res->'events'->0->'new_values'->'capabilities'->>'void_order' from t_owner_caps), 'false', 'RPC: capabilities retains the canonical booleans');
select is((select res->'events'->0->'new_values' ? 'permissions' from t_owner_caps), false, 'RPC: capabilities event drops the non-allowlisted permissions object');
select is((select res->'events'->0->'new_values' ? 'employee_profile_id' from t_owner_caps), false, 'RPC: capabilities event drops the actor employee_profile_id from the payload');
select is((select res->'events'->0->'new_values'->>'status' from t_owner_shift), 'closed', 'RPC: shift close retains the safe status');
select is((select res->'events'->0->'new_values' ? 'shift_id' from t_owner_shift), false, 'RPC: shift close drops the internal shift_id (not allowlisted)');

-- ===== ACTOR PRIVACY (no email / auth internals) ==============================
select is((select res->'events'->0->>'actor_name' from t_owner_grant), 'Amira K.', 'actor is shown as the staff display name, not an id');
select is((select res->'events'->0 ? 'actor_app_user_id' from t_owner_grant), false, 'the actor app_user_id is NOT returned to the client');
select is((select res->'events'->0 ? 'actor_employee_profile_id' from t_owner_grant), false, 'the actor employee_profile_id is NOT returned to the client');
select is((select res->'events'->0->'new_values' ? 'target_app_user_id' from t_owner_grant), false, 'a membership grant drops the target app_user_id (auth internal)');
select is((select position('@example.test' in res::text)::int from t_owner_org), 0, 'no actor email address leaks into the audit payload');

-- ===== READ-ONLY + WRAPPER HYGIENE (34-35) ====================================
-- REVIEW DELTA (hygiene): count THIS FILE'S audit rows, not the whole
-- database — the exact expected total (12) is unchanged, but a concurrency
-- harness run in the same disposable db leaves append-only rows under its own
-- org that a global count would wrongly absorb.
select is((select count(*)::int from audit_events
            where organization_id in ('00000000-0000-0000-0000-0000000a0000',
                                      '00000000-0000-0000-0000-0000000b0000')),
  12, 'owner_audit_events is read-only: audit_events row count is unchanged after all reads');
select ok(
  (select prosecdef from pg_proc where proname = 'owner_audit_events' and pronamespace = 'app'::regnamespace)
  and not (select prosecdef from pg_proc where proname = 'owner_audit_events' and pronamespace = 'public'::regnamespace)
  and has_function_privilege('authenticated', 'app.owner_audit_events(uuid,uuid,uuid,text,text,text,boolean,uuid,uuid,int,text)', 'execute')
  and not has_function_privilege('anon', 'app.owner_audit_events(uuid,uuid,uuid,text,text,text,boolean,uuid,uuid,int,text)', 'execute'),
  'app fn is DEFINER, public wrapper is INVOKER, authenticated may execute, anon may NOT (D-011)');

select * from finish();
rollback;
