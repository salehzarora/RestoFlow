-- ============================================================================
-- RF-REPORT-001 (Slice 1) — app.owner_daily_report: GUC-free real owner daily
-- report for the Dashboard Overview. DECISIONS D-001/D-007/D-011/D-012/D-020;
-- RISK R-003.
-- ============================================================================
-- The Dashboard Overview needs a REAL (not demo) daily report. The RF-075/RF-092
-- daily views hold the right buckets but are security_invoker over the GUC-pinned
-- RF-059 SELECT policies, so a real anon-key + JWT dashboard caller reads ZERO
-- rows. The existing public.sales_summary is a thin headline (today's
-- orders/payments/gross + a 7-day trend) that CONFLATES billed sales with
-- collected payments. This additive, forward-only migration adds a richer
-- GUC-free SECURITY DEFINER read (+ thin public SECURITY INVOKER wrapper,
-- the RF-160 / sales_summary pattern) that:
--   * SPLITS billed sales (orders + order_items) from collected cash (payments) —
--     they are NOT the same figure;
--   * exposes gross / discount / net (billed), void count+total, collected /
--     cash / last-cash-payment, a per-method tender breakdown, and a prior-day
--     comparison block for the Overview's "vs yesterday" deltas;
--   * reconciles with RF-075: identical billed/collected definitions and the
--     SAME branch-local business-day bucketing (zero drift).
-- It writes nothing. sales_summary is left intact (unused after the client
-- switches to this RPC; retained for compatibility).
--
-- GUC-FREE authorization (mirrors sales_summary / RF-112 D-033):
--   * caller identity from auth.uid() -> app.current_app_user_id() (NULL -> 42501);
--   * tenant scope validated by app.actor_rank_in_scope over the PASSED
--     (org, restaurant?, branch?) scope, downward-only coverage; 0 -> 42501
--     (fail closed, no cross-tenant);
--   * ROLE GATE (RF-REPORT-001 decision): a GUC-free financial-read allowlist,
--     app.can_read_financials-STYLE — the SAME role set that gates the money-table
--     RLS (cashier / manager / restaurant_owner / org_owner / ACCOUNTANT);
--     kitchen_staff -> {ok:false, error:'permission_denied'}. Checked GUC-free
--     (can_read_financials itself is org-GUC-bound and would deny in this
--     GUC-free context). Exposes no figure a permitted caller could not already
--     SELECT+SUM under RLS. No anon / service_role (D-011).
--
-- MONEY (D-007): integer minor units ONLY. Every SUM is over a persisted bigint
--   *_minor column and cast back to bigint (SUM(bigint) is numeric in Postgres);
--   no float, ever. Nothing is recomputed.
--
-- BILLED vs COLLECTED (reconciles with RF-075):
--   * BILLED sales = orders NOT IN (voided, cancelled, draft):
--       gross_minor    = SUM(order_items.line_total_minor + line_discount_minor)
--       discount_minor = SUM(order_items.line_discount_minor)
--                        + SUM(orders.discount_total_minor)
--       net_minor      = SUM(orders.subtotal_minor - orders.discount_total_minor)
--   * VOIDS = orders.status = 'voided': void_count, void_total_minor (grand total)
--   * COLLECTED = payments.status = 'completed' joined to LIVE non-void/cancel
--     orders: collected_minor = SUM(amount_minor); cash_minor = the cash filter;
--     last_cash_payment_minor = the most recent completed cash payment on the day;
--     tenders = per-method {method, count, total_minor}.
--
-- COUNTS: order_count (billed), completed_count (status='completed'),
--   open_count (billed - completed), unpaid_count (billed orders with no completed
--   payment). These feed the Overview KPI cards + avg-ticket (= net // order_count,
--   client-side integer division).
--
-- DAY BOUNDARY (RF-REPORT-001 decision, matches RF-075): each order/payment is
--   bucketed by its BRANCH-LOCAL business day,
--   (created_at at time zone COALESCE(branch.timezone, restaurant.timezone))::date,
--   so this report RECONCILES with the RF-075 daily report (no UTC/local mixing).
--   Rows whose branch+restaurant both lack a timezone are EXCLUDED (same as
--   RF-075 — configure a timezone to include them; onboarding sets one). The
--   today/prior reference is the server date (current_date / current_date - 1);
--   a full per-branch-timezone "today" for multi-timezone orgs is DEFERRED.
--
-- FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.
-- PENDING: RISK R-003 human RLS/security sign-off before this serves real tenant
-- data (shared with sales_summary).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. app.owner_daily_report — today + prior-day owner report in the caller's scope.
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
  -- is DENIED. This is app.can_read_financials' exact role boundary computed
  -- WITHOUT the org GUC (which a GUC-free RPC never sets, so has_role_in_scope /
  -- can_read_financials would deny everyone here). Distinguishes kitchen_staff
  -- from cashier/accountant (both role_rank 1), which the rank check cannot.
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
           (o.created_at at time zone t.zone)::date as business_day
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
      'cash_minor',   coalesce((select c.cash_minor  from collected c where c.business_day = v_prior), 0))
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
  'RF-REPORT-001 Slice 1 (D-007/D-011/D-020): GUC-free real owner daily report for the Dashboard Overview. Authorized via app.actor_rank_in_scope over the PASSED (org, restaurant?, branch?) scope (0 -> 42501) + a GUC-free can_read_financials-STYLE role allowlist (cashier/manager/restaurant_owner/org_owner/accountant; kitchen_staff -> permission_denied). SPLITS billed sales (orders+order_items: gross/discount/net, void count+total) from collected payments (completed: collected/cash/last-cash + per-method tenders); today + prior_day blocks for KPI deltas. Branch-local business day (RF-075 bucketing; tz-less branches excluded). All money integer minor (bigint; SUM cast to bigint, never float). LIVE branch/restaurant + deleted_at IS NULL filters (D-020). Read-only; scope-safe (no GUC trusted); no anon/service_role (D-011).';

-- ---------------------------------------------------------------------------
-- 2. Thin public SECURITY INVOKER wrapper (RF-160 / sales_summary pattern).
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
--   drop function if exists public.owner_daily_report(uuid, uuid, uuid);
--   drop function if exists app.owner_daily_report(uuid, uuid, uuid);
-- ============================================================================
