-- ============================================================================
-- RF-REPORT-004 — app.owner_report_range: date-range reporting with a prior-
-- period comparison, branch-local "today", single-day hourly, and a DEEPER
-- shift/cash block. Additive to RF-REPORT-001/002/003 (owner_daily_report is
-- left UNTOUCHED). DECISIONS D-001/D-007/D-011/D-012/D-020/D-028; RISK R-003.
-- ============================================================================
-- The owner asked for (a) accurate sales-by-hour, (b) deeper shift/cash detail,
-- and (c) range + comparison controls (today / yesterday / last 7 / last 30).
-- RF-REPORT-004 introduces a NEW, additive function `owner_report_range` that
-- serves all three, so the deployed owner_daily_report (and its R-003 sign-off)
-- is not disturbed and stays the compatibility fallback for the "today" view.
--
--   * RANGE (p_range in 'today','yesterday','last7','last30'): the current window
--     and the PRIOR equal-length window are computed PER BRANCH in that branch's
--     OWN local time — cur_end/cur_start/prev_end/prev_start are derived from
--     (now() at time zone COALESCE(branch, restaurant)):::date. This both handles
--     a multi-timezone org correctly AND fixes the latent "today" bug where
--     owner_daily_report used `current_date` (SERVER/UTC date), which mis-defines
--     "today" for the ~2-3h near a branch's local midnight.
--   * COMPARISON: current vs the immediately-preceding equal-length window
--     (yesterday vs day-before; last7 vs previous 7; last30 vs previous 30).
--     Real data only — the client hides a delta when the prior window is empty.
--   * HOURLY: 24 zero-filled branch-local buckets, but ONLY for single-day ranges
--     (today / yesterday). Multi-day ranges return an EMPTY hourly array (an
--     averaged/collapsed curve would be misleading), so the chart hides.
--   * SHIFT_CASH v2: today->range window (closed shifts bucketed by branch-local
--     closed_at day within the current window; tz-less excluded). Adds, per shift,
--     the RF-055 opening float (cash_drawer_sessions), opened_by name + duration,
--     and — from the FK-enforced, server-stamped payments.shift_id — the shift's
--     paid-order count, collected total and cash sales. Still READS the stored
--     RF-055 expected/counted/variance (never recomputes cash).
--   * All money integer minor (bigint; SUM cast to bigint, never float — D-007).
--     deleted_at IS NULL throughout (D-020).
--
-- Same authorization as owner_daily_report, verbatim: identity from auth.uid()
-- -> app.current_app_user_id() (null -> 42501); app.actor_rank_in_scope over the
-- PASSED scope (0 -> 42501); GUC-free can_read_financials-STYLE allowlist
-- (cashier / manager / restaurant_owner / org_owner / accountant; kitchen_staff
-- DENIED via {ok:false,error:'permission_denied'}). Exposes no figure a permitted
-- caller could not already SELECT+SUM under RLS. No new privilege, no anon /
-- service_role (D-011). Custom (arbitrary from/to) ranges remain DEFERRED.
--
-- FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.
-- PENDING: RISK R-003 human RLS/security sign-off before this serves real tenant
-- data. NOT applied to hosted DB by this migration.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. app.owner_report_range — range totals + prior-period + hourly + shift_cash.
-- ---------------------------------------------------------------------------
create or replace function app.owner_report_range(
  p_organization_id uuid,
  p_restaurant_id   uuid default null,
  p_branch_id       uuid default null,
  p_range           text default 'today'
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
  v_span       integer;  -- number of days in the window (1 / 7 / 30)
  v_end_offset integer;  -- days back from a branch's local_today to cur_end
  v_result     jsonb;
begin
  if v_actor is null then
    raise exception 'owner_report_range: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_report_range: organization_id is required' using errcode = '42501';
  end if;

  -- Range -> (span, end_offset). Unknown range is a bad request, not a denial.
  case p_range
    when 'today'     then v_span := 1;  v_end_offset := 0;
    when 'yesterday' then v_span := 1;  v_end_offset := 1;
    when 'last7'     then v_span := 7;  v_end_offset := 0;
    when 'last30'    then v_span := 30; v_end_offset := 0;
    else raise exception 'owner_report_range: unknown range %', p_range using errcode = '22023';
  end case;

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

  select o.default_currency into v_currency
    from public.organizations o
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
    -- per-branch local today + the current/prior window bounds (branch-local).
    select bt.organization_id, bt.restaurant_id, bt.branch_id, bt.zone,
           lt.local_today,
           (lt.local_today - v_end_offset)                        as cur_end,
           (lt.local_today - v_end_offset - (v_span - 1))         as cur_start,
           (lt.local_today - v_end_offset - v_span)               as prev_end,
           (lt.local_today - v_end_offset - v_span - (v_span - 1)) as prev_start
    from branch_tz_base bt
    cross join lateral (
      select (now() at time zone bt.zone)::date as local_today
    ) lt
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
    select oi.order_id,
           sum(oi.line_total_minor + oi.line_discount_minor) as gross_minor,
           sum(oi.line_discount_minor)                       as item_discount_minor
    from public.order_items oi
    where oi.deleted_at is null
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
  paid_orders_cur as (
    select distinct p.order_id
    from public.payments p
    join branch_tz t
      on t.organization_id = p.organization_id
     and t.branch_id       = p.branch_id
    where p.organization_id = p_organization_id
      and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or p.branch_id     = p_branch_id)
      and p.deleted_at is null
      and p.status = 'completed'
      and (p.created_at at time zone t.zone)::date between t.cur_start and t.cur_end
  ),
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
    -- current-window billed orders with NO completed payment (honest unpaid).
    select count(*)::bigint as unpaid_count
    from order_win ow
    where ow.bucket = 'cur'
      and ow.status not in ('voided', 'cancelled', 'draft')
      and not exists (select 1 from paid_orders_cur po where po.order_id = ow.order_id)
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
    -- single-day ranges only: TODAY/YESTERDAY billed net per branch-local hour.
    select ow.business_hour                                                     as hour,
           coalesce(sum(ow.subtotal_minor - ow.discount_total_minor), 0)::bigint as net_minor
    from order_win ow
    where v_span = 1
      and ow.bucket = 'cur'
      and ow.status not in ('voided', 'cancelled', 'draft')
    group by ow.business_hour
  ),
  hourly_series as (
    -- 24 zero-filled buckets for single-day ranges; EMPTY for multi-day.
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
      'collected_minor', coalesce((select collected_minor from collected where bucket = 'prev'), 0)),
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
    'range', p_range
  ) || v_result;
end;
$$;

comment on function app.owner_report_range(uuid, uuid, uuid, text) is
  'RF-REPORT-004 (additive to RF-REPORT-001/002/003; D-007/D-011/D-020/D-028): GUC-free range owner report for the Dashboard Overview. Same authorization as owner_daily_report (app.actor_rank_in_scope over the PASSED scope, 0 -> 42501; GUC-free can_read_financials-STYLE allowlist cashier/manager/restaurant_owner/org_owner/accountant; kitchen_staff -> permission_denied). p_range in today/yesterday/last7/last30. Current + prior equal-length window are computed PER BRANCH in the branch-local zone (RF-075) from (now() at time zone COALESCE(branch,restaurant))::date, fixing the UTC "today" drift and handling multi-timezone orgs. Returns current + comparison (billed/collected), hourly (24 branch-local buckets, single-day ranges only; empty for multi-day), and a DEEPER shift_cash (closed shifts in window: RF-055 stored expected/counted/variance + opening float, opened_by, duration, and FK-stamped per-shift order_count/collected/cash from payments.shift_id). Reads stored cash (never recomputes). All money integer minor (bigint; SUM cast, never float). LIVE deleted_at IS NULL filters (D-020). Read-only; scope-safe (no GUC trusted); no anon/service_role (D-011).';

-- ---------------------------------------------------------------------------
-- 2. Thin public SECURITY INVOKER wrapper (RF-160 / sales_summary pattern).
-- ---------------------------------------------------------------------------
create or replace function public.owner_report_range(
  p_organization_id uuid, p_restaurant_id uuid default null,
  p_branch_id uuid default null, p_range text default 'today')
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.owner_report_range(p_organization_id, p_restaurant_id, p_branch_id, p_range); $$;

-- ---------------------------------------------------------------------------
-- 3. Grants: authenticated only (never anon / service_role; D-011).
-- ---------------------------------------------------------------------------
revoke all on function app.owner_report_range(uuid, uuid, uuid, text)    from public;
grant execute on function app.owner_report_range(uuid, uuid, uuid, text) to authenticated;
revoke all on function public.owner_report_range(uuid, uuid, uuid, text)    from public;
grant execute on function public.owner_report_range(uuid, uuid, uuid, text) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists public.owner_report_range(uuid, uuid, uuid, text);
--   drop function if exists app.owner_report_range(uuid, uuid, uuid, text);
--   (owner_daily_report is untouched and remains the compatibility fallback.)
-- ============================================================================
