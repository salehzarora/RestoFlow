-- DASHBOARD-OWNER-ANALYTICS-PHASE-A (SERVER-B).
--
-- Two ADDITIVE evolutions of existing read-only owner RPCs. No new table,
-- column, trigger, writer, RLS policy, backfill or index. owner_sales_series
-- (SERVER-A) is untouched.
--
-- Both function bodies below are the CURRENT definitions reproduced verbatim
-- with only the changes described here, so a reviewer can diff them against
-- 20260715090000 (owner_report_range) and 20260802090000 (owner_order_history)
-- and see exactly what moved.
--
-- (A) owner_report_range.comparison gains TWO keys: completed_count and
--     discount_minor. Every existing key, value and semantic is unchanged, and
--     both new values read the SAME `sales` CTE the current-window numbers come
--     from at bucket='prev' — so they are the prior equal-length branch-local
--     window by construction, not a second definition of "previous".
--
--     Both keys already exist in the `current` object, so this makes comparison
--     symmetric with current for exactly those two metrics — which is the whole
--     point: a client cannot render a delta from a prior value alone.
--
--     NOT ADDED, deliberately:
--       * open_count — it is exactly order_count - completed_count, and after
--         this change comparison carries both. A third stored copy of the same
--         subtraction is a place for the two to disagree.
--       * average ticket / percentage — comparison already carries order_count
--         and net_minor, which is everything a client needs to derive it. A
--         server-side average would also have to be a float, and F0's
--         ComparisonDelta already owns prior-zero, prior-null and percent
--         derivation. Integer primitives only.
--       * unpaid_count comparison — unpaid is a CURRENT settlement snapshot
--         (app.order_is_fully_settled evaluated now), not a fact the schema
--         stored as-of a past window. A "prior unpaid" would be today's
--         settlement state of old orders wearing a historical label.
--
-- (B) owner_order_history accepts card / bit / external in p_payment, and now
--     VALIDATES the token. Signature unchanged.
--
--     BEHAVIOUR CHANGE WORTH NAMING: p_payment was previously unvalidated. An
--     unknown token matched no branch and returned an empty list, which reads
--     exactly like "no such orders exist". It now raises 22023, the same idiom
--     this function already uses for p_range and p_cursor.
--
--     The method filters compare against `pay`, the lateral that already
--     selects the single COMPLETED payment per order, so a pending or failed
--     row can never make an order a method match. Recorded tender only — this
--     platform stores no acquirer settlement.
--
-- NO GRANTS ARE RESTATED. Both signatures are byte-identical to the ones being
-- replaced, so CREATE OR REPLACE keeps the existing ACL (revoked from public
-- and anon, granted to authenticated, never service_role — D-011). The pgTAP
-- suite asserts that rather than assuming it.
--
-- NO INDEX. Neither change introduces a new access path: the comparison keys
-- read a CTE the function already materialises for the current window, and the
-- payment filter compares a column of a lateral that is already joined for
-- every row. The query plan is the one this function had yesterday.

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
    'range', p_range
  ) || v_result;
end;
$$;

create or replace function app.owner_order_history(
  p_organization_id uuid,
  p_restaurant_id   uuid  default null,
  p_branch_id       uuid  default null,
  p_range           text  default 'today',
  p_search          text  default null,
  p_status          text  default null,
  p_order_type      text  default null,
  p_payment         text  default null,   -- null | paid | unpaid | cash | card | bit | external
  p_limit           int   default 25,
  p_cursor          text  default null     -- keyset cursor "<created_at>|<id>"
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
  v_span       integer;
  v_end_offset integer;
  v_limit      integer := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_search     text    := nullif(btrim(coalesce(p_search, '')), '');
  v_cursor_ts  timestamptz;
  v_cursor_id  uuid;
  v_result     jsonb;
begin
  if v_actor is null then
    raise exception 'owner_order_history: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_order_history: organization_id is required' using errcode = '42501';
  end if;

  -- Range -> (span, end_offset). Unknown range is a bad request, not a denial.
  case p_range
    when 'today'     then v_span := 1;  v_end_offset := 0;
    when 'yesterday' then v_span := 1;  v_end_offset := 1;
    when 'last7'     then v_span := 7;  v_end_offset := 0;
    when 'last30'    then v_span := 30; v_end_offset := 0;
    else raise exception 'owner_order_history: unknown range %', p_range using errcode = '22023';
  end case;

  -- SERVER-B: p_payment was previously UNVALIDATED — an unknown token fell
  -- through every branch of the filter and returned an empty list, which is
  -- indistinguishable from "this window genuinely has no such orders". A
  -- filter the caller misspelled must fail loudly, using the same 22023 idiom
  -- this function already applies to p_range and p_cursor.
  if p_payment is not null
     and p_payment not in ('paid', 'unpaid', 'cash', 'card', 'bit', 'external') then
    raise exception 'owner_order_history: unknown payment filter %', p_payment using errcode = '22023';
  end if;

  -- authority over the PASSED scope (downward-only coverage); 0 => not a member.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_order_history: caller has no active membership covering the requested scope' using errcode = '42501';
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
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_order_history');
  end if;

  select o.default_currency into v_currency
    from public.organizations o
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'owner_order_history: organization not found (or deleted)' using errcode = '42501';
  end if;

  -- Keyset cursor: "<created_at::text>|<id>". A malformed cursor is a bad request.
  if p_cursor is not null and btrim(p_cursor) <> '' then
    begin
      v_cursor_ts := split_part(p_cursor, '|', 1)::timestamptz;
      v_cursor_id := split_part(p_cursor, '|', 2)::uuid;
    exception when others then
      raise exception 'owner_order_history: invalid cursor' using errcode = '22023';
    end;
  end if;

  with branch_tz_base as (
    -- branch-local zone (RF-075): COALESCE(branch, restaurant, 'UTC'). UNLIKE the
    -- owner_* REPORTS (which exclude tz-less branches from an aggregate), a
    -- history LIST must never silently DROP an order, so a tz-less branch falls
    -- back to UTC for its day window rather than disappearing. ORG-SCOPED at the
    -- source so an org-wide call's windows are not computed over other tenants'
    -- branches (D-001 / RISK R-003).
    select b.organization_id, b.restaurant_id, b.id as branch_id,
           coalesce(b.timezone, r.timezone, 'UTC') as zone
    from public.branches b
    join public.restaurants r
      on r.organization_id = b.organization_id
     and r.id              = b.restaurant_id
     and r.deleted_at is null
    where b.organization_id = p_organization_id
      and b.deleted_at is null
  ),
  branch_tz as (
    select bt.organization_id, bt.restaurant_id, bt.branch_id, bt.zone,
           (lt.local_today - v_end_offset)                as cur_end,
           (lt.local_today - v_end_offset - (v_span - 1)) as cur_start
    from branch_tz_base bt
    cross join lateral (
      select (now() at time zone bt.zone)::date as local_today
    ) lt
  ),
  matched as (
    select o.id,
           o.status,
           o.order_type,
           o.customer_name,
           o.customer_phone,
           o.receipt_number,
           o.subtotal_minor,
           o.discount_total_minor,
           o.tax_total_minor,
           o.grand_total_minor,
           o.created_at,
           t.zone,
           '#' || upper(right(replace(o.id::text, '-', ''), 6)) as order_code,
           tbl.label                                            as table_label,
           ep.display_name                                      as staff_name,
           coalesce(items.item_count, 0)                        as item_count,
           pay.method                                           as payment_method,
           pay.amount_minor                                     as paid_amount_minor,
           -- MONEY-SETTLEMENT-CONSISTENCY-001: SETTLEMENT, not a marker (see
           -- owner_active_orders). History and the live board must never disagree about
           -- whether the same order owes money.
           app.order_is_fully_settled(o.organization_id, o.id) as is_paid,
           (o.grand_total_minor > 0)                            as is_chargeable
    from public.orders o
    join branch_tz t
      on t.organization_id = o.organization_id
     and t.branch_id       = o.branch_id
    left join public.tables tbl
      on tbl.organization_id = o.organization_id
     and tbl.id             = o.table_id
     and tbl.deleted_at is null
    left join public.employee_profiles ep
      on ep.organization_id = o.organization_id
     and ep.id             = o.opened_by_employee_profile_id
    left join lateral (
      select sum(oi.quantity)::bigint as item_count
      from public.order_items oi
      where oi.organization_id = o.organization_id
        and oi.order_id        = o.id
        and oi.deleted_at is null
    ) items on true
    left join lateral (
      -- the single completed payment for the order (at most one; D-024/D-025).
      select p.method, p.amount_minor
      from public.payments p
      where p.organization_id = o.organization_id
        and p.order_id        = o.id
        and p.deleted_at is null
        and p.status = 'completed'
      order by p.created_at desc, p.id desc
      limit 1
    ) pay on true
    where o.organization_id = p_organization_id
      and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or o.branch_id     = p_branch_id)
      and o.deleted_at is null
      and (o.created_at at time zone t.zone)::date between t.cur_start and t.cur_end
      and (p_order_type is null or o.order_type = p_order_type)
      and (p_status     is null or o.status     = p_status)
      and (
        p_payment is null
        -- Settlement, not the marker — the SAME rule the badge renders, so filtering
        -- `unpaid` can never surface an order that owes nothing.
        or (p_payment = 'paid'   and app.order_is_fully_settled(o.organization_id, o.id))
        or (p_payment = 'unpaid' and not app.order_is_fully_settled(o.organization_id, o.id))
        -- SERVER-B: the method filters compare against `pay`, which is the
        -- single COMPLETED payment for the order. A pending or failed row is
        -- therefore never a method match — this is recorded-tender truth,
        -- not processor settlement.
        or (p_payment in ('cash', 'card', 'bit', 'external') and pay.method = p_payment)
      )
      and (
        v_search is null
        or o.customer_name ilike '%' || v_search || '%'
        or coalesce(o.receipt_number, '') ilike '%' || v_search || '%'
        or coalesce(tbl.label, '') ilike '%' || v_search || '%'
        or upper(right(replace(o.id::text, '-', ''), 6)) like '%' || upper(replace(v_search, '#', '')) || '%'
      )
      and (
        p_cursor is null
        or v_cursor_ts is null
        or o.created_at < v_cursor_ts
        or (o.created_at = v_cursor_ts and o.id < v_cursor_id)
      )
  ),
  page as (
    select m.*, m.created_at::text || '|' || m.id::text as cursor
    from matched m
    order by m.created_at desc, m.id desc
    limit v_limit + 1
  ),
  numbered as (
    select p.*, row_number() over (order by p.created_at desc, p.id desc) as rn
    from page p
  )
  select jsonb_build_object(
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object(
               'order_id',             n.id,
               'order_code',           n.order_code,
               'receipt_number',       n.receipt_number,
               'status',               n.status,
               'order_type',           n.order_type,
               'customer_name',        n.customer_name,
               'customer_phone',       n.customer_phone,
               'table_label',          n.table_label,
               'staff_name',           n.staff_name,
               'created_at',           to_char(n.created_at at time zone n.zone, 'YYYY-MM-DD HH24:MI'),
               'item_count',           n.item_count,
               'subtotal_minor',       n.subtotal_minor,
               'discount_total_minor', n.discount_total_minor,
               'tax_total_minor',      n.tax_total_minor,
               'grand_total_minor',    n.grand_total_minor,
               'payment_method',       n.payment_method,
               'payment_status',       case when not n.is_chargeable then 'not_chargeable'
                                             when n.is_paid           then 'paid'
                                             else                          'unpaid' end,
               'paid_amount_minor',    n.paid_amount_minor)
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
    'entity', 'owner_order_history',
    'currency_code', v_currency,
    'range', p_range,
    'limit', v_limit
  ) || v_result;
end;
$$;
