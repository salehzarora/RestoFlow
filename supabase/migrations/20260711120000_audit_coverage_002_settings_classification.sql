-- ============================================================================
-- AUDIT-COVERAGE-002 — classify configuration/settings changes (and make the
-- Activity-log classification a single, testable source of truth).
--
-- CONTEXT: the settings/timezone writers (RF-112 update_branch_settings /
-- update_restaurant_settings / update_organization_settings) emit
-- `settings.<entity>.updated` / `settings.<entity>.update_denied`. The
-- owner_audit_events classifier had NO `settings.%` branch, so those events fell
-- into the generic **'other'** category, AND `audit_action_has_detail` excluded
-- `settings.%`, so the before/after timezone (recorded in the audit payload as
-- `to_jsonb(branch)`) was never surfaced. Result: the owner's timezone change
-- appeared under "Other" with no detail.
--
-- THIS migration (additive, forward-only, CREATE OR REPLACE — no table / CHECK /
-- RLS / index / audit-data change; does NOT edit the applied 20260626090000 /
-- 090000 / 100000 / 110000):
--   1. Extracts the classification CASE into `app.audit_category(action)` — the
--      single, reviewable, per-action-testable source of truth — and adds the
--      `settings.%` -> 'settings' branch.
--   2. Adds `settings.%` to `audit_action_has_detail` so settings changes carry a
--      safe payload projection.
--   3. Adds the safe settings scalar keys (`timezone`, `name`, `receipt_prefix`)
--      to the `audit_safe_detail` allowlist (so previous/new timezone show; the
--      full `to_jsonb(branch)` row is still projected down to ONLY these keys —
--      internal ids/addresses/timestamps are dropped).
--   4. CREATE OR REPLACE `app.owner_audit_events` to call `app.audit_category`
--      and add 'settings' to the filter vocabulary. Everything else (per-event
--      branch-local time from TIMEZONE-GLOBAL-001, authorization, keyset
--      pagination, allowlist projection, authenticated-only ACL) is UNCHANGED.
--
-- No writer changes, no key renames, no historical-row rewrite. FORWARD-ONLY
-- (Supabase replays on db reset). NOT applied to hosted by this file.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. app.audit_category(action) — the single classification source of truth.
--    Maps a canonical action key to its Activity-log category. Unknown / legacy
--    actions fall back to 'other' (safe). Pure; used by owner_audit_events and
--    directly unit-testable (per-action) by the coverage guard.
-- ---------------------------------------------------------------------------
create or replace function app.audit_category(p_action text)
  returns text
  language sql
  immutable
  set search_path = ''
as $$
  select case
    when p_action like 'order.discount%'                               then 'discounts'
    when p_action like 'order.void%'                                   then 'voids'
    when p_action like 'order.%'                                       then 'orders'
    when p_action like 'payment.%' or p_action like 'receipt_number.%' then 'payments'
    when p_action like 'shift.%'   or p_action like 'cash_drawer.%'    then 'shifts'
    when p_action like 'staff.%'                                       then 'staff'
    when p_action like 'membership.%' or p_action like 'employee.%'
         or p_action like 'pin_session.%'                             then 'access'
    when p_action like 'device.%'                                     then 'devices'
    when p_action like 'settings.%'                                   then 'settings'
    when p_action like 'menu.%'                                       then 'menu'
    when p_action like 'table.%'                                      then 'tables'
    when p_action like 'organization.%'                               then 'organization'
    when p_action like 'sync.%'                                       then 'sync'
    else 'other'
  end;
$$;

comment on function app.audit_category(text) is
  'AUDIT-COVERAGE-002: the single source of truth for Activity-log action classification. Maps a canonical action key to its category (orders/voids/discounts/payments/shifts/staff/access/devices/settings/menu/tables/organization/sync); unknown/legacy actions -> ''other'' (safe fallback). settings.* (config/timezone changes) -> ''settings''. Pure; used by owner_audit_events and unit-tested per-action.';

revoke all on function app.audit_category(text) from public;

-- ---------------------------------------------------------------------------
-- 2. audit_action_has_detail — supported actions now include settings.* so a
--    settings change carries a safe payload projection (before/after values).
-- ---------------------------------------------------------------------------
create or replace function app.audit_action_has_detail(p_action text)
  returns boolean
  language sql
  immutable
  set search_path = ''
as $$
  select coalesce(p_action, '') like 'order.void%'
      or p_action like 'order.discount%'
      or p_action like 'order.status%'
      or p_action =    'order.submitted'
      or p_action like 'staff.capabilities%'
      or p_action like 'membership.%'
      or p_action like 'shift.%'
      or p_action like 'cash_drawer.%'
      or p_action like 'payment.%'
      or p_action like 'settings.%'
      or p_action =    'pin_session.failed';
$$;

comment on function app.audit_action_has_detail(text) is
  'AUDIT-LOG-DASHBOARD-001 + AUDIT-COVERAGE-002: is p_action a SUPPORTED action that may carry a safe payload projection? Unknown/unsupported actions return NO payload details (metadata + category only). Now includes settings.* (config changes). Gates app.audit_safe_detail.';

-- ---------------------------------------------------------------------------
-- 3. audit_safe_detail — allowlist now includes the safe settings scalars
--    (timezone / name / receipt_prefix; status already present). The settings
--    writers record to_jsonb(branch|restaurant|organization); this projects it
--    down to ONLY these keys — internal ids, address, and timestamps are dropped.
-- ---------------------------------------------------------------------------
create or replace function app.audit_safe_detail(p_action text, p_values jsonb)
  returns jsonb
  language plpgsql
  immutable
  set search_path = ''
as $$
declare
  v_out  jsonb := '{}'::jsonb;
  v_caps jsonb;
  v_key  text;
begin
  -- Unknown / unsupported action -> no payload details.
  if not app.audit_action_has_detail(p_action) then
    return '{}'::jsonb;
  end if;
  -- Malformed / missing / non-object payload -> empty safe detail (never throws).
  if p_values is null or jsonb_typeof(p_values) <> 'object' then
    return '{}'::jsonb;
  end if;

  -- Canonical SAFE SCALAR allowlist. A key is emitted ONLY when it is on this
  -- list AND its value is a scalar (string/number/boolean) — nested objects,
  -- arrays, and every un-listed key (secret OR merely unknown) are dropped.
  foreach v_key in array array[
    'status','order_status','scope','discount_type','value','attempted_action','order_type',
    'role','from_role','to_role','target_role',
    'discount_total_minor','grand_total_minor','subtotal_minor','line_total_minor','line_discount_minor',
    'amount_minor','tendered_minor','change_minor','opening_float_minor',
    'expected_cash_minor','counted_cash_minor','cash_variance_minor','variance_minor',
    'voided_item_count','failed_attempt_count','locked',
    'timezone','name','receipt_prefix'
  ] loop
    if p_values ? v_key
       and jsonb_typeof(p_values -> v_key) in ('string','number','boolean') then
      v_out := v_out || jsonb_build_object(v_key, p_values -> v_key);
    end if;
  end loop;

  -- The ONLY allowlisted nested object: `capabilities`, kept to its three
  -- canonical boolean capability keys (unknown nested keys dropped).
  if jsonb_typeof(p_values -> 'capabilities') = 'object' then
    select coalesce(jsonb_object_agg(k, p_values -> 'capabilities' -> k), '{}'::jsonb)
      into v_caps
      from unnest(array['apply_discount','void_order','close_shift']) as k
      where (p_values -> 'capabilities') ? k
        and jsonb_typeof(p_values -> 'capabilities' -> k) in ('string','number','boolean');
    if v_caps is distinct from '{}'::jsonb then
      v_out := v_out || jsonb_build_object('capabilities', v_caps);
    end if;
  end if;

  return v_out;
end;
$$;

comment on function app.audit_safe_detail(text, jsonb) is
  'AUDIT-LOG-DASHBOARD-001 + AUDIT-COVERAGE-002: ALLOWLIST projection of ONE audit payload (old or new) to canonical safe fields. Gated by app.audit_action_has_detail (unsupported action -> ''{}''). Emits only allowlisted scalar keys (status/scope/discount_type/value/attempted_action/order_type/roles/*_minor money/voided_item_count/failed_attempt_count/locked/timezone/name/receipt_prefix) plus the nested `capabilities` object (3 canonical booleans). Every un-listed key (secret OR unknown) and every other nested structure is DROPPED. Malformed/non-object -> ''{}''; never throws. This is the server-side privacy boundary; the RPC returns NO raw payload JSON.';

-- ---------------------------------------------------------------------------
-- 4. app.owner_audit_events — now classifies via app.audit_category and accepts
--    the 'settings' filter category. Body otherwise identical to 20260711110000
--    (per-event branch-local time preserved). CREATE OR REPLACE keeps the ACL.
-- ---------------------------------------------------------------------------
create or replace function app.owner_audit_events(
  p_organization_id           uuid,
  p_restaurant_id             uuid    default null,
  p_branch_id                 uuid    default null,
  p_range                     text    default 'today',
  p_category                  text    default null,
  p_action                    text    default null,
  p_sensitive_only            boolean default false,
  p_actor_app_user_id         uuid    default null,
  p_actor_employee_profile_id uuid    default null,
  p_limit                     int     default 25,
  p_cursor                    text    default null
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
  v_zone       text;
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

  case p_range
    when 'today'     then v_span := 1;  v_end_offset := 0;
    when 'yesterday' then v_span := 1;  v_end_offset := 1;
    when 'last7'     then v_span := 7;  v_end_offset := 0;
    when 'last30'    then v_span := 30; v_end_offset := 0;
    else raise exception 'owner_audit_events: unknown range %', p_range using errcode = '22023';
  end case;

  -- 'settings' is now a first-class filter category (AUDIT-COVERAGE-002).
  if p_category is not null and p_category not in (
    'orders','voids','discounts','payments','shifts','staff',
    'access','devices','settings','menu','tables','organization','sync'
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

  v_zone := coalesce(
    (select b.timezone from public.branches b
       where b.organization_id = p_organization_id and b.id = p_branch_id and b.deleted_at is null),
    (select r.timezone from public.restaurants r
       where r.organization_id = p_organization_id and r.id = p_restaurant_id and r.deleted_at is null),
    (select min(r2.timezone) from public.restaurants r2
       where r2.organization_id = p_organization_id and r2.deleted_at is null and r2.timezone is not null),
    'UTC'
  );

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
    -- Single source of truth for classification (AUDIT-COVERAGE-002).
    cross join lateral (select app.audit_category(ae.action) as category) cat
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
  'AUDIT-LOG-DASHBOARD-001 + TIMEZONE-GLOBAL-001 + AUDIT-COVERAGE-002 (read-only; D-001/D-007/D-011/D-013): GUC-free paginated operational audit timeline. Classification via app.audit_category (settings.* -> settings); ''settings'' is a filter category. Authorization, PER-EVENT branch-local time, payload allowlist projection, keyset pagination, and the authenticated-only ACL are unchanged.';

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   -- revert owner_audit_events / audit_safe_detail / audit_action_has_detail to
--   -- their 20260711110000 / 090000 bodies, then:
--   drop function if exists app.audit_category(text);
-- ============================================================================
