-- DASHBOARD-VISUAL-RANGE-REFRESH-S0 (SERVER) — 60/90/custom windows everywhere,
-- plus a real TOP-SELLING-ITEMS aggregate.
--
-- ADDITIVE AND READ-ONLY. This migration creates and replaces functions and
-- reissues their grants. It creates no table, column, index, trigger, writer,
-- RLS policy, backfill or seed, and no function below writes a single row.
--
-- WHY A SERVER SLICE AT ALL. The Dashboard wants three things the database
-- cannot currently answer:
--
--   1. "What sells best?" — there is no top-items RPC. Without one the only
--      client-side route is downloading raw orders and their lines and rolling
--      them up in a browser, which is the exact failure owner_sales_series was
--      created to prevent: unbounded transfer, and a client re-deriving "which
--      day / which item" outside the branch's own truth.
--   2. 60 / 90 day windows — owner_report_range and owner_order_history know
--      only today/yesterday/last7/last30.
--   3. A custom From/To window — owner_sales_series has one; the range report
--      and the order history do not.
--
-- FOUR FUNCTIONS, ONE VOCABULARY. After this migration every owner analytics
-- surface accepts the SAME six preset tokens (today, yesterday, last7, last30,
-- last60, last90) and the SAME custom (p_start, p_end) pair, with the same
-- validation and the same branch-local arithmetic. That symmetry is the point:
-- a KPI card, a chart, a top-items list and an order list rendered from one
-- picker must not be able to disagree about which days they cover.
--
--   * PRESETS are BRANCH-LOCAL and RELATIVE. lastN = N branch-local calendar
--     days ending on that branch's own local today (inclusive). In a
--     multi-timezone org each branch resolves its own window; a single
--     org-wide "today" would move revenue between days for one of them.
--   * CUSTOM is FIXED and ABSOLUTE. p_start/p_end are calendar dates, applied
--     inclusively and identically to every branch in scope. A date the owner
--     typed is not relative to anything.
--
-- CUSTOM VALIDATION IS IDENTICAL IN ALL FOUR, and is the block
-- owner_sales_series already shipped:
--     both-or-neither         -> 22023   (a half-open window has no defensible
--                                         end and becomes an unbounded scan)
--     p_end < p_start         -> 22023
--     (p_end - p_start) > 91  -> 22023   (inclusive, so 92 days is the largest
--                                         accepted window: a full quarter)
-- An invalid preset token is 22023 as well, never a silent fall back to today.
-- Supplying a custom pair activates custom and the preset token is not read —
-- again matching owner_sales_series, so the four agree on precedence too.
--
-- WHY DROP + RECREATE for owner_report_range and owner_order_history: both gain
-- parameters, so CREATE OR REPLACE cannot be used (Postgres would keep the old
-- signature alongside the new one, leaving two functions of the same name — an
-- ambiguity PostgREST resolves by the argument set, i.e. silently, and a place
-- for old and new semantics to coexist). The old signatures are dropped so
-- exactly one definition of each name survives. Existing callers are unaffected:
-- every added parameter has a default, and the ones they already pass keep their
-- position, name and meaning.
--
-- ACL. A DROP takes the grants with it, so every recreated function restates
-- them. `anon` is revoked EXPLICITLY and not merely via PUBLIC: hosted
-- Supabase's ALTER DEFAULT PRIVILEGES hands anon an execute grant at CREATE
-- time, which a revoke-from-PUBLIC does not remove. service_role is never
-- granted (D-011). This also closes a real gap — the 2026-07-06 and 2026-07-10
-- migrations revoked only PUBLIC on these four wrappers.
--
-- All money is integer minor units (D-007). No floating point anywhere: every
-- SUM is cast to bigint, no ratio, average or percentage is computed here.

-- ===========================================================================
-- 1. app.owner_top_items — NEW. Top-selling menu items for a window.
-- ===========================================================================
--
-- IDENTITY IS menu_item_id, NOT THE NAME. Aggregating by name would merge two
-- genuinely different products that happen to share a label, and would split
-- one product across a rename — "Falafel" sold before the rename and "Falafel
-- Wrap" after it would appear as two half-sized rows for the same item. The
-- stable id is the only thing that survives editing the menu.
--
-- THE NAME IS A HISTORICAL SNAPSHOT, NOT A CATALOG LOOKUP. Display uses the
-- most recently CAPTURED menu_item_name_snapshot among the rows in the window,
-- chosen deterministically (newest order_items.created_at, then id). It does
-- NOT join public.menu_items. Two consequences, both deliberate:
--   * a menu item DELETED after the fact still reports the name it was sold
--     under, instead of vanishing or rendering as a bare uuid;
--   * a menu item RENAMED after the fact reports the name captured at order
--     time — the same D-008 snapshot rule the receipt and the order detail
--     already obey. A "top items" list that silently adopted today's catalog
--     names would be describing history with the present's vocabulary.
--
-- REVENUE IS ITEM-LEVEL NET. revenue_minor = Σ order_items.line_total_minor,
-- which is already net of that line's own discount. ORDER-level discounts are
-- deliberately NOT allocated across items: the schema stores no such split, and
-- inventing a proportional one would require rounding a share per line, which
-- is a fabricated number and a float in disguise. This makes the aggregate
-- exactly reconcilable — Σ revenue_minor over all items of an order equals that
-- order's subtotal_minor, by the same rule apply_discount uses when it re-rolls
-- the order up.
--
-- WHICH ROWS COUNT: billed orders only (deleted_at is null, status not in
-- voided/cancelled/draft — the same truth set as owner_report_range and
-- owner_sales_series), and within them only live lines (deleted_at is null,
-- status not in voided/cancelled). That item filter is the canonical one the
-- writers themselves use when recomputing orders.subtotal_minor, so a voided
-- line cannot inflate a product's ranking after it was taken off the bill.
--
-- TZ-LESS BRANCHES ARE EXCLUDED, as in every owner financial AGGREGATE
-- (owner_report_range, owner_sales_series): without a zone there is no
-- defensible day to bucket into. owner_order_history's UTC fallback is
-- deliberately not copied — that one is a LIST, where dropping a row would hide
-- an order; here a branch simply contributes no facts.
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

  select o.default_currency into v_currency
    from public.organizations o
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

comment on function app.owner_top_items(uuid, uuid, uuid, text, date, date, integer) is
  'DASHBOARD-VISUAL-RANGE-REFRESH-S0 (read-only; D-007/D-008/D-011/D-020): top-selling '
  'menu items for a branch-local window. Grouped by the STABLE menu_item_id, never by '
  'name; the display name is the most recently captured menu_item_name_snapshot in the '
  'window (never a live menu_items lookup), so a renamed or deleted product still reports '
  'the name it was sold under. revenue_minor = SUM(order_items.line_total_minor), i.e. net '
  'of line discounts; ORDER-level discounts are deliberately not allocated across lines. '
  'Billed orders only (voided/cancelled/draft/deleted excluded) and live lines only. '
  'p_range in today/yesterday/last7/last30/last60/last90, or a custom inclusive p_start/'
  'p_end capped at 92 days (22023 on invalid input). Ranking is revenue desc with a TOTAL '
  'deterministic tie-break. p_limit clamped 1..50. Integer minor units, no float. GUC-free '
  'auth; kitchen_staff denied. Scope-safe; no anon/service_role.';

-- ---------------------------------------------------------------------------
-- public.owner_top_items — the thin PostgREST-reachable INVOKER wrapper.
-- ---------------------------------------------------------------------------
create or replace function public.owner_top_items(
  p_organization_id uuid,
  p_restaurant_id   uuid    default null,
  p_branch_id       uuid    default null,
  p_range           text    default 'today',
  p_start           date    default null,
  p_end             date    default null,
  p_limit           integer default 10
)
  returns jsonb
  language sql
  security invoker
  set search_path = ''
as $$
  select app.owner_top_items(p_organization_id, p_restaurant_id, p_branch_id,
                             p_range, p_start, p_end, p_limit);
$$;

comment on function public.owner_top_items(uuid, uuid, uuid, text, date, date, integer) is
  'Thin public SECURITY INVOKER wrapper over app.owner_top_items — the '
  'PostgREST-reachable surface. Safe columns only. Scope-safe; no anon/service_role.';

-- ===========================================================================
-- 2. app.owner_report_range — WIDENED with last60 / last90 / custom.
-- ===========================================================================
--
-- The body below is the CURRENT definition (20260811090000) reproduced verbatim
-- with only these changes, so a reviewer can diff it:
--
--   * p_start / p_end APPENDED (defaults null). No existing parameter moved,
--     was renamed, or changed meaning.
--   * the shared custom-window validation block, ahead of the preset CASE.
--   * last60 / last90 added to the preset CASE.
--   * branch_tz computes cur_start/cur_end from the custom pair when one was
--     given, and the PRIOR window is now expressed as (cur_start - 1) and
--     (cur_start - v_span). For every preset this is ARITHMETICALLY IDENTICAL
--     to the previous formula — prev_end was local_today - end_offset - span,
--     which is exactly cur_start - 1 — so no existing range moved by a day.
--   * the envelope reports range='custom' when a custom pair was supplied,
--     matching owner_sales_series.
--
-- THE COMPARISON WINDOW FOR CUSTOM is the IMMEDIATELY PRECEDING window of the
-- SAME LENGTH: [start - span, start - 1] where span = (end - start + 1). It is
-- fixed, like the window it follows, and never re-derived from local_today. A
-- 14-day custom window therefore compares against the 14 days before it, which
-- is the only reading of "previous period" that keeps the two lengths equal.
--
-- HOURLY still fills 24 buckets for SINGLE-DAY windows only. A one-day custom
-- window (p_start = p_end) has span 1 and so now produces hourly data, which is
-- the consistent answer: it is a single day, whichever way it was requested.

-- The OLD 4-argument signatures are dropped so exactly ONE owner_report_range
-- survives. Leaving them would create an overload pair: PostgREST picks between
-- overloads by the argument set it was given, so a caller omitting p_start/p_end
-- would silently reach the OLD body — which knows nothing of last60/last90 — and
-- two definitions of the same report would coexist. Wrapper first, then the
-- implementation it calls.
drop function if exists public.owner_report_range(uuid, uuid, uuid, text);
drop function if exists app.owner_report_range(uuid, uuid, uuid, text);

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

comment on function app.owner_report_range(uuid, uuid, uuid, text, date, date) is
  'RF-REPORT-004 + DASHBOARD-VISUAL-RANGE-REFRESH-S0 (read-only; D-007/D-011/D-020/D-028): '
  'GUC-free range owner report for the Dashboard Overview. Authorization as owner_daily_report '
  '(app.actor_rank_in_scope over the PASSED scope, 0 -> 42501; GUC-free financial-read allowlist '
  'cashier/manager/restaurant_owner/org_owner/accountant; kitchen_staff -> permission_denied). '
  'p_range in today/yesterday/last7/last30/last60/last90, or a CUSTOM inclusive p_start/p_end '
  '(both-or-neither, From <= To, max 92 days; 22023 on invalid input) which reports range=custom. '
  'Preset windows are computed PER BRANCH in the branch-local zone (RF-075); a custom window is '
  'the same fixed calendar dates for every branch. The comparison window is always the '
  'IMMEDIATELY PRECEDING window of equal length. Returns current + comparison (billed/collected), '
  'hourly (24 branch-local buckets for single-day windows, including a one-day custom window; '
  'empty for multi-day), and shift_cash. All money integer minor (bigint; never float). LIVE '
  'deleted_at IS NULL filters (D-020). Read-only; scope-safe; no anon/service_role (D-011).';

-- ---------------------------------------------------------------------------
-- public.owner_report_range — thin INVOKER wrapper, widened to match.
-- ---------------------------------------------------------------------------
create or replace function public.owner_report_range(
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
  select app.owner_report_range(p_organization_id, p_restaurant_id, p_branch_id,
                                p_range, p_start, p_end);
$$;

comment on function public.owner_report_range(uuid, uuid, uuid, text, date, date) is
  'Thin public SECURITY INVOKER wrapper over app.owner_report_range — the '
  'PostgREST-reachable surface. Scope-safe; no anon/service_role.';

-- ===========================================================================
-- 3. app.owner_order_history — WIDENED with last60 / last90 / custom.
-- ===========================================================================
--
-- The body below is the CURRENT definition (20260811090000) reproduced verbatim
-- with only these changes:
--
--   * p_start / p_end APPENDED AFTER p_cursor (defaults null). Appending rather
--     than inserting them next to p_range keeps every existing parameter at its
--     current position, so positional callers and the PostgREST clients that
--     name only what they use are both unaffected.
--   * the shared custom-window validation block.
--   * last60 / last90 added to the preset CASE.
--   * branch_tz uses the custom pair when one was given.
--   * the envelope reports range='custom' for a custom window.
--
-- EXPLICITLY UNCHANGED, because this is a LIST and not an aggregate: newest-
-- first ordering (created_at desc, id desc), the keyset cursor and its 22023
-- validation, the p_limit 1..100 clamp, the payment-filter vocabulary and its
-- validation, the search predicate, and the UTC fallback for a tz-less branch
-- (a report may exclude such a branch from a total; a list must never silently
-- drop somebody's order). Pagination therefore behaves identically inside a
-- custom window: the window only decides which rows are candidates.
drop function if exists public.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text);
drop function if exists app.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text);

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
  p_cursor          text  default null,    -- keyset cursor "<created_at>|<id>"
  p_start           date  default null,
  p_end             date  default null
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
  v_custom     boolean := false;
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

  -- Window selection — the shared block (see the header).
  if p_start is not null or p_end is not null then
    if p_start is null or p_end is null then
      raise exception 'owner_order_history: p_start and p_end must be supplied together'
        using errcode = '22023';
    end if;
    if p_end < p_start then
      raise exception 'owner_order_history: p_end precedes p_start'
        using errcode = '22023';
    end if;
    if (p_end - p_start) > 91 then
      raise exception 'owner_order_history: window exceeds 92 days'
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
      else raise exception 'owner_order_history: unknown range %', p_range using errcode = '22023';
    end case;
  end if;

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
    -- Presets are branch-local and relative; a custom pair is the same fixed
    -- calendar dates for every branch.
    select bt.organization_id, bt.restaurant_id, bt.branch_id, bt.zone,
           case when v_custom then p_end
                else (lt.local_today - v_end_offset) end                as cur_end,
           case when v_custom then p_start
                else (lt.local_today - v_end_offset - (v_span - 1)) end as cur_start
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
    'range', case when v_custom then 'custom' else p_range end,
    'limit', v_limit
  ) || v_result;
end;
$$;

comment on function app.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text, date, date) is
  'ORDERS-HISTORY-001 + DASHBOARD-VISUAL-RANGE-REFRESH-S0 (read-only; D-007/D-008/D-011/D-020): '
  'GUC-free paginated order-history LIST for the owner/manager Dashboard. Same authorization as '
  'owner_report_range (app.actor_rank_in_scope over the PASSED scope, 0 -> 42501; GUC-free '
  'financial-read allowlist; kitchen_staff -> permission_denied). Branch-local date window: '
  'p_range in today/yesterday/last7/last30/last60/last90, or a CUSTOM inclusive p_start/p_end '
  '(both-or-neither, From <= To, max 92 days; 22023 on invalid input) reported as range=custom. '
  'A tz-less branch falls back to UTC rather than dropping its orders. Optional filters: '
  'p_status, p_order_type, p_payment (paid/unpaid/cash/card/bit/external, VALIDATED -> 22023), '
  'p_search (order code #hex / customer / table / receipt). Keyset pagination '
  '("<created_at>|<id>", newest first, p_limit clamped 1..100, has_more/next_cursor). Money '
  'integer minor, read from stored snapshots (never recomputed). Scope-safe; no anon/service_role.';

-- ---------------------------------------------------------------------------
-- public.owner_order_history — thin INVOKER wrapper, widened to match.
-- ---------------------------------------------------------------------------
create or replace function public.owner_order_history(
  p_organization_id uuid,
  p_restaurant_id   uuid  default null,
  p_branch_id       uuid  default null,
  p_range           text  default 'today',
  p_search          text  default null,
  p_status          text  default null,
  p_order_type      text  default null,
  p_payment         text  default null,
  p_limit           int   default 25,
  p_cursor          text  default null,
  p_start           date  default null,
  p_end             date  default null
)
  returns jsonb
  language sql
  security invoker
  set search_path = ''
as $$
  select app.owner_order_history(
    p_organization_id, p_restaurant_id, p_branch_id, p_range, p_search,
    p_status, p_order_type, p_payment, p_limit, p_cursor, p_start, p_end);
$$;

comment on function public.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text, date, date) is
  'Thin public SECURITY INVOKER wrapper over app.owner_order_history — the '
  'PostgREST-reachable surface. Scope-safe; no anon/service_role.';

-- ===========================================================================
-- 4. app.owner_sales_series — last60 / last90 as FIRST-CLASS preset tokens.
-- ===========================================================================
--
-- Signature UNCHANGED, so this is a CREATE OR REPLACE and the existing ACL
-- survives; it is restated below anyway, under the rider.
--
-- The only change is two CASE arms. Everything else is the 20260810090000 body
-- verbatim, including the custom-window block, which is where 60/90 could
-- otherwise have been faked from the client.
--
-- WHY NOT LET THE CLIENT SEND last90 AS A CUSTOM PAIR: a client computing
-- (today - 89, today) has to decide what "today" is, and its only honest answer
-- is the DEVICE's today. For a single-branch org in the device's own zone that
-- is usually right; for an org spanning zones it is wrong for every branch but
-- one, and the chart would disagree with the KPI card above it — which resolves
-- "today" per branch, on the server. A preset token keeps that resolution where
-- the branch's timezone actually lives.
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
  'DASHBOARD-OWNER-ANALYTICS-A + VISUAL-RANGE-REFRESH-S0: read-only branch-local DAILY owner '
  'sales series. Money is integer minor units. Billed excludes voided/cancelled/draft and deleted; '
  'voids are a separate bucket; collected counts COMPLETED payments only and is NOT '
  'billed. by_method reports RECORDED tenders (cash/card/bit/external) — not acquirer '
  'settlement. p_range in today/yesterday/last7/last30/last60/last90; custom p_start/p_end are '
  'inclusive and capped at 92 days. GUC-free auth; kitchen_staff denied. Scope-safe; no '
  'anon/service_role.';

-- ===========================================================================
-- 5. ACL RIDER — every function this migration touched.
-- ===========================================================================
--
-- A DROP took the old grants with it, so the recreated functions MUST have
-- theirs restated; the CREATE OR REPLACE ones keep theirs, and are restated
-- anyway so this block is the single readable answer to "who can call these".
--
-- `anon` is revoked EXPLICITLY on every one. Revoking from PUBLIC is NOT
-- sufficient on hosted Supabase, where ALTER DEFAULT PRIVILEGES grants anon
-- EXECUTE on functions at CREATE time — a direct grant that a PUBLIC revoke
-- leaves untouched. The 2026-07-06 / 2026-07-10 migrations revoked only PUBLIC
-- on owner_report_range and owner_order_history; this closes that gap for the
-- four functions in scope here.
--
-- service_role is never granted (D-011). It is not revoked either: it is a
-- BYPASSRLS superuser-adjacent role whose access does not come from these
-- grants, and pretending otherwise would be security theatre.
--
-- SCOPE NOTE: app.owner_daily_report, app.owner_order_detail and the other
-- older owner wrappers share the PUBLIC-only revoke pattern. They are NOT
-- touched here — hardening them is unrelated to any signature this migration
-- changes, and is reported separately rather than smuggled into this slice.

revoke all on function app.owner_top_items(uuid, uuid, uuid, text, date, date, integer) from public;
revoke all on function app.owner_top_items(uuid, uuid, uuid, text, date, date, integer) from anon;
grant execute on function app.owner_top_items(uuid, uuid, uuid, text, date, date, integer) to authenticated;

revoke all on function public.owner_top_items(uuid, uuid, uuid, text, date, date, integer) from public;
revoke all on function public.owner_top_items(uuid, uuid, uuid, text, date, date, integer) from anon;
grant execute on function public.owner_top_items(uuid, uuid, uuid, text, date, date, integer) to authenticated;

revoke all on function app.owner_report_range(uuid, uuid, uuid, text, date, date) from public;
revoke all on function app.owner_report_range(uuid, uuid, uuid, text, date, date) from anon;
grant execute on function app.owner_report_range(uuid, uuid, uuid, text, date, date) to authenticated;

revoke all on function public.owner_report_range(uuid, uuid, uuid, text, date, date) from public;
revoke all on function public.owner_report_range(uuid, uuid, uuid, text, date, date) from anon;
grant execute on function public.owner_report_range(uuid, uuid, uuid, text, date, date) to authenticated;

revoke all on function app.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text, date, date) from public;
revoke all on function app.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text, date, date) from anon;
grant execute on function app.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text, date, date) to authenticated;

revoke all on function public.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text, date, date) from public;
revoke all on function public.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text, date, date) from anon;
grant execute on function public.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text, date, date) to authenticated;

revoke all on function app.owner_sales_series(uuid, uuid, uuid, text, date, date) from public;
revoke all on function app.owner_sales_series(uuid, uuid, uuid, text, date, date) from anon;
grant execute on function app.owner_sales_series(uuid, uuid, uuid, text, date, date) to authenticated;

revoke all on function public.owner_sales_series(uuid, uuid, uuid, text, date, date) from public;
revoke all on function public.owner_sales_series(uuid, uuid, uuid, text, date, date) from anon;
grant execute on function public.owner_sales_series(uuid, uuid, uuid, text, date, date) to authenticated;

-- ============================================================================
-- HOSTED APPLY NOTE (not performed by this slice): dropping and recreating
-- PostgREST-reachable functions changes the exposed RPC surface, so a hosted
-- apply must be followed by a schema-cache reload before the new parameters are
-- callable over HTTP.
--
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists public.owner_top_items(uuid, uuid, uuid, text, date, date, integer);
--   drop function if exists app.owner_top_items(uuid, uuid, uuid, text, date, date, integer);
--   -- and re-apply 20260706110000 / 20260710090000 / 20260811090000 to restore
--   -- the narrower owner_report_range / owner_order_history signatures.
-- ============================================================================
