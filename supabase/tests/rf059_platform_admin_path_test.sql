-- ============================================================================
-- RF-059 — pgTAP: minimal isolated + audited platform-admin path (A6, D-026, T-007..T-010)
-- ============================================================================
-- The platform plane is SEPARATE from the tenant plane:
--   * a platform_admin_grant alone is NOT a tenant membership — it yields ZERO
--     tenant rows through the normal path (T-009);
--   * a tenant member cannot call the platform path (T-008);
--   * the platform path (app.platform_admin_list_organizations) requires a reason,
--     returns cross-tenant data only to a platform admin, and writes a platform-scoped
--     audit row (T-007); the audit table is unreadable from the tenant path.
-- Fixtures inserted as the BYPASSRLS connection role; assertions run as authenticated.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(9);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf059pa-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf059pa-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee0f', 'rf059pa-platadmin@example.test'),
  ('00000000-0000-0000-0000-00000000ee01', 'rf059pa-cashier@example.test');
-- the platform admin holds an ACTIVE grant and NO tenant membership.
insert into platform_admin_grants (id, app_user_id, status, granted_by) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-00000000ee0f', 'active', '00000000-0000-0000-0000-00000000ee0f');
-- the tenant member is an org_owner in Org A (the most privileged tenant role).
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', 'org_owner');

set local role authenticated;

-- ===== platform admin (grant holder, NO membership) ========================= 1-5
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee0f';
set local app.current_organization_id = '';
-- RF-119: the platform path now requires MFA aal2 (app.platform_admin_guard). The
-- assurance level is read ONLY from request.jwt.claims (no sub => auth.uid() stays
-- null, so the GUC identity above is preserved); provide the required aal2 claim.
set local request.jwt.claims = '{"aal":"aal2"}';
select is(app.is_platform_admin(), true, 'grant holder: app.is_platform_admin() is true');                                                   -- 1
select is((app.platform_admin_list_organizations('support incident #42') ->> 'ok')::boolean, true,
  'platform admin can use the audited platform path (ok=true)');                                                                              -- 2
select is(
  jsonb_array_length(app.platform_admin_list_organizations('cross-tenant audit') -> 'organizations')::int, 2,
  'platform admin sees BOTH organizations (cross-tenant, only via the platform path)');                                                       -- 3
-- T-009: a platform-admin grant is NOT a tenant membership — zero tenant rows
select is((select count(*) from restaurants)::int, 0,
  'T-009: a platform-admin grant alone yields ZERO tenant rows (grant != membership)');                                                       -- 4
select throws_ok($$ select app.platform_admin_list_organizations('') $$, '42501', NULL,
  'platform path requires a non-empty reason (reason-tagged access)');                                                                        -- 5

-- ===== tenant member (org_owner, NO grant) =================================== 6-7
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee01';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is(app.is_platform_admin(), false, 'tenant org_owner: app.is_platform_admin() is false');                                              -- 6
select throws_ok($$ select app.platform_admin_list_organizations('try') $$, '42501', NULL,
  'T-008: a tenant membership (even org_owner) CANNOT invoke the platform path');                                                             -- 7

reset role;

-- ===== T-007: every platform access wrote a platform-scoped audit row ======= 8-9
select ok(
  (select count(*) from platform_admin_audit_events where action = 'platform.organizations.list') >= 1,
  'T-007: the platform path wrote a platform_admin_audit_events row');
select is(
  (select actor_app_user_id from platform_admin_audit_events where action='platform.organizations.list' order by created_at limit 1),
  '00000000-0000-0000-0000-00000000ee0f'::uuid,
  'the platform audit row records the platform-admin actor');

select * from finish();
rollback;
