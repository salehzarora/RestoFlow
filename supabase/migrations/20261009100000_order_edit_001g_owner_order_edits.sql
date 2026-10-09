-- ============================================================================
-- ORDER-EDIT-001G (1 of 2) — app.owner_order_edits: the read-only "Order edits"
-- report reader (API_CONTRACT §4.47; MONEY_AND_TAX_SPEC §9.2 M12 / M13 and §13;
-- DECISION D-043).
--
-- ADDITIVE and READ-ONLY: two NEW functions (app.owner_order_edits + a thin
-- public SECURITY INVOKER wrapper). No table, column, index, CHECK, RLS policy,
-- trigger, grant on a table, or row write. Reads write no audit event (D-013).
--
-- Rules this reader implements (the contract owns the full text):
--   * M13 AS WRITTEN. Each edit's figures come from provenance only —
--     removed_by_edit_id for the lines the edit retired, edit_id for the rows
--     it wrote, replaces_order_item_id for the retired line a written row
--     replaces — never from a row's status NOW. "Live" in MONEY §13 means live
--     when that edit wrote the row, so a later edit (an edit chain) or a
--     whole-order void never rewrites an earlier edit's figures, and each
--     edit's net_change_minor equals the change it made to the order's
--     subtotal_minor (M5).
--   * M12 window. An edit is bucketed by its ORDER's created_at business day in
--     COALESCE(branch.timezone, restaurant.timezone). A branch with NO time
--     zone contributes nothing — the owner_report_range AGGREGATE rule (not the
--     history list's UTC fallback), so the block covers the same orders as the
--     Gross / Net / Voids figures beside it.
--   * Staff names (who made each edit) go only to callers holding an active
--     manager / restaurant_owner / org_owner membership covering the passed
--     scope — the owner_audit_events audience. Cashier and accountant callers
--     read every other figure with staff_visible false, by_staff [] and every
--     edits[].staff_name null. reason_text is never returned.
--
-- RISK R-003 (cross-tenant read). Every source is filtered on the PASSED
-- organization at the source (order_edits, orders, branches, restaurants,
-- order_items, employee_profiles); scope authority is app.actor_rank_in_scope
-- over the passed scope (downward-only; a foreign and a nonexistent restaurant
-- or branch both raise the same 42501, so there is no existence oracle). The
-- scope check deliberately uses the MEMBER rank, never the ADMIN-126B support
-- read rank: the result names staff, so a platform support session gets 42501
-- (as owner_audit_events).
--
-- ACL (D-011 / D-037): PUBLIC and anon revoked explicitly on both layers;
-- authenticated only; no service_role.
--
-- ROLLBACK: drop function public.owner_order_edits(uuid, uuid, uuid, text,
-- date, date, text, integer, text); drop function app.owner_order_edits(uuid,
-- uuid, uuid, text, date, date, text, integer, text). Nothing else depends on
-- them in the database.
-- ============================================================================

create or replace function app.owner_order_edits(
  p_organization_id uuid,
  p_restaurant_id   uuid    default null,
  p_branch_id       uuid    default null,
  p_range           text    default 'today',
  p_start           date    default null,
  p_end             date    default null,
  p_reason_code     text    default null,   -- null | one of the five reason codes | 'none'
  p_limit           integer default 25,
  p_cursor          text    default null    -- keyset cursor "<created_at>|<order_edit_id>"
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor        uuid    := app.current_app_user_id();
  v_rank         integer;
  v_currency     text;
  v_span         integer;
  v_end_offset   integer;
  v_custom       boolean := false;
  v_limit        integer := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_cursor_ts    timestamptz;
  v_cursor_id    uuid;
  v_staff_visible boolean;
  v_result       jsonb;
begin
  if v_actor is null then
    raise exception 'owner_order_edits: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_order_edits: organization_id is required' using errcode = '42501';
  end if;

  -- Window selection — the shared owner analytics block (owner_top_items /
  -- owner_order_history): a custom pair wins over p_range.
  if p_start is not null or p_end is not null then
    if p_start is null or p_end is null then
      raise exception 'owner_order_edits: p_start and p_end must be supplied together'
        using errcode = '22023';
    end if;
    if p_end < p_start then
      raise exception 'owner_order_edits: p_end precedes p_start'
        using errcode = '22023';
    end if;
    if (p_end - p_start) > 91 then
      raise exception 'owner_order_edits: window exceeds 92 days'
        using errcode = '22023';
    end if;
    v_custom := true;
  else
    -- Range -> (span, end_offset). Unknown range is a bad request, not a denial.
    case p_range
      when 'today'     then v_span := 1;  v_end_offset := 0;
      when 'yesterday' then v_span := 1;  v_end_offset := 1;
      when 'last7'     then v_span := 7;  v_end_offset := 0;
      when 'last30'    then v_span := 30; v_end_offset := 0;
      when 'last60'    then v_span := 60; v_end_offset := 0;
      when 'last90'    then v_span := 90; v_end_offset := 0;
      else raise exception 'owner_order_edits: unknown range %', p_range using errcode = '22023';
    end case;
  end if;

  -- The reason filter: one of the five order_edits.reason_code values, or
  -- 'none' (an edit with no reason — adds and increases only). A misspelled
  -- filter fails loudly rather than returning an empty list.
  if p_reason_code is not null
     and p_reason_code not in ('customer_changed_mind', 'entry_mistake', 'item_unavailable',
                               'kitchen_issue', 'other', 'none') then
    raise exception 'owner_order_edits: unknown reason filter %', p_reason_code using errcode = '22023';
  end if;

  -- Keyset cursor: "<created_at::text>|<id>" (the owner_order_history idiom).
  -- A malformed cursor is a bad request.
  if p_cursor is not null and btrim(p_cursor) <> '' then
    begin
      v_cursor_ts := split_part(p_cursor, '|', 1)::timestamptz;
      v_cursor_id := split_part(p_cursor, '|', 2)::uuid;
    exception when others then
      raise exception 'owner_order_edits: invalid cursor' using errcode = '22023';
    end;
  end if;

  -- authority over the PASSED scope (downward-only coverage); 0 => not a member.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_order_edits: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  -- FINANCIAL-READ allowlist (GUC-free, app.can_read_financials-STYLE);
  -- kitchen_staff DENIED.
  if not exists (
    select 1
    from public.memberships m
    where m.app_user_id     = v_actor
      and m.organization_id = p_organization_id
      and m.status          = 'active'
      and m.deleted_at is null
      and m.role in ('cashier', 'manager', 'restaurant_owner', 'org_owner', 'accountant')
      and (m.restaurant_id is null or m.restaurant_id = p_restaurant_id)
      and (m.branch_id     is null or m.branch_id     = p_branch_id)
  ) then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_order_edits');
  end if;

  -- Staff names: the owner_audit_events audience (manager and above covering
  -- the passed scope). The same membership predicate, roles narrowed.
  v_staff_visible := exists (
    select 1
    from public.memberships m
    where m.app_user_id     = v_actor
      and m.organization_id = p_organization_id
      and m.status          = 'active'
      and m.deleted_at is null
      and m.role in ('manager', 'restaurant_owner', 'org_owner')
      and (m.restaurant_id is null or m.restaurant_id = p_restaurant_id)
      and (m.branch_id     is null or m.branch_id     = p_branch_id)
  );

  -- The EFFECTIVE currency (OPS-043): the restaurant override when a restaurant
  -- is in scope, else the organization default. Per-row currency_code carries
  -- the truth for a mixed scope.
  select coalesce(r.currency_override, o.default_currency) into v_currency
    from public.organizations o
    left join public.restaurants r
      on r.id              = p_restaurant_id
     and r.organization_id = o.id
     and r.deleted_at is null
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'owner_order_edits: organization not found (or deleted)' using errcode = '42501';
  end if;

  with branch_tz_base as (
    -- branch-local zone (RF-075): COALESCE(branch, restaurant). A tz-less
    -- branch is EXCLUDED (the owner_report_range aggregate rule). ORG-SCOPED at
    -- the source so an org-wide call's windows are never computed over other
    -- tenants' branches (D-001 / RISK R-003).
    select b.organization_id, b.id as branch_id, b.name as branch_name,
           coalesce(b.timezone, r.timezone) as zone
    from public.branches b
    join public.restaurants r
      on r.organization_id = b.organization_id
     and r.id              = b.restaurant_id
     and r.deleted_at is null
    where b.organization_id = p_organization_id
      and b.deleted_at is null
      and coalesce(b.timezone, r.timezone) is not null
  ),
  branch_tz as (
    -- Presets are branch-local and relative; a custom pair is the same fixed
    -- calendar dates for every branch.
    select bt.organization_id, bt.branch_id, bt.branch_name, bt.zone,
           case when v_custom then p_start
                else (lt.local_today - v_end_offset - (v_span - 1)) end as win_start,
           case when v_custom then p_end
                else (lt.local_today - v_end_offset) end                as win_end
    from branch_tz_base bt
    cross join lateral (
      select (now() at time zone bt.zone)::date as local_today
    ) lt
  ),
  edits as (
    -- Every applied edit of a non-deleted order in scope whose ORDER was
    -- created in the window (M12), whatever the order's status is now.
    select e.id, e.order_id, e.edit_number, e.created_at, e.reason_code, e.kitchen_channel,
           e.employee_profile_id,
           o.status        as order_status,
           o.order_type,
           o.currency_code,
           o.created_at    as order_created_at,
           t.zone,
           t.branch_name
    from public.order_edits e
    join public.orders o
      on o.organization_id = e.organization_id
     and o.id              = e.order_id
    join branch_tz t
      on t.organization_id = o.organization_id
     and t.branch_id       = o.branch_id
    where e.organization_id = p_organization_id
      and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or o.branch_id     = p_branch_id)
      and e.deleted_at is null
      and o.deleted_at is null
      and (o.created_at at time zone t.zone)::date between t.win_start and t.win_end
  ),
  retired as (
    -- The lines each edit RETIRED (removed_by_edit_id). A retired line is
    -- "replaced out" iff a row written by THE SAME edit names it in
    -- replaces_order_item_id (counted once however many rows name it);
    -- otherwise it is "removed".
    select r.removed_by_edit_id as edit_id,
           sum(r.line_total_minor) filter (where not rp.replaced) as removed_minor,
           sum(r.line_total_minor) filter (where rp.replaced)     as replaced_out_minor
    from public.order_items r
    join edits e
      on e.id = r.removed_by_edit_id
    cross join lateral (
      select exists (
        select 1
        from public.order_items n
        where n.organization_id        = r.organization_id
          and n.order_id               = r.order_id
          and n.edit_id                = r.removed_by_edit_id
          and n.replaces_order_item_id = r.id
          and n.deleted_at is null) as replaced
    ) rp
    where r.organization_id = p_organization_id
      and r.order_id        = e.order_id
      and r.deleted_at is null
    group by r.removed_by_edit_id
  ),
  written as (
    -- The rows each edit WROTE (edit_id), AS WRITTEN: never re-judged by their
    -- status NOW — a later edit or a whole-order void does not rewrite this
    -- edit's figures (MONEY §13, "live when that edit wrote them").
    -- Valued at line_total_minor + line_discount_minor: app.edit_order writes
    -- every row with line_discount_minor 0, and a LATER item-scope
    -- app.apply_discount moves line_total_minor down by exactly the discount
    -- it records, so the sum is the amount this edit wrote — a later discount
    -- is reported under Discounts, never subtracted from this edit again.
    -- Retired rows (above) stay on line_total_minor: once voided or cancelled
    -- a line cannot be discounted, so that value is fixed at retirement and is
    -- exactly what the retiring edit took off the subtotal.
    select n.edit_id,
           sum(n.line_total_minor + n.line_discount_minor) filter (where n.replaces_order_item_id is not null) as replaced_in_minor,
           sum(n.line_total_minor + n.line_discount_minor) filter (where n.replaces_order_item_id is null)     as added_minor
    from public.order_items n
    join edits e
      on e.id = n.edit_id
    where n.organization_id = p_organization_id
      and n.order_id        = e.order_id
      and n.deleted_at is null
    group by n.edit_id
  ),
  per_edit as (
    select e.*,
           coalesce(rt.removed_minor, 0)::bigint      as removed_minor,
           coalesce(rt.replaced_out_minor, 0)::bigint as replaced_out_minor,
           coalesce(w.replaced_in_minor, 0)::bigint   as replaced_in_minor,
           coalesce(w.added_minor, 0)::bigint         as added_minor,
           ep.display_name                            as staff_name
    from edits e
    left join retired rt
      on rt.edit_id = e.id
    left join written w
      on w.edit_id = e.id
    left join public.employee_profiles ep
      on ep.organization_id = p_organization_id
     and ep.id              = e.employee_profile_id
  ),
  summary as (
    -- The whole scope and window; never narrowed by the reason filter.
    select count(*)::bigint                                as edit_count,
           count(distinct pe.order_id)::bigint             as edited_order_count,
           coalesce(sum(pe.removed_minor), 0)::bigint      as removed_minor,
           coalesce(sum(pe.replaced_out_minor), 0)::bigint as replaced_out_minor,
           coalesce(sum(pe.replaced_in_minor), 0)::bigint  as replaced_in_minor,
           coalesce(sum(pe.added_minor), 0)::bigint        as added_minor
    from per_edit pe
  ),
  by_reason as (
    select pe.reason_code,
           count(*)::bigint                    as edit_count,
           count(distinct pe.order_id)::bigint as edited_order_count,
           sum(pe.removed_minor)::bigint       as removed_minor,
           sum(pe.replaced_out_minor)::bigint  as replaced_out_minor,
           sum(pe.replaced_in_minor)::bigint   as replaced_in_minor,
           sum(pe.added_minor)::bigint         as added_minor
    from per_edit pe
    group by pe.reason_code
  ),
  by_staff as (
    -- grouped by the person who made the edit (D-005); the profile id orders
    -- ties but is never returned.
    select pe.employee_profile_id,
           min(pe.staff_name)                  as staff_name,
           count(*)::bigint                    as edit_count,
           count(distinct pe.order_id)::bigint as edited_order_count,
           sum(pe.removed_minor)::bigint       as removed_minor,
           sum(pe.replaced_out_minor)::bigint  as replaced_out_minor,
           sum(pe.replaced_in_minor)::bigint   as replaced_in_minor,
           sum(pe.added_minor)::bigint         as added_minor
    from per_edit pe
    group by pe.employee_profile_id
  ),
  listed as (
    -- The reason filter narrows ONLY the list (edits[], matching, paging).
    select pe.*
    from per_edit pe
    where p_reason_code is null
       or (p_reason_code = 'none' and pe.reason_code is null)
       or pe.reason_code = p_reason_code
  ),
  page as (
    -- Keyset continuation, newest edit first; `id` breaks ties. One extra row
    -- is fetched to decide has_more.
    select l.*, l.created_at::text || '|' || l.id::text as cursor
    from listed l
    where p_cursor is null
       or v_cursor_ts is null
       or l.created_at < v_cursor_ts
       or (l.created_at = v_cursor_ts and l.id < v_cursor_id)
    order by l.created_at desc, l.id desc
    limit v_limit + 1
  ),
  numbered as (
    select p.*, row_number() over (order by p.created_at desc, p.id desc) as rn
    from page p
  )
  select jsonb_build_object(
    'currency_codes', coalesce((
      select jsonb_agg(distinct pe.currency_code order by pe.currency_code)
      from per_edit pe), '[]'::jsonb),
    'order_edit_enabled_in_scope', exists (
      select 1
      from public.branches b
      where b.organization_id = p_organization_id
        and (p_restaurant_id is null or b.restaurant_id = p_restaurant_id)
        and (p_branch_id     is null or b.id            = p_branch_id)
        and b.deleted_at is null
        and b.order_edit_enabled),
    'staff_visible', v_staff_visible,
    'summary', (
      select jsonb_build_object(
               'edit_count',          s.edit_count,
               'edited_order_count',  s.edited_order_count,
               'removed_minor',       s.removed_minor,
               'replaced_out_minor',  s.replaced_out_minor,
               'replaced_in_minor',   s.replaced_in_minor,
               'added_minor',         s.added_minor,
               'net_change_minor',    s.replaced_in_minor + s.added_minor - s.removed_minor - s.replaced_out_minor,
               'gross_retired_minor', s.removed_minor + s.replaced_out_minor)
      from summary s),
    'by_reason', coalesce((
      select jsonb_agg(jsonb_build_object(
               'reason_code',         b.reason_code,
               'edit_count',          b.edit_count,
               'edited_order_count',  b.edited_order_count,
               'removed_minor',       b.removed_minor,
               'replaced_out_minor',  b.replaced_out_minor,
               'replaced_in_minor',   b.replaced_in_minor,
               'added_minor',         b.added_minor,
               'net_change_minor',    b.replaced_in_minor + b.added_minor - b.removed_minor - b.replaced_out_minor,
               'gross_retired_minor', b.removed_minor + b.replaced_out_minor)
             order by b.removed_minor + b.replaced_out_minor desc, b.edit_count desc,
                      b.reason_code asc nulls last)
      from by_reason b), '[]'::jsonb),
    'by_staff', case when v_staff_visible then coalesce((
      select jsonb_agg(jsonb_build_object(
               'staff_name',          b.staff_name,
               'edit_count',          b.edit_count,
               'edited_order_count',  b.edited_order_count,
               'removed_minor',       b.removed_minor,
               'replaced_out_minor',  b.replaced_out_minor,
               'replaced_in_minor',   b.replaced_in_minor,
               'added_minor',         b.added_minor,
               'net_change_minor',    b.replaced_in_minor + b.added_minor - b.removed_minor - b.replaced_out_minor,
               'gross_retired_minor', b.removed_minor + b.replaced_out_minor)
             order by b.removed_minor + b.replaced_out_minor desc, b.edit_count desc,
                      b.staff_name asc, b.employee_profile_id asc)
      from by_staff b), '[]'::jsonb) else '[]'::jsonb end,
    'edits', coalesce((
      select jsonb_agg(jsonb_build_object(
               'order_edit_id',       n.id,
               'order_id',            n.order_id,
               'order_code',          '#' || upper(right(replace(n.order_id::text, '-', ''), 6)),
               'edit_number',         n.edit_number,
               'order_status',        n.order_status,
               'order_type',          n.order_type,
               'branch_name',         n.branch_name,
               'staff_name',          case when v_staff_visible then n.staff_name end,
               'reason_code',         n.reason_code,
               'kitchen_channel',     n.kitchen_channel,
               -- Branch-local DISPLAY string of the EDIT, the absolute instant,
               -- the ORDER's branch-local business day and the resolved zone.
               'created_at',          to_char(n.created_at at time zone n.zone, 'YYYY-MM-DD HH24:MI'),
               'created_at_utc',      to_char(n.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
               'business_day',        to_char((n.order_created_at at time zone n.zone)::date, 'YYYY-MM-DD'),
               'timezone',            n.zone,
               'currency_code',       n.currency_code,
               'removed_minor',       n.removed_minor,
               'replaced_out_minor',  n.replaced_out_minor,
               'replaced_in_minor',   n.replaced_in_minor,
               'added_minor',         n.added_minor,
               'net_change_minor',    n.replaced_in_minor + n.added_minor - n.removed_minor - n.replaced_out_minor,
               'gross_retired_minor', n.removed_minor + n.replaced_out_minor)
             order by n.rn)
      from numbered n
      where n.rn <= v_limit), '[]'::jsonb),
    'count',       least((select count(*) from numbered), v_limit),
    'matching',    (select count(*) from listed),
    'has_more',    (select count(*) from numbered) > v_limit,
    'next_cursor', case when (select count(*) from numbered) > v_limit
                        then (select cursor from numbered where rn = v_limit)
                        else null end
  ) into v_result;

  return jsonb_build_object(
    'ok', true,
    'entity', 'owner_order_edits',
    'currency_code', v_currency,
    'range', case when v_custom then 'custom' else p_range end,
    'limit', v_limit
  ) || v_result;
end;
$$;

comment on function app.owner_order_edits(uuid, uuid, uuid, text, date, date, text, integer, text) is
  'ORDER-EDIT-001G (D-043; API_CONTRACT §4.47; MONEY §13): READ-ONLY "Order edits" report. '
  'Every applied edit of a non-deleted order in scope whose ORDER created_at falls in the '
  'branch-local window (M12; tz-less branches excluded, the owner_report_range rule), whatever '
  'the order''s status now. Per-edit figures computed AS WRITTEN from provenance only '
  '(removed_by_edit_id / edit_id / replaces_order_item_id): removed, replaced_out, replaced_in, '
  'added, net_change and gross_retired, integer minor units. summary / by_reason / by_staff '
  'cover the whole window; p_reason_code (five codes or none) narrows only edits[] / matching / '
  'paging (keyset "<created_at>|<id>", newest first, p_limit 1..100). Financial-read allowlist '
  '(kitchen_staff -> permission_denied); staff names only for manager / restaurant_owner / '
  'org_owner (staff_visible). Never returns reason_text or any device / session / membership / '
  'employee id. Scope by app.actor_rank_in_scope (0 -> 42501; no existence oracle). No audit.';

-- ----------------------------------------------------------------------------
-- public.owner_order_edits — thin SECURITY INVOKER wrapper (the PostgREST-
-- reachable surface; the app schema is not Data-API-exposed).
-- ----------------------------------------------------------------------------
create or replace function public.owner_order_edits(
  p_organization_id uuid,
  p_restaurant_id   uuid    default null,
  p_branch_id       uuid    default null,
  p_range           text    default 'today',
  p_start           date    default null,
  p_end             date    default null,
  p_reason_code     text    default null,
  p_limit           integer default 25,
  p_cursor          text    default null
)
  returns jsonb
  language sql
  security invoker
  set search_path = ''
as $$
  select app.owner_order_edits(
    p_organization_id, p_restaurant_id, p_branch_id, p_range, p_start, p_end,
    p_reason_code, p_limit, p_cursor);
$$;

comment on function public.owner_order_edits(uuid, uuid, uuid, text, date, date, text, integer, text) is
  'ORDER-EDIT-001G: thin public SECURITY INVOKER wrapper over app.owner_order_edits — the '
  'PostgREST-reachable surface. authenticated only; PUBLIC and anon revoked (D-037).';

revoke all on function app.owner_order_edits(uuid, uuid, uuid, text, date, date, text, integer, text) from public;
revoke all on function app.owner_order_edits(uuid, uuid, uuid, text, date, date, text, integer, text) from anon;
grant execute on function app.owner_order_edits(uuid, uuid, uuid, text, date, date, text, integer, text) to authenticated;
revoke all on function public.owner_order_edits(uuid, uuid, uuid, text, date, date, text, integer, text) from public;
revoke all on function public.owner_order_edits(uuid, uuid, uuid, text, date, date, text, integer, text) from anon;
grant execute on function public.owner_order_edits(uuid, uuid, uuid, text, date, date, text, integer, text) to authenticated;

-- ----------------------------------------------------------------------------
-- The new functions never broaden either global public surface (D-037). These
-- assertions match ORDER-EDIT-001A / 001B and pending #288 in either apply
-- order.
-- ----------------------------------------------------------------------------
do $$
declare
  v_anon_set text;
  v_defs text;
begin
  select coalesce(string_agg(regexp_replace(p.oid::regprocedure::text, '^public\.', ''), ', '
    order by regexp_replace(p.oid::regprocedure::text, '^public\.', '')), '')
    into v_anon_set from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
      and has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_anon_set <> 'storefront_menu(text)' then
    raise exception 'ORDER-EDIT-001G: unexpected anon public surface [%]', v_anon_set;
  end if;
  select coalesce(string_agg(regexp_replace(p.oid::regprocedure::text, '^public\.', ''), ', '
    order by regexp_replace(p.oid::regprocedure::text, '^public\.', '')), '')
    into v_defs from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') and p.prosecdef;
  if v_defs <> 'storefront_menu(text)' then
    raise exception 'ORDER-EDIT-001G: unexpected public DEFINER surface [%]', v_defs;
  end if;
  if has_schema_privilege('anon', 'app', 'USAGE') then
    raise exception 'ORDER-EDIT-001G: anon has app schema usage';
  end if;
end;
$$;
