-- OPS-043 Phase 5A - REPORT CURRENCY AUTHORITY.
--
-- WHAT THIS FIXES. Phase 1 made `restaurants.currency_override` writable.
-- Phase 2 (20260818090000) moved `owner_order_history` and
-- `owner_active_orders` onto `coalesce(currency_override, default_currency)`
-- but left the four RPCs that feed the Dashboard Overview reading the
-- ORGANIZATION default alone:
--
--   app.owner_report_range     (the Overview envelope)
--   app.owner_top_items
--   app.owner_sales_series
--   app.owner_daily_report
--
-- Phase 5 reproduced the consequence in a browser: with an organization
-- default of ILS and a restaurant override of JOD, the guarded KPI row
-- rendered `JOD 47.400` while the payment-mix card rendered the same
-- 47400 minor units as a 2-decimal figure on the SAME screen. The
-- formatter takes its exponent from the label, so a wrong label is a
-- 100x wrong number, not merely an unfamiliar symbol.
--
-- WHAT THIS IS NOT. No FX, no conversion, no rescaling: the stored integer
-- minor units are untouched and only the LABEL is corrected. It does not
-- relabel history either - the per-row currency codes and the Phase-2
-- breakdown guard still decide what a window may display; this only stops
-- the envelope from advertising a currency the restaurant does not use.
--
-- SCOPE. Four `create or replace function` statements, bodies extracted
-- verbatim from 20260812090000 with exactly one block changed each. No
-- table, column, index, policy or trigger is touched; there is no
-- top-level INSERT/UPDATE/DELETE and no data is rewritten. Signatures,
-- `stable security definer`, `set search_path = ''`, the membership
-- predicates, the return shape and the aggregation math are unchanged, so
-- the existing ACLs survive (CREATE OR REPLACE keeps grants; nothing is
-- dropped) and no overload is introduced. The `security invoker` public
-- wrappers delegate by name and need no change.


-- --------------------------------------------------------------------------
-- app.owner_report_range(uuid, uuid, uuid, text, date, date)
-- --------------------------------------------------------------------------

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

-- --------------------------------------------------------------------------
-- app.owner_top_items(uuid, uuid, uuid, text, date, date, integer)
-- --------------------------------------------------------------------------

create or replace function app.owner_top_items(
  p_organization_id uuid,
  p_restaurant_id   uuid    default null,
  p_branch_id       uuid    default null,
  p_range           text    default 'today',
  p_start           date    default null,
  p_end             date    default null,
  p_limit           integer default 10
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor    uuid := app.current_app_user_id();
  v_rank     integer;
  v_currency text;
  v_span     integer;  -- window length in days, for the preset ranges
  v_end_off  integer;  -- days back from a branch's local_today to the window end
  v_custom   boolean := false;
  -- Clamped, never rejected: a caller asking for 0 or 5000 rows has made a
  -- display choice, not a malformed request. Invalid WINDOWS raise; an
  -- out-of-band page size is simply bounded.
  v_limit    integer := least(greatest(coalesce(p_limit, 10), 1), 50);
  v_items    jsonb;
begin
  if v_actor is null then
    raise exception 'owner_top_items: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_top_items: organization_id is required' using errcode = '42501';
  end if;

  -- Window selection — the shared block (see the header).
  if p_start is not null or p_end is not null then
    if p_start is null or p_end is null then
      raise exception 'owner_top_items: p_start and p_end must be supplied together'
        using errcode = '22023';
    end if;
    if p_end < p_start then
      raise exception 'owner_top_items: p_end precedes p_start'
        using errcode = '22023';
    end if;
    if (p_end - p_start) > 91 then
      raise exception 'owner_top_items: window exceeds 92 days'
        using errcode = '22023';
    end if;
    v_custom := true;
  else
    case p_range
      when 'today'     then v_span := 1;  v_end_off := 0;
      when 'yesterday' then v_span := 1;  v_end_off := 1;
      when 'last7'     then v_span := 7;  v_end_off := 0;
      when 'last30'    then v_span := 30; v_end_off := 0;
      when 'last60'    then v_span := 60; v_end_off := 0;
      when 'last90'    then v_span := 90; v_end_off := 0;
      else raise exception 'owner_top_items: unknown range %', p_range using errcode = '22023';
    end case;
  end if;

  -- Authority over the PASSED scope (downward-only coverage). 0 => the caller
  -- holds no membership covering it.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_top_items: caller has no active membership covering the requested scope'
      using errcode = '42501';
  end if;

  -- FINANCIAL-READ allowlist — GUC-FREE, the same inline predicate the rest of
  -- the owner analytics family uses rather than app.can_read_financials /
  -- app.current_org_id, which resolve through a GUC that production's JWT path
  -- never sets and would deny a legitimate owner. kitchen_staff is DENIED.
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
    -- A soft denial object, matching the owner-report family: raising here
    -- would leak scope existence through the error channel.
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_top_items');
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
    raise exception 'owner_top_items: organization not found (or deleted)' using errcode = '42501';
  end if;

  with branch_tz_base as (
    -- Branch-local zone (RF-075): COALESCE(branch, restaurant); tz-less
    -- excluded. ORG-SCOPED AT THE SOURCE: SECURITY DEFINER bypasses RLS and the
    -- window CTE reads this directly, so without this filter an org-wide call
    -- would compute day boundaries from OTHER tenants' branches (D-001 / R-003).
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
    -- PER-BRANCH bounds for presets; the SAME fixed dates for every branch when
    -- the window is custom.
    select bt.organization_id, bt.restaurant_id, bt.branch_id, bt.zone,
           case when v_custom then p_start
                else (lt.local_today - v_end_off - (v_span - 1)) end as win_start,
           case when v_custom then p_end
                else (lt.local_today - v_end_off) end                as win_end
    from branch_tz_base bt
    cross join lateral (
      select (now() at time zone bt.zone)::date as local_today
    ) lt
  ),
  order_win as (
    -- BILLED orders in scope whose branch-local day falls in the window.
    select o.id as order_id
    from public.orders o
    join branch_tz t
      on t.organization_id = o.organization_id
     and t.branch_id       = o.branch_id
    where o.organization_id = p_organization_id
      and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or o.branch_id     = p_branch_id)
      and o.deleted_at is null
      and o.status not in ('voided', 'cancelled', 'draft')
      and (o.created_at at time zone t.zone)::date between t.win_start and t.win_end
  ),
  item_win as (
    -- LIVE lines of those orders. The status filter is the canonical one the
    -- order writers use when they recompute subtotal_minor, so a line voided
    -- off the bill stops counting towards its product's ranking.
    select oi.menu_item_id,
           oi.order_id,
           oi.quantity,
           oi.line_total_minor,
           oi.menu_item_name_snapshot,
           oi.created_at,
           oi.id
    from public.order_items oi
    join order_win ow on ow.order_id = oi.order_id
    where oi.organization_id = p_organization_id
      and oi.deleted_at is null
      and oi.status not in ('voided', 'cancelled')
  ),
  rollup as (
    select iw.menu_item_id,
           sum(iw.quantity)::bigint            as quantity,
           sum(iw.line_total_minor)::bigint    as revenue_minor,
           count(distinct iw.order_id)::bigint as order_count
    from item_win iw
    group by iw.menu_item_id
  ),
  display_name as (
    -- The most recently CAPTURED snapshot for this product, deterministically:
    -- newest line first, id as the final tie-break so two lines created in the
    -- same transaction still resolve to one answer.
    select distinct on (iw.menu_item_id)
           iw.menu_item_id,
           iw.menu_item_name_snapshot as name
    from item_win iw
    order by iw.menu_item_id, iw.created_at desc, iw.id desc
  ),
  ranked as (
    -- Revenue first (the question being asked), then quantity, then name, then
    -- the id — which is unique per group, so the order is TOTAL and two runs
    -- over identical data can never disagree about who is 9th and who is 10th.
    select r.menu_item_id, dn.name, r.quantity, r.revenue_minor, r.order_count
    from rollup r
    join display_name dn on dn.menu_item_id = r.menu_item_id
    order by r.revenue_minor desc, r.quantity desc, dn.name asc, r.menu_item_id asc
    limit v_limit
  )
  -- The aggregate repeats the ORDER BY: a LIMIT in a CTE selects WHICH rows
  -- survive, it does not promise the aggregate will consume them in that order.
  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'menu_item_id',  k.menu_item_id,
               'name',          k.name,
               'quantity',      k.quantity,
               'revenue_minor', k.revenue_minor,
               'order_count',   k.order_count
             )
             order by k.revenue_minor desc, k.quantity desc, k.name asc, k.menu_item_id asc
           ),
           '[]'::jsonb
         )
    into v_items
    from ranked k;

  return jsonb_build_object(
    'ok',            true,
    'entity',        'owner_top_items',
    'currency_code', v_currency,
    'range',         case when v_custom then 'custom' else p_range end,
    'limit',         v_limit,
    'items',         coalesce(v_items, '[]'::jsonb)
  );
end;
$$;

-- --------------------------------------------------------------------------
-- app.owner_sales_series(uuid, uuid, uuid, text, date, date)
-- --------------------------------------------------------------------------

create or replace function app.owner_sales_series(
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
  v_actor    uuid := app.current_app_user_id();
  v_rank     integer;
  v_currency text;
  v_span     integer;  -- window length in days, for the predefined ranges
  v_end_off  integer;  -- days back from a branch's local_today to the window end
  v_custom   boolean := false;
  v_buckets  jsonb;
begin
  if v_actor is null then
    raise exception 'owner_sales_series: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_sales_series: organization_id is required' using errcode = '42501';
  end if;

  -- ---------------------------------------------------------------------
  -- Window selection. A CUSTOM window is requested by supplying BOTH bounds;
  -- supplying exactly one is a malformed request rather than a silent
  -- half-open range, because "from the 3rd" has no defensible end and would
  -- quietly become an unbounded historical scan.
  -- ---------------------------------------------------------------------
  if p_start is not null or p_end is not null then
    if p_start is null or p_end is null then
      raise exception 'owner_sales_series: p_start and p_end must be supplied together'
        using errcode = '22023';
    end if;
    if p_end < p_start then
      raise exception 'owner_sales_series: p_end precedes p_start'
        using errcode = '22023';
    end if;
    -- INCLUSIVE of both endpoints, so a single day is start = end and spans 1
    -- day. 92 days is therefore (end - start) <= 91: a full calendar quarter
    -- is expressible, and anything larger is refused rather than scanned.
    if (p_end - p_start) > 91 then
      raise exception 'owner_sales_series: window exceeds 92 days'
        using errcode = '22023';
    end if;
    v_custom := true;
  else
    -- Same range vocabulary and the same (span, end_offset) mapping as
    -- app.owner_report_range, so a chart and a KPI card cannot describe
    -- different windows while claiming the same label.
    case p_range
      when 'today'     then v_span := 1;  v_end_off := 0;
      when 'yesterday' then v_span := 1;  v_end_off := 1;
      when 'last7'     then v_span := 7;  v_end_off := 0;
      when 'last30'    then v_span := 30; v_end_off := 0;
      when 'last60'    then v_span := 60; v_end_off := 0;
      when 'last90'    then v_span := 90; v_end_off := 0;
      else raise exception 'owner_sales_series: unknown range %', p_range using errcode = '22023';
    end case;
  end if;

  -- Authority over the PASSED scope (downward-only coverage). 0 => the caller
  -- holds no membership covering it.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_sales_series: caller has no active membership covering the requested scope'
      using errcode = '42501';
  end if;

  -- FINANCIAL-READ allowlist — GUC-FREE, and deliberately the same inline
  -- predicate app.owner_report_range uses rather than app.can_read_financials
  -- or app.current_org_id: those resolve through a GUC that is not set in the
  -- JWT path this family is called on, and would deny a legitimate owner.
  -- kitchen_staff is DENIED here, as everywhere in owner financial analytics.
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
    -- A soft denial object, matching the owner-report family: a raise here
    -- would leak scope existence through the error channel.
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_sales_series');
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
    raise exception 'owner_sales_series: organization not found (or deleted)' using errcode = '42501';
  end if;

  with branch_tz_base as (
    -- Branch-local zone (RF-075): COALESCE(branch, restaurant). A tz-less
    -- branch is EXCLUDED from financial windows, exactly as the owner-report
    -- family does — without a zone there is no defensible "day" to bucket into.
    --
    -- ORG-SCOPED AT THE SOURCE: SECURITY DEFINER bypasses RLS and the window
    -- CTE reads this directly, so without this filter an org-wide call would
    -- compute day boundaries from OTHER tenants' branches (D-001 / RISK R-003).
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
    -- PER-BRANCH window bounds, each in that branch's OWN zone. An org-wide
    -- call must never pick one organization-wide timezone first: two branches
    -- an hour apart genuinely close their day at different instants, and
    -- collapsing that would move revenue between days for one of them.
    select bt.organization_id, bt.restaurant_id, bt.branch_id, bt.zone,
           case when v_custom then p_start
                else (lt.local_today - v_end_off - (v_span - 1)) end as win_start,
           case when v_custom then p_end
                else (lt.local_today - v_end_off) end                as win_end
    from branch_tz_base bt
    cross join lateral (
      select (now() at time zone bt.zone)::date as local_today
    ) lt
  ),
  order_win as (
    -- Billed-candidate orders in scope, stamped with their BRANCH-LOCAL day.
    select o.id as order_id,
           o.status,
           o.order_type,
           o.subtotal_minor,
           o.discount_total_minor,
           o.grand_total_minor,
           (o.created_at at time zone t.zone)::date as business_day
    from public.orders o
    join branch_tz t
      on t.organization_id = o.organization_id
     and t.branch_id       = o.branch_id
    where o.organization_id = p_organization_id
      and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or o.branch_id     = p_branch_id)
      and o.deleted_at is null
      and (o.created_at at time zone t.zone)::date between t.win_start and t.win_end
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
    -- COMPLETED payments only, on LIVE non-void/cancelled orders, stamped with
    -- the branch-local day of the PAYMENT. Collected is a cash-flow question,
    -- so it is bucketed by when money arrived, not when the order was raised.
    select p.method,
           p.amount_minor,
           (p.created_at at time zone t.zone)::date as business_day
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
      and (p.created_at at time zone t.zone)::date between t.win_start and t.win_end
  ),
  billed_day as (
    select ow.business_day                                                      as day,
           count(*)::bigint                                                     as order_count,
           coalesce(sum(ir.gross_minor), 0)::bigint                             as gross_minor,
           (coalesce(sum(ir.item_discount_minor), 0)
             + coalesce(sum(ow.discount_total_minor), 0))::bigint               as discount_minor,
           coalesce(sum(ow.subtotal_minor - ow.discount_total_minor), 0)::bigint as net_minor
    from order_win ow
    left join item_rollup ir on ir.order_id = ow.order_id
    where ow.status not in ('voided', 'cancelled', 'draft')
    group by ow.business_day
  ),
  void_day as (
    select ow.business_day                                as day,
           count(*)::bigint                               as void_count,
           coalesce(sum(ow.grand_total_minor), 0)::bigint as void_total_minor
    from order_win ow
    where ow.status = 'voided'
    group by ow.business_day
  ),
  collected_day as (
    select pw.business_day                                                       as day,
           coalesce(sum(pw.amount_minor), 0)::bigint                             as collected_minor,
           coalesce(sum(pw.amount_minor) filter (where pw.method = 'cash'), 0)::bigint as cash_minor
    from payment_win pw
    group by pw.business_day
  ),
  method_day as (
    -- Element shape matches owner_report_range's `tenders`
    -- ({method, count, total_minor}) so a client can reuse one parser.
    select g.day,
           jsonb_agg(jsonb_build_object('method', g.method, 'count', g.cnt, 'total_minor', g.total_minor)
                     order by g.method) as by_method
    from (
      select pw.business_day                       as day,
             pw.method,
             count(*)::bigint                      as cnt,
             coalesce(sum(pw.amount_minor), 0)::bigint as total_minor
      from payment_win pw
      group by pw.business_day, pw.method
    ) g
    group by g.day
  ),
  type_day as (
    -- Only PERSISTED order_type values ('dine_in' / 'takeaway'); no invented
    -- grouping label ever enters this payload.
    select g.day,
           jsonb_agg(jsonb_build_object('order_type', g.order_type,
                                        'order_count', g.order_count,
                                        'net_minor', g.net_minor)
                     order by g.order_type) as by_order_type
    from (
      select ow.business_day as day,
             ow.order_type,
             count(*)::bigint as order_count,
             coalesce(sum(ow.subtotal_minor - ow.discount_total_minor), 0)::bigint as net_minor
      from order_win ow
      where ow.status not in ('voided', 'cancelled', 'draft')
      group by ow.business_day, ow.order_type
    ) g
    group by g.day
  ),
  all_days as (
    -- Every day that produced ANY fact: a day with only voids, or only a
    -- payment against an earlier order, is still a real day and must appear.
    select day from billed_day
    union select day from void_day
    union select day from collected_day
  )
  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'day',              to_char(d.day, 'YYYY-MM-DD'),
               'order_count',      coalesce(b.order_count, 0),
               'gross_minor',      coalesce(b.gross_minor, 0),
               'discount_minor',   coalesce(b.discount_minor, 0),
               'net_minor',        coalesce(b.net_minor, 0),
               'void_count',       coalesce(v.void_count, 0),
               'void_total_minor', coalesce(v.void_total_minor, 0),
               'collected_minor',  coalesce(c.collected_minor, 0),
               'cash_minor',       coalesce(c.cash_minor, 0),
               'by_method',        coalesce(m.by_method, '[]'::jsonb),
               'by_order_type',    coalesce(t.by_order_type, '[]'::jsonb)
             )
             order by d.day
           ),
           '[]'::jsonb
         )
    into v_buckets
    from all_days d
    left join billed_day    b on b.day = d.day
    left join void_day      v on v.day = d.day
    left join collected_day c on c.day = d.day
    left join method_day    m on m.day = d.day
    left join type_day      t on t.day = d.day;

  return jsonb_build_object(
    'ok',            true,
    'entity',        'owner_sales_series',
    'currency_code', v_currency,
    'range',         case when v_custom then 'custom' else p_range end,
    'buckets',       coalesce(v_buckets, '[]'::jsonb)
  );
end;
$$;

-- --------------------------------------------------------------------------
-- app.owner_daily_report(uuid, uuid, uuid)
-- --------------------------------------------------------------------------

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
      and oi.status not in ('voided', 'cancelled')
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
  -- MONEY-SETTLEMENT-CONSISTENCY-001 removed the `paid_orders` CTE. It was a MARKER
  -- ("a completed payment row exists"), and it was DAY-KEYED: it matched the PAYMENT's
  -- branch-local day against the ORDER's branch-local day, so an order billed at 23:50
  -- and paid at 00:10 was counted unpaid forever. Settlement is a property of the ORDER,
  -- not of a calendar day, so unpaid_count now asks the canonical predicate directly.
  sales as (
    -- billed sales = orders NOT voided/cancelled/draft.
    select od.business_day,
           count(*)::bigint                                                                as order_count,
           count(*) filter (where od.status = 'completed')::bigint                         as completed_count,
           -- OUTSTANDING money, the canonical rule. A NON-CHARGEABLE zero-total order owes
           -- nothing and is NOT counted; an UNDER-COVERED order still owes and IS counted.
           count(*) filter (
             where not app.order_is_fully_settled(p_organization_id, od.order_id)
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
