-- ============================================================================
-- PLATFORM-ADMIN-125C.1 — the Platform Console read contract
-- (D-011/D-012/D-013/D-026; RISK R-003)
-- ============================================================================
-- Five cross-tenant READ endpoints the internal Platform Console (125C.2) will
-- consume. FUNCTIONS AND GRANTS ONLY: no table, no column, no index, no data.
-- The only rows any of these write are the reason-tagged platform-admin audit
-- events that platform access has always produced (D-013).
--
-- WHY NEW ENDPOINTS RATHER THAN WIDENING THE OLD ONES. RF-091's
-- platform_admin_organization_overview / _get_organization / _recent_audit are
-- deployed and in use by the live Admin app. Changing their signatures would
-- risk PostgREST resolution and the running client, so they are left untouched
-- and page-specific contracts are added beside them. Each new endpoint is
-- bounded, filterable and independently auditable.
--
-- THE GATE IS THE FEATURE. Every one of these reads EVERY tenant's data, so
-- each body's FIRST statement is app.platform_admin_guard(p_reason): an active
-- platform_admin_grant AND a verified aal2 JWT AND a non-empty reason. A tenant
-- membership — even org_owner — can never satisfy it (D-026, T-008), and the
-- guard is the boundary; the client's own assurance state is UX only.
--
-- WHAT IS DELIBERATELY NOT HERE: no money (no price_minor), no device counts,
-- no order or payment data, no member identities, no created_by/creation_request
-- UUIDs, no audit `details` blob. A platform operator needs to run the business,
-- not to read the tenants' books.
--
-- CONTENTS
--   1. app.platform_admin_console_overview   — platform-wide counts
--   2. app.platform_admin_list_subscribers   — bounded, filterable, sortable
--   3. app.platform_admin_get_subscriber     — one subscriber, V1 envelope
--   4. app.platform_admin_list_restaurants   — platform-wide, bounded
--   5. app.platform_admin_audit_search       — keyset-paginated, filterable
--   6. thin public SECURITY INVOKER wrappers
--   7. grants — REPORT-123: BOTH layers, authenticated only, anon revoked
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. app.platform_admin_console_overview — the Overview page's numbers.
--
--    Counts only. Soft-deleted organizations, restaurants and branches are
--    excluded everywhere, and a subscription belonging to a tombstoned
--    organization is NOT counted — otherwise the subscription totals would
--    disagree with the organization total they sit beside.
--    Memberships use status = 'active', matching RF-091's existing definition
--    exactly so the two endpoints can never quote different numbers.
-- ----------------------------------------------------------------------------
create or replace function app.platform_admin_console_overview(p_reason text)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor uuid;
begin
  v_actor := app.platform_admin_guard(p_reason);

  insert into public.platform_admin_audit_events
    (actor_app_user_id, target_organization_id, action, reason, details)
  values
    (v_actor, null, 'platform.console.overview', btrim(p_reason),
     jsonb_build_object('scope', 'platform_counts'));

  return jsonb_build_object(
    'ok', true,
    'organizations_total',
      (select count(*) from public.organizations o where o.deleted_at is null),
    'organizations_active',
      (select count(*) from public.organizations o where o.deleted_at is null and o.status = 'active'),
    'organizations_suspended',
      (select count(*) from public.organizations o where o.deleted_at is null and o.status = 'suspended'),
    'restaurants_total',
      (select count(*) from public.restaurants r
         join public.organizations o on o.id = r.organization_id and o.deleted_at is null
        where r.deleted_at is null),
    'branches_total',
      (select count(*) from public.branches b
         join public.organizations o on o.id = b.organization_id and o.deleted_at is null
        where b.deleted_at is null),
    'active_memberships_total',
      (select count(*) from public.memberships m
         join public.organizations o on o.id = m.organization_id and o.deleted_at is null
        where m.status = 'active'),
    'subscriptions_trialing', app.platform_admin_subscription_count('trialing'),
    'subscriptions_active',   app.platform_admin_subscription_count('active'),
    'subscriptions_past_due', app.platform_admin_subscription_count('past_due'),
    'subscriptions_canceled', app.platform_admin_subscription_count('canceled'),
    'server_ts', now());
end;
$$;

-- Small helper so the four subscription counts cannot drift apart. Deliberately
-- NOT granted to anyone: it is an internal detail of the overview above, called
-- only from a SECURITY DEFINER body that has already passed the guard.
create or replace function app.platform_admin_subscription_count(p_status text)
  returns bigint
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select count(*)
    from public.organization_subscriptions s
    join public.organizations o on o.id = s.organization_id and o.deleted_at is null
   where s.status = p_status;
$$;

-- ----------------------------------------------------------------------------
-- 2. app.platform_admin_list_subscribers — the Subscribers page.
--
--    "Subscriber" is the owner-facing word for the ORGANIZATION: it is the
--    tenant root (D-003) and it is the billing unit (organization_subscriptions
--    is keyed on organization_id). No new entity is introduced.
--
--    A LEFT JOIN to the subscription and its plan, so an organization with no
--    subscription comes back with NULL subscription fields rather than being
--    dropped or given a fabricated default — today every production tenant is
--    in exactly that state.
--
--    Every input is validated against a fixed vocabulary and the sort is a CASE
--    ladder, so there is no dynamic SQL anywhere and no injection surface. The
--    expensive per-row counts run on the PAGE only, never on the whole set.
-- ----------------------------------------------------------------------------
create or replace function app.platform_admin_list_subscribers(
  p_reason              text,
  p_limit               integer default 50,
  p_offset              integer default 0,
  p_search              text    default null,
  p_org_status          text    default null,
  p_plan_code           text    default null,
  p_subscription_status text    default null,
  p_sort                text    default 'name_asc'
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor  uuid;
  v_limit  integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_search text    := nullif(btrim(coalesce(p_search, '')), '');
  v_sort   text    := coalesce(nullif(btrim(coalesce(p_sort, '')), ''), 'name_asc');
  v_total  bigint;
  v_rows   jsonb;
begin
  v_actor := app.platform_admin_guard(p_reason);

  if p_org_status is not null and p_org_status not in ('active', 'suspended') then
    raise exception 'platform admin: organization status must be active|suspended'
      using errcode = '22023';
  end if;
  if p_subscription_status is not null
     and p_subscription_status not in ('trialing', 'active', 'past_due', 'canceled') then
    raise exception 'platform admin: subscription status must be trialing|active|past_due|canceled'
      using errcode = '22023';
  end if;
  if p_plan_code is not null
     and not exists (select 1 from public.plans p where p.code = p_plan_code) then
    raise exception 'platform admin: unknown plan code' using errcode = '22023';
  end if;
  if v_sort not in ('name_asc', 'name_desc', 'created_asc', 'created_desc',
                    'period_end_asc', 'period_end_desc') then
    raise exception 'platform admin: unsupported sort key' using errcode = '22023';
  end if;

  insert into public.platform_admin_audit_events
    (actor_app_user_id, target_organization_id, action, reason, details)
  values
    (v_actor, null, 'platform.subscribers.list', btrim(p_reason),
     jsonb_build_object('limit', v_limit, 'offset', v_offset, 'sort', v_sort,
                        'filtered', (v_search is not null or p_org_status is not null
                                     or p_plan_code is not null
                                     or p_subscription_status is not null)));

  with base as (
    select o.id, o.name, o.status, o.created_at, o.default_currency,
           s.plan_code, pl.display_name as plan_display_name,
           s.status as subscription_status,
           s.current_period_start, s.current_period_end
      from public.organizations o
      left join public.organization_subscriptions s on s.organization_id = o.id
      left join public.plans pl on pl.code = s.plan_code
     where o.deleted_at is null
       and (p_org_status is null or o.status = p_org_status)
       and (p_plan_code is null or s.plan_code = p_plan_code)
       and (p_subscription_status is null or s.status = p_subscription_status)
       and (v_search is null or o.name ilike '%' || v_search || '%')
  ),
  ranked as (
    select b.*, row_number() over (order by
             case when v_sort = 'name_asc'        then b.name end asc,
             case when v_sort = 'name_desc'       then b.name end desc,
             case when v_sort = 'created_asc'     then b.created_at end asc,
             case when v_sort = 'created_desc'    then b.created_at end desc,
             case when v_sort = 'period_end_asc'  then b.current_period_end end asc nulls last,
             case when v_sort = 'period_end_desc' then b.current_period_end end desc nulls last,
             b.id) as rn
      from base b
  ),
  page as (
    select * from ranked where rn > v_offset and rn <= v_offset + v_limit
  )
  select (select count(*) from base),
         coalesce(jsonb_agg(
           jsonb_build_object(
             'organization_id',          p.id,
             'organization_name',        p.name,
             'organization_status',      p.status,
             'created_at',               p.created_at,
             'default_currency',         p.default_currency,
             'restaurants_count',
               (select count(*) from public.restaurants r
                 where r.organization_id = p.id and r.deleted_at is null),
             'branches_count',
               (select count(*) from public.branches b
                 where b.organization_id = p.id and b.deleted_at is null),
             'active_memberships_count',
               (select count(*) from public.memberships m
                 where m.organization_id = p.id and m.status = 'active'),
             'plan_code',                p.plan_code,
             'plan_display_name',        p.plan_display_name,
             'subscription_status',      p.subscription_status,
             'current_period_start',     p.current_period_start,
             'current_period_end',       p.current_period_end)
           order by p.rn), '[]'::jsonb)
    into v_total, v_rows
    from page p;

  return jsonb_build_object(
    'ok', true, 'rows', v_rows, 'total_count', v_total,
    'limit', v_limit, 'offset', v_offset, 'server_ts', now());
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. app.platform_admin_get_subscriber — one subscriber, the console's V1 shape.
--
--    A NEW envelope rather than a change to RF-091's get_organization: that one
--    stays byte-identical for the deployed client, while this one adds the
--    subscription block and drops created_by_app_user_id / creation_request_id
--    (raw UUIDs the console cannot resolve to a person, and PII-adjacent for no
--    product gain).
--
--    An unknown, or tombstoned, organization raises 42501 — the SAME code as a
--    denial, deliberately, so a caller who somehow reached this function cannot
--    use it to probe which organization ids exist. The attempt is audited either
--    way: the audit row is written BEFORE the lookup, matching RF-091.
-- ----------------------------------------------------------------------------
create or replace function app.platform_admin_get_subscriber(
  p_organization_id uuid,
  p_reason          text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor uuid;
  v_org   public.organizations%rowtype;
  v_sub   jsonb;
  v_rests jsonb;
begin
  v_actor := app.platform_admin_guard(p_reason);

  insert into public.platform_admin_audit_events
    (actor_app_user_id, target_organization_id, action, reason, details)
  values
    (v_actor, p_organization_id, 'platform.subscriber.detail', btrim(p_reason),
     jsonb_build_object('organization_id', p_organization_id));

  select * into v_org
    from public.organizations o
   where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'platform admin: organization % not found', p_organization_id
      using errcode = '42501';
  end if;

  -- null when the tenant has no subscription row at all (every production
  -- tenant today) — never an invented "free" default.
  select jsonb_build_object(
           'plan_code', s.plan_code,
           'plan_display_name', pl.display_name,
           'status', s.status,
           'current_period_start', s.current_period_start,
           'current_period_end', s.current_period_end)
    into v_sub
    from public.organization_subscriptions s
    left join public.plans pl on pl.code = s.plan_code
   where s.organization_id = p_organization_id;

  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', r.id, 'name', r.name, 'status', r.status,
             'branches_count',
               (select count(*) from public.branches b
                 where b.organization_id = r.organization_id
                   and b.restaurant_id = r.id and b.deleted_at is null))
           order by r.name, r.id), '[]'::jsonb)
    into v_rests
    from public.restaurants r
   where r.organization_id = p_organization_id and r.deleted_at is null;

  return jsonb_build_object(
    'ok', true,
    'organization', jsonb_build_object(
      'id', v_org.id, 'name', v_org.name, 'status', v_org.status,
      'default_currency', v_org.default_currency, 'created_at', v_org.created_at),
    'counts', jsonb_build_object(
      'restaurants_count',
        (select count(*) from public.restaurants r
          where r.organization_id = p_organization_id and r.deleted_at is null),
      'branches_count',
        (select count(*) from public.branches b
          where b.organization_id = p_organization_id and b.deleted_at is null),
      'active_memberships_count',
        (select count(*) from public.memberships m
          where m.organization_id = p_organization_id and m.status = 'active')),
    'subscription', coalesce(v_sub, 'null'::jsonb),
    'restaurants', v_rests,
    'server_ts', now());
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. app.platform_admin_list_restaurants — the Restaurants page.
--
--    The FIRST platform-wide restaurant read in the system: until now
--    restaurants were reachable only one organization at a time, so a console
--    list would have meant N+1 calls. Bounded and searchable from the start.
--
--    effective_currency uses the SAME rule as app.list_menu / app.pos_menu —
--    coalesce(restaurant override, organization default) — so the console can
--    never disagree with what the tills and the Dashboard show.
-- ----------------------------------------------------------------------------
create or replace function app.platform_admin_list_restaurants(
  p_reason     text,
  p_limit      integer default 50,
  p_offset     integer default 0,
  p_search     text    default null,
  p_org_status text    default null,
  p_sort       text    default 'name_asc'
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor  uuid;
  v_limit  integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_search text    := nullif(btrim(coalesce(p_search, '')), '');
  v_sort   text    := coalesce(nullif(btrim(coalesce(p_sort, '')), ''), 'name_asc');
  v_total  bigint;
  v_rows   jsonb;
begin
  v_actor := app.platform_admin_guard(p_reason);

  if p_org_status is not null and p_org_status not in ('active', 'suspended') then
    raise exception 'platform admin: organization status must be active|suspended'
      using errcode = '22023';
  end if;
  if v_sort not in ('name_asc', 'name_desc', 'created_asc', 'created_desc',
                    'organization_asc', 'organization_desc') then
    raise exception 'platform admin: unsupported sort key' using errcode = '22023';
  end if;

  insert into public.platform_admin_audit_events
    (actor_app_user_id, target_organization_id, action, reason, details)
  values
    (v_actor, null, 'platform.restaurants.list', btrim(p_reason),
     jsonb_build_object('limit', v_limit, 'offset', v_offset, 'sort', v_sort,
                        'filtered', (v_search is not null or p_org_status is not null)));

  with base as (
    select r.id as restaurant_id, r.name as restaurant_name, r.status as restaurant_status,
           r.created_at, r.currency_override,
           o.id as organization_id, o.name as organization_name, o.status as organization_status,
           coalesce(r.currency_override, o.default_currency) as effective_currency
      from public.restaurants r
      join public.organizations o
        on o.id = r.organization_id and o.deleted_at is null
     where r.deleted_at is null
       and (p_org_status is null or o.status = p_org_status)
       -- search spans the restaurant AND its subscriber: an operator looking
       -- for "Bravo" means either, and the predicate stays a plain OR.
       and (v_search is null
            or r.name ilike '%' || v_search || '%'
            or o.name ilike '%' || v_search || '%')
  ),
  ranked as (
    select b.*, row_number() over (order by
             case when v_sort = 'name_asc'          then b.restaurant_name end asc,
             case when v_sort = 'name_desc'         then b.restaurant_name end desc,
             case when v_sort = 'created_asc'       then b.created_at end asc,
             case when v_sort = 'created_desc'      then b.created_at end desc,
             case when v_sort = 'organization_asc'  then b.organization_name end asc,
             case when v_sort = 'organization_desc' then b.organization_name end desc,
             b.restaurant_id) as rn
      from base b
  ),
  page as (
    select * from ranked where rn > v_offset and rn <= v_offset + v_limit
  )
  select (select count(*) from base),
         coalesce(jsonb_agg(
           jsonb_build_object(
             'restaurant_id',       p.restaurant_id,
             'restaurant_name',     p.restaurant_name,
             'restaurant_status',   p.restaurant_status,
             'organization_id',     p.organization_id,
             'organization_name',   p.organization_name,
             'organization_status', p.organization_status,
             'branches_count',
               (select count(*) from public.branches b
                 where b.organization_id = p.organization_id
                   and b.restaurant_id = p.restaurant_id and b.deleted_at is null),
             'created_at',          p.created_at,
             'currency_override',   p.currency_override,
             'effective_currency',  p.effective_currency)
           order by p.rn), '[]'::jsonb)
    into v_total, v_rows
    from page p;

  return jsonb_build_object(
    'ok', true, 'rows', v_rows, 'total_count', v_total,
    'limit', v_limit, 'offset', v_offset, 'server_ts', now());
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. app.platform_admin_audit_search — the Audit Log page.
--
--    KEYSET, not offset: the audit table only grows, and an offset page 50 gets
--    slower and starts skipping rows as new events arrive underneath it. The
--    cursor is the (occurred_at, id) of the last row handed out, compared as a
--    row value so ties on the timestamp are still exact.
--
--    The projection is the same safe six RF-091's recent_audit exposes; the
--    `details` jsonb stays out, so nothing a future audited action puts in it
--    can leak through this page. Actor stays an opaque id in this phase — a
--    name/email join would put tenant PII on the platform plane for no V1 need.
--
--    NOTE (performance): there is no (occurred_at DESC, id DESC) index on
--    platform_admin_audit_events today, so an unfiltered scan sorts. The
--    existing target_organization_id index does serve the org-filtered query,
--    which is the common console case. Adding an index is out of scope for a
--    function-and-grant migration — see the phase report.
-- ----------------------------------------------------------------------------
create or replace function app.platform_admin_audit_search(
  p_reason                 text,
  p_limit                  integer     default 50,
  p_cursor_occurred_at     timestamptz default null,
  p_cursor_id              uuid        default null,
  p_action                 text        default null,
  p_target_organization_id uuid        default null,
  p_from                   timestamptz default null,
  p_to                     timestamptz default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor uuid;
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_page  jsonb;   -- v_limit + 1 rows: the extra one answers has_more
  v_rows  jsonb;
  v_last  jsonb;
begin
  v_actor := app.platform_admin_guard(p_reason);

  -- A half cursor would silently degrade to an unbounded scan and hand back
  -- rows the caller has already seen; refuse it instead.
  if (p_cursor_occurred_at is null) <> (p_cursor_id is null) then
    raise exception 'platform admin: a cursor needs BOTH occurred_at and id'
      using errcode = '22023';
  end if;
  if p_from is not null and p_to is not null and p_to < p_from then
    raise exception 'platform admin: the date range ends before it starts'
      using errcode = '22023';
  end if;

  insert into public.platform_admin_audit_events
    (actor_app_user_id, target_organization_id, action, reason, details)
  values
    (v_actor, p_target_organization_id, 'platform.audit.search', btrim(p_reason),
     jsonb_build_object('limit', v_limit, 'paged', (p_cursor_id is not null)));

  -- Fetch ONE more than the page so has_more needs no second count.
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', k.id,
             'actor_app_user_id', k.actor_app_user_id,
             'target_organization_id', k.target_organization_id,
             'action', k.action,
             'reason', k.reason,
             'occurred_at', k.occurred_at)
           order by k.occurred_at desc, k.id desc), '[]'::jsonb)
    into v_page
    from (
      select a.id, a.actor_app_user_id, a.target_organization_id,
             a.action, a.reason, a.occurred_at
        from public.platform_admin_audit_events a
       where (p_action is null or a.action = p_action)
         and (p_target_organization_id is null
              or a.target_organization_id = p_target_organization_id)
         and (p_from is null or a.occurred_at >= p_from)
         and (p_to   is null or a.occurred_at <= p_to)
         and (p_cursor_occurred_at is null
              or (a.occurred_at, a.id) < (p_cursor_occurred_at, p_cursor_id))
       order by a.occurred_at desc, a.id desc
       limit v_limit + 1
    ) k;

  if jsonb_array_length(v_page) > v_limit then
    -- Trim to the page, and hand back the LAST kept row as the next cursor.
    select coalesce(jsonb_agg(e order by o), '[]'::jsonb)
      into v_rows
      from jsonb_array_elements(v_page) with ordinality as t(e, o)
     where o <= v_limit;
    v_last := v_rows -> (v_limit - 1);
    return jsonb_build_object(
      'ok', true,
      'rows', v_rows,
      'has_more', true,
      'next_cursor', jsonb_build_object(
        'occurred_at', v_last -> 'occurred_at',
        'id',          v_last -> 'id'),
      'limit', v_limit,
      'server_ts', now());
  end if;

  return jsonb_build_object(
    'ok', true,
    'rows', v_page,
    'has_more', false,
    'next_cursor', 'null'::jsonb,
    'limit', v_limit,
    'server_ts', now());
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. Thin public SECURITY INVOKER wrappers (RF-125 pattern).
--    Delegation only: no authorization logic, no transformation, no richer
--    return. The whole gate stays inside the app.* bodies.
-- ----------------------------------------------------------------------------
create or replace function public.platform_admin_console_overview(p_reason text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.platform_admin_console_overview(p_reason); $$;

create or replace function public.platform_admin_list_subscribers(
  p_reason text, p_limit integer default 50, p_offset integer default 0,
  p_search text default null, p_org_status text default null,
  p_plan_code text default null, p_subscription_status text default null,
  p_sort text default 'name_asc')
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.platform_admin_list_subscribers(p_reason, p_limit, p_offset, p_search,
                                                 p_org_status, p_plan_code,
                                                 p_subscription_status, p_sort); $$;

create or replace function public.platform_admin_get_subscriber(
  p_organization_id uuid, p_reason text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.platform_admin_get_subscriber(p_organization_id, p_reason); $$;

create or replace function public.platform_admin_list_restaurants(
  p_reason text, p_limit integer default 50, p_offset integer default 0,
  p_search text default null, p_org_status text default null,
  p_sort text default 'name_asc')
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.platform_admin_list_restaurants(p_reason, p_limit, p_offset, p_search,
                                                 p_org_status, p_sort); $$;

create or replace function public.platform_admin_audit_search(
  p_reason text, p_limit integer default 50,
  p_cursor_occurred_at timestamptz default null, p_cursor_id uuid default null,
  p_action text default null, p_target_organization_id uuid default null,
  p_from timestamptz default null, p_to timestamptz default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.platform_admin_audit_search(p_reason, p_limit, p_cursor_occurred_at,
                                             p_cursor_id, p_action,
                                             p_target_organization_id, p_from, p_to); $$;

-- ----------------------------------------------------------------------------
-- 7. Grants — authenticated only, at BOTH layers.
--
--    REPORT-123 IS BINDING. The wrappers are SECURITY INVOKER: they run with
--    the CALLER's privileges and delegate to the SECURITY DEFINER body, so
--    granting only the wrapper grants NOTHING — the caller is refused on the
--    inner function with 42501, which is exactly how the currency breakdown
--    reached production broken. Both layers are granted below and the pgTAP
--    suite pins both AS the real `authenticated` role.
--
--    TABLE-120/121 posture: PUBLIC *and* anon are revoked EXPLICITLY at both
--    layers. `revoke ... from public` alone does not remove the anon grant that
--    Supabase's hosted ALTER DEFAULT PRIVILEGES adds to everything created in
--    `public` (the POS-124 lesson) — anon is named here on purpose.
--
--    app.platform_admin_subscription_count is deliberately granted to NOBODY:
--    it is an internal helper of the overview body.
-- ----------------------------------------------------------------------------
revoke all on function app.platform_admin_console_overview(text)                                   from public;
revoke all on function app.platform_admin_console_overview(text)                                   from anon;
revoke all on function app.platform_admin_list_subscribers(text, integer, integer, text, text, text, text, text) from public;
revoke all on function app.platform_admin_list_subscribers(text, integer, integer, text, text, text, text, text) from anon;
revoke all on function app.platform_admin_get_subscriber(uuid, text)                               from public;
revoke all on function app.platform_admin_get_subscriber(uuid, text)                               from anon;
revoke all on function app.platform_admin_list_restaurants(text, integer, integer, text, text, text) from public;
revoke all on function app.platform_admin_list_restaurants(text, integer, integer, text, text, text) from anon;
revoke all on function app.platform_admin_audit_search(text, integer, timestamptz, uuid, text, uuid, timestamptz, timestamptz) from public;
revoke all on function app.platform_admin_audit_search(text, integer, timestamptz, uuid, text, uuid, timestamptz, timestamptz) from anon;
revoke all on function app.platform_admin_subscription_count(text)                                 from public;
revoke all on function app.platform_admin_subscription_count(text)                                 from anon;

grant execute on function app.platform_admin_console_overview(text)                                   to authenticated;
grant execute on function app.platform_admin_list_subscribers(text, integer, integer, text, text, text, text, text) to authenticated;
grant execute on function app.platform_admin_get_subscriber(uuid, text)                               to authenticated;
grant execute on function app.platform_admin_list_restaurants(text, integer, integer, text, text, text) to authenticated;
grant execute on function app.platform_admin_audit_search(text, integer, timestamptz, uuid, text, uuid, timestamptz, timestamptz) to authenticated;

revoke all on function public.platform_admin_console_overview(text)                                   from public;
revoke all on function public.platform_admin_console_overview(text)                                   from anon;
revoke all on function public.platform_admin_list_subscribers(text, integer, integer, text, text, text, text, text) from public;
revoke all on function public.platform_admin_list_subscribers(text, integer, integer, text, text, text, text, text) from anon;
revoke all on function public.platform_admin_get_subscriber(uuid, text)                               from public;
revoke all on function public.platform_admin_get_subscriber(uuid, text)                               from anon;
revoke all on function public.platform_admin_list_restaurants(text, integer, integer, text, text, text) from public;
revoke all on function public.platform_admin_list_restaurants(text, integer, integer, text, text, text) from anon;
revoke all on function public.platform_admin_audit_search(text, integer, timestamptz, uuid, text, uuid, timestamptz, timestamptz) from public;
revoke all on function public.platform_admin_audit_search(text, integer, timestamptz, uuid, text, uuid, timestamptz, timestamptz) from anon;

grant execute on function public.platform_admin_console_overview(text)                                   to authenticated;
grant execute on function public.platform_admin_list_subscribers(text, integer, integer, text, text, text, text, text) to authenticated;
grant execute on function public.platform_admin_get_subscriber(uuid, text)                               to authenticated;
grant execute on function public.platform_admin_list_restaurants(text, integer, integer, text, text, text) to authenticated;
grant execute on function public.platform_admin_audit_search(text, integer, timestamptz, uuid, text, uuid, timestamptz, timestamptz) to authenticated;

comment on function app.platform_admin_console_overview(text) is
  'ADMIN-125C.1: platform-wide COUNTS for the internal console Overview (organizations total/active/suspended, restaurants, branches, active memberships, subscriptions by status). Grant + aal2 + reason gated (app.platform_admin_guard); reason-tagged audit as platform.console.overview. Soft-deleted organizations/restaurants/branches are excluded, and a subscription on a tombstoned organization is NOT counted. No money, no devices, no orders, no alerts - none of those have a platform-wide source.';
comment on function app.platform_admin_list_subscribers(text, integer, integer, text, text, text, text, text) is
  'ADMIN-125C.1: the Subscribers page. "Subscriber" = ORGANIZATION (tenant root D-003 and billing unit). Bounded (limit clamped [1,200]), offset-paged, name-searchable, filterable by organization status / plan / subscription status, sortable by name|created|period_end. LEFT JOIN to organization_subscriptions + plans, so a tenant with no subscription returns NULL subscription fields rather than an invented default. Per-row counts run on the PAGE only. No dynamic SQL: every input is validated against a fixed vocabulary (22023) and the sort is a CASE ladder. No price, no created_by, no member PII.';
comment on function app.platform_admin_get_subscriber(uuid, text) is
  'ADMIN-125C.1: one subscriber for the console detail page - organization (id/name/status/default_currency/created_at), counts, subscription (NULL when the tenant has none) and its restaurants with branch counts. A NEW envelope so RF-091 platform_admin_get_organization stays byte-identical for the deployed client; created_by_app_user_id and creation_request_id are deliberately withheld. An unknown OR tombstoned organization raises 42501 - the same code as a denial, so this cannot be used to probe which ids exist - and the attempt is audited either way.';
comment on function app.platform_admin_list_restaurants(text, integer, integer, text, text, text) is
  'ADMIN-125C.1: the first PLATFORM-WIDE restaurant read (previously restaurants were reachable one organization at a time, so a console list meant N+1 calls). Bounded/searchable/sortable; each row carries its subscriber and that subscriber''s status. effective_currency = coalesce(restaurant override, organization default) - the SAME rule app.list_menu/app.pos_menu use, so the console can never disagree with the tills. No financial, order or member data.';
comment on function app.platform_admin_audit_search(text, integer, timestamptz, uuid, text, uuid, timestamptz, timestamptz) is
  'ADMIN-125C.1: the Audit Log page. KEYSET pagination on (occurred_at, id) compared as a row value - an append-only log makes offset paging both slow and lossy. Filters: action, target organization, date range. Same safe six-column projection as RF-091 recent_audit; the details jsonb is NEVER exposed and the actor stays an opaque id (no PII join in this phase). A half cursor and an inverted date range are refused with 22023.';
comment on function app.platform_admin_subscription_count(text) is
  'ADMIN-125C.1 internal helper for app.platform_admin_console_overview: counts subscriptions in one status, scoped to LIVE organizations. Granted to NOBODY - it performs no authorization of its own and is only ever called from a body that has already passed app.platform_admin_guard.';
