-- ============================================================================
-- ADMIN-126C (core remediation) — SUPPORT-SESSION SCOPE CONTAINMENT + STAFF-PII
-- REDACTION. Forward-only fix for the two reviewer-CONFIRMED defects in the
-- applied 20260903090001 support-session read path. NOT YET APPLIED HOSTED.
--
-- DEFECT 1 — RESTAURANT-SCOPE WIDENING.
--   app.platform_support_can_read_scope accepted a NULL request restaurant
--   ('or p_restaurant_id is null'), so a session scoped to ONE restaurant
--   could read ORG-WIDE aggregates (sales_summary/owner_report_range with
--   NULL scope) that include every sibling restaurant's revenue.
--   THE CONTRACT (derived from the session model, now explicit):
--     * a session names ONE organization; nothing outside it, ever;
--     * an ORGANIZATION-scoped session (target_restaurant_id IS NULL) may read
--       org-level aggregates and any restaurant of that organization — that is
--       the Subscriber-Detail intent;
--     * a RESTAURANT-scoped session may read ONLY that restaurant; a NULL
--       restaurant request DENIES (never widens) — matching the strictly
--       downward-only semantics of the membership rank helper;
--     * cross-restaurant and cross-org requests fail closed (42501 via the
--       callers' existing gates).
--
-- DEFECT 2 — STAFF-NAME PII THROUGH APPROVED READS.
--   owner_daily_report and owner_report_range emit shift rows carrying
--   employee display names (opened_by_name / closed_by_name), while the
--   support policy withholds staff identities (list_staff, owner_audit_events
--   are DENIED for exactly that reason). Fix is SERVER-SIDE: when the caller
--   is SUPPORT-ONLY (live support session AND zero tenant membership rank),
--   the result envelope passes through app.platform_support_redact_staff_names
--   which nulls exactly those two keys everywhere in the document. A caller
--   with a real membership (rank > 0) is entitled and sees names unchanged.
--
-- MECHANICS: the two report bodies below are PROGRAMMATIC EXTRACTIONS of the
-- applied 20260903090001 text with ONLY the final return patched (the
-- generator asserts patched.replace(new,old) == original). No aggregation,
-- window, currency or authorization line was retyped.
--
-- READ-ONLY posture unchanged: nothing here touches a write path; CREATE OR
-- REPLACE preserves the existing ACLs and they are re-stated explicitly.
-- ============================================================================

-- ---- 1. Scope guard: strict restaurant containment --------------------------
create or replace function app.platform_support_can_read_scope(
  p_organization_id uuid,
  p_restaurant_id   uuid default null,
  p_branch_id       uuid default null
)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select exists (
    select 1
    from public.platform_support_sessions s
    where s.id = app.current_support_session()
      -- the session names ONE organization and grants nothing outside it
      and s.target_organization_id = p_organization_id
      and p_organization_id is not null
      -- ADMIN-126C: a restaurant-scoped session reaches ONLY that restaurant.
      -- A NULL request no longer widens it to org-level aggregates; only an
      -- organization-scoped session (target_restaurant_id IS NULL) may read
      -- org-wide.
      and (s.target_restaurant_id is null
           or (p_restaurant_id is not null
               and s.target_restaurant_id = p_restaurant_id))
  )
$$;

comment on function app.platform_support_can_read_scope(uuid, uuid, uuid) is
  'ADMIN-126B/126C: may the caller READ this scope under a live support '
  'session? Org-scoped sessions read the whole organization; restaurant-scoped '
  'sessions read only that restaurant and a NULL restaurant request DENIES '
  '(126C: no widening). Never returns a rank; no write meaning anywhere.';

-- ---- 2. Staff-name redaction helper (internal only) -------------------------
create or replace function app.platform_support_redact_staff_names(p_doc jsonb)
  returns jsonb
  language plpgsql
  immutable
  set search_path = ''
as $function$
begin
  return case jsonb_typeof(p_doc)
    when 'object' then coalesce(
      (select jsonb_object_agg(
                e.key,
                case when e.key in ('opened_by_name', 'closed_by_name')
                     then 'null'::jsonb
                     else app.platform_support_redact_staff_names(e.value) end)
         from jsonb_each(p_doc) e),
      '{}'::jsonb)
    when 'array' then coalesce(
      (select jsonb_agg(app.platform_support_redact_staff_names(t.elem)
                        order by t.ord)
         from jsonb_array_elements(p_doc) with ordinality t(elem, ord)),
      '[]'::jsonb)
    else p_doc
  end;
end;
$function$;

comment on function app.platform_support_redact_staff_names(jsonb) is
  'ADMIN-126C internal: nulls opened_by_name/closed_by_name everywhere in a '
  'report envelope for SUPPORT-ONLY readers. Not granted to any client role.';

revoke all on function app.platform_support_redact_staff_names(jsonb) from public;
revoke all on function app.platform_support_redact_staff_names(jsonb) from anon;
revoke all on function app.platform_support_redact_staff_names(jsonb) from authenticated;

-- ---- 3. owner_daily_report: support-only staff-name redaction ---------------
CREATE OR REPLACE FUNCTION app.owner_daily_report(p_organization_id uuid, p_restaurant_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  v_rank := app.actor_read_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_daily_report: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  -- FINANCIAL-READ allowlist (GUC-free, app.can_read_financials-STYLE): the caller
  -- must hold an ACTIVE membership covering the PASSED scope (downward-only,
  -- mirroring app.actor_rank_in_scope) whose role is a financial-read role —
  -- cashier / manager / restaurant_owner / org_owner / accountant; kitchen_staff
  -- is DENIED.
  -- ADMIN-126B: ...or a live, scoped, read-only platform support session. The
  -- tenant allowlist below is untouched; this only adds a second way in for an
  -- actor who holds no membership at all.
  if not app.platform_support_can_read_scope(p_organization_id, p_restaurant_id, p_branch_id)
     and not exists (
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

  v_result := jsonb_build_object(
    'ok', true,
    'entity', 'owner_daily_report',
    'currency_code', v_currency,
    'business_date', v_today
  ) || v_result;
  -- ADMIN-126C: a SUPPORT-ONLY reader (live support session and ZERO tenant
  -- membership rank) never receives staff identity fields. Members and
  -- owners see the exact pre-126C payload: the redaction fires only when
  -- access is purely support-derived.
  if app.current_support_session() is not null
     and app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id) = 0 then
    v_result := app.platform_support_redact_staff_names(v_result);
  end if;
  return v_result;
end;
$function$;

-- ---- 4. owner_report_range: support-only staff-name redaction ---------------
CREATE OR REPLACE FUNCTION app.owner_report_range(p_organization_id uuid, p_restaurant_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid, p_range text DEFAULT 'today'::text, p_start date DEFAULT NULL::date, p_end date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if (coalesce(current_setting('app.platform_report_read', true), '') = 'on'
      and app.is_platform_admin()
      and app.current_auth_assurance_level() = 'aal2')
     -- ADMIN-126B: or a live, scoped, read-only support session, which is how
     -- the tenant Dashboard renders this same report during support.
     or app.platform_support_can_read_scope(p_organization_id, p_restaurant_id, p_branch_id) then
    null;  -- audited platform read: the tenant membership gate does not apply
  else
    -- authority over the PASSED scope (downward-only coverage); 0 => not a covering member.
    v_rank := app.actor_read_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
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

  v_result := jsonb_build_object(
    'ok', true,
    'entity', 'owner_report_range',
    'currency_code', v_currency,
    'range', case when v_custom then 'custom' else p_range end
  ) || v_result;
  -- ADMIN-126C: a SUPPORT-ONLY reader (live support session and ZERO tenant
  -- membership rank) never receives staff identity fields. Members and
  -- owners see the exact pre-126C payload: the redaction fires only when
  -- access is purely support-derived.
  if app.current_support_session() is not null
     and app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id) = 0 then
    v_result := app.platform_support_redact_staff_names(v_result);
  end if;
  return v_result;
end;
$function$;

-- ---- 5. Grants (re-stated; CREATE OR REPLACE preserved them) ----------------
revoke all on function app.owner_daily_report(uuid, uuid, uuid) from public;
revoke all on function app.owner_daily_report(uuid, uuid, uuid) from anon;
grant execute on function app.owner_daily_report(uuid, uuid, uuid) to authenticated;
revoke all on function app.owner_report_range(uuid, uuid, uuid, text, date, date) from public;
revoke all on function app.owner_report_range(uuid, uuid, uuid, text, date, date) from anon;
grant execute on function app.owner_report_range(uuid, uuid, uuid, text, date, date) to authenticated;
revoke all on function app.platform_support_can_read_scope(uuid, uuid, uuid) from public;
revoke all on function app.platform_support_can_read_scope(uuid, uuid, uuid) from anon;
revoke all on function app.platform_support_can_read_scope(uuid, uuid, uuid) from authenticated;

-- DOWN (manual, documented only — forward-only per D-016):
--   restore app.platform_support_can_read_scope, app.owner_daily_report and
--   app.owner_report_range from 20260903090001; drop function
--   app.platform_support_redact_staff_names(jsonb).
