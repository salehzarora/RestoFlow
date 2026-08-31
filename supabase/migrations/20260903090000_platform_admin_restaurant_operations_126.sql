-- ============================================================================
-- ADMIN-126 (1/2) — PLATFORM RESTAURANT OPERATIONS: today's sales, today's
-- order count, and the active organization-owner contact(s), per restaurant.
--
-- WHY THIS MIGRATION TOUCHES app.owner_report_range
-- -------------------------------------------------
-- The console must show the SAME "sales today" the restaurant owner sees. The
-- only way to guarantee that permanently is to call the owner's own reporting
-- function, so this migration adds ONE additive branch to its authorization
-- gate and leaves the entire computation byte-identical. No second formula is
-- introduced anywhere in this file.
--
-- WHAT THE OWNER'S NUMBER ACTUALLY IS (audited, not assumed):
--   today's sales  = current.net_minor
--                  = sum(orders.subtotal_minor - orders.discount_total_minor)
--     over orders with deleted_at is null
--          and status not in ('voided','cancelled','draft')
--          bucketed on (orders.created_at at time zone
--                       coalesce(branches.timezone, restaurants.timezone))::date
--   today's orders = current.order_count over that same set
--   currency       = coalesce(restaurants.currency_override,
--                             organizations.default_currency)
--   The formula is subtotal-minus-discount, so it is NET of discounts and does
--   not add tax on top. Whether tax sits INSIDE that subtotal depends on the
--   write path: app.submit_order builds grand = subtotal - discount + tax
--   (exclusive), while app.kiosk_submit_order supports a branch configured for
--   INCLUSIVE tax, where the tax is already inside subtotal. This migration
--   takes no position on that — it reuses the owner's own function, so the
--   console reports whatever the owner is reported, per branch configuration.
--   It is BILLED sales, not cash collected (that is current.collected_minor,
--   deliberately kept separate).
--
-- READ-ONLY (DECISION D-026). The only row this migration's functions ever
-- write is a platform_admin_audit_events row.
--
-- Money stays integer minor units end to end (DECISION D-007). Currencies are
-- NEVER summed across restaurants — the envelope groups totals BY currency,
-- because adding ILS to USD produces a number that is wrong in every currency.
-- ============================================================================

create or replace function app.owner_report_range(
  p_organization_id uuid,
  p_restaurant_id   uuid default null,
  p_branch_id       uuid default null,
  p_range           text default 'today',
  p_start           date default null,
  p_end             date default null
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
  v_span       integer;  -- number of days in the window
  v_end_offset integer;  -- days back from a branch's local_today to cur_end
  v_custom     boolean := false;
  v_result     jsonb;
begin
  if v_actor is null then
    raise exception 'owner_report_range: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_report_range: organization_id is required' using errcode = '42501';
  end if;

  -- Window selection — the shared block (see the header). A custom pair wins
  -- over p_range, exactly as in owner_sales_series.
  if p_start is not null or p_end is not null then
    if p_start is null or p_end is null then
      raise exception 'owner_report_range: p_start and p_end must be supplied together'
        using errcode = '22023';
    end if;
    if p_end < p_start then
      raise exception 'owner_report_range: p_end precedes p_start'
        using errcode = '22023';
    end if;
    if (p_end - p_start) > 91 then
      raise exception 'owner_report_range: window exceeds 92 days'
        using errcode = '22023';
    end if;
    v_custom := true;
    -- INCLUSIVE, so a single day is span 1. This drives both the prior-window
    -- length and the single-day hourly series.
    v_span   := (p_end - p_start) + 1;
  else
    -- Range -> (span, end_offset). Unknown range is a bad request, not a denial.
    case p_range
      when 'today'     then v_span := 1;  v_end_offset := 0;
      when 'yesterday' then v_span := 1;  v_end_offset := 1;
      when 'last7'     then v_span := 7;  v_end_offset := 0;
      when 'last30'    then v_span := 30; v_end_offset := 0;
      when 'last60'    then v_span := 60; v_end_offset := 0;
      when 'last90'    then v_span := 90; v_end_offset := 0;
      else raise exception 'owner_report_range: unknown range %', p_range using errcode = '22023';
    end case;
  end if;

  -- ==========================================================================
  -- ADMIN-126 — TWO CALLERS, ONE FORMULA.
  --
  -- The platform operations console reports each restaurant's sales for today.
  -- It reads them THROUGH THIS FUNCTION rather than computing its own, because
  -- a second revenue formula is a second source of truth: the day it disagrees
  -- with the owner's Dashboard, neither number can be trusted and there is no
  -- way to tell which is wrong. Everything below this gate is untouched and is
  -- evaluated identically for both callers — the body reads only scope and
  -- dates, never the caller.
  --
  -- The platform branch is NOT a membership, NOT an impersonation, and NOT a
  -- widening of tenant authority. It requires ALL of:
  --   * an active platform_admin_grants row  (app.is_platform_admin)
  --   * a VERIFIED aal2 session              (app.current_auth_assurance_level)
  --   * a transaction-local marker that only the audited SECURITY DEFINER
  --     platform read path sets.
  -- The marker is a defence-in-depth detail, not the boundary: PostgREST cannot
  -- set arbitrary GUCs, so it keeps a legitimate platform admin from reading
  -- tenant revenue OUTSIDE the reason-tagged, audited console path. The grant
  -- and aal2 are the actual gate, and no tenant caller can ever satisfy them.
  -- ==========================================================================
  if coalesce(current_setting('app.platform_report_read', true), '') = 'on'
     and app.is_platform_admin()
     and app.current_auth_assurance_level() = 'aal2' then
    null;  -- audited platform read: the tenant membership gate does not apply
  else
    -- authority over the PASSED scope (downward-only coverage); 0 => not a covering member.
    v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
    if v_rank = 0 then
      raise exception 'owner_report_range: caller has no active membership covering the requested scope' using errcode = '42501';
    end if;
    -- FINANCIAL-READ allowlist (GUC-free, app.can_read_financials-STYLE): an ACTIVE
    -- membership covering the PASSED scope (downward-only) whose role is a financial-
    -- read role — cashier / manager / restaurant_owner / org_owner / accountant;
    -- kitchen_staff is DENIED.
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
      return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_report_range');
    end if;
  end if;

  -- OPS-043 Phase 5A: the EFFECTIVE currency, not the organization
  -- default. Phase 1 made restaurants.currency_override writable and
  -- Phase 2 moved owner_order_history / owner_active_orders onto the
  -- coalesce; this envelope was left behind, so a restaurant operating
  -- in an overridden currency had its Overview labelled with the org's.
  -- With different exponents that is not a wrong symbol but a wrong
  -- NUMBER: 47400 minor units reads JOD 47.400 under one label and
  -- 474.00 under the other, on the same screen.
  --
  -- An ORG-WIDE call (no restaurant in scope) keeps the org default:
  -- there is no single restaurant whose override could apply. A
  -- restaurant that is missing, deleted, or belongs to another
  -- organization falls back the same way, so the LEFT JOIN can never
  -- import a sibling tenant's currency.
  --
  -- The `not found` test still keys on the ORGANIZATION row, so a
  -- missing/deleted org raises exactly as before.
  select coalesce(r.currency_override, o.default_currency) into v_currency
    from public.organizations o
    left join public.restaurants r
      on r.id              = p_restaurant_id
     and r.organization_id = o.id
     and r.deleted_at is null
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'owner_report_range: organization not found (or deleted)' using errcode = '42501';
  end if;

  with branch_tz_base as (
    -- branch-local zone (RF-075): COALESCE(branch, restaurant); tz-less excluded.
    -- ORG-SCOPED at the source (SECURITY DEFINER bypasses RLS): the `win` CTE
    -- reads branch_tz DIRECTLY (not via an org-filtered fact join), so without
    -- this filter an org-wide call's range_start/range_end would be computed over
    -- OTHER tenants' branches (D-001 / RISK R-003). All other consumers already
    -- re-scope via their fact tables; this keeps branch_tz itself single-tenant.
    select b.organization_id, b.restaurant_id, b.id as branch_id,
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
    -- per-branch local today + the current/prior window bounds. PRESETS are
    -- branch-local and relative; a CUSTOM pair is the same fixed calendar dates
    -- for every branch. The prior window is derived from cur_start in both
    -- cases, so it is always the immediately preceding equal-length window.
    select bt.organization_id, bt.restaurant_id, bt.branch_id, bt.zone,
           lt.local_today,
           w.cur_end,
           w.cur_start,
           (w.cur_start - 1)      as prev_end,
           (w.cur_start - v_span) as prev_start
    from branch_tz_base bt
    cross join lateral (
      select (now() at time zone bt.zone)::date as local_today
    ) lt
    cross join lateral (
      select case when v_custom then p_end
                  else (lt.local_today - v_end_offset) end                as cur_end,
             case when v_custom then p_start
                  else (lt.local_today - v_end_offset - (v_span - 1)) end as cur_start
    ) w
  ),
  order_win as (
    -- orders in scope, branch-local day + hour, tagged current ('cur') / prior.
    select o.id as order_id,
           o.status,
           o.subtotal_minor,
           o.discount_total_minor,
           o.grand_total_minor,
           (o.created_at at time zone t.zone)::date        as business_day,
           extract(hour from (o.created_at at time zone t.zone))::int as business_hour,
           case
             when (o.created_at at time zone t.zone)::date between t.cur_start  and t.cur_end  then 'cur'
             when (o.created_at at time zone t.zone)::date between t.prev_start and t.prev_end then 'prev'
           end as bucket
    from public.orders o
    join branch_tz t
      on t.organization_id = o.organization_id
     and t.branch_id       = o.branch_id
    where o.organization_id = p_organization_id
      and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or o.branch_id     = p_branch_id)
      and o.deleted_at is null
      and (o.created_at at time zone t.zone)::date between t.prev_start and t.cur_end
  ),
  item_rollup as (
    -- S0.1 — LIVE LINES ONLY. A line voided or cancelled OFF a live bill was
    -- not sold, and the order writers already encode exactly that: after
    -- apply_discount or void_order, orders.subtotal_minor is recomputed as
    -- SUM(line_total_minor) over this same predicate.
    --
    -- Reading every non-deleted line instead let a struck-off line inflate
    -- gross_minor, and the discount captured on that dead line inflate
    -- discount_minor — while net_minor, which reads orders.subtotal_minor,
    -- stayed correct. That is precisely why it went unnoticed: the headline
    -- number was right and the number beside it was wrong.
    --
    -- The filter belongs on the CTE rather than on the gross sum alone, because
    -- gross and the item-discount component must describe the SAME set of
    -- lines. Otherwise the identity gross - discount = net stops holding.
    --
    -- NOTE this is only reachable for a dead line inside a LIVE order: when the
    -- ORDER itself is voided or cancelled, `sales` already drops it wholesale.
    select oi.order_id,
           sum(oi.line_total_minor + oi.line_discount_minor) as gross_minor,
           sum(oi.line_discount_minor)                       as item_discount_minor
    from public.order_items oi
    where oi.deleted_at is null
      and oi.status not in ('voided', 'cancelled')
      and oi.order_id in (select ow.order_id from order_win ow)
    group by oi.order_id
  ),
  payment_win as (
    -- completed payments joined to LIVE non-void/cancel orders, tagged cur/prev.
    select p.id,
           p.method,
           p.amount_minor,
           p.created_at,
           case
             when (p.created_at at time zone t.zone)::date between t.cur_start  and t.cur_end  then 'cur'
             when (p.created_at at time zone t.zone)::date between t.prev_start and t.prev_end then 'prev'
           end as bucket
    from public.payments p
    join branch_tz t
      on t.organization_id = p.organization_id
     and t.branch_id       = p.branch_id
    join public.orders o
      on o.organization_id = p.organization_id
     and o.id              = p.order_id
     and o.deleted_at is null
     and o.status not in ('cancelled', 'voided')
    where p.organization_id = p_organization_id
      and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or p.branch_id     = p_branch_id)
      and p.deleted_at is null
      and p.status = 'completed'
      and (p.created_at at time zone t.zone)::date between t.prev_start and t.cur_end
  ),
  -- MONEY-SETTLEMENT-CONSISTENCY-001 removed the `paid_orders_cur` CTE: a MARKER, and
  -- WINDOW-BOUND (the payment had to land inside the selected range, so an order billed
  -- at a window edge but paid just outside it was reported unpaid). Settlement is a
  -- property of the ORDER, not of the window.
  sales as (
    -- billed sales per bucket = orders NOT voided/cancelled/draft.
    select ow.bucket,
           count(*)::bigint                                                        as order_count,
           count(*) filter (where ow.status = 'completed')::bigint                 as completed_count,
           coalesce(sum(ir.gross_minor), 0)::bigint                                as gross_minor,
           (coalesce(sum(ir.item_discount_minor), 0)
             + coalesce(sum(ow.discount_total_minor), 0))::bigint                  as discount_minor,
           coalesce(sum(ow.subtotal_minor - ow.discount_total_minor), 0)::bigint   as net_minor
    from order_win ow
    left join item_rollup ir on ir.order_id = ow.order_id
    where ow.bucket is not null
      and ow.status not in ('voided', 'cancelled', 'draft')
    group by ow.bucket
  ),
  unpaid_cur as (
    -- Current-window billed orders that still OWE MONEY, by the canonical rule: a
    -- NON-CHARGEABLE zero-total order owes nothing and is not counted; an UNDER-COVERED
    -- order still owes and is counted.
    select count(*)::bigint as unpaid_count
    from order_win ow
    where ow.bucket = 'cur'
      and ow.status not in ('voided', 'cancelled', 'draft')
      and not app.order_is_fully_settled(p_organization_id, ow.order_id)
  ),
  voids_cur as (
    select count(*)::bigint                               as void_count,
           coalesce(sum(ow.grand_total_minor), 0)::bigint as void_total_minor
    from order_win ow
    where ow.bucket = 'cur' and ow.status = 'voided'
  ),
  collected as (
    select bucket,
           coalesce(sum(amount_minor), 0)::bigint                                as collected_minor,
           coalesce(sum(amount_minor) filter (where method = 'cash'), 0)::bigint as cash_minor
    from payment_win
    where bucket is not null
    group by bucket
  ),
  last_cash as (
    select amount_minor as last_cash_payment_minor
    from payment_win
    where bucket = 'cur' and method = 'cash'
    order by created_at desc, id desc
    limit 1
  ),
  tenders_cur as (
    select jsonb_agg(jsonb_build_object('method', method, 'count', cnt, 'total_minor', total_minor)
                     order by method) as tenders
    from (
      select method,
             count(*)::bigint                       as cnt,
             coalesce(sum(amount_minor), 0)::bigint as total_minor
      from payment_win
      where bucket = 'cur'
      group by method
    ) g
  ),
  hourly_net as (
    -- single-day windows only: billed net per branch-local hour.
    select ow.business_hour                                                     as hour,
           coalesce(sum(ow.subtotal_minor - ow.discount_total_minor), 0)::bigint as net_minor
    from order_win ow
    where v_span = 1
      and ow.bucket = 'cur'
      and ow.status not in ('voided', 'cancelled', 'draft')
    group by ow.business_hour
  ),
  hourly_series as (
    -- 24 zero-filled buckets for single-day windows; EMPTY for multi-day.
    select h.hour::int                                                                        as hour,
           coalesce((select hn.net_minor from hourly_net hn where hn.hour = h.hour), 0)::bigint as net_minor
    from generate_series(0, 23) as h(hour)
    where v_span = 1
  ),
  closed_shifts_cur as (
    -- CLOSED/reconciled shifts whose branch-local closed_at day is IN the current
    -- window (tz-less excluded). Reads RF-055 stored expected/counted/variance;
    -- adds opening float (cash_drawer_sessions), opened_by, and duration.
    select s.id                    as shift_id,
           s.branch_id,
           b.name                  as branch_name,
           epc.display_name        as closed_by_name,
           epo.display_name        as opened_by_name,
           coalesce(cds.opening_float_minor, 0)::bigint as opening_float_minor,
           to_char((s.opened_at at time zone t.zone), 'YYYY-MM-DD HH24:MI') as opened_at,
           to_char((s.closed_at at time zone t.zone), 'YYYY-MM-DD HH24:MI') as closed_at,
           (extract(epoch from (s.closed_at - s.opened_at))::bigint / 60)::int as duration_minutes,
           s.expected_total_minor,
           s.counted_total_minor,
           s.variance_minor
    from public.shifts s
    join branch_tz t
      on t.organization_id = s.organization_id
     and t.branch_id       = s.branch_id
    join public.branches b
      on b.organization_id = s.organization_id
     and b.id              = s.branch_id
    left join public.employee_profiles epc
      on epc.organization_id = s.organization_id
     and epc.id             = s.closed_by_employee_profile_id
    left join public.employee_profiles epo
      on epo.organization_id = s.organization_id
     and epo.id             = s.opened_by_employee_profile_id
    left join public.cash_drawer_sessions cds
      on cds.organization_id = s.organization_id
     and cds.shift_id        = s.id
     and cds.deleted_at is null
    where s.organization_id = p_organization_id
      and (p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or s.branch_id     = p_branch_id)
      and s.deleted_at is null
      and s.status in ('closed', 'reconciled')
      and s.closed_at is not null
      and (s.closed_at at time zone t.zone)::date between t.cur_start and t.cur_end
  ),
  shift_sales as (
    -- per-shift paid-order metrics from FK-enforced, server-stamped payments.shift_id
    -- (RF-055/RF-117). Reliable: count(distinct order) / collected / cash.
    select p.shift_id,
           count(distinct p.order_id)::bigint                                     as order_count,
           coalesce(sum(p.amount_minor), 0)::bigint                               as collected_minor,
           coalesce(sum(p.amount_minor) filter (where p.method = 'cash'), 0)::bigint as cash_sales_minor
    from public.payments p
    where p.organization_id = p_organization_id
      and p.deleted_at is null
      and p.status = 'completed'
      and p.shift_id in (select shift_id from closed_shifts_cur)
    group by p.shift_id
  ),
  shift_rows as (
    -- closed shifts enriched with per-shift sales, newest first, capped at 8.
    select cs.*,
           coalesce(ss.order_count, 0)::bigint      as order_count,
           coalesce(ss.collected_minor, 0)::bigint  as collected_minor,
           coalesce(ss.cash_sales_minor, 0)::bigint as cash_sales_minor
    from closed_shifts_cur cs
    left join shift_sales ss on ss.shift_id = cs.shift_id
    order by cs.closed_at desc, cs.shift_id desc
    limit 8
  ),
  open_shifts as (
    -- OPEN shifts NOW in scope (point-in-time count; NOT day/tz bucketed).
    select count(*)::bigint as cnt
    from public.shifts s
    where s.organization_id = p_organization_id
      and (p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or s.branch_id     = p_branch_id)
      and s.deleted_at is null
      and s.status in ('opening', 'open', 'closing')
  ),
  win as (
    -- representative display window over the SCOPED branches (exact for single-tz).
    select min(cur_start) as range_start, max(cur_end) as range_end
    from branch_tz
    where (p_restaurant_id is null or restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or branch_id     = p_branch_id)
  )
  select jsonb_build_object(
    'current', jsonb_build_object(
      'order_count',             coalesce((select order_count     from sales where bucket = 'cur'), 0),
      'completed_count',         coalesce((select completed_count from sales where bucket = 'cur'), 0),
      'open_count',              coalesce((select order_count - completed_count from sales where bucket = 'cur'), 0),
      'unpaid_count',            coalesce((select unpaid_count    from unpaid_cur), 0),
      'gross_minor',             coalesce((select gross_minor     from sales where bucket = 'cur'), 0),
      'discount_minor',          coalesce((select discount_minor  from sales where bucket = 'cur'), 0),
      'net_minor',               coalesce((select net_minor       from sales where bucket = 'cur'), 0),
      'void_count',              coalesce((select void_count      from voids_cur), 0),
      'void_total_minor',        coalesce((select void_total_minor from voids_cur), 0),
      'collected_minor',         coalesce((select collected_minor from collected where bucket = 'cur'), 0),
      'cash_minor',              coalesce((select cash_minor      from collected where bucket = 'cur'), 0),
      'last_cash_payment_minor', coalesce((select last_cash_payment_minor from last_cash), 0),
      'tenders',                 coalesce((select tenders         from tenders_cur), '[]'::jsonb)),
    'comparison', jsonb_build_object(
      'order_count',     coalesce((select order_count     from sales     where bucket = 'prev'), 0),
      'gross_minor',     coalesce((select gross_minor     from sales     where bucket = 'prev'), 0),
      'net_minor',       coalesce((select net_minor       from sales     where bucket = 'prev'), 0),
      'cash_minor',      coalesce((select cash_minor      from collected where bucket = 'prev'), 0),
      'collected_minor', coalesce((select collected_minor from collected where bucket = 'prev'), 0),
      -- SERVER-B additive keys. Both read the SAME `sales` CTE the
      -- current-window values come from, at bucket='prev', so they are the
      -- prior equal-length branch-local window by construction.
      'completed_count', coalesce((select completed_count from sales where bucket = 'prev'), 0),
      'discount_minor',  coalesce((select discount_minor  from sales where bucket = 'prev'), 0)),
    'hourly', coalesce(
      (select jsonb_agg(jsonb_build_object('hour', hs.hour, 'net_minor', hs.net_minor) order by hs.hour)
       from hourly_series hs),
      '[]'::jsonb),
    'shift_cash', jsonb_build_object(
      'closed_shift_count',  coalesce((select count(*)::int from closed_shifts_cur), 0),
      'open_shift_count',    coalesce((select cnt::int from open_shifts), 0),
      'expected_cash_minor', coalesce((select sum(expected_total_minor)::bigint from closed_shifts_cur), 0),
      'counted_cash_minor',  coalesce((select sum(counted_total_minor)::bigint  from closed_shifts_cur), 0),
      'cash_variance_minor', coalesce((select sum(variance_minor)::bigint       from closed_shifts_cur), 0),
      'last_closed_shift', (
        select jsonb_build_object(
                 'shift_id',            r.shift_id,
                 'branch_id',           r.branch_id,
                 'branch_name',         r.branch_name,
                 'opened_at',           r.opened_at,
                 'closed_at',           r.closed_at,
                 'opened_by_name',      r.opened_by_name,
                 'closed_by_name',      r.closed_by_name,
                 'opening_float_minor', r.opening_float_minor,
                 'duration_minutes',    r.duration_minutes,
                 'order_count',         r.order_count,
                 'collected_minor',     r.collected_minor,
                 'cash_sales_minor',    r.cash_sales_minor,
                 'expected_cash_minor', r.expected_total_minor,
                 'counted_cash_minor',  r.counted_total_minor,
                 'cash_variance_minor', r.variance_minor)
        from shift_rows r
        order by r.closed_at desc, r.shift_id desc
        limit 1),
      'recent_closed_shifts', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'shift_id',            r.shift_id,
                 'branch_id',           r.branch_id,
                 'branch_name',         r.branch_name,
                 'opened_at',           r.opened_at,
                 'closed_at',           r.closed_at,
                 'opened_by_name',      r.opened_by_name,
                 'closed_by_name',      r.closed_by_name,
                 'opening_float_minor', r.opening_float_minor,
                 'duration_minutes',    r.duration_minutes,
                 'order_count',         r.order_count,
                 'collected_minor',     r.collected_minor,
                 'cash_sales_minor',    r.cash_sales_minor,
                 'expected_cash_minor', r.expected_total_minor,
                 'counted_cash_minor',  r.counted_total_minor,
                 'cash_variance_minor', r.variance_minor)
               order by r.closed_at desc, r.shift_id desc)
        from shift_rows r),
        '[]'::jsonb))
  ) || jsonb_build_object(
    'range_start', (select to_char(range_start, 'YYYY-MM-DD') from win),
    'range_end',   (select to_char(range_end,   'YYYY-MM-DD') from win)
  ) into v_result;

  return jsonb_build_object(
    'ok', true,
    'entity', 'owner_report_range',
    'currency_code', v_currency,
    'range', case when v_custom then 'custom' else p_range end
  ) || v_result;
end;
$$;


-- ----------------------------------------------------------------------------
-- 2. Per-restaurant operations read
-- ----------------------------------------------------------------------------
create or replace function app.platform_admin_restaurant_operations(
  p_reason     text,
  p_limit      integer default 50,
  p_offset     integer default 0,
  p_search     text    default null,
  p_org_status text    default null,
  p_sort       text    default 'name_asc',
  p_with_sales boolean default null
)
  returns jsonb
  language plpgsql
  volatile              -- it appends an audit row
  security definer
  set search_path = ''
as $$
declare
  v_actor   uuid;
  v_limit   integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset  integer := greatest(coalesce(p_offset, 0), 0);
  v_search  text    := nullif(btrim(coalesce(p_search, '')), '');
  v_sort    text    := coalesce(nullif(btrim(coalesce(p_sort, '')), ''), 'name_asc');
  v_total   integer;
  v_rows    jsonb;
  v_totals  jsonb;
begin
  v_actor := app.platform_admin_guard(p_reason);

  if p_org_status is not null and p_org_status not in ('active', 'suspended') then
    raise exception 'platform admin: unknown organization status %', p_org_status
      using errcode = '22023';
  end if;
  if v_sort not in ('name_asc', 'name_desc', 'organization_asc', 'organization_desc',
                    'sales_desc', 'sales_asc', 'orders_desc', 'orders_asc') then
    raise exception 'platform admin: unknown sort %', v_sort using errcode = '22023';
  end if;

  insert into public.platform_admin_audit_events
    (actor_app_user_id, target_organization_id, action, reason, details)
  values
    (v_actor, null, 'platform.restaurant.operations.read', btrim(p_reason),
     jsonb_build_object('limit', v_limit, 'offset', v_offset, 'sort', v_sort));

  -- The marker the owner-report gate looks for. Transaction-local, so it cannot
  -- outlive this call, and it is cleared explicitly below.
  perform set_config('app.platform_report_read', 'on', true);

  create temp table if not exists _pa_ops (
    restaurant_id        uuid,
    restaurant_name      text,
    restaurant_status    text,
    organization_id      uuid,
    organization_name    text,
    organization_status  text,
    branches_count       integer,
    currency_code        text,
    reporting_date       text,
    today_orders_count   bigint,
    today_revenue_minor  bigint,
    owner_contacts       jsonb,
    report               jsonb   -- the owner's own report envelope, kept whole
  ) on commit drop;
  delete from _pa_ops;

  -- Candidate set: live restaurants under live organizations, filtered.
  -- Sales must be evaluated for EVERY candidate (not just the page) or a
  -- sales sort would only sort the page — so the candidate set is capped and
  -- the cap is reported honestly rather than silently truncating.
  if (select count(*)
        from public.restaurants r
        join public.organizations o on o.id = r.organization_id
       where r.deleted_at is null
         and o.deleted_at is null
         and (p_org_status is null or o.status = p_org_status)
         and (v_search is null
              or r.name ilike '%' || v_search || '%'
              or o.name ilike '%' || v_search || '%')) > 200 then
    raise exception 'platform admin: more than 200 restaurants match; narrow the search'
      using errcode = '22023';
  end if;

  insert into _pa_ops
  select r.id,
         r.name,
         r.status,
         o.id,
         o.name,
         o.status,
         (select count(*)::integer from public.branches b
           where b.restaurant_id = r.id and b.deleted_at is null),
         null, null, null, null, null, null
    from public.restaurants r
    join public.organizations o on o.id = r.organization_id
   where r.deleted_at is null
     and o.deleted_at is null
     and (p_org_status is null or o.status = p_org_status)
     and (v_search is null
          or r.name ilike '%' || v_search || '%'
          or o.name ilike '%' || v_search || '%');

  -- One owner-report call per restaurant. Deliberately not vectorised: the
  -- point of this design is that every figure comes out of the tenant's own
  -- reporting function unchanged. The envelope is stored WHOLE first and read
  -- afterwards, so the function is called exactly once per restaurant rather
  -- than once per field.
  update _pa_ops t
     set report = app.owner_report_range(t.organization_id, t.restaurant_id, null, 'today');

  update _pa_ops
     set currency_code       = report ->> 'currency_code',
         reporting_date      = report ->> 'range_end',
         today_orders_count  = coalesce((report -> 'current' ->> 'order_count')::bigint, 0),
         today_revenue_minor = coalesce((report -> 'current' ->> 'net_minor')::bigint, 0);

  -- Active ORGANIZATION-OWNER contacts only. Never any other staff: a support
  -- console needs the person who signed the contract, not the roster.
  update _pa_ops t
     set owner_contacts = coalesce((
           select jsonb_agg(distinct u.email order by u.email)
             from public.memberships m
             join public.app_users u on u.id = m.app_user_id
            where m.organization_id = t.organization_id
              and m.role       = 'org_owner'
              and m.status     = 'active'
              and m.deleted_at is null
              and u.is_active
              and coalesce(btrim(u.email), '') <> ''
         ), '[]'::jsonb);

  perform set_config('app.platform_report_read', '', true);

  if p_with_sales is not null then
    if p_with_sales then
      delete from _pa_ops where coalesce(today_revenue_minor, 0) = 0;
    else
      delete from _pa_ops where coalesce(today_revenue_minor, 0) <> 0;
    end if;
  end if;

  select count(*)::integer into v_total from _pa_ops;

  select coalesce(jsonb_agg(
           jsonb_build_object(
             'restaurant_id',       k.restaurant_id,
             'restaurant_name',     k.restaurant_name,
             'restaurant_status',   k.restaurant_status,
             'organization_id',     k.organization_id,
             'organization_name',   k.organization_name,
             'organization_status', k.organization_status,
             'branches_count',      k.branches_count,
             'currency_code',       k.currency_code,
             'reporting_date',      k.reporting_date,
             'today_orders_count',  k.today_orders_count,
             'today_revenue_minor', k.today_revenue_minor,
             'owner_contacts',      k.owner_contacts)
           order by k.rn), '[]'::jsonb)
    into v_rows
    from (
      select p.*,
             row_number() over (
               order by
                 case when v_sort = 'sales_desc'  then p.today_revenue_minor end desc nulls last,
                 case when v_sort = 'sales_asc'   then p.today_revenue_minor end asc  nulls last,
                 case when v_sort = 'orders_desc' then p.today_orders_count  end desc nulls last,
                 case when v_sort = 'orders_asc'  then p.today_orders_count  end asc  nulls last,
                 case when v_sort = 'organization_desc' then lower(p.organization_name) end desc,
                 case when v_sort in ('organization_asc') then lower(p.organization_name) end asc,
                 case when v_sort = 'name_desc' then lower(p.restaurant_name) end desc,
                 -- name_asc is the tiebreaker for EVERY sort, so paging is
                 -- stable: without a total order two equal-revenue restaurants
                 -- could swap between page 1 and page 2 and one would vanish.
                 lower(p.restaurant_name) asc,
                 p.restaurant_id asc
             ) as rn
        from _pa_ops p
    ) k
   where k.rn > v_offset and k.rn <= v_offset + v_limit;

  -- Totals GROUPED BY CURRENCY. There is deliberately no combined total: a
  -- single number spanning ILS and USD is wrong in both.
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'currency_code',       c.currency_code,
             'restaurants_count',   c.n,
             'today_orders_count',  c.orders,
             'today_revenue_minor', c.revenue)
           order by c.currency_code), '[]'::jsonb)
    into v_totals
    from (
      select coalesce(currency_code, '') as currency_code,
             count(*)::integer            as n,
             sum(coalesce(today_orders_count, 0))::bigint  as orders,
             sum(coalesce(today_revenue_minor, 0))::bigint as revenue
        from _pa_ops
       group by 1
    ) c;

  return jsonb_build_object(
    'ok', true,
    'rows', v_rows,
    'total_count', v_total,
    'totals_by_currency', v_totals,
    'limit', v_limit,
    'offset', v_offset,
    'server_ts', now());
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. Thin public SECURITY INVOKER wrapper
-- ----------------------------------------------------------------------------
create or replace function public.platform_admin_restaurant_operations(
  p_reason     text,
  p_limit      integer default 50,
  p_offset     integer default 0,
  p_search     text    default null,
  p_org_status text    default null,
  p_sort       text    default 'name_asc',
  p_with_sales boolean default null
)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.platform_admin_restaurant_operations(
       p_reason, p_limit, p_offset, p_search, p_org_status, p_sort, p_with_sales); $$;

-- ----------------------------------------------------------------------------
-- 4. Grants
--
-- BOTH layers are granted to `authenticated`: the public wrapper is SECURITY
-- INVOKER, so granting only the wrapper yields 42501 on the inner function
-- (the REPORT-123 defect that hid all money once already).
--
-- PUBLIC *and* anon are revoked EXPLICITLY at both layers. `revoke ... from
-- public` does NOT remove the anon grant that hosted Supabase's ALTER DEFAULT
-- PRIVILEGES adds to everything created in `public` — anon is named on purpose.
-- ----------------------------------------------------------------------------
revoke all on function app.platform_admin_restaurant_operations(text, integer, integer, text, text, text, boolean) from public;
revoke all on function app.platform_admin_restaurant_operations(text, integer, integer, text, text, text, boolean) from anon;
revoke all on function public.platform_admin_restaurant_operations(text, integer, integer, text, text, text, boolean) from public;
revoke all on function public.platform_admin_restaurant_operations(text, integer, integer, text, text, text, boolean) from anon;
grant execute on function app.platform_admin_restaurant_operations(text, integer, integer, text, text, text, boolean) to authenticated;
grant execute on function public.platform_admin_restaurant_operations(text, integer, integer, text, text, text, boolean) to authenticated;

comment on function app.platform_admin_restaurant_operations(text, integer, integer, text, text, text, boolean) is
  'ADMIN-126 platform operations read. Per restaurant: today''s order count and '
  'net sales taken from app.owner_report_range (the SAME function the tenant '
  'Dashboard reads, so the two can never diverge), the effective currency, and '
  'the ACTIVE organization-owner email(s). Totals are grouped BY CURRENCY and '
  'never summed across currencies. Guarded by app.platform_admin_guard: active '
  'grant + aal2 + a non-empty reason; audited as platform.restaurant.operations.read.';


-- ----------------------------------------------------------------------------
-- 5. Subscriber detail gains the owner contact(s)
--
-- Taken verbatim from the live catalog and extended with one key, so the rest
-- of the ADMIN-125C.1 contract is untouched and the existing console keeps
-- working exactly as before.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.platform_admin_get_subscriber(p_organization_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    -- ADMIN-126: the ACTIVE organization-owner email(s) — the person a support
    -- operator would actually contact. Deliberately NOT the staff roster: a
    -- console needs the signatory, not everyone who can log in.
    'owner_contacts', coalesce((
      select jsonb_agg(distinct u.email order by u.email)
        from public.memberships m
        join public.app_users u on u.id = m.app_user_id
       where m.organization_id = p_organization_id
         and m.role       = 'org_owner'
         and m.status     = 'active'
         and m.deleted_at is null
         and u.is_active
         and coalesce(btrim(u.email), '') <> ''
    ), '[]'::jsonb),
    'server_ts', now());
end;
$function$;
