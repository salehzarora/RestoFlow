-- ============================================================================
-- RF-091 — pgTAP: platform admin can read the overview/detail/recent-audit RPCs;
-- every access is audited; the reads are read-only (AC1/AC3 + read-only).
-- ============================================================================
-- The platform admin holds an ACTIVE grant + NO tenant membership, authenticates
-- via a JWT at aal2 (MFA gate), and reads narrow summary data. Each call writes a
-- platform_admin_audit_events row; no tenant rows change.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(13);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf091oa-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf091oa-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000adf0', 'rf091oa-admin@example.test'),
  ('00000000-0000-0000-0000-00000000ad01', 'rf091oa-owner@example.test');
insert into app_users (id, email, auth_user_id) values
  ('00000000-0000-0000-0000-00000000ee0f', 'rf091oa-admin@example.test', '00000000-0000-0000-0000-00000000adf0'),
  ('00000000-0000-0000-0000-00000000ee01', 'rf091oa-owner@example.test', '00000000-0000-0000-0000-00000000ad01');
-- platform admin: ACTIVE grant, NO membership
insert into platform_admin_grants (id, app_user_id, status, granted_by) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-00000000ee0f', 'active', '00000000-0000-0000-0000-00000000ee0f');
-- a tenant org_owner in Org A (counts as an active membership for Org A)
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', 'org_owner');

-- snapshot tenant + audit counts before
create temp table before_counts as select
  (select count(*) from organizations) as orgs,
  (select count(*) from restaurants)   as rests,
  (select count(*) from branches)      as branches,
  (select count(*) from memberships)   as mems,
  (select count(*) from platform_admin_audit_events) as audits;

-- ===== act as the platform admin (JWT, aal2) =====
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000adf0","email":"rf091oa-admin@example.test","aal":"aal2"}';

create temp table ov as select app.platform_admin_organization_overview('support overview #1') as res;
create temp table de as select app.platform_admin_get_organization('00000000-0000-0000-0000-0000000000a0','support detail #2') as res;
create temp table ra as select app.platform_admin_recent_audit('support audit #3', 10) as res;

-- ----- overview returns both orgs + Org A counts -----
select is((select (res->>'ok')::boolean from ov), true, 'overview ok=true');
select is((select jsonb_array_length(res->'organizations') from ov)::int, 2, 'overview lists BOTH organizations (cross-tenant via platform path)');
select is(
  (select (e->>'restaurants_count')::int
   from ov, lateral jsonb_array_elements(res->'organizations') e
   where (e->>'id') = '00000000-0000-0000-0000-0000000000a0'),
  1, 'overview: Org A restaurants_count = 1');
select is(
  (select (e->>'active_memberships_count')::int
   from ov, lateral jsonb_array_elements(res->'organizations') e
   where (e->>'id') = '00000000-0000-0000-0000-0000000000a0'),
  1, 'overview: Org A active_memberships_count = 1');

-- ----- detail returns Org A + restaurant summary -----
select is((select (res->'organization'->>'id') from de), '00000000-0000-0000-0000-0000000000a0', 'detail returns the requested org');
select is((select jsonb_array_length(res->'restaurants') from de)::int, 1, 'detail returns Org A restaurant summary (1)');
select is((select (res->>'branches_count')::int from de), 1, 'detail: Org A branches_count = 1');

-- ----- recent audit returns events -----
select cmp_ok((select jsonb_array_length(res->'events') from ra)::int, '>=', 2, 'recent audit returns events');

-- ===== every access audited (reset to bypass for table reads) =====
reset role;
select is((select count(*) from platform_admin_audit_events where action='platform.organizations.overview')::int, 1, 'overview wrote an audit row');
select is((select target_organization_id from platform_admin_audit_events where action='platform.organization.read' limit 1),
          '00000000-0000-0000-0000-0000000000a0'::uuid, 'detail audit row records target_organization_id');
select is((select count(*) from platform_admin_audit_events where action='platform.audit.read')::int, 1, 'recent-audit read wrote an audit row');
select is((select actor_app_user_id from platform_admin_audit_events where action='platform.organizations.overview' limit 1),
          '00000000-0000-0000-0000-00000000ee0f'::uuid, 'audit row records the platform-admin actor');

-- ===== read-only: tenant rows unchanged (only platform audit grew) =====
select ok(
  (select b.orgs = (select count(*) from organizations)
       and b.rests = (select count(*) from restaurants)
       and b.branches = (select count(*) from branches)
       and b.mems = (select count(*) from memberships)
   from before_counts b),
  'read-only: no organization/restaurant/branch/membership rows were created or changed');

select * from finish();
rollback;
