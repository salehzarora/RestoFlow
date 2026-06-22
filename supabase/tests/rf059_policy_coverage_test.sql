-- ============================================================================
-- RF-059 — pgTAP: per-command policy coverage (AC1) + grant lockdown
-- ============================================================================
-- AC1: every tenant-scoped table has EXPLICIT SELECT/INSERT/UPDATE/DELETE policies
-- (no broad FOR ALL); a coverage check finds no RLS-enabled tenant table missing a
-- per-command policy. Also asserts: RLS stays enabled+forced everywhere; the A2
-- management tables have direct INSERT/UPDATE/DELETE REVOKED from authenticated;
-- sync_operations SELECT is revoked (A4); the platform-admin audit table is a
-- separate, RLS-locked plane (A6). Catalog introspection — runs as the connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(18);

-- A throwaway temp helper: per-command policy coverage for every tenant-scoped
-- table (has organization_id, plus the tenant root `organizations`; minus the
-- global identity/platform tables). polcmd: r=SELECT a=INSERT w=UPDATE d=DELETE *=ALL.
create function pg_temp.rf059_cmd_coverage()
  returns table(relname name, rls_ok boolean, has_sel boolean, has_ins boolean, has_upd boolean, has_del boolean)
  language sql stable
as $$
  select c.relname,
         (c.relrowsecurity and c.relforcerowsecurity) as rls_ok,
         coalesce(bool_or(p.polcmd in ('r', '*')), false) as has_sel,
         coalesce(bool_or(p.polcmd in ('a', '*')), false) as has_ins,
         coalesce(bool_or(p.polcmd in ('w', '*')), false) as has_upd,
         coalesce(bool_or(p.polcmd in ('d', '*')), false) as has_del
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  left join pg_policy p on p.polrelid = c.oid
  where n.nspname = 'public'
    and c.relkind = 'r'
    and not c.relispartition
    and (
      c.relname = 'organizations'
      or exists (select 1 from pg_attribute a
                 where a.attrelid = c.oid and a.attname = 'organization_id'
                   and not a.attisdropped and a.attnum > 0)
    )
    and c.relname not in ('app_users', 'platform_admin_grants')
  group by c.relname, c.relrowsecurity, c.relforcerowsecurity
$$;

-- 1: no tenant-scoped table lacks RLS enabled+forced
select is(
  (select count(*) from pg_temp.rf059_cmd_coverage() where not rls_ok)::int, 0,
  'every tenant-scoped table has RLS enabled + forced');

-- 2: no tenant-scoped table is missing ANY per-command policy (AC1, the coverage gate)
select is(
  (select count(*) from pg_temp.rf059_cmd_coverage()
    where not (has_sel and has_ins and has_upd and has_del))::int, 0,
  'AC1: every tenant-scoped table has explicit SELECT + INSERT + UPDATE + DELETE policies (no FOR ALL gap)');

-- 3: non-vacuity — the coverage detector classifies a representative, broad set
select ok(
  (select count(*) from pg_temp.rf059_cmd_coverage()
    where relname in ('organizations','restaurants','branches','stations','memberships',
                      'employee_profiles','devices','device_pairings','device_sessions',
                      'pin_sessions','pin_attempt_states','audit_events','orders','order_items',
                      'order_item_modifiers','order_operations','payments','branch_receipt_counters',
                      'shifts','cash_drawer_sessions','shift_operations','sync_operations')) >= 22,
  'coverage detector classifies the full RF-014..056 tenant-scoped table set (>=22)');

-- 4: no broad FOR ALL ('*') policy remains on any tenant-scoped table (A1)
select is(
  (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
     join pg_policy p on p.polrelid=c.oid
   where n.nspname='public' and p.polcmd='*'
     and (c.relname='organizations'
          or exists (select 1 from pg_attribute a where a.attrelid=c.oid and a.attname='organization_id' and not a.attisdropped and a.attnum>0))
     and c.relname not in ('app_users','platform_admin_grants'))::int, 0,
  'A1: no FOR ALL (*) policy remains on any tenant-scoped table');

-- ---- A2 management-table write lockdown (direct I/U/D revoked from authenticated) ----- 5-13
select ok(not has_table_privilege('authenticated', 'public.memberships',       'insert'), 'memberships: authenticated INSERT revoked');                -- 5
select ok(not has_table_privilege('authenticated', 'public.memberships',       'update'), 'memberships: authenticated UPDATE revoked');                -- 6
select ok(not has_table_privilege('authenticated', 'public.employee_profiles', 'insert'), 'employee_profiles: authenticated INSERT revoked');          -- 7
select ok(not has_table_privilege('authenticated', 'public.devices',           'insert'), 'devices: authenticated INSERT revoked');                    -- 8
select ok(not has_table_privilege('authenticated', 'public.device_pairings',   'insert'), 'device_pairings: authenticated INSERT revoked');            -- 9
select ok(not has_table_privilege('authenticated', 'public.device_sessions',   'insert'), 'device_sessions: authenticated INSERT revoked');            -- 10
select ok(not has_table_privilege('authenticated', 'public.organizations',     'insert'), 'organizations: authenticated INSERT revoked');              -- 11
select ok(not has_table_privilege('authenticated', 'public.restaurants',       'update'), 'restaurants: authenticated UPDATE revoked');                -- 12
select ok(not has_table_privilege('authenticated', 'public.branches',          'delete'), 'branches: authenticated DELETE revoked');                   -- 13

-- ---- SELECT is preserved where reads are role/scope-safe ------------------------------ 14
select ok(has_table_privilege('authenticated', 'public.memberships', 'select'), 'memberships: authenticated SELECT preserved (role/scope-safe reads)');

-- ---- A4: sync_operations has NO direct authenticated SELECT (but keeps a policy) ------ 15-16
select ok(not has_table_privilege('authenticated', 'public.sync_operations', 'select'), 'A4: sync_operations authenticated SELECT revoked');
select ok(
  (select count(*) from pg_policy p join pg_class c on c.oid=p.polrelid where c.relname='sync_operations') >= 1,
  'sync_operations still has >=1 policy (RF-019 detector stays green)');

-- ---- A6: platform_admin_audit_events is a separate, RLS-locked, non-tenant plane ----- 17-18
select ok(
  (select c.relrowsecurity and c.relforcerowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='platform_admin_audit_events'),
  'platform_admin_audit_events has RLS enabled + forced');
select ok(
  not exists (select 1 from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace
              where n.nspname='public' and c.relname='platform_admin_audit_events'
                and a.attname='organization_id' and not a.attisdropped and a.attnum>0)
  and not has_table_privilege('authenticated', 'public.platform_admin_audit_events', 'select'),
  'platform_admin_audit_events is NOT tenant-scoped (no organization_id) and is denied to the tenant path');

select * from finish();
rollback;
