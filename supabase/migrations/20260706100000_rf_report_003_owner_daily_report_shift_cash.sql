-- ============================================================================
-- RF-REPORT-003 — app.owner_daily_report: add TODAY's shift / cash reconciliation.
-- Extends RF-REPORT-001 (Slice 1) + RF-REPORT-002 (hourly). DECISIONS
-- D-001/D-007/D-011/D-012/D-020/D-028; RISK R-003.
-- ============================================================================
-- The Dashboard Overview should show CLOSED shift + cash-reconciliation results
-- (a closed shift's expected / counted cash and its variance) — the owner asked
-- why a closed shift's cash (e.g. "370₪") never appears. RF-REPORT-003 adds a
-- TOP-LEVEL `shift_cash` object to the SAME owner_daily_report, surfacing the
-- values that RF-055 close_shift ALREADY persisted on `shifts`:
--     expected_total_minor (= opening float + completed CASH payments for the
--       drawer; RF-055 A6 — card/online tenders are NOT in expected),
--     counted_total_minor  (= the operator's actual counted amount at close),
--     variance_minor       (= counted - expected, SIGNED).
-- The report READS the stored columns (it never recomputes cash), so the figures
-- reconcile exactly with the POS shift-close result. Reconciliation counting +
-- the expected/counted math itself live in RF-055 close_shift (SECURITY DEFINER);
-- this report only reads them for authorized owners/managers.
--
-- This is a forward-only CREATE OR REPLACE of app.owner_daily_report + its thin
-- public SECURITY INVOKER wrapper (re-affirmed grants). NOTHING about the
-- authorization model, scope, money rules, or the RF-REPORT-001/002 blocks
-- changes — one derived, already-authorized object is ADDED:
--   * CLOSED shifts (status in 'closed','reconciled') are bucketed by their
--     BRANCH-LOCAL `closed_at` day (RF-075 zone COALESCE(branch, restaurant);
--     tz-less branches EXCLUDED, same as the sales figures), and only TODAY's
--     closes count. A shift spanning midnight is attributed to the day it was
--     CLOSED (when the cash was counted) — documented behavior.
--   * OPEN shifts (status in 'opening','open','closing') are counted LIVE in
--     scope (a point-in-time "open now" count; NOT day- or tz-bucketed).
--   * aggregate expected / counted / variance = SUM over today's closed shifts;
--     last_closed_shift = the latest close today; recent_closed_shifts = today's
--     closes, newest first, capped at 5. All money integer minor (bigint; SUM
--     cast to bigint, never float — D-007). deleted_at IS NULL throughout (D-020).
--     closed_by_name = employee_profiles.display_name (same-org).
--
-- Exposes no figure a permitted caller could not already SELECT under RLS
-- (shifts / cash_drawer_sessions are authenticated-SELECT in scope, RF-055). No
-- new privilege, no anon / service_role (D-011). Prior-day shift/cash and a
-- per-branch-timezone "today" for multi-timezone orgs remain DEFERRED.
--
-- FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.
-- PENDING: RISK R-003 human RLS/security sign-off before this serves real tenant
-- data (shared with sales_summary / RF-REPORT-001/002). NOT applied to hosted DB.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. app.owner_daily_report — today + prior-day + hourly + shift_cash, in scope.
-- ---------------------------------------------------------------------------
create or replace function app.owner_daily_report(
  p_organization_id uuid,
  p_restaurant_id   uuid default null,
  p_branch_id       uuid default null
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor    uuid    := app.current_app_user_id();
  v_rank     integer;
  v_currency text;
  v_today    date    := current_date;
  v_prior    date    := current_date - 1;
  v_result   jsonb;
begin
  if v_actor is null then
    raise exception 'owner_daily_report: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_daily_report: organization_id is required' using errcode = '42501';
  end if;

  -- authority over the PASSED scope (downward-only coverage); 0 => not a covering member.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_daily_report: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  -- FINANCIAL-READ allowlist (GUC-free, app.can_read_financials-STYLE): the caller
  -- must hold an ACTIVE membership covering the PASSED scope (downward-only,
  -- mirroring app.actor_rank_in_scope) whose role is a financial-read role —
  -- cashier / manager / restaurant_owner / org_owner / accountant; kitchen_staff
  -- is DENIED.
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
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_daily_report');
  end if;

  select o.default_currency into v_currency
    from public.organizations o
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'owner_daily_report: organization not found (or deleted)' using errcode = '42501';
  end if;

  with branch_tz as (
    -- branch-local zone (RF-075): COALESCE(branch, restaurant); tz-less excluded.
    select b.organization_id, b.restaurant_id, b.id as branch_id,
           coalesce(b.timezone, r.timezone) as zone
    from public.branches b
    join public.restaurants r
      on r.organization_id = b.organization_id
     and r.id              = b.restaurant_id
     and r.deleted_at is null
    where b.deleted_at is null
  ),
  order_day as (
    select o.id as order_id,
           o.status,
           o.subtotal_minor,
           o.discount_total_minor,
           o.grand_total_minor,
           (o.created_at at time zone t.zone)::date        as business_day,
           -- RF-REPORT-002: branch-local hour (0..23) for the sales-by-hour chart.
           extract(hour from (o.created_at at time zone t.zone))::int as business_hour
    from public.orders o
    join branch_tz t
      on t.organization_id = o.organization_id
     and t.branch_id       = o.branch_id
    where o.organization_id = p_organization_id
      and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or o.branch_id     = p_branch_id)
      and o.deleted_at is null
      and t.zone is not null
      and (o.created_at at time zone t.zone)::date in (v_today, v_prior)
  ),
  item_rollup as (
    -- per-order pre-discount gross + item-level discount (integer sums).
    select oi.order_id,
           sum(oi.line_total_minor + oi.line_discount_minor) as gross_minor,
           sum(oi.line_discount_minor)                       as item_discount_minor
    from public.order_items oi
    where oi.deleted_at is null
      and oi.order_id in (select od.order_id from order_day od)
    group by oi.order_id
  ),
  payment_day as (
    -- completed payments joined to LIVE non-void/cancel orders, branch-local day.
    select p.id,
           p.method,
           p.amount_minor,
           p.created_at,
           (p.created_at at time zone t.zone)::date as business_day
    from public.payments p
    join branch_tz t
      on t.organization_id = p.organization_id
     and t.branch_id       = p.branch_id
    join public.orders o
      on o.organization_id = p.organization_id
     and o.id              = p.order_id
     and o.deleted_at is null
     and o.status not in ('cancelled', 'voided')  -- defensive belt (RF-062 blocks structurally)
    where p.organization_id = p_organization_id
      and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or p.branch_id     = p_branch_id)
      and p.deleted_at is null
      and p.status = 'completed'
      and t.zone is not null
      and (p.created_at at time zone t.zone)::date in (v_today, v_prior)
  ),
  paid_orders as (
    select distinct business_day, order_id
    from (
      select (p.created_at at time zone t.zone)::date as business_day, p.order_id
      from public.payments p
      join branch_tz t
        on t.organization_id = p.organization_id
       and t.branch_id       = p.branch_id
      where p.organization_id = p_organization_id
        and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)
        and (p_branch_id     is null or p.branch_id     = p_branch_id)
        and p.deleted_at is null
        and p.status = 'completed'
        and t.zone is not null
        and (p.created_at at time zone t.zone)::date in (v_today, v_prior)
    ) pp
  ),
  sales as (
    -- billed sales = orders NOT voided/cancelled/draft.
    select od.business_day,
           count(*)::bigint                                                                as order_count,
           count(*) filter (where od.status = 'completed')::bigint                         as completed_count,
           count(*) filter (
             where not exists (select 1 from paid_orders po
                               where po.business_day = od.business_day and po.order_id = od.order_id)
           )::bigint                                                                        as unpaid_count,
           coalesce(sum(ir.gross_minor), 0)::bigint                                         as gross_minor,
           (coalesce(sum(ir.item_discount_minor), 0)
             + coalesce(sum(od.discount_total_minor), 0))::bigint                           as discount_minor,
           coalesce(sum(od.subtotal_minor - od.discount_total_minor), 0)::bigint            as net_minor
    from order_day od
    left join item_rollup ir on ir.order_id = od.order_id
    where od.status not in ('voided', 'cancelled', 'draft')
    group by od.business_day
  ),
  voids as (
    select od.business_day,
           count(*)::bigint                              as void_count,
           coalesce(sum(od.grand_total_minor), 0)::bigint as void_total_minor
    from order_day od
    where od.status = 'voided'
    group by od.business_day
  ),
  collected as (
    select business_day,
           coalesce(sum(amount_minor), 0)::bigint                              as collected_minor,
           coalesce(sum(amount_minor) filter (where method = 'cash'), 0)::bigint as cash_minor
    from payment_day
    group by business_day
  ),
  last_cash as (
    -- the most recent completed cash payment on the day (id desc tiebreak).
    select distinct on (business_day)
           business_day, amount_minor as last_cash_payment_minor
    from payment_day
    where method = 'cash'
    order by business_day, created_at desc, id desc
  ),
  tenders as (
    select business_day,
           jsonb_agg(jsonb_build_object('method', method, 'count', cnt, 'total_minor', total_minor)
                     order by method) as tenders
    from (
      select business_day, method,
             count(*)::bigint                       as cnt,
             coalesce(sum(amount_minor), 0)::bigint as total_minor
      from payment_day
      group by business_day, method
    ) g
    group by business_day
  ),
  hourly_net as (
    -- RF-REPORT-002: TODAY's BILLED net (subtotal - discount) per branch-local
    -- hour, over the SAME billed orders as `sales` (void/cancelled/draft excluded).
    select od.business_hour                                                     as hour,
           coalesce(sum(od.subtotal_minor - od.discount_total_minor), 0)::bigint as net_minor
    from order_day od
    where od.business_day = v_today
      and od.status not in ('voided', 'cancelled', 'draft')
    group by od.business_hour
  ),
  hourly_series as (
    -- 24 zero-filled buckets so the chart axis is stable (honest zeros).
    select h.hour::int                                                                        as hour,
           coalesce((select hn.net_minor from hourly_net hn where hn.hour = h.hour), 0)::bigint as net_minor
    from generate_series(0, 23) as h(hour)
  ),
  closed_shifts_today as (
    -- RF-REPORT-003: CLOSED (or reconciled) shifts whose BRANCH-LOCAL closed_at
    -- day is TODAY (tz-less branches excluded, same as the sales figures). Reads
    -- the RF-055-persisted expected/counted/variance (integer minor). A shift
    -- that spanned midnight is attributed to its CLOSE day (cash-count day).
    select s.id                    as shift_id,
           s.branch_id,
           b.name                  as branch_name,
           ep.display_name         as closed_by_name,
           -- BRANCH-LOCAL display strings (consistent with the closed_at bucketing;
           -- never leak a raw UTC ISO whose calendar date contradicts the bucket).
           to_char((s.opened_at at time zone t.zone), 'YYYY-MM-DD HH24:MI') as opened_at,
           to_char((s.closed_at at time zone t.zone), 'YYYY-MM-DD HH24:MI') as closed_at,
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
    left join public.employee_profiles ep
      on ep.organization_id = s.organization_id
     and ep.id             = s.closed_by_employee_profile_id
    where s.organization_id = p_organization_id
      and (p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or s.branch_id     = p_branch_id)
      and s.deleted_at is null
      and s.status in ('closed', 'reconciled')
      and s.closed_at is not null
      and t.zone is not null
      and (s.closed_at at time zone t.zone)::date = v_today
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
  )
  select jsonb_build_object(
    'today', jsonb_build_object(
      'order_count',             coalesce((select s.order_count     from sales s     where s.business_day = v_today), 0),
      'completed_count',         coalesce((select s.completed_count from sales s     where s.business_day = v_today), 0),
      'open_count',              coalesce((select s.order_count - s.completed_count from sales s where s.business_day = v_today), 0),
      'unpaid_count',            coalesce((select s.unpaid_count    from sales s     where s.business_day = v_today), 0),
      'gross_minor',             coalesce((select s.gross_minor     from sales s     where s.business_day = v_today), 0),
      'discount_minor',          coalesce((select s.discount_minor  from sales s     where s.business_day = v_today), 0),
      'net_minor',               coalesce((select s.net_minor       from sales s     where s.business_day = v_today), 0),
      'void_count',              coalesce((select v.void_count      from voids v     where v.business_day = v_today), 0),
      'void_total_minor',        coalesce((select v.void_total_minor from voids v    where v.business_day = v_today), 0),
      'collected_minor',         coalesce((select c.collected_minor from collected c where c.business_day = v_today), 0),
      'cash_minor',              coalesce((select c.cash_minor      from collected c where c.business_day = v_today), 0),
      'last_cash_payment_minor', coalesce((select l.last_cash_payment_minor from last_cash l where l.business_day = v_today), 0),
      'tenders',                 coalesce((select t.tenders         from tenders t   where t.business_day = v_today), '[]'::jsonb)),
    'prior_day', jsonb_build_object(
      'order_count',  coalesce((select s.order_count from sales s     where s.business_day = v_prior), 0),
      'gross_minor',  coalesce((select s.gross_minor from sales s     where s.business_day = v_prior), 0),
      'net_minor',    coalesce((select s.net_minor   from sales s     where s.business_day = v_prior), 0),
      'cash_minor',   coalesce((select c.cash_minor  from collected c where c.business_day = v_prior), 0)),
    -- RF-REPORT-002: TODAY's 24 sales-by-hour buckets (billed net, integer minor).
    'hourly', coalesce(
      (select jsonb_agg(jsonb_build_object('hour', hs.hour, 'net_minor', hs.net_minor) order by hs.hour)
       from hourly_series hs),
      '[]'::jsonb),
    -- RF-REPORT-003: TODAY's shift / cash reconciliation (stored RF-055 values).
    'shift_cash', jsonb_build_object(
      'closed_shift_count',  coalesce((select count(*)::int from closed_shifts_today), 0),
      'open_shift_count',    coalesce((select cnt::int from open_shifts), 0),
      'expected_cash_minor', coalesce((select sum(expected_total_minor)::bigint from closed_shifts_today), 0),
      'counted_cash_minor',  coalesce((select sum(counted_total_minor)::bigint  from closed_shifts_today), 0),
      'cash_variance_minor', coalesce((select sum(variance_minor)::bigint       from closed_shifts_today), 0),
      'last_closed_shift', (
        select jsonb_build_object(
                 'shift_id',            cs.shift_id,
                 'branch_id',           cs.branch_id,
                 'branch_name',         cs.branch_name,
                 'opened_at',           cs.opened_at,
                 'closed_at',           cs.closed_at,
                 'closed_by_name',      cs.closed_by_name,
                 'expected_cash_minor', cs.expected_total_minor,
                 'counted_cash_minor',  cs.counted_total_minor,
                 'cash_variance_minor', cs.variance_minor)
        from closed_shifts_today cs
        order by cs.closed_at desc, cs.shift_id desc
        limit 1),
      'recent_closed_shifts', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'shift_id',            r.shift_id,
                 'branch_id',           r.branch_id,
                 'branch_name',         r.branch_name,
                 'closed_at',           r.closed_at,
                 'closed_by_name',      r.closed_by_name,
                 'expected_cash_minor', r.expected_total_minor,
                 'counted_cash_minor',  r.counted_total_minor,
                 'cash_variance_minor', r.variance_minor)
               order by r.closed_at desc, r.shift_id desc)
        from (select * from closed_shifts_today order by closed_at desc, shift_id desc limit 5) r),
        '[]'::jsonb))
  ) into v_result;

  return jsonb_build_object(
    'ok', true,
    'entity', 'owner_daily_report',
    'currency_code', v_currency,
    'business_date', v_today
  ) || v_result;
end;
$$;

comment on function app.owner_daily_report(uuid, uuid, uuid) is
  'RF-REPORT-003 (extends RF-REPORT-001/002; D-007/D-011/D-020/D-028): GUC-free real owner daily report for the Dashboard Overview. Same authorization (app.actor_rank_in_scope over the PASSED scope, 0 -> 42501; GUC-free can_read_financials-STYLE allowlist cashier/manager/restaurant_owner/org_owner/accountant; kitchen_staff -> permission_denied). today + prior_day (billed vs collected split) + hourly (24 branch-local buckets, billed net) + shift_cash. shift_cash = TODAY''s CLOSED shifts (status closed/reconciled, bucketed by branch-local closed_at day; tz-less excluded) surfacing the RF-055-STORED expected_total_minor (opening float + completed CASH payments; card NOT included), counted_total_minor (operator count), variance_minor (counted - expected, signed); plus a live open_shift_count and last/recent (cap 5, newest first) closes with branch/closed_by names. Reads stored columns (never recomputes cash). All money integer minor (bigint; SUM cast, never float). LIVE deleted_at IS NULL filters (D-020). Read-only; scope-safe (no GUC trusted); no anon/service_role (D-011).';

-- ---------------------------------------------------------------------------
-- 2. Thin public SECURITY INVOKER wrapper (RF-160 / sales_summary pattern).
--    Re-affirmed verbatim (the signature is unchanged; the body delegates).
-- ---------------------------------------------------------------------------
create or replace function public.owner_daily_report(
  p_organization_id uuid, p_restaurant_id uuid default null, p_branch_id uuid default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.owner_daily_report(p_organization_id, p_restaurant_id, p_branch_id); $$;

-- ---------------------------------------------------------------------------
-- 3. Grants: authenticated only (never anon / service_role; D-011).
-- ---------------------------------------------------------------------------
revoke all on function app.owner_daily_report(uuid, uuid, uuid)    from public;
grant execute on function app.owner_daily_report(uuid, uuid, uuid) to authenticated;
revoke all on function public.owner_daily_report(uuid, uuid, uuid)    from public;
grant execute on function public.owner_daily_report(uuid, uuid, uuid) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   RF-REPORT-003 is a CREATE OR REPLACE; to revert, re-apply the RF-REPORT-002
--   body (20260706090000) which restores the no-shift_cash version.
-- ============================================================================
