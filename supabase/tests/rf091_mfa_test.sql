-- ============================================================================
-- RF-091 — pgTAP: MFA/aal2 gate on the platform RPCs (RF-050, Q-008)
-- ============================================================================
-- Same active platform admin: at aal1 the platform RPCs are denied; at aal2 they
-- succeed. A JWT with no assurance claim is also denied (fail-closed).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(4);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf091mfa-a', 'USD');
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000adf0', 'rf091mfa-admin@example.test');
insert into app_users (id, email, auth_user_id) values
  ('00000000-0000-0000-0000-00000000ee0f', 'rf091mfa-admin@example.test', '00000000-0000-0000-0000-00000000adf0');
insert into platform_admin_grants (id, app_user_id, status, granted_by) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-00000000ee0f', 'active', '00000000-0000-0000-0000-00000000ee0f');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000adf0';

-- aal1 -> denied (privileged platform access requires MFA)
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000adf0","aal":"aal1"}';
select throws_ok($$ select app.platform_admin_organization_overview('mfa test') $$, '42501', null, 'aal1: platform overview denied (MFA required)');

-- no assurance claim -> denied (fail-closed)
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000adf0"}';
select throws_ok($$ select app.platform_admin_get_organization('00000000-0000-0000-0000-0000000000a0','mfa test') $$, '42501', null, 'no aal claim: platform detail denied (fail-closed)');

-- aal2 -> allowed
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000adf0","aal":"aal2"}';
select is((app.platform_admin_organization_overview('mfa test') ->> 'ok')::boolean, true, 'aal2: platform overview allowed');
select is((app.platform_admin_recent_audit('mfa test', 5) ->> 'ok')::boolean, true, 'aal2: recent-audit allowed');

select * from finish();
rollback;
