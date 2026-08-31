-- ============================================================================
-- ADMIN-126C — pgTAP: support-session SCOPE CONTAINMENT + STAFF-PII redaction.
--
-- BEHAVIORAL proof (the 126B structural grep is kept elsewhere; this file
-- INVOKES the reads): a RESTAURANT-scoped support session must never widen to
-- org-level aggregates via a NULL request scope, must never reach a sibling
-- restaurant or another org, and must never receive staff display names from
-- the approved report reads — while a REAL member sees the exact pre-126C
-- payload (names included) and org-scoped sessions keep their documented
-- org-wide reach.
--
-- Fixture (UTC session; hex-only UUIDs prefix c5):
--   Org A: Rest ONE (branch B1, order net 1000, one CLOSED shift by
--          'Owner One') + Rest TWO (branch B2, order net 700).
--   Org B: empty (cross-org probe target only).
--   Operator: active platform grant + aal2 JWT. Owner: real org_owner of A.
-- Times use now() so the branch-local "today" bucket always holds them
-- (the midnight trap: now() - interval '1 hour' can be YESTERDAY).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(32);

-- ===== fixture ==============================================================
insert into organizations (id, name, slug, default_currency) values
  ('c5000000-0000-0000-0000-0000000000a0', 'Scope A', 'sc126c-a', 'ILS'),
  ('c5000000-0000-0000-0000-0000000000b0', 'Scope B', 'sc126c-b', 'EUR');
insert into restaurants (id, organization_id, name, timezone) values
  ('c5000000-0000-0000-0000-0000000000a1', 'c5000000-0000-0000-0000-0000000000a0', 'Rest ONE', 'UTC'),
  ('c5000000-0000-0000-0000-0000000000a2', 'c5000000-0000-0000-0000-0000000000a0', 'Rest TWO', 'UTC'),
  ('c5000000-0000-0000-0000-0000000000b1', 'c5000000-0000-0000-0000-0000000000b0', 'Rest B',   'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('c5000000-0000-0000-0000-00000000a1b1', 'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a1', 'B1', 'UTC'),
  ('c5000000-0000-0000-0000-00000000a2b1', 'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a2', 'B2', 'UTC'),
  ('c5000000-0000-0000-0000-00000000b1b1', 'c5000000-0000-0000-0000-0000000000b0', 'c5000000-0000-0000-0000-0000000000b1', 'BB', 'UTC');
insert into auth.users (id, email) values
  ('c5000000-0000-0000-0000-00000000adf0', 'sc126c-op@example.test'),
  ('c5000000-0000-0000-0000-00000000adf1', 'sc126c-owner@example.test');
insert into app_users (id, email, auth_user_id) values
  ('c5000000-0000-0000-0000-00000000ee0f', 'sc126c-op@example.test',    'c5000000-0000-0000-0000-00000000adf0'),
  ('c5000000-0000-0000-0000-00000000ee0e', 'sc126c-owner@example.test', 'c5000000-0000-0000-0000-00000000adf1');
insert into platform_admin_grants (id, app_user_id, status, granted_by) values
  ('c5000000-0000-0000-0000-0000000000e1', 'c5000000-0000-0000-0000-00000000ee0f', 'active',
   'c5000000-0000-0000-0000-00000000ee0f');
insert into memberships (id, app_user_id, organization_id, role, status) values
  ('c5000000-0000-0000-0000-0000000000e2', 'c5000000-0000-0000-0000-00000000ee0e',
   'c5000000-0000-0000-0000-0000000000a0', 'org_owner', 'active');
insert into employee_profiles (id, organization_id, app_user_id, membership_id, display_name) values
  ('c5000000-0000-0000-0000-0000000000e3', 'c5000000-0000-0000-0000-0000000000a0',
   'c5000000-0000-0000-0000-00000000ee0e', 'c5000000-0000-0000-0000-0000000000e2', 'Owner One');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('c5000000-0000-0000-0000-00000000d0d1', 'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a1', 'c5000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('c5000000-0000-0000-0000-00000000d0d2', 'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a2', 'c5000000-0000-0000-0000-00000000a2b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('c5000000-0000-0000-0000-00000000c0c1', 'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a1', 'c5000000-0000-0000-0000-00000000a1b1', 'c5000000-0000-0000-0000-00000000d0d1', 'active'),
  ('c5000000-0000-0000-0000-00000000c0c2', 'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a2', 'c5000000-0000-0000-0000-00000000a2b1', 'c5000000-0000-0000-0000-00000000d0d2', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('c5000000-0000-0000-0000-00000000e0e1', 'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a1', 'c5000000-0000-0000-0000-00000000a1b1', 'c5000000-0000-0000-0000-00000000d0d1', 'c5000000-0000-0000-0000-00000000c0c1'),
  ('c5000000-0000-0000-0000-00000000e0e2', 'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a2', 'c5000000-0000-0000-0000-00000000a2b1', 'c5000000-0000-0000-0000-00000000d0d2', 'c5000000-0000-0000-0000-00000000c0c2');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('c5000000-0000-0000-0000-00000000b001', 'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a1', 'c5000000-0000-0000-0000-00000000a1b1', 'c5000000-0000-0000-0000-00000000e0e1', 'c5000000-0000-0000-0000-0000000000e3', 'c5000000-0000-0000-0000-0000000000e2', now() + interval '1 hour'),
  ('c5000000-0000-0000-0000-00000000b002', 'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a2', 'c5000000-0000-0000-0000-00000000a2b1', 'c5000000-0000-0000-0000-00000000e0e2', 'c5000000-0000-0000-0000-0000000000e3', 'c5000000-0000-0000-0000-0000000000e2', now() + interval '1 hour');
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, created_at) values
  ('c5000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a1', 'c5000000-0000-0000-0000-00000000a1b1', 'c5000000-0000-0000-0000-00000000d0d1', 'c5000000-0000-0000-0000-00000000b001', 'c5000000-0000-0000-0000-0000000000e3', 'c5000000-0000-0000-0000-0000000000e2', 'takeaway', 'completed', 'ILS', 1000, 0, 0, 1000, 'sc126c-o1', now()),
  ('c5000000-0000-0000-0000-000000000002', 'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a2', 'c5000000-0000-0000-0000-00000000a2b1', 'c5000000-0000-0000-0000-00000000d0d2', 'c5000000-0000-0000-0000-00000000b002', 'c5000000-0000-0000-0000-0000000000e3', 'c5000000-0000-0000-0000-0000000000e2', 'takeaway', 'completed', 'ILS', 700, 0, 0, 700, 'sc126c-o2', now());
insert into shifts (id, organization_id, restaurant_id, branch_id, device_id, opened_by_employee_profile_id, resolved_membership_id, closed_by_employee_profile_id, status, opened_at, closed_at, local_operation_id) values
  ('c5000000-0000-0000-0000-00000000f001', 'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a1', 'c5000000-0000-0000-0000-00000000a1b1', 'c5000000-0000-0000-0000-00000000d0d1', 'c5000000-0000-0000-0000-0000000000e3', 'c5000000-0000-0000-0000-0000000000e2', 'c5000000-0000-0000-0000-0000000000e3', 'closed', now() - interval '10 minutes', now(), 'sc126c-s1');

-- ===========================================================================
-- R. RESTAURANT-SCOPED SESSION: exact containment
-- ===========================================================================
set local role authenticated;
set local request.jwt.claim.sub = 'c5000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"c5000000-0000-0000-0000-00000000adf0","aal":"aal2"}';

create temp table r_started as select public.platform_admin_start_support_session(
  'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a1',
  'scope containment proof') as res;
select is((select public.platform_support_exchange(res ->> 'handoff_token') ->> 'ok' from r_started),
  'true', 'R1. a RESTAURANT-scoped session starts and exchanges');

select is((select public.owner_daily_report(
    'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a1', null) ->> 'ok'),
  'true', 'R2. the in-scope restaurant read works');
select is((select public.owner_daily_report(
    'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a1', null)
    #>> '{today,net_minor}'),
  '1000', 'R3. and reports ONLY Rest ONE''s net (1000, never the org''s 1700)');

select throws_ok(
  $$ select public.owner_daily_report('c5000000-0000-0000-0000-0000000000a0', null, null) $$,
  '42501', null,
  'R4. a NULL restaurant request does NOT widen the session to org level (daily)');
select throws_ok(
  $$ select public.sales_summary('c5000000-0000-0000-0000-0000000000a0', null, null) $$,
  '42501', null,
  'R5. ... nor for sales_summary');
select throws_ok(
  $$ select public.owner_report_range('c5000000-0000-0000-0000-0000000000a0', null, null, 'today', null, null) $$,
  '42501', null,
  'R6. ... nor for owner_report_range');
select throws_ok(
  $$ select public.owner_report_currency_breakdown('c5000000-0000-0000-0000-0000000000a0', null, null, current_date, current_date) $$,
  '42501', null,
  'R7. ... nor for the currency breakdown');
select throws_ok(
  $$ select public.owner_daily_report('c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a2', null) $$,
  '42501', null,
  'R8. the SIBLING restaurant is denied (cross-restaurant fail-closed)');
select throws_ok(
  $$ select public.list_menu('c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a2', null) $$,
  '42501', null,
  'R9. ... including catalog reads (list_menu at Rest TWO)');
select throws_ok(
  $$ select public.owner_daily_report('c5000000-0000-0000-0000-0000000000b0', 'c5000000-0000-0000-0000-0000000000b1', null) $$,
  '42501', null,
  'R10. another ORGANIZATION is denied (cross-org fail-closed)');

-- ===========================================================================
-- P. STAFF-PII REDACTION under the restaurant-scoped session
-- ===========================================================================
create temp table r_daily as select public.owner_daily_report(
  'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a1', null) as doc;
select is((select doc #>> '{shift_cash,closed_shift_count}' from r_daily), '1',
  'P1. the closed shift itself IS visible to support (structure intact)');
select ok((select (doc #> '{shift_cash,last_closed_shift}') is not null from r_daily),
  'P2. the last-closed-shift object is present');
select is((select doc #>> '{shift_cash,last_closed_shift,closed_by_name}' from r_daily), null,
  'P3. ... but its staff display name is NULLED for a support-only reader');
select is((select doc #>> '{shift_cash,recent_closed_shifts,0,closed_by_name}' from r_daily), null,
  'P4. the recent-closed list is name-redacted too');
create temp table r_range as select public.owner_report_range(
  'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a1', null,
  'today', null, null) as doc;
select is((select doc #>> '{shift_cash,last_closed_shift,closed_by_name}' from r_range), null,
  'P5. owner_report_range: closed_by_name redacted');
select is((select doc #>> '{shift_cash,recent_closed_shifts,0,opened_by_name}' from r_range), null,
  'P6. owner_report_range: opened_by_name redacted');
select is((select doc #>> '{shift_cash,recent_closed_shifts,0,closed_by_name}' from r_range), null,
  'P7. owner_report_range: recent list closed_by_name redacted');
select is((select doc #>> '{current,net_minor}' from r_range), '1000',
  'P8. redaction never touches the money figures (net 1000 intact)');

-- ===========================================================================
-- O. ORGANIZATION-SCOPED SESSION: documented org-wide reach, still redacted
-- ===========================================================================
create temp table o_started as select public.platform_admin_start_support_session(
  'c5000000-0000-0000-0000-0000000000a0', null, 'org-scope contract proof') as res;
select is((select public.platform_support_exchange(res ->> 'handoff_token') ->> 'ok' from o_started),
  'true', 'O1. an ORG-scoped session starts and exchanges (prior session force-ended)');
select is((select public.sales_summary('c5000000-0000-0000-0000-0000000000a0', null, null) ->> 'ok'),
  'true', 'O2. org-level aggregates are the org-scoped session''s documented intent');
select is((select public.owner_report_range(
    'c5000000-0000-0000-0000-0000000000a0', null, null, 'today', null, null) #>> '{current,net_minor}'),
  '1700', 'O3. the org-wide window covers both restaurants (1000 + 700)');
select is((select public.owner_daily_report(
    'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a2', null) ->> 'ok'),
  'true', 'O4. each restaurant of the org is reachable');
select throws_ok(
  $$ select public.owner_daily_report('c5000000-0000-0000-0000-0000000000b0', null, null) $$,
  '42501', null,
  'O5. another organization stays out of reach');
select is((select public.owner_daily_report(
    'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a1', null)
    #>> '{shift_cash,last_closed_shift,closed_by_name}'),
  null, 'O6. staff names stay redacted under the org-scoped session too');

-- ===========================================================================
-- W. WRITE PATH UNCHANGED: support rank never leaks into writes
-- ===========================================================================
select throws_ok(
  $$ select public.upsert_table(
       'c5000000-0000-0000-0000-00000000aa01'::uuid,
       'c5000000-0000-0000-0000-0000000000a0'::uuid,
       'c5000000-0000-0000-0000-0000000000a1'::uuid,
       'c5000000-0000-0000-0000-00000000a1b1'::uuid,
       null, 'Support Table', 4, null, true) $$,
  '42501', null,
  'W1. a tenant write under the org-scoped session is refused (write rank unmoved)');
select is((select count(*)::int from tables
            where organization_id = 'c5000000-0000-0000-0000-0000000000a0'), 0,
  'W2. ... and no row was written');

-- ===========================================================================
-- N. MEMBER PARITY: the real owner sees the pre-126C payload
-- ===========================================================================
set local request.jwt.claim.sub = 'c5000000-0000-0000-0000-00000000adf1';
set local request.jwt.claims = '{"sub":"c5000000-0000-0000-0000-00000000adf1","aal":"aal1"}';
create temp table n_daily as select public.owner_daily_report(
  'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a1', null) as doc;
select is((select doc #>> '{shift_cash,last_closed_shift,closed_by_name}' from n_daily),
  'Owner One', 'N1. the REAL org_owner still sees the closer''s name (no over-redaction)');
select is((select public.owner_report_range(
    'c5000000-0000-0000-0000-0000000000a0', 'c5000000-0000-0000-0000-0000000000a1', null,
    'today', null, null) #>> '{shift_cash,recent_closed_shifts,0,opened_by_name}'),
  'Owner One', 'N2. owner_report_range keeps opened_by_name for members');
select is((select public.owner_daily_report(
    'c5000000-0000-0000-0000-0000000000a0', null, null) ->> 'ok'),
  'true', 'N3. the owner''s own org-wide read is untouched by the scope fix');

-- ===========================================================================
-- X. STRUCTURE: the helper is internal-only
-- ===========================================================================
reset role;
select ok(not has_function_privilege('authenticated',
    'app.platform_support_redact_staff_names(jsonb)', 'execute'),
  'X1. the redaction helper is NOT executable by authenticated');
select ok(not has_function_privilege('anon',
    'app.platform_support_redact_staff_names(jsonb)', 'execute'),
  'X2. ... nor by anon');
select is(app.platform_support_redact_staff_names(
    '{"a":{"closed_by_name":"Z","keep":1},"b":[{"opened_by_name":"Y"}],"closed_by_name":"X"}'::jsonb),
  '{"a":{"closed_by_name":null,"keep":1},"b":[{"opened_by_name":null}],"closed_by_name":null}'::jsonb,
  'X3. the helper nulls exactly the two staff-name keys at every depth');

select * from finish();
rollback;
