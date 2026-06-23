-- ============================================================================
-- RF-091 — pgTAP: revoked/suspended platform grant is denied (status check)
-- ============================================================================
-- app.is_platform_admin() only accepts an ACTIVE grant, so a revoked or suspended
-- grant cannot reach the platform RPCs (even with aal2 + a reason).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(4);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000adf0', 'rf091rg-revoked@example.test'),
  ('00000000-0000-0000-0000-00000000adf1', 'rf091rg-suspended@example.test');
insert into app_users (id, email, auth_user_id) values
  ('00000000-0000-0000-0000-00000000ee0f', 'rf091rg-revoked@example.test', '00000000-0000-0000-0000-00000000adf0'),
  ('00000000-0000-0000-0000-00000000ee10', 'rf091rg-suspended@example.test', '00000000-0000-0000-0000-00000000adf1');
-- a REVOKED grant and a SUSPENDED grant (neither is ACTIVE)
insert into platform_admin_grants (id, app_user_id, status, granted_by, revoked_by, revoked_at) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-00000000ee0f', 'revoked', '00000000-0000-0000-0000-00000000ee0f', '00000000-0000-0000-0000-00000000ee0f', now());
insert into platform_admin_grants (id, app_user_id, status, granted_by) values
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-00000000ee10', 'suspended', '00000000-0000-0000-0000-00000000ee10');

set local role authenticated;

-- revoked grant -> not a platform admin -> denied
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000adf0","aal":"aal2"}';
select is(app.is_platform_admin(), false, 'revoked grant: is_platform_admin() is false');
select throws_ok($$ select app.platform_admin_organization_overview('revoked attempt') $$, '42501', null, 'revoked grant: platform overview denied');

-- suspended grant -> not a platform admin -> denied
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000adf1';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000adf1","aal":"aal2"}';
select is(app.is_platform_admin(), false, 'suspended grant: is_platform_admin() is false');
select throws_ok($$ select app.platform_admin_organization_overview('suspended attempt') $$, '42501', null, 'suspended grant: platform overview denied');

select * from finish();
rollback;
