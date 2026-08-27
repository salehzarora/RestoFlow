-- ============================================================================
-- REPORT-123 — pgTAP: the owner-report family's ACL parity, exercised AS THE
-- AUTHENTICATED ROLE.
--
-- WHY THIS FILE EXISTS. Every owner-report wrapper in `public` is SECURITY
-- INVOKER: it runs with the CALLER's privileges and delegates to a SECURITY
-- DEFINER `app.*` implementation. So a wrapper granted to `authenticated` is
-- useless unless the INNER function is granted too. `owner_report_currency_
-- breakdown` shipped with the wrapper granted and the inner function only
-- revoked — never granted — and production authenticated callers got
-- `42501 permission denied for function owner_report_currency_breakdown`.
-- The Dashboard read that as "currency unverifiable" and hid every monetary
-- total on the Overview.
--
-- The existing OPS-043 P2 suite could not catch it: it sets the identity GUC
-- but never `set local role authenticated`, so it executes as superuser, for
-- whom EXECUTE is irrelevant. Every assertion here that matters therefore runs
-- AS the authenticated role.
--
-- The family guard is deliberately DYNAMIC: it discovers every
-- `public.owner_*` INVOKER wrapper granted to authenticated and requires its
-- `app.*` counterpart to be executable by authenticated too. A future report
-- function added with the same mistake fails this test without anyone
-- remembering to extend a list.
--
-- Session pinned to UTC; hex-only UUIDs; identity GUC only.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(14);

-- ===== fixture: one all-ILS organization with one billed order ==============
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-000001230000', 'Org R123', 'r123-a', 'ILS'),
  ('00000000-0000-0000-0000-000001240000', 'Org R123 Other', 'r123-b', 'ILS');
insert into restaurants (id, organization_id, name, timezone, currency_override) values
  ('00000000-0000-0000-0000-000001231000', '00000000-0000-0000-0000-000001230000', 'Rest R123', 'UTC', null),
  ('00000000-0000-0000-0000-000001241000', '00000000-0000-0000-0000-000001240000', 'Rest Other', 'UTC', null);
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0000-000001231a00', '00000000-0000-0000-0000-000001230000', '00000000-0000-0000-0000-000001231000', 'Branch R123', null),
  ('00000000-0000-0000-0000-000001241a00', '00000000-0000-0000-0000-000001240000', '00000000-0000-0000-0000-000001241000', 'Branch Other', null);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000123d001', '00000000-0000-0000-0000-000001230000', '00000000-0000-0000-0000-000001231000', '00000000-0000-0000-0000-000001231a00', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000123c001', '00000000-0000-0000-0000-000001230000', '00000000-0000-0000-0000-000001231000', '00000000-0000-0000-0000-000001231a00', '00000000-0000-0000-0000-00000123d001', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-00000123e001', '00000000-0000-0000-0000-000001230000', '00000000-0000-0000-0000-000001231000', '00000000-0000-0000-0000-000001231a00', '00000000-0000-0000-0000-00000123d001', '00000000-0000-0000-0000-00000123c001');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000123f001', 'r123-owner@example.test'),
  ('00000000-0000-0000-0000-00000124f001', 'r123-outsider@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-000001230001', '00000000-0000-0000-0000-00000123f001',
   '00000000-0000-0000-0000-000001230000', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-000001240001', '00000000-0000-0000-0000-00000124f001',
   '00000000-0000-0000-0000-000001240000', null, null, 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-00000123e0f1', '00000000-0000-0000-0000-000001230000', null, null, '00000000-0000-0000-0000-00000123f001', '00000000-0000-0000-0000-000001230001', 'Owner R123');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000123b001', '00000000-0000-0000-0000-000001230000', '00000000-0000-0000-0000-000001231000', '00000000-0000-0000-0000-000001231a00', '00000000-0000-0000-0000-00000123e001', '00000000-0000-0000-0000-00000123e0f1', '00000000-0000-0000-0000-000001230001', now() + interval '1 hour');

-- one completed, paid, ILS order today: the single-currency production shape
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, customer_name, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-000001231d01', '00000000-0000-0000-0000-000001230000', '00000000-0000-0000-0000-000001231000', '00000000-0000-0000-0000-000001231a00', '00000000-0000-0000-0000-00000123d001', '00000000-0000-0000-0000-00000123b001', '00000000-0000-0000-0000-00000123e0f1', '00000000-0000-0000-0000-000001230001', 'dine_in', 'completed', 'ILS', 1200, 0, 0, 1200, 'R123 ILS', 'r123-o1', (current_date + interval '9 hours') at time zone 'UTC');
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-000001231f01', '00000000-0000-0000-0000-000001230000', '00000000-0000-0000-0000-000001231000', '00000000-0000-0000-0000-000001231a00', '00000000-0000-0000-0000-000001231d01', '00000000-0000-0000-0000-00000123d001', '00000000-0000-0000-0000-00000123e0f1', '00000000-0000-0000-0000-000001230001', 'cash', 'completed', 1200, 1200, 0, 'ILS', 'r123-p1', (current_date + interval '9 hours') at time zone 'UTC');

-- ===========================================================================
-- A. DIRECT PRIVILEGE PINS
-- ===========================================================================
select ok(
  has_function_privilege('authenticated',
    'app.owner_report_currency_breakdown(uuid,uuid,uuid,date,date)', 'EXECUTE'),
  'A1. authenticated may EXECUTE the INNER app.owner_report_currency_breakdown');

select ok(
  not has_function_privilege('anon',
    'app.owner_report_currency_breakdown(uuid,uuid,uuid,date,date)', 'EXECUTE'),
  'A2. anon may NOT execute the inner breakdown');

select ok(
  not has_function_privilege('anon',
    'public.owner_report_currency_breakdown(uuid,uuid,uuid,date,date)', 'EXECUTE'),
  'A3. anon may NOT execute the public breakdown wrapper');

select ok(
  not has_function_privilege('public',
    'app.owner_report_currency_breakdown(uuid,uuid,uuid,date,date)', 'EXECUTE'),
  'A4. PUBLIC may NOT execute the inner breakdown');

select is(
  (select prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'owner_report_currency_breakdown'),
  false, 'A5. the public breakdown wrapper is still SECURITY INVOKER');

select is(
  (select prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'owner_report_currency_breakdown'),
  true, 'A6. the inner breakdown is still SECURITY DEFINER');

-- ===========================================================================
-- C. FAMILY-WIDE PARITY (dynamic: covers functions added later)
-- ===========================================================================
select is(
  (select coalesce(string_agg(w.proname, ', ' order by w.proname), '')
     from pg_proc w
     join pg_namespace wn on wn.oid = w.pronamespace
     join pg_proc a on a.proname = w.proname
     join pg_namespace an on an.oid = a.pronamespace
    where wn.nspname = 'public'
      and an.nspname = 'app'
      and w.proname like 'owner\_%'
      and w.prosecdef = false                                   -- INVOKER wrapper
      and has_function_privilege('authenticated', w.oid, 'EXECUTE')
      and not has_function_privilege('authenticated', a.oid, 'EXECUTE')),
  '',
  'C1. no public owner_* INVOKER wrapper is granted to authenticated while its app.* implementation is not');

select cmp_ok(
  (select count(*)::int
     from pg_proc w join pg_namespace wn on wn.oid = w.pronamespace
    where wn.nspname = 'public' and w.proname like 'owner\_%'
      and w.prosecdef = false
      and has_function_privilege('authenticated', w.oid, 'EXECUTE')),
  '>=', 8,
  'C2. the family guard actually covers the owner-report wrappers (not vacuous)');

select is(
  (select coalesce(string_agg(a.proname, ', ' order by a.proname), '')
     from pg_proc a join pg_namespace an on an.oid = a.pronamespace
    where an.nspname = 'app' and a.proname like 'owner\_%'
      and has_function_privilege('anon', a.oid, 'EXECUTE')),
  '', 'C3. anon can execute NO app.owner_* implementation');

-- ===========================================================================
-- B. ROLE-ACCURATE EXECUTION — as the authenticated role, like production
-- ===========================================================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000123f001';

select is(
  (select (r->>'ok')::boolean from public.owner_report_currency_breakdown(
     '00000000-0000-0000-0000-000001230000', '00000000-0000-0000-0000-000001231000',
     null, current_date, current_date) r),
  true, 'B1. AS AUTHENTICATED the public breakdown wrapper succeeds (the incident)');

select is(
  (select c->>'currency_code'
     from public.owner_report_currency_breakdown(
       '00000000-0000-0000-0000-000001230000', '00000000-0000-0000-0000-000001231000',
       null, current_date, current_date) r,
          jsonb_array_elements(r->'by_currency') c),
  'ILS', 'B2. the single-currency window reports exactly one ILS bucket');

select is(
  (select jsonb_array_length(r->'by_currency')
     from public.owner_report_currency_breakdown(
       '00000000-0000-0000-0000-000001230000', '00000000-0000-0000-0000-000001231000',
       null, current_date - 30, current_date - 20) r),
  0, 'B3. a window with no sales returns an EMPTY by_currency, not an error');

select is(
  (select (r->>'ok')::boolean from public.owner_report_range(
     '00000000-0000-0000-0000-000001230000', '00000000-0000-0000-0000-000001231000',
     null, 'custom', current_date, current_date) r),
  true, 'B4. the sibling owner_report_range still succeeds as authenticated');

-- cross-org: the outsider owns another organization entirely
set local app.current_app_user_id = '00000000-0000-0000-0000-00000124f001';
select throws_ok(
  $$ select public.owner_report_currency_breakdown(
       '00000000-0000-0000-0000-000001230000', '00000000-0000-0000-0000-000001231000',
       null, current_date, current_date) $$,
  '42501', null,
  'B5. AS AUTHENTICATED a cross-org caller is still refused (RISK R-003)');

reset role;
select finish();
rollback;
