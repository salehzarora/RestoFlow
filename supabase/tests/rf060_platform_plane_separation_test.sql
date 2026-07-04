-- ============================================================================
-- RF-060 — CANONICAL gate: platform-plane separation (T-007..T-010 + audit)
-- ============================================================================
-- T-007 platform-admin access is audited (separate platform_admin_audit_events row);
-- T-008 a tenant membership (even org_owner) cannot invoke the platform path;
-- T-009 a platform-admin grant is NOT a tenant membership (zero tenant rows on the
--   normal path);
-- T-010 a principal holding BOTH a platform grant AND a tenant membership is STILL
--   limited to its membership scope on the normal tenant path — the grant does not
--   widen tenant RLS (is_platform_admin is never used in a tenant policy);
-- plus platform_admin_audit_events is append-only (UPDATE/DELETE/TRUNCATE blocked).
-- Two orgs so cross-tenant breadth is visible. Fixtures as the BYPASSRLS connection
-- role; principal selected via the GUC under `set local role authenticated`.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(13);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf060pp-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf060pp-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000eef0', 'rf060pp-platadmin@example.test'),       -- platform grant, NO membership
  ('00000000-0000-0000-0000-00000000eef1', 'rf060pp-platadmin-member@example.test'), -- platform grant AND a tenant membership
  ('00000000-0000-0000-0000-00000000ee01', 'rf060pp-org-owner@example.test');         -- tenant org_owner, NO grant
insert into platform_admin_grants (id, app_user_id, status, granted_by) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-00000000eef0', 'active', '00000000-0000-0000-0000-00000000eef0'),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-00000000eef1', 'active', '00000000-0000-0000-0000-00000000eef1');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-00000000abf1', '00000000-0000-0000-0000-00000000eef1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');

set local role authenticated;

-- ===== T-009 + T-007: grant-only platform admin ============================= 1-4
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000eef0';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
-- RF-119: the platform path now requires MFA aal2 (app.platform_admin_guard). The
-- assurance is read ONLY from request.jwt.claims (no sub => auth.uid() stays null,
-- so the GUC identity above is preserved); provide the required aal2 claim.
set local request.jwt.claims = '{"aal":"aal2"}';
select is(app.is_platform_admin(), true, 'grant holder: is_platform_admin() is true');
select is((select count(*) from restaurants)::int, 0,
  'T-009: a platform-admin grant alone (no membership) yields ZERO tenant rows on the normal path');
select is((app.platform_admin_list_organizations('support incident #7') ->> 'ok')::boolean, true,
  'T-007: the platform admin can use the audited platform path');
select ok(jsonb_array_length(app.platform_admin_list_organizations('cross-tenant audit') -> 'organizations') >= 2,
  'T-007: the platform path returns BOTH organizations (cross-tenant only via the separate path)');

-- ===== T-008: a tenant membership cannot reach the platform path ============= 5-6
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee01';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is(app.is_platform_admin(), false, 'T-008: a tenant org_owner is NOT a platform admin');
select throws_ok($$ select app.platform_admin_list_organizations('try') $$, '42501', NULL,
  'T-008: a tenant membership (even org_owner) CANNOT invoke the platform path');

-- ===== T-010: grant + membership is STILL membership-scoped on the normal path = 7-9
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000eef1';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is(app.is_platform_admin(), true, 'T-010 setup: eef1 holds an active platform grant');
select is((select count(*) from restaurants where organization_id = '00000000-0000-0000-0000-0000000000b0')::int, 0,
  'T-010: a principal with BOTH a platform grant and an Org A membership sees ZERO Org B rows on the normal path (grant does not widen tenant RLS)');
select ok((select count(*) from restaurants where organization_id = '00000000-0000-0000-0000-0000000000a0') >= 1,
  'T-010 control: eef1 still sees its own Org A scope on the normal path (RLS is membership-derived, not grant-derived)');
reset role;

-- ===== platform_admin_audit_events is append-only =========================== 10-13
select throws_ok($$ update platform_admin_audit_events set action = 'tampered' $$, '42501', NULL,
  'platform_admin_audit_events UPDATE is blocked (append-only)');
select throws_ok($$ delete from platform_admin_audit_events $$, '42501', NULL,
  'platform_admin_audit_events DELETE is blocked (append-only)');
select throws_ok($$ truncate platform_admin_audit_events $$, '42501', NULL,
  'platform_admin_audit_events TRUNCATE is blocked (append-only)');
select ok(exists(select 1 from platform_admin_audit_events
                 where action='platform.organizations.list'
                   and actor_app_user_id='00000000-0000-0000-0000-00000000eef0'),
  'T-007: the platform path wrote a platform_admin_audit_events row attributed to the platform admin');

select * from finish();
rollback;
