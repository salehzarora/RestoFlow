-- ============================================================================
-- TIMEZONE-GLOBAL-001 — branch-local audit timestamps (PER EVENT) + a global
-- IANA timezone catalog RPC for the Settings picker.
--
-- CONTEXT / ROOT CAUSE: audit_events.occurred_at is stored + transported as an
-- absolute UTC timestamptz (unchanged, correct). The Activity-log RPC
-- (20260711090000) FORMATTED every event with a SINGLE scope zone `v_zone` that
-- coalesces to 'UTC' when the branch's (and restaurant's) `timezone` is NULL.
-- The Israel pilot branch was onboarded with a NULL/UTC timezone (branches.
-- timezone is nullable text with NO default + NO CHECK; the pre-fix client
-- default was not Asia/Jerusalem), so timestamps rendered in UTC — ~3h behind
-- Israel local (IDT = UTC+3). Nothing in the client re-formats; the fix is here.
--
-- This migration (additive, forward-only, CREATE OR REPLACE — it does NOT edit
-- the already-applied 20260711090000/100000 migrations, and makes NO table /
-- CHECK / RLS / index / audit-data change):
--   1. CREATE OR REPLACE app.owner_audit_events so each event's occurred_at is
--      formatted, AND its Today/Yesterday/last7/last30 day-window is computed,
--      using that EVENT's OWN branch-local zone (branch -> restaurant -> scope
--      fallback), and the event now carries its resolved IANA `timezone`. An
--      all-branches view therefore shows each event in ITS branch's local time,
--      never one branch's zone applied to another. (Per-branch day windows
--      match the owner_order_history / owner_report_range model — RF-075/
--      RF-REPORT-004.) CREATE OR REPLACE PRESERVES the existing
--      authenticated-only ACL from 20260711100000.
--   2. NEW read-only app.list_timezones() (+ public wrapper) returning the
--      canonical IANA zones from pg_timezone_names (the maintained catalog the
--      backend ALREADY validates writes against — create_organization /
--      update_branch_settings / update_restaurant_settings). This replaces the
--      client's hard-coded 3/4-zone dropdown with the real global catalog. No
--      new validation is needed: the save path is already IANA-validated, so the
--      3-zone limit was purely the CLIENT dropdown, not any DB constraint.
--
-- The branch timezone itself is corrected by the OWNER via Settings (the
-- existing update_branch_settings(p_timezone)); this migration does NOT mutate
-- any branch's stored value. FORWARD-ONLY (Supabase replays on db reset). NOT
-- applied to the hosted DB by this file.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. app.owner_audit_events — PER-EVENT branch-local timestamps + day windows.
--    (Body reproduced from 20260711090000 with the timezone change ONLY;
--    authorization, allowlist projection, filters, keyset pagination all
--    unchanged. CREATE OR REPLACE keeps the authenticated-only grant.)
-- ---------------------------------------------------------------------------
create or replace function app.owner_audit_events(
  p_organization_id           uuid,
  p_restaurant_id             uuid    default null,
  p_branch_id                 uuid    default null,
  p_range                     text    default 'today',   -- today|yesterday|last7|last30
  p_category                  text    default null,
  p_action                    text    default null,
  p_sensitive_only            boolean default false,
  p_actor_app_user_id         uuid    default null,
  p_actor_employee_profile_id uuid    default null,
  p_limit                     int     default 25,
  p_cursor                    text    default null        -- keyset cursor "<occurred_at>|<id>"
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor      uuid    := app.current_app_user_id();
  v_rank       integer;
  v_currency   text;
  v_zone       text;     -- scope-representative FALLBACK zone (rows with no branch+restaurant tz)
  v_span       integer;
  v_end_offset integer;
  v_limit      integer := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_cursor_ts  timestamptz;
  v_cursor_id  uuid;
  v_result     jsonb;
begin
  if v_actor is null then
    raise exception 'owner_audit_events: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_audit_events: organization_id is required' using errcode = '42501';
  end if;

  -- Range -> (span, end_offset). Unknown range is a bad request, not a denial.
  case p_range
    when 'today'     then v_span := 1;  v_end_offset := 0;
    when 'yesterday' then v_span := 1;  v_end_offset := 1;
    when 'last7'     then v_span := 7;  v_end_offset := 0;
    when 'last30'    then v_span := 30; v_end_offset := 0;
    else raise exception 'owner_audit_events: unknown range %', p_range using errcode = '22023';
  end case;

  if p_category is not null and p_category not in (
    'orders','voids','discounts','payments','shifts','staff',
    'access','devices','menu','tables','organization','sync'
  ) then
    raise exception 'owner_audit_events: unknown category %', p_category using errcode = '22023';
  end if;

  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_audit_events: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.memberships m
    where m.app_user_id     = v_actor
      and m.organization_id = p_organization_id
      and m.status          = 'active'
      and m.deleted_at is null
      and m.role in ('manager', 'restaurant_owner', 'org_owner')
      and (m.restaurant_id is null or m.restaurant_id = p_restaurant_id)
      and (m.branch_id     is null or m.branch_id     = p_branch_id)
  ) then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_audit_events');
  end if;

  select o.default_currency into v_currency
    from public.organizations o
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'owner_audit_events: organization not found (or deleted)' using errcode = '42501';
  end if;

  -- Scope-representative FALLBACK zone, used ONLY for rows that carry neither a
  -- branch nor a restaurant timezone (org-level events). Per-event zones below
  -- prefer the event's own branch, then restaurant, then this fallback.
  v_zone := coalesce(
    (select b.timezone from public.branches b
       where b.organization_id = p_organization_id and b.id = p_branch_id and b.deleted_at is null),
    (select r.timezone from public.restaurants r
       where r.organization_id = p_organization_id and r.id = p_restaurant_id and r.deleted_at is null),
    (select min(r2.timezone) from public.restaurants r2
       where r2.organization_id = p_organization_id and r2.deleted_at is null and r2.timezone is not null),
    'UTC'
  );

  -- Keyset cursor "<occurred_at::text>|<id>". A malformed cursor is a bad request.
  if p_cursor is not null and btrim(p_cursor) <> '' then
    begin
      v_cursor_ts := split_part(p_cursor, '|', 1)::timestamptz;
      v_cursor_id := split_part(p_cursor, '|', 2)::uuid;
    exception when others then
      raise exception 'owner_audit_events: invalid cursor' using errcode = '22023';
    end;
  end if;

  with matched as (
    select ae.id,
           ae.action,
           ae.occurred_at,
           ae.reason,
           ae.restaurant_id,
           ae.branch_id,
           ae.actor_app_user_id,
           ae.actor_employee_profile_id,
           ae.device_id,
           cat.category,
           ez.zone as event_zone,
           coalesce(ep_actor.display_name, ep_appuser.display_name) as actor_name,
           r.name  as restaurant_name,
           b.name  as branch_name,
           dev.label as device_label,
           app.audit_safe_detail(ae.action, ae.old_values) as old_values_safe,
           app.audit_safe_detail(ae.action, ae.new_values) as new_values_safe
    from public.audit_events ae
    cross join lateral (
      select case
        when ae.action like 'order.discount%'                                  then 'discounts'
        when ae.action like 'order.void%'                                      then 'voids'
        when ae.action like 'order.%'                                          then 'orders'
        when ae.action like 'payment.%' or ae.action like 'receipt_number.%'   then 'payments'
        when ae.action like 'shift.%'   or ae.action like 'cash_drawer.%'      then 'shifts'
        when ae.action like 'staff.%'                                          then 'staff'
        when ae.action like 'membership.%' or ae.action like 'employee.%'
             or ae.action like 'pin_session.%'                                 then 'access'
        when ae.action like 'device.%'                                         then 'devices'
        when ae.action like 'menu.%'                                           then 'menu'
        when ae.action like 'table.%'                                          then 'tables'
        when ae.action like 'organization.%'                                   then 'organization'
        when ae.action like 'sync.%'                                           then 'sync'
        else 'other'
      end as category
    ) cat
    left join public.employee_profiles ep_actor
      on ep_actor.organization_id = ae.organization_id
     and ep_actor.id             = ae.actor_employee_profile_id
    left join lateral (
      select ep.display_name
      from public.employee_profiles ep
      where ep.organization_id = ae.organization_id
        and ae.actor_employee_profile_id is null
        and ae.actor_app_user_id is not null
        and ep.app_user_id = ae.actor_app_user_id
        and ep.deleted_at is null
      order by ep.created_at, ep.id
      limit 1
    ) ep_appuser on true
    left join public.restaurants r
      on r.organization_id = ae.organization_id and r.id = ae.restaurant_id and r.deleted_at is null
    left join public.branches b
      on b.organization_id = ae.organization_id and b.id = ae.branch_id and b.deleted_at is null
    left join public.devices dev
      on dev.organization_id = ae.organization_id and dev.id = ae.device_id and dev.deleted_at is null
    -- PER-EVENT zone: the event's own branch tz, else its restaurant tz, else
    -- the scope-representative fallback. Both the day window AND the displayed
    -- timestamp use THIS zone, so every event reads in its own branch-local time.
    cross join lateral (
      select coalesce(b.timezone, r.timezone, v_zone) as zone
    ) ez
    where ae.organization_id = p_organization_id
      and (p_restaurant_id is null or ae.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or ae.branch_id     = p_branch_id)
      and (ae.occurred_at at time zone ez.zone)::date
          between ((now() at time zone ez.zone)::date - v_end_offset - (v_span - 1))
              and ((now() at time zone ez.zone)::date - v_end_offset)
      and (p_category is null or cat.category = p_category)
      and (p_action   is null or ae.action    = p_action)
      and (p_actor_app_user_id is null or ae.actor_app_user_id = p_actor_app_user_id)
      and (p_actor_employee_profile_id is null or ae.actor_employee_profile_id = p_actor_employee_profile_id)
      and (
        not p_sensitive_only
        or ae.action like '%denied'
        or ae.action like 'order.void%'
        or ae.action like 'order.discount%'
        or ae.action like 'staff.capabilities%'
        or ae.action =    'staff.pin_set'
        or ae.action like 'membership.%'
        or ae.action like 'employee.revok%'
        or ae.action like 'device.revok%'
        or ae.action like 'shift.%'
        or ae.action like 'cash_drawer.%'
        or ae.action like 'payment.%'
      )
      and (
        p_cursor is null
        or v_cursor_ts is null
        or ae.occurred_at < v_cursor_ts
        or (ae.occurred_at = v_cursor_ts and ae.id < v_cursor_id)
      )
  ),
  page as (
    select m.*, m.occurred_at::text || '|' || m.id::text as cursor
    from matched m
    order by m.occurred_at desc, m.id desc
    limit v_limit + 1
  ),
  numbered as (
    select p.*, row_number() over (order by p.occurred_at desc, p.id desc) as rn
    from page p
  )
  select jsonb_build_object(
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
               'event_id',        n.id,
               'action',          n.action,
               'category',        n.category,
               'occurred_at',     to_char(n.occurred_at at time zone n.event_zone, 'YYYY-MM-DD HH24:MI'),
               'timezone',        n.event_zone,
               'actor_name',      n.actor_name,
               'restaurant_id',   n.restaurant_id,
               'restaurant_name', n.restaurant_name,
               'branch_id',       n.branch_id,
               'branch_name',     n.branch_name,
               'device_label',    n.device_label,
               'reason',          n.reason,
               'old_values',      n.old_values_safe,
               'new_values',      n.new_values_safe)
             order by n.rn)
      from numbered n
      where n.rn <= v_limit), '[]'::jsonb),
    'has_more',    (select count(*) from numbered) > v_limit,
    'next_cursor', case when (select count(*) from numbered) > v_limit
                        then (select cursor from numbered where rn = v_limit)
                        else null end,
    'count',       least((select count(*) from numbered), v_limit)
  ) into v_result;

  return jsonb_build_object(
    'ok', true,
    'entity', 'owner_audit_events',
    'currency_code', v_currency,
    'range', p_range,
    'limit', v_limit
  ) || v_result;
end;
$$;

comment on function app.owner_audit_events(uuid, uuid, uuid, text, text, text, boolean, uuid, uuid, int, text) is
  'AUDIT-LOG-DASHBOARD-001 + TIMEZONE-GLOBAL-001 (read-only; D-001/D-007/D-011/D-013): GUC-free paginated operational audit timeline. Authorization unchanged (actor_rank_in_scope + management-only allowlist; cashier/kitchen_staff/accountant -> permission_denied). PER-EVENT branch-local time: each event''s occurred_at is formatted AND its today/yesterday/last7/last30 day window is computed using that event''s OWN branch timezone (branch -> restaurant -> scope-representative fallback -> UTC), and the resolved IANA id is returned as `timezone`. occurred_at is stored/kept as absolute UTC; only the DISPLAY string is branch-local. Payload allowlist projection, keyset pagination, and the authenticated-only ACL are unchanged.';

-- ---------------------------------------------------------------------------
-- 2. app.list_timezones — the canonical IANA catalog for the Settings picker.
--    Reads pg_catalog.pg_timezone_names (the maintained IANA DB the write path
--    already validates against), filtered to canonical Region/City ids. No
--    tenant data; authenticated-only (no anon). Read-only.
-- ---------------------------------------------------------------------------
create or replace function app.list_timezones()
  returns jsonb
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select jsonb_build_object(
    'ok', true,
    'entity', 'timezones',
    'zones', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id',             tz.name,
               'offset_minutes', (extract(epoch from tz.utc_offset) / 60)::int)
             order by tz.name)
      from pg_catalog.pg_timezone_names tz
      where tz.name like '%/%'
        and tz.name not like 'posix/%'
        and tz.name not like 'SystemV/%'
        and tz.name !~ '^Etc/'
    ), '[]'::jsonb)
  );
$$;

comment on function app.list_timezones() is
  'TIMEZONE-GLOBAL-001 (read-only): the canonical IANA timezone catalog for the Dashboard Settings timezone picker. Returns {ok, entity:''timezones'', zones:[{id, offset_minutes}]} from pg_catalog.pg_timezone_names, filtered to canonical Region/City ids (excludes posix/, SystemV/, Etc/). This is the SAME catalog the write path validates against (create_organization / update_branch_settings / update_restaurant_settings check pg_timezone_names), so every offered id is guaranteed acceptable on save. No tenant data; authenticated-only, no anon/service_role (D-011).';

-- ---------------------------------------------------------------------------
-- 3. Thin public SECURITY INVOKER wrapper for list_timezones.
-- ---------------------------------------------------------------------------
create or replace function public.list_timezones()
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.list_timezones(); $$;

-- ---------------------------------------------------------------------------
-- 4. Grants: authenticated ONLY (never anon / PUBLIC / service_role; D-011).
--    Explicit REVOKE FROM anon closes the hosted ALTER DEFAULT PRIVILEGES path
--    (the lesson from 20260711100000 — a new public function otherwise inherits
--    an anon EXECUTE grant on hosted). owner_audit_events keeps its existing ACL
--    (CREATE OR REPLACE does not reset grants).
-- ---------------------------------------------------------------------------
revoke all    on function app.list_timezones()    from public;
revoke all    on function app.list_timezones()    from anon;
grant  execute on function app.list_timezones()    to authenticated;
revoke all    on function public.list_timezones() from public;
revoke all    on function public.list_timezones() from anon;
grant  execute on function public.list_timezones() to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists public.list_timezones();
--   drop function if exists app.list_timezones();
--   -- owner_audit_events reverts to its 20260711090000 body only by editing that
--   -- migration; this file's CREATE OR REPLACE is forward-only.
-- ============================================================================
