-- ============================================================================
-- MVP (product-rescue) — app.sales_summary: GUC-free today + last-7-days sales
-- summary for the owner/manager dashboard. DECISIONS D-001/D-007/D-011/D-012/
-- D-020/D-033; RISK R-003.
-- ============================================================================
-- The dashboard needs ONE cheap call for the home screen: today's order/payment
-- counts + gross, and a zero-filled 7-day trend. The RF-075 daily views exist
-- but are security_invoker over the GUC-pinned RF-059 SELECT policies, so a real
-- JWT caller gets zero rows. This additive, forward-only migration adds a
-- GUC-free SECURITY DEFINER read: app.sales_summary + a thin public SECURITY
-- INVOKER wrapper (the RF-160 list_devices pattern). It writes nothing.
--
-- GUC-FREE authorization (mirrors RF-160 / RF-112 D-033):
--   * caller identity from auth.uid() -> app.current_app_user_id();
--   * authority via app.actor_rank_in_scope over the PASSED (org, restaurant?,
--     branch?) scope, downward-only coverage;
--   * rank >= manager(2) may read; rank 1 in-scope -> {ok:false,
--     error:'permission_denied'} (read path — no audit, matching list_devices);
--   * no covering membership -> 42501 (fail closed). No anon / service_role (D-011).
--
-- MONEY (D-007): integer minor units ONLY. amount_minor is bigint; every SUM is
--   cast back to bigint (SUM(bigint) is numeric in PostgreSQL); no float ever.
--   Nothing is recomputed — gross is a passthrough SUM of persisted completed
--   payments' amount_minor (the RF-075 'collected' definition).
--
-- DEFINITIONS:
--   * orders_count = orders CREATED on the day (created_at::date), in scope,
--     live (deleted_at IS NULL), status NOT IN ('cancelled','voided'), and on a
--     LIVE branch/restaurant (D-020).
--   * payments_count / gross_minor = COMPLETED payments on the day, live,
--     in scope, on a LIVE branch/restaurant, joined to LIVE orders. The joined
--     order must also not be cancelled/voided — RF-062 already blocks voiding an
--     order with a completed payment, so this is a defensive belt (D-012), not a
--     new rule; it keeps 'cancelled orders are excluded from sums' literally true.
--   * last_7_days = 6 prior days + today, zero-filled per day (generate_series),
--     ascending.
--   * currency_code = organizations.default_currency (per-restaurant
--     currency_override display is a client concern; not resolved here).
--
-- DAY BOUNDARIES: server-clock days (created_at::date under the database
--   timezone — UTC on Supabase). Branch-timezone business days are DEFERRED:
--   the RF-075 daily views own tz-aware bucketing; this summary is a fast
--   dashboard headline, not the reconciliation report.
--
-- FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.
-- PENDING: RISK R-003 human RLS/security sign-off before this serves real
-- tenant data (AGENTS.md).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. app.sales_summary — today + last-7-days sales in the caller's scope.
-- ---------------------------------------------------------------------------
create or replace function app.sales_summary(
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
  v_actor    uuid := app.current_app_user_id();
  v_rank     integer;
  v_currency text;
  v_agg      jsonb;
begin
  if v_actor is null then
    raise exception 'sales_summary: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'sales_summary: organization_id is required' using errcode = '42501';
  end if;

  -- authority over the PASSED scope (downward-only coverage); 0 => not a covering member.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'sales_summary: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then  -- cashier/kitchen_staff/accountant cannot read the summary
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'sales_summary');
  end if;

  select o.default_currency into v_currency
    from public.organizations o
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'sales_summary: organization not found (or deleted)' using errcode = '42501';
  end if;

  with days as (
    -- 6 prior days + today, ascending (zero-filled below).
    select generate_series(current_date - 6, current_date, interval '1 day')::date as day
  ),
  scoped_orders as (
    select o.created_at::date as day,
           count(*)::bigint   as orders_count
    from public.orders o
    join public.branches b
      on b.organization_id = o.organization_id
     and b.restaurant_id   = o.restaurant_id
     and b.id              = o.branch_id
     and b.deleted_at is null
    join public.restaurants r
      on r.organization_id = o.organization_id
     and r.id              = o.restaurant_id
     and r.deleted_at is null
    where o.organization_id = p_organization_id
      and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or o.branch_id     = p_branch_id)
      and o.deleted_at is null
      and o.status not in ('cancelled', 'voided')
      and o.created_at::date between current_date - 6 and current_date
    group by o.created_at::date
  ),
  scoped_payments as (
    select p.created_at::date                       as day,
           count(*)::bigint                         as payments_count,
           coalesce(sum(p.amount_minor), 0)::bigint as gross_minor   -- SUM(bigint) is numeric; cast back (D-007)
    from public.payments p
    join public.orders o
      on o.organization_id = p.organization_id
     and o.id              = p.order_id
     and o.deleted_at is null
     and o.status not in ('cancelled', 'voided')  -- defensive belt; RF-062 blocks this structurally
    join public.branches b
      on b.organization_id = p.organization_id
     and b.restaurant_id   = p.restaurant_id
     and b.id              = p.branch_id
     and b.deleted_at is null
    join public.restaurants r
      on r.organization_id = p.organization_id
     and r.id              = p.restaurant_id
     and r.deleted_at is null
    where p.organization_id = p_organization_id
      and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or p.branch_id     = p_branch_id)
      and p.deleted_at is null
      and p.status = 'completed'                    -- only completed payments are money taken (RF-075)
      and p.created_at::date between current_date - 6 and current_date
    group by p.created_at::date
  )
  select jsonb_build_object(
    'today', jsonb_build_object(
      'orders_count',   coalesce((select so.orders_count   from scoped_orders   so where so.day = current_date), 0),
      'payments_count', coalesce((select sp.payments_count from scoped_payments sp where sp.day = current_date), 0),
      'gross_minor',    coalesce((select sp.gross_minor    from scoped_payments sp where sp.day = current_date), 0)),
    'last_7_days', (
      select jsonb_agg(jsonb_build_object(
               'day',          d.day,
               'orders_count', coalesce(so.orders_count, 0),
               'gross_minor',  coalesce(sp.gross_minor, 0)) order by d.day)
      from days d
      left join scoped_orders   so on so.day = d.day
      left join scoped_payments sp on sp.day = d.day))
  into v_agg;

  return jsonb_build_object('ok', true, 'entity', 'sales_summary', 'currency_code', v_currency) || v_agg;
end;
$$;

comment on function app.sales_summary(uuid, uuid, uuid) is
  'MVP (D-007/D-011/D-020/D-033): GUC-free today + last-7-days sales summary for the owner/manager dashboard. Authorized via app.actor_rank_in_scope over the PASSED (org, restaurant?, branch?) scope, rank >= manager (rank 1 in-scope -> permission_denied; no covering membership -> 42501). orders_count = live non-cancelled/voided orders created on the day; gross_minor/payments_count = completed payments joined to live non-cancelled/voided orders; all money integer minor (bigint; SUM cast back to bigint, never float). Rows are filtered through LIVE branches/restaurants (D-020). last_7_days is zero-filled ascending via generate_series. Server-clock (UTC) day boundaries; branch-timezone business days DEFERRED (RF-075 owns tz-aware bucketing). currency_code = organizations.default_currency. Read-only; scope-safe (no GUC trusted).';

-- ---------------------------------------------------------------------------
-- 2. Thin public SECURITY INVOKER wrapper (RF-064 / RF-109 / RF-160 pattern).
-- ---------------------------------------------------------------------------
create or replace function public.sales_summary(
  p_organization_id uuid, p_restaurant_id uuid default null, p_branch_id uuid default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.sales_summary(p_organization_id, p_restaurant_id, p_branch_id); $$;

-- ---------------------------------------------------------------------------
-- 3. Grants: authenticated only (never anon / service_role; D-011).
-- ---------------------------------------------------------------------------
revoke all on function app.sales_summary(uuid, uuid, uuid)    from public;
grant execute on function app.sales_summary(uuid, uuid, uuid) to authenticated;
revoke all on function public.sales_summary(uuid, uuid, uuid)    from public;
grant execute on function public.sales_summary(uuid, uuid, uuid) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists public.sales_summary(uuid, uuid, uuid);
--   drop function if exists app.sales_summary(uuid, uuid, uuid);
-- ============================================================================
