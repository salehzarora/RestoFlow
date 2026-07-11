-- ============================================================================
-- AUDIT-LOG-DASHBOARD-001 — Read-only operational audit timeline for the
-- owner/manager Dashboard ("Activity log" / سجل النشاط / יומן פעילות).
--
-- ONE new, READ-ONLY, ADDITIVE function (+ a thin public wrapper + two small
-- projection helpers). It surfaces the EXISTING append-only public.audit_events
-- (DECISION D-013, RF-017) as a paginated, filtered, scope-gated timeline.
--   * app.owner_audit_events — keyset-paginated, filtered LIST of audit events
--     in the caller's covered scope, returning a SERVER-SIDE ALLOWLIST projection
--     of old/new values (NEVER raw payload JSON).
--   * app.audit_action_has_detail / app.audit_safe_detail — the action-gated,
--     field-allowlisted safe projection (the server privacy boundary).
--
-- Nothing about the audit subsystem changes: no writer is touched, no audit row
-- is ever mutated, no new audit action is introduced, and no immutability rule
-- is altered (audit_events remains append-only — enforced by RF-017 triggers +
-- RF-059 deny policies + no UPDATE/DELETE grant; this migration adds only READ).
-- No new index: the RF-017 audit_events_org_occurred_idx (organization_id,
-- occurred_at desc) supports the org-scoped occurred_at-DESC keyset scan; a
-- branch drill-down filters branch_id on top of that org-ordered scan (adequate
-- at pilot volume). DECISIONS D-001/D-007/D-011/D-012/D-013; RISK R-003.
-- ----------------------------------------------------------------------------
-- The Dashboard is a JWT (auth.uid()) caller. The audit_events RLS SELECT policy
-- is GUC-bound (app.current_org_id() + app.has_scope()), so a direct table read
-- from the Dashboard returns ZERO rows. As with the owner_* reports / order
-- history, this read is therefore a GUC-free SECURITY DEFINER function in `app`
-- with a thin public SECURITY INVOKER wrapper, re-implementing tenant isolation
-- with EXPLICIT organization_id / scope filters (DEFINER bypasses RLS, so the
-- WHERE clauses ARE the isolation boundary — RISK R-003).
--
-- AUTHORIZATION — the owner_order_history / owner_report_range idiom, but
-- STRICTER (management-only; the audit log is not a cashier surface):
--   identity from auth.uid() -> app.current_app_user_id() (null -> 42501);
--   app.actor_rank_in_scope over the PASSED scope (0 -> 42501, downward-only);
--   role allowlist manager / restaurant_owner / org_owner ONLY (cashier,
--   kitchen_staff, accountant DENIED via {ok:false,error:'permission_denied'}).
--   No new privilege, no anon / service_role (D-011). An out-of-scope branch is
--   rejected identically to a non-existent one (no cross-tenant existence oracle).
--
-- PRIVACY — two independent ALLOWLIST layers (not a denylist):
--   (1) SERVER (authoritative): the RPC returns NO raw payload JSON. old_values /
--       new_values are projected by app.audit_safe_detail to a documented,
--       action-gated, field-allowlisted safe subset — unknown actions carry no
--       payload, and every un-listed key (secret OR merely unknown) is dropped,
--       so a direct authenticated caller can never retrieve the original payload.
--   (2) CLIENT: the Dashboard mapper independently ALLOWLISTS again, per action,
--       the specific fields it renders (protecting the demo path too); unknown
--       actions get a generic label and render no payload. No "show raw JSON".
--
-- MONEY — every money field inside old/new payloads is integer minor units
--   (bigint), read straight from the stored audit snapshot (D-007). currency_code
--   is returned once at the top level for client-side formatting; nothing is
--   recomputed.
--
-- FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.
-- NOT applied to the hosted DB by this migration (local validation only).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Server-side SAFE PROJECTION (allowlist, not denylist). The RPC must NEVER
--    return raw audit payload JSON — not even secret-key-redacted raw JSON — to a
--    direct authenticated caller. Instead it returns ONLY a documented,
--    action-gated, field-allowlisted safe projection of old/new values.
--      * app.audit_action_has_detail(action) — is this a SUPPORTED action that may
--        carry a safe payload projection? Unknown/unsupported actions get NO
--        payload details (event metadata + category only).
--      * app.audit_safe_detail(action, values) — projects ONE payload to the
--        canonical safe field allowlist; unknown keys (secret OR non-secret) are
--        dropped; the only nested object kept is `capabilities` (its three
--        canonical booleans). Malformed / non-object input -> '{}' (never throws).
-- ---------------------------------------------------------------------------
create or replace function app.audit_action_has_detail(p_action text)
  returns boolean
  language sql
  immutable
  set search_path = ''
as $$
  -- The curated set of actions whose stored payloads carry safe, presentable
  -- fields. Everything else (menu/table/device/organization/staff.created/
  -- staff.pin_set/pin_session.started/sync/receipt_number/employee.*) is shown
  -- from metadata only, with NO payload details.
  select coalesce(p_action, '') like 'order.void%'
      or p_action like 'order.discount%'
      or p_action like 'order.status%'
      or p_action =    'order.submitted'
      or p_action like 'staff.capabilities%'
      or p_action like 'membership.%'
      or p_action like 'shift.%'
      or p_action like 'cash_drawer.%'
      or p_action like 'payment.%'
      or p_action =    'pin_session.failed';
$$;

comment on function app.audit_action_has_detail(text) is
  'AUDIT-LOG-DASHBOARD-001: is p_action a SUPPORTED action that may carry a safe payload projection? Unknown/unsupported actions return NO payload details (metadata + category only). Gates app.audit_safe_detail.';

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
    'voided_item_count','failed_attempt_count','locked'
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
  'AUDIT-LOG-DASHBOARD-001: ALLOWLIST projection of ONE audit payload (old or new) to canonical safe fields. Gated by app.audit_action_has_detail (unsupported action -> ''{}''). Emits only allowlisted scalar keys (status/scope/discount_type/value/attempted_action/order_type/roles/*_minor money/voided_item_count/failed_attempt_count/locked) plus the nested `capabilities` object (3 canonical booleans). Every un-listed key (secret OR unknown) and every other nested structure is DROPPED. Malformed/non-object -> ''{}''; never throws. This is the server-side privacy boundary; the RPC returns NO raw payload JSON.';

-- ---------------------------------------------------------------------------
-- 2. app.owner_audit_events — paginated / filtered operational audit timeline.
-- ---------------------------------------------------------------------------
create or replace function app.owner_audit_events(
  p_organization_id           uuid,
  p_restaurant_id             uuid    default null,
  p_branch_id                 uuid    default null,
  p_range                     text    default 'today',   -- today|yesterday|last7|last30
  p_category                  text    default null,      -- see allowlist below
  p_action                    text    default null,      -- exact canonical action (drill-down)
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
  v_zone       text;
  v_span       integer;
  v_end_offset integer;
  v_local_today date;
  v_cur_start  date;
  v_cur_end    date;
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

  -- Category vocabulary is validated up-front so an unknown value is a clear bad
  -- request rather than silently matching nothing.
  if p_category is not null and p_category not in (
    'orders','voids','discounts','payments','shifts','staff',
    'access','devices','menu','tables','organization','sync'
  ) then
    raise exception 'owner_audit_events: unknown category %', p_category using errcode = '22023';
  end if;

  -- Authority over the PASSED scope (downward-only coverage); 0 => not a member
  -- covering this scope (non-member / cross-org / out-of-scope / unauthenticated).
  -- Identical 42501 whether the scope exists or not => no cross-tenant oracle.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_audit_events: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;

  -- MANAGEMENT-ONLY allowlist (STRICTER than the financial reads): manager /
  -- restaurant_owner / org_owner. cashier / kitchen_staff / accountant DENIED.
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

  -- Representative branch-local zone for the day window (single-tz pilot: exact;
  -- multi-tz org-wide: representative). Prefer the passed branch, then restaurant,
  -- then any org restaurant, then UTC. Never invents a second tz model (RF-075).
  v_zone := coalesce(
    (select b.timezone from public.branches b
       where b.organization_id = p_organization_id and b.id = p_branch_id and b.deleted_at is null),
    (select r.timezone from public.restaurants r
       where r.organization_id = p_organization_id and r.id = p_restaurant_id and r.deleted_at is null),
    (select min(r2.timezone) from public.restaurants r2
       where r2.organization_id = p_organization_id and r2.deleted_at is null and r2.timezone is not null),
    'UTC'
  );
  v_local_today := (now() at time zone v_zone)::date;
  v_cur_end     := v_local_today - v_end_offset;
  v_cur_start   := v_local_today - v_end_offset - (v_span - 1);

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
           coalesce(ep_actor.display_name, ep_appuser.display_name) as actor_name,
           r.name  as restaurant_name,
           b.name  as branch_name,
           dev.label as device_label,
           -- SAFE payloads: SERVER-SIDE ALLOWLIST projection (never raw JSON). Only
           -- documented safe fields for SUPPORTED actions survive; unknown keys and
           -- unknown actions carry no payload details.
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
      -- Fallback name for an app_user actor (management events carry no employee
      -- profile): their employee profile in THIS org, if any. No email/phone.
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
    where ae.organization_id = p_organization_id
      and (p_restaurant_id is null or ae.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or ae.branch_id     = p_branch_id)
      and (ae.occurred_at at time zone v_zone)::date between v_cur_start and v_cur_end
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
               'occurred_at',     to_char(n.occurred_at at time zone v_zone, 'YYYY-MM-DD HH24:MI'),
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
  'AUDIT-LOG-DASHBOARD-001 (read-only; D-001/D-007/D-011/D-013): GUC-free paginated operational audit timeline for the owner/manager Dashboard over the append-only public.audit_events. Authorization = actor_rank_in_scope over the PASSED scope (0 -> 42501) + MANAGEMENT-ONLY allowlist (manager/restaurant_owner/org_owner; cashier/kitchen_staff/accountant -> permission_denied). Branch-local day window (p_range today/yesterday/last7/last30). Optional filters: p_category, p_action (exact), p_sensitive_only, p_actor_app_user_id, p_actor_employee_profile_id. Keyset pagination ("<occurred_at>|<id>", newest first, p_limit clamped 1..100, has_more/next_cursor). old/new payloads are a SERVER-SIDE ALLOWLIST projection via app.audit_safe_detail (NO raw JSON: only documented safe fields for supported actions; unknown keys + unknown actions carry no payload); money integer minor from stored snapshots. Actor shown as display_name only (no email/phone, no actor/auth ids); missing -> null. Scope-safe (no GUC trusted, no cross-tenant existence oracle); no anon/service_role. READ-ONLY: no audit row is ever mutated.';

-- ---------------------------------------------------------------------------
-- 3. Thin public SECURITY INVOKER wrapper (sales_summary / owner_report_range
--    pattern) — the PostgREST-reachable surface; adds no new privilege.
-- ---------------------------------------------------------------------------
create or replace function public.owner_audit_events(
  p_organization_id uuid, p_restaurant_id uuid default null,
  p_branch_id uuid default null, p_range text default 'today',
  p_category text default null, p_action text default null,
  p_sensitive_only boolean default false, p_actor_app_user_id uuid default null,
  p_actor_employee_profile_id uuid default null, p_limit int default 25,
  p_cursor text default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.owner_audit_events(
  p_organization_id, p_restaurant_id, p_branch_id, p_range, p_category, p_action,
  p_sensitive_only, p_actor_app_user_id, p_actor_employee_profile_id, p_limit, p_cursor); $$;

-- ---------------------------------------------------------------------------
-- 4. Grants: authenticated only (never anon / service_role; D-011).
-- ---------------------------------------------------------------------------
revoke all on function app.audit_action_has_detail(text) from public;
grant execute on function app.audit_action_has_detail(text) to authenticated;
revoke all on function app.audit_safe_detail(text, jsonb) from public;
grant execute on function app.audit_safe_detail(text, jsonb) to authenticated;

revoke all on function app.owner_audit_events(uuid, uuid, uuid, text, text, text, boolean, uuid, uuid, int, text)    from public;
grant execute on function app.owner_audit_events(uuid, uuid, uuid, text, text, text, boolean, uuid, uuid, int, text) to authenticated;
revoke all on function public.owner_audit_events(uuid, uuid, uuid, text, text, text, boolean, uuid, uuid, int, text)    from public;
grant execute on function public.owner_audit_events(uuid, uuid, uuid, text, text, text, boolean, uuid, uuid, int, text) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists public.owner_audit_events(uuid, uuid, uuid, text, text, text, boolean, uuid, uuid, int, text);
--   drop function if exists app.owner_audit_events(uuid, uuid, uuid, text, text, text, boolean, uuid, uuid, int, text);
--   drop function if exists app.audit_safe_detail(text, jsonb);
--   drop function if exists app.audit_action_has_detail(text);
-- ============================================================================
