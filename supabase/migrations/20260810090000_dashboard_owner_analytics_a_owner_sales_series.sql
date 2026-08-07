-- DASHBOARD-OWNER-ANALYTICS-PHASE-A (SERVER-A) — owner_sales_series.
--
-- A NEW read-only owner analytics RPC returning BRANCH-LOCAL DAILY buckets, so
-- the Dashboard can draw a real trend without downloading raw orders to the
-- client and aggregating there. Server aggregation is the entire point: an
-- owner with a month of orders must not ship them all to a browser, and a
-- client-side rollup would inevitably re-derive "which day is this" in the
-- device's timezone rather than the branch's.
--
-- ADDITIVE ONLY. This migration creates one function family and its grants.
-- It does NOT touch owner_report_range or owner_order_history (those are a
-- separate SERVER-B slice), and it creates no table, column, trigger, writer,
-- RLS policy or index.
--
-- SEMANTICS ARE COPIED, NOT REINVENTED. Every money rule below mirrors
-- app.owner_report_range as it stands after MONEY-SETTLEMENT-CONSISTENCY-001,
-- because two owner surfaces disagreeing about "net sales" is worse than either
-- definition being imperfect:
--
--   gross_minor    = Σ(order_items.line_total_minor + line_discount_minor)
--   discount_minor = Σ(item line_discount) + Σ(orders.discount_total_minor)
--   net_minor      = Σ(orders.subtotal_minor - discount_total_minor)
--   billed rows    = deleted_at IS NULL AND status NOT IN
--                    ('voided','cancelled','draft')
--   voids          = a SEPARATE bucket (count + grand_total), never folded into
--                    billed and never merged with discounts
--   collected      = COMPLETED payments only, on live non-void/cancelled orders
--
-- BILLED != COLLECTED. They answer different questions ("what did we charge"
-- vs "what did we take"), and this RPC returns both per day without ever
-- letting one stand in for the other.
--
-- CARD IS A RECORDED TENDER. by_method reports what the POS recorded. It is
-- NOT acquirer settlement, EMV approval or processor reconciliation, none of
-- which this platform stores.
--
-- All money is integer minor units (D-007). No floating point anywhere.

-- ---------------------------------------------------------------------------
-- app.owner_sales_series — the SECURITY DEFINER implementation.
-- ---------------------------------------------------------------------------
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

  select o.default_currency into v_currency
    from public.organizations o
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
    select oi.order_id,
           sum(oi.line_total_minor + oi.line_discount_minor) as gross_minor,
           sum(oi.line_discount_minor)                       as item_discount_minor
    from public.order_items oi
    where oi.deleted_at is null
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

comment on function app.owner_sales_series(uuid, uuid, uuid, text, date, date) is
  'DASHBOARD-OWNER-ANALYTICS-A: read-only branch-local DAILY owner sales series. '
  'Money is integer minor units. Billed excludes voided/cancelled/draft and deleted; '
  'voids are a separate bucket; collected counts COMPLETED payments only and is NOT '
  'billed. by_method reports RECORDED tenders (cash/card/bit/external) — not acquirer '
  'settlement. Custom p_start/p_end are inclusive and capped at 92 days. GUC-free auth; '
  'kitchen_staff denied. Scope-safe; no anon/service_role.';

-- ---------------------------------------------------------------------------
-- public.owner_sales_series — the thin PostgREST-reachable INVOKER wrapper.
-- ---------------------------------------------------------------------------
create or replace function public.owner_sales_series(
  p_organization_id uuid,
  p_restaurant_id   uuid default null,
  p_branch_id       uuid default null,
  p_range           text default 'today',
  p_start           date default null,
  p_end             date default null
)
  returns jsonb
  language sql
  security invoker
  set search_path = ''
as $$
  select app.owner_sales_series(p_organization_id, p_restaurant_id, p_branch_id,
                                p_range, p_start, p_end);
$$;

comment on function public.owner_sales_series(uuid, uuid, uuid, text, date, date) is
  'Thin public SECURITY INVOKER wrapper over app.owner_sales_series — the '
  'PostgREST-reachable surface. Safe columns only. Scope-safe; no anon/service_role.';

-- ---------------------------------------------------------------------------
-- ACL. `anon` is revoked EXPLICITLY on both: a revoke-from-PUBLIC does NOT
-- remove the grant hosted Supabase's ALTER DEFAULT PRIVILEGES hands to anon at
-- CREATE time. Never service_role (D-011).
-- ---------------------------------------------------------------------------
revoke all on function app.owner_sales_series(uuid, uuid, uuid, text, date, date) from public;
revoke all on function app.owner_sales_series(uuid, uuid, uuid, text, date, date) from anon;
grant execute on function app.owner_sales_series(uuid, uuid, uuid, text, date, date) to authenticated;

revoke all on function public.owner_sales_series(uuid, uuid, uuid, text, date, date) from public;
revoke all on function public.owner_sales_series(uuid, uuid, uuid, text, date, date) from anon;
grant execute on function public.owner_sales_series(uuid, uuid, uuid, text, date, date) to authenticated;
