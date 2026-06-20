-- ============================================================================
-- RF-019 — Reusable tenant-isolation test harness  (RISK R-003, CRITICAL)
-- ============================================================================
-- A REUSABLE, table-agnostic harness that proves the multi-tenant isolation
-- baseline holds across the whole schema, and — crucially — auto-detects any
-- FUTURE tenant-scoped table that ships without RLS (the "default-deny presence
-- check", TESTING_STRATEGY §6). It does NOT duplicate the per-table RF-014/015/
-- 016/017 tests (those stay as-is); it adds a generic detector + a multi-org
-- cross-tenant smoke test + an automated negative control.
--
-- Scope boundary: this is the SKELETON harness (RF-019). The FULL canonical
-- isolation/permission suite incl. the platform-admin separation assertions
-- (SECURITY T-007..T-011, DECISION D-026) is RF-060 — only fixture scaffolding
-- for it is seeded here (no platform-admin assertions). Reuses the RF-015
-- resolver/scope helpers UNCHANGED; no new GUCs; no schema/migration change.
--
-- Detector heuristic (Codex A3): a public BASE TABLE is "tenant-scoped" iff it
-- has an `organization_id` column, PLUS `organizations` (the tenant root, which
-- has none), MINUS the explicitly global identity/platform tables `app_users`
-- and `platform_admin_grants`. Every tenant-scoped table MUST have RLS enabled,
-- RLS forced, and >= 1 policy.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(15);

-- ---- seed_isolation fixture (TESTING_STRATEGY §6), connection role / BYPASSRLS
-- Org A: R-A1/B-A1a, R-A2/B-A2a ; Org B: R-B1/B-B1a ; one org-owner member per org.
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf019-org-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf019-org-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Restaurant A1'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a0', 'Restaurant A2'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Restaurant B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('00000000-0000-0000-0000-00000000a2b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a2', 'Branch A2a'),
  ('00000000-0000-0000-0000-00000000b1b1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee0a', 'rf019-owner-a@example.test'),
  ('00000000-0000-0000-0000-00000000ee0b', 'rf019-owner-b@example.test'),
  ('00000000-0000-0000-0000-00000000ee0c', 'rf019-platadmin@example.test');
insert into memberships (app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-0000000000a0', 'org_owner'),
  ('00000000-0000-0000-0000-00000000ee0b', '00000000-0000-0000-0000-0000000000b0', 'org_owner');
-- platform-admin separation SCAFFOLDING ONLY (fixture shape for RF-060 T-008..T-011;
-- no platform-admin assertions here — those are RF-060): a grant on a tenant-only-less user.
insert into platform_admin_grants (app_user_id, granted_by) values
  ('00000000-0000-0000-0000-00000000ee0c', '00000000-0000-0000-0000-00000000ee0c');

set local role authenticated;

-- ===== cross-tenant + no-context isolation (the multi-org smoke proof) =======
-- no tenant context => zero tenant rows -------------------------------------- 1-2
-- (assumes `supabase db reset` yields an UNSEEDED DB — there is no supabase/seed.sql;
--  a future seed file must not populate tenant tables visible without context.)
select is((select count(*) from restaurants)::int, 0, 'no tenant context: zero restaurants');
select is((select count(*) from branches)::int,    0, 'no tenant context: zero branches');

-- Org A principal: sees only Org A, never Org B (cross-tenant READ denial) ---- 3-6
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee0a';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from restaurants)::int, 2, 'Org A owner: sees its 2 restaurants');
select is((select count(*) from restaurants where id = '00000000-0000-0000-0000-0000000000b1')::int, 0, 'Org A owner: cannot read the Org B restaurant');
select is((select count(*) from branches)::int, 2, 'Org A owner: sees its 2 branches');
select is((select count(*) from branches where id = '00000000-0000-0000-0000-00000000b1b1')::int, 0, 'Org A owner: cannot read the Org B branch');

-- cross-tenant WRITE denial (RLS WITH CHECK) --------------------------------- 7
select throws_ok(
  $$ insert into restaurants (organization_id, name) values ('00000000-0000-0000-0000-0000000000b0', 'rogue') $$,
  '42501', NULL, 'Org A owner: cannot INSERT a restaurant into Org B (WITH CHECK)');

-- symmetric: Org B principal sees only Org B --------------------------------- 8-9
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee0b';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000b0';
select is((select count(*) from restaurants)::int, 1, 'Org B owner: sees its 1 restaurant');
select is((select count(*) from restaurants where id = '00000000-0000-0000-0000-0000000000a1')::int, 0, 'Org B owner: cannot read an Org A restaurant');

reset role;

-- ===== generic default-deny presence DETECTOR (the reusable core) ===========
-- A throwaway temp function (rolled back with the transaction) encapsulates the
-- detector so the main check and the negative control share identical logic.
create function pg_temp.rf019_tenant_tables()
  returns table(relname name, guarded boolean)
  language sql stable
as $$
  select c.relname,
         (c.relrowsecurity
          and c.relforcerowsecurity
          and exists (select 1 from pg_policy p where p.polrelid = c.oid)) as guarded
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind in ('r', 'p')                           -- plain base tables AND partitioned parents (future high-volume tenant tables)
    and not c.relispartition                              -- exclude child partitions: RLS enforcement flows through the parent (children show relrowsecurity=false in their own catalog)
    and (
      c.relname = 'organizations'                         -- tenant root: no organization_id column, but IS tenant-scoped
      or exists (
        select 1 from pg_attribute a
        where a.attrelid = c.oid and a.attname = 'organization_id'
          and not a.attisdropped and a.attnum > 0
      )
    )
    and c.relname not in ('app_users', 'platform_admin_grants')  -- explicitly global / non-tenant; forward-defensive (they lack organization_id today, so this also guards a future refactor that mistakenly adds one)
$$;

-- every tenant-scoped table is guarded (RLS enabled + forced + >=1 policy) ---- 10
select is(
  (select count(*) from pg_temp.rf019_tenant_tables() where not guarded)::int, 0,
  'default-deny presence check: every tenant-scoped public table has RLS enabled + forced + a policy');

-- non-vacuity: the detector actually classifies the known tenant tables ------ 11
select is(
  (select count(*) from pg_temp.rf019_tenant_tables()
    where relname in ('organizations','restaurants','branches','stations',
                      'memberships','employee_profiles',
                      'devices','device_pairings','device_sessions','pin_sessions',
                      'audit_events'))::int, 11,
  'detector classifies all 11 known tenant-scoped tables (RF-014..017)');

-- the explicitly global tables are NOT treated as tenant-scoped --------------- 12
select is(
  (select count(*) from pg_temp.rf019_tenant_tables() where relname in ('app_users','platform_admin_grants'))::int, 0,
  'detector excludes the global tables app_users and platform_admin_grants');

-- ===== negative control: an unguarded tenant table MUST be flagged ==========
-- Create a deliberately broken tenant table (organization_id, but NO RLS / NO
-- policy). The detector must report it as unguarded. Transaction rollback
-- removes it — no schema artifact persists.
-- (a) no RLS at all (exercises the relrowsecurity conjunct) ------------------ 13
create table public.rf019_negctl_bad (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null
);
select is(
  (select count(*) from pg_temp.rf019_tenant_tables() where relname = 'rf019_negctl_bad' and not guarded)::int, 1,
  'negative control: an unguarded tenant table (no RLS) IS flagged by the detector');

-- (b) RLS enabled+forced but ZERO policies — the canonical "ran ENABLE/FORCE,
--     forgot CREATE POLICY" slip (exercises the policy-presence conjunct) ----- 14
create table public.rf019_negctl_norls (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null
);
alter table public.rf019_negctl_norls enable row level security;
alter table public.rf019_negctl_norls force  row level security;
select is(
  (select count(*) from pg_temp.rf019_tenant_tables() where relname = 'rf019_negctl_norls' and not guarded)::int, 1,
  'negative control: RLS enabled+forced but ZERO policies IS flagged');

-- (c) a policy present but FORCE omitted — the table owner silently bypasses
--     non-forced RLS (exercises the relforcerowsecurity conjunct) ------------- 15
create table public.rf019_negctl_noforce (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null
);
alter table public.rf019_negctl_noforce enable row level security;
create policy rf019_negctl_noforce_p on public.rf019_negctl_noforce for all to authenticated using (true);
select is(
  (select count(*) from pg_temp.rf019_tenant_tables() where relname = 'rf019_negctl_noforce' and not guarded)::int, 1,
  'negative control: a policy present but FORCE omitted IS flagged');

select * from finish();
rollback;  -- removes the fixtures, all rf019_negctl_* throwaway tables, and the temp function
