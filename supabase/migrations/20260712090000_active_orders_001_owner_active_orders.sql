-- ============================================================================
-- ACTIVE-ORDERS-001 — Dashboard read-only ACTIVE-ORDER operations centre.
-- ONE new, READ-ONLY, ADDITIVE function (+ its thin public wrapper):
--   * app.owner_active_orders — every order that is still OPERATIONALLY ACTIVE
--     in the caller's scope, oldest-first (FIFO), with a scope-wide summary.
-- Nothing else changes: submit_order / update_order_status / record_payment /
-- void_order / sync_pull / owner_order_history / owner_order_detail / the report
-- RPCs are UNTOUCHED. No table, column, CHECK, RLS policy, trigger or order row
-- is altered. This migration adds NO write path of any kind.
-- DECISIONS D-001/D-007/D-008/D-011/D-012/D-018/D-020/D-025; RISK R-003.
-- ----------------------------------------------------------------------------
-- WHY A NEW FUNCTION (app.owner_order_history cannot serve this):
--   1. `p_status` is a SINGLE-VALUE equality filter — the active set is FIVE
--      statuses and cannot be expressed in one call.
--   2. It MANDATES a branch-local CALENDAR-DAY window (p_range today/yesterday/
--      last7/last30), so an order still `preparing` after midnight silently
--      disappears from "today". An operations board must never lose a live order.
--   3. Its ordering is hard-coded NEWEST-first; an ops board is FIFO (the
--      project's canonical rule — KDS-FIFO-001).
--   4. It returns only a pre-formatted, zone-less local time string, so elapsed
--      ("open for N minutes") cannot be computed by the client.
--
-- CANONICAL STATE MODEL (NOT inferred from labels — this is the one already in
-- the tree; ACTIVE-ORDERS-001 introduces NO second taxonomy):
--   ACTIVE   = submitted, accepted, preparing, ready, served
--   TERMINAL = completed, cancelled, voided
-- Proven three independent ways in the shipped SQL:
--   * app.update_order_status legal FROM set (20260702130000_mvp_order_status_sync.sql)
--   * app.void_order legal SOURCE gate      (20260710110000_staff_cashier_permissions_001…)
--   * app.record_payment legal SOURCE gate  (20260704150000_rf117_tax_and_noncash_tenders.sql)
-- and matching docs/STATE_MACHINES.md + DECISION D-018 + OrderStatus.isTerminal.
-- `draft` is a LOCAL-ONLY pre-state (RF-032) — never written server-side — so it
-- is not part of the active set. `deleted_at is null` throughout (D-020).
--
-- PAYMENT IS A SEPARATE AXIS (D-025): app.record_payment NEVER writes
-- orders.status, and there is no paid column — "paid" is derived as "a payments
-- row with status='completed' exists". A PAID order therefore stays ACTIVE, and
-- an UNPAID order can be `served`. Payment state is reported alongside, never
-- folded into, the operational status.
--
-- NO PROMISED/DUE TIME EXISTS anywhere in the schema (no promised_at / due_at /
-- eta / sla / target on orders, order_items, branches or organizations;
-- menu_items.prep_minutes is menu CONFIG and is never snapshotted onto an order).
-- This function therefore returns ELAPSED-time inputs only — `created_at_utc`
-- (an absolute instant) + the resolved branch `timezone` — and NEVER a "late" or
-- "overdue" flag. Lateness would be fabricated. See §4 of the ticket.
--
-- The Dashboard is a JWT (auth.uid()) caller and the orders/payments RLS SELECT
-- policies are GUC-bound, so a direct table read returns ZERO rows. As with
-- owner_order_history / the owner_* reports this is therefore a GUC-free
-- SECURITY DEFINER function in `app` with a thin public SECURITY INVOKER
-- wrapper, re-implementing tenant isolation with EXPLICIT organization_id /
-- scope / deleted_at filters (SECURITY DEFINER bypasses RLS, so the WHERE
-- clauses ARE the isolation boundary — RISK R-003).
--
-- AUTHORIZATION — copied VERBATIM from app.owner_order_history:
--   identity from auth.uid() -> app.current_app_user_id() (null -> 42501);
--   app.actor_rank_in_scope over the PASSED scope (0 -> 42501, downward-only);
--   GUC-free can_read_financials-STYLE allowlist (cashier / manager /
--   restaurant_owner / org_owner / accountant; kitchen_staff DENIED via
--   {ok:false,error:'permission_denied'}).
-- Every filter token is ENUM-VALIDATED (a bad token is 22023, never a silent
-- empty result) and NOTHING is interpolated into SQL. Page size is CAPPED.
-- No anon / service_role (D-011).
--
-- FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.
-- PENDING: RISK R-003 human RLS/security sign-off before this serves real tenant
-- data. NOT applied to hosted DB by this migration.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. app.owner_active_orders — the FIFO active-order board + scope summary.
-- ---------------------------------------------------------------------------
create or replace function app.owner_active_orders(
  p_organization_id uuid,
  p_restaurant_id   uuid default null,
  p_branch_id       uuid default null,
  p_status          text default null,   -- one ACTIVE status, or null = all
  p_order_type      text default null,   -- 'dine_in' | 'takeaway'
  p_payment         text default null,   -- 'paid' | 'unpaid' | 'cash'
  p_search          text default null,   -- order code / customer / table / receipt
  p_limit           int  default 100
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
  v_limit    integer := least(greatest(coalesce(p_limit, 100), 1), 200);
  v_search   text    := nullif(btrim(coalesce(p_search, '')), '');
  -- The canonical OPERATIONALLY ACTIVE set (see the header). Terminal states
  -- (completed / cancelled / voided) and the local-only `draft` are excluded.
  v_active   text[]  := array['submitted', 'accepted', 'preparing', 'ready', 'served'];
  v_summary  jsonb;
  v_rows     jsonb;
  v_matching bigint;
begin
  if v_actor is null then
    raise exception 'owner_active_orders: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_active_orders: organization_id is required' using errcode = '42501';
  end if;

  -- Enum-validated filters. An unknown token is a BAD REQUEST (22023) — never a
  -- silently-empty board, and never interpolated into SQL.
  if p_status is not null and not (p_status = any (v_active)) then
    raise exception 'owner_active_orders: % is not an active order status', p_status using errcode = '22023';
  end if;
  if p_order_type is not null and p_order_type not in ('dine_in', 'takeaway') then
    raise exception 'owner_active_orders: unknown order_type %', p_order_type using errcode = '22023';
  end if;
  if p_payment is not null and p_payment not in ('paid', 'unpaid', 'cash') then
    raise exception 'owner_active_orders: unknown payment filter %', p_payment using errcode = '22023';
  end if;

  -- authority over the PASSED scope (downward-only coverage); 0 => not a member.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_active_orders: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  -- FINANCIAL-READ allowlist (GUC-free, app.can_read_financials-STYLE);
  -- kitchen_staff DENIED (the board carries order totals).
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
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_active_orders');
  end if;

  select o.default_currency into v_currency
    from public.organizations o
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'owner_active_orders: organization not found (or deleted)' using errcode = '42501';
  end if;

  with scoped as (
    -- Every ACTIVE order in scope. Deliberately NO date window: an order that is
    -- still open across midnight must NOT vanish from an operations board.
    -- The branch/restaurant joins are LEFT (with a 'UTC' zone fallback) so a
    -- tz-less or soft-deleted branch can never silently DROP a live order.
    select o.id,
           o.status,
           o.order_type,
           o.customer_name,
           o.receipt_number,
           o.grand_total_minor,
           o.created_at,
           o.table_id,
           o.opened_by_employee_profile_id,
           coalesce(b.timezone, r.timezone, 'UTC') as zone,
           b.name                                  as branch_name,
           pay.method                              as payment_method,
           pay.amount_minor                        as paid_amount_minor,
           (pay.method is not null)                as is_paid
    from public.orders o
    left join public.branches b
      on b.organization_id = o.organization_id
     and b.id              = o.branch_id
     and b.deleted_at is null
    left join public.restaurants r
      on r.organization_id = o.organization_id
     and r.id              = o.restaurant_id
     and r.deleted_at is null
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
      and o.status = any (v_active)
  ),
  matched as (
    -- The list the caller asked for (the SUMMARY above deliberately ignores
    -- these filters: it is the scope's operational picture, so the counters stay
    -- stable while the operator narrows the list).
    select s.*,
           tbl.label                     as table_label,
           ep.display_name               as staff_name,
           coalesce(items.item_count, 0) as item_count
    from scoped s
    left join public.tables tbl
      on tbl.organization_id = p_organization_id
     and tbl.id             = s.table_id
     and tbl.deleted_at is null
    left join public.employee_profiles ep
      on ep.organization_id = p_organization_id
     and ep.id             = s.opened_by_employee_profile_id
    left join lateral (
      select sum(oi.quantity)::bigint as item_count
      from public.order_items oi
      where oi.organization_id = p_organization_id
        and oi.order_id        = s.id
        and oi.deleted_at is null
    ) items on true
    where (p_status     is null or s.status     = p_status)
      and (p_order_type is null or s.order_type = p_order_type)
      and (
        p_payment is null
        or (p_payment = 'paid'   and s.is_paid)
        or (p_payment = 'unpaid' and not s.is_paid)
        or (p_payment = 'cash'   and s.payment_method = 'cash')
      )
      and (
        v_search is null
        or s.customer_name ilike '%' || v_search || '%'
        or coalesce(s.receipt_number, '') ilike '%' || v_search || '%'
        or coalesce(tbl.label, '') ilike '%' || v_search || '%'
        or upper(right(replace(s.id::text, '-', ''), 6)) like '%' || upper(replace(v_search, '#', '')) || '%'
      )
  ),
  page as (
    -- FIFO: oldest first, `id` breaking ties so equal timestamps order stably.
    -- Bounded by the CAPPED v_limit (no cursor: a live board is a bounded set,
    -- and `truncated` below reports honestly when the cap bites).
    select m.*
    from matched m
    order by m.created_at asc, m.id asc
    limit v_limit
  )
  select
    jsonb_build_object(
      'total',  (select count(*) from scoped),
      'unpaid', (select count(*) from scoped where not is_paid),
      'by_status', jsonb_build_object(
        'submitted', (select count(*) from scoped where status = 'submitted'),
        'accepted',  (select count(*) from scoped where status = 'accepted'),
        'preparing', (select count(*) from scoped where status = 'preparing'),
        'ready',     (select count(*) from scoped where status = 'ready'),
        'served',    (select count(*) from scoped where status = 'served'))),
    (select count(*) from matched),
    coalesce((
      select jsonb_agg(jsonb_build_object(
               'order_id',          p.id,
               'order_code',        '#' || upper(right(replace(p.id::text, '-', ''), 6)),
               'receipt_number',    p.receipt_number,
               'status',            p.status,
               'order_type',        p.order_type,
               'customer_name',     p.customer_name,
               'table_label',       p.table_label,
               'branch_name',       p.branch_name,
               'staff_name',        p.staff_name,
               -- Branch-local DISPLAY string (same shape as owner_order_history)
               -- + the ABSOLUTE instant the client needs for elapsed time, plus
               -- the resolved zone. Storage stays UTC; only display is local.
               'created_at',        to_char(p.created_at at time zone p.zone, 'YYYY-MM-DD HH24:MI'),
               'created_at_utc',    to_char(p.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
               'timezone',          p.zone,
               'item_count',        p.item_count,
               'grand_total_minor', p.grand_total_minor,
               'payment_method',    p.payment_method,
               'payment_status',    case when p.is_paid then 'paid' else 'unpaid' end,
               'paid_amount_minor', p.paid_amount_minor)
             order by p.created_at asc, p.id asc)
      from page p), '[]'::jsonb)
    into v_summary, v_matching, v_rows;

  return jsonb_build_object(
    'ok', true,
    'entity', 'owner_active_orders',
    'currency_code', v_currency,
    'limit', v_limit,
    'count', jsonb_array_length(v_rows),
    'matching', v_matching,
    'truncated', v_matching > jsonb_array_length(v_rows),
    'summary', v_summary,
    'orders', v_rows
  );
end;
$$;

comment on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int) is
  'ACTIVE-ORDERS-001 (READ-ONLY; D-007/D-008/D-011/D-018/D-020/D-025): the owner/manager Dashboard active-order operations board. Returns every order in the CANONICAL ACTIVE set (submitted/accepted/preparing/ready/served — terminal completed/cancelled/voided excluded; local-only draft excluded) in the caller''s scope, OLDEST-FIRST (FIFO, id tie-break), with NO date window (an order open across midnight must not vanish). Same authorization as owner_order_history (actor_rank_in_scope over the PASSED scope, 0 -> 42501; GUC-free financial-read allowlist; kitchen_staff -> permission_denied). Optional ENUM-VALIDATED filters: p_status (one active status), p_order_type, p_payment (paid/unpaid/cash), p_search (order code #hex / customer / table / receipt); an unknown token is 22023. p_limit is CAPPED 1..200 and `truncated`/`matching` report honestly when the cap bites. `summary` (total / unpaid / by_status) covers the SCOPE, not the filters. Money is integer minor units read from the stored snapshot (never recomputed). Payment status is a SEPARATE axis (D-025): a paid order stays active. Returns created_at (branch-local display) + created_at_utc (absolute) + timezone so the client can show ELAPSED time; there is NO promised/due field in the schema, so this NEVER reports "late". Safe columns only (no ids beyond order_id, no notes, no device/pin-session/membership identifiers, no raw payloads). Scope-safe (no GUC trusted); no anon/service_role.';

-- ---------------------------------------------------------------------------
-- 2. Thin public SECURITY INVOKER wrapper — the PostgREST-reachable surface.
-- ---------------------------------------------------------------------------
create or replace function public.owner_active_orders(
  p_organization_id uuid, p_restaurant_id uuid default null,
  p_branch_id uuid default null, p_status text default null,
  p_order_type text default null, p_payment text default null,
  p_search text default null, p_limit int default 100)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.owner_active_orders(
  p_organization_id, p_restaurant_id, p_branch_id, p_status,
  p_order_type, p_payment, p_search, p_limit); $$;

-- ---------------------------------------------------------------------------
-- 3. Grants: authenticated ONLY.
--    `revoke ... from public` does NOT remove the grant hosted Supabase's
--    `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO
--    anon` hands to `anon` at CREATE time (the defect AUDIT-LOG-DASHBOARD-001
--    had to correct in 20260711100000_audit_log_dashboard_001_revoke_anon.sql),
--    so anon is revoked EXPLICITLY here. Never anon / service_role (D-011).
-- ---------------------------------------------------------------------------
revoke all on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int)    from public;
revoke all on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int)    from anon;
grant execute on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int) to authenticated;

revoke all on function public.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int)    from public;
revoke all on function public.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int)    from anon;
grant execute on function public.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Supporting index — the exact scan this board makes: org/branch equality
--    over LIVE, ACTIVE rows in FIFO order. PARTIAL on (deleted_at is null AND
--    the active status set), so it stays small (terminal orders — the vast
--    majority over time — are not indexed) and is not usable by, nor a cost to,
--    any other query. The existing orders_history_keyset_idx is DESC-ordered and
--    carries no status, so it cannot serve this predicate efficiently.
-- ---------------------------------------------------------------------------
create index if not exists orders_active_ops_idx
  on public.orders (organization_id, branch_id, created_at asc, id asc)
  where deleted_at is null
    and status in ('submitted', 'accepted', 'preparing', 'ready', 'served');

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop index if exists public.orders_active_ops_idx;
--   drop function if exists public.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int);
--   drop function if exists app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int);
-- ============================================================================
