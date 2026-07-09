-- ============================================================================
-- ORDERS-HISTORY-001 — Dashboard completed-orders history + safe reprint center.
-- Two NEW, READ-ONLY, ADDITIVE functions for the owner/manager Dashboard:
--   * app.owner_order_history — a paginated, filtered, searchable LIST of orders
--     in scope (keyset pagination, branch-local date windows).
--   * app.owner_order_detail  — one order's full detail (header + items +
--     modifier snapshots + payments), for the details drawer and the receipt /
--     money-free kitchen-ticket previews.
-- Nothing else changes: submit_order / record_payment / sync_pull / the report
-- RPCs are UNTOUCHED. DECISIONS D-001/D-007/D-008/D-011/D-012/D-020; RISK R-003.
-- ----------------------------------------------------------------------------
-- The Dashboard is a JWT (auth.uid()) caller and the orders/payments RLS SELECT
-- policies are GUC-bound (app.current_org_id() + app.can_read_financials), so a
-- direct table read returns ZERO rows. As with the owner_* reports, these reads
-- are therefore GUC-free SECURITY DEFINER functions in `app` with a thin public
-- SECURITY INVOKER wrapper, and re-implement tenant isolation with EXPLICIT
-- organization_id / scope / deleted_at filters (SECURITY DEFINER bypasses RLS,
-- so the WHERE clauses ARE the isolation boundary — RISK R-003).
--
-- AUTHORIZATION — copied VERBATIM from owner_report_range (RF-REPORT-004):
--   identity from auth.uid() -> app.current_app_user_id() (null -> 42501);
--   app.actor_rank_in_scope over the PASSED scope (0 -> 42501, downward-only);
--   GUC-free can_read_financials-STYLE allowlist (cashier / manager /
--   restaurant_owner / org_owner / accountant; kitchen_staff DENIED via
--   {ok:false,error:'permission_denied'}). These reads expose no figure a
--   permitted caller could not already SELECT+SUM under RLS. No new privilege,
--   no anon / service_role (D-011).
--
-- MONEY — every money field is integer minor units (bigint), read STRAIGHT from
--   the stored order/payment/item snapshots (D-007/D-008); NOTHING is recomputed
--   from the live menu. deleted_at IS NULL throughout (D-020).
--
-- ORDER CODE — the SAME human display code every other surface shows
--   (packages/domain displayOrderCode): '#' || the last 6 hex of the order UUID,
--   uppercased. There is still no per-branch order-number column (its own
--   API-contract ticket); the RF-054 receipt_number is surfaced separately.
--
-- FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.
-- PENDING: RISK R-003 human RLS/security sign-off before this serves real tenant
-- data. NOT applied to hosted DB by this migration.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. app.owner_order_history — paginated / filtered / searchable order list.
-- ---------------------------------------------------------------------------
create or replace function app.owner_order_history(
  p_organization_id uuid,
  p_restaurant_id   uuid  default null,
  p_branch_id       uuid  default null,
  p_range           text  default 'today',
  p_search          text  default null,
  p_status          text  default null,
  p_order_type      text  default null,
  p_payment         text  default null,   -- null | 'paid' | 'unpaid' | 'cash'
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
           (pay.method is not null)                             as is_paid
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
        or (p_payment = 'paid'   and pay.method is not null)
        or (p_payment = 'unpaid' and pay.method is null)
        or (p_payment = 'cash'   and pay.method = 'cash')
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
               'table_label',          n.table_label,
               'staff_name',           n.staff_name,
               'created_at',           to_char(n.created_at at time zone n.zone, 'YYYY-MM-DD HH24:MI'),
               'item_count',           n.item_count,
               'subtotal_minor',       n.subtotal_minor,
               'discount_total_minor', n.discount_total_minor,
               'tax_total_minor',      n.tax_total_minor,
               'grand_total_minor',    n.grand_total_minor,
               'payment_method',       n.payment_method,
               'payment_status',       case when n.is_paid then 'paid' else 'unpaid' end,
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

comment on function app.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text) is
  'ORDERS-HISTORY-001 (read-only; D-007/D-008/D-011/D-020): GUC-free paginated order-history LIST for the owner/manager Dashboard. Same authorization as owner_report_range (app.actor_rank_in_scope over the PASSED scope, 0 -> 42501; GUC-free can_read_financials-STYLE allowlist; kitchen_staff -> permission_denied). Branch-local date window (p_range in today/yesterday/last7/last30). Optional filters: p_status, p_order_type, p_payment (paid/unpaid/cash), p_search (order code #hex / customer / table / receipt). Keyset pagination ("<created_at>|<id>", newest first, p_limit clamped 1..100, has_more/next_cursor). Money integer minor, read from stored snapshots (never recomputed). Scope-safe (no GUC trusted); no anon/service_role.';

-- ---------------------------------------------------------------------------
-- 2. app.owner_order_detail — one order's full detail (header + items +
--    modifier snapshots + payments) for the detail drawer / reprint previews.
-- ---------------------------------------------------------------------------
create or replace function app.owner_order_detail(
  p_organization_id uuid,
  p_restaurant_id   uuid default null,
  p_branch_id       uuid default null,
  p_order_id        uuid default null
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
  v_zone     text;
  v_order    jsonb;
  v_items    jsonb;
  v_payments jsonb;
begin
  if v_actor is null then
    raise exception 'owner_order_detail: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_order_detail: organization_id is required' using errcode = '42501';
  end if;
  if p_order_id is null then
    raise exception 'owner_order_detail: order_id is required' using errcode = '22023';
  end if;

  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_order_detail: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
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
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_order_detail');
  end if;

  select o.default_currency into v_currency
    from public.organizations o
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'owner_order_detail: organization not found (or deleted)' using errcode = '42501';
  end if;

  -- The order, scoped. A miss (wrong tenant / out of scope / deleted) returns a
  -- clean not_found (never leaks that another tenant's order exists).
  select
    coalesce(b.timezone, r.timezone, 'UTC'),
    jsonb_build_object(
      'order_id',             o.id,
      'order_code',           '#' || upper(right(replace(o.id::text, '-', ''), 6)),
      'receipt_number',       o.receipt_number,
      'status',               o.status,
      'order_type',           o.order_type,
      'customer_name',        o.customer_name,
      'table_label',          tbl.label,
      'branch_name',          b.name,
      'staff_name',           ep.display_name,
      'notes',                o.notes,
      'created_at',           to_char(o.created_at at time zone coalesce(b.timezone, r.timezone, 'UTC'), 'YYYY-MM-DD HH24:MI'),
      'currency_code',        o.currency_code,
      'subtotal_minor',       o.subtotal_minor,
      'discount_total_minor', o.discount_total_minor,
      'tax_total_minor',      o.tax_total_minor,
      'grand_total_minor',    o.grand_total_minor)
    into v_zone, v_order
  from public.orders o
  left join public.branches b
    on b.organization_id = o.organization_id and b.id = o.branch_id
  left join public.restaurants r
    on r.organization_id = o.organization_id and r.id = o.restaurant_id
  left join public.tables tbl
    on tbl.organization_id = o.organization_id and tbl.id = o.table_id and tbl.deleted_at is null
  left join public.employee_profiles ep
    on ep.organization_id = o.organization_id and ep.id = o.opened_by_employee_profile_id
  where o.id              = p_order_id
    and o.organization_id = p_organization_id
    and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
    and (p_branch_id     is null or o.branch_id     = p_branch_id)
    and o.deleted_at is null;

  if v_order is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'owner_order_detail');
  end if;

  -- Line items with their captured modifier snapshots (option name/qty +
  -- price + the non-money meat_snapshot) and the item prep_snapshot. The KDS
  -- kitchen-count/prep totals are aggregated client-side from these snapshots.
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'order_item_id',      oi.id,
             'name',               oi.menu_item_name_snapshot,
             'quantity',           oi.quantity,
             'station_id',         oi.station_id,
             'notes',              oi.notes,
             'unit_price_minor',   oi.unit_price_minor_snapshot,
             'line_discount_minor',oi.line_discount_minor,
             'line_total_minor',   oi.line_total_minor,
             'prep_snapshot',      oi.prep_snapshot,
             'modifiers', (
               select coalesce(jsonb_agg(
                        jsonb_build_object(
                          'option_name',   m.option_name_snapshot,
                          'modifier_name', m.modifier_name_snapshot,
                          'quantity',      m.quantity,
                          'price_minor',   m.price_minor_snapshot,
                          'meat_snapshot', m.meat_snapshot)
                        order by m.created_at, m.id), '[]'::jsonb)
               from public.order_item_modifiers m
               where m.organization_id = oi.organization_id
                 and m.order_item_id   = oi.id
                 and m.deleted_at is null))
           order by oi.created_at, oi.id), '[]'::jsonb)
    into v_items
  from public.order_items oi
  where oi.organization_id = p_organization_id
    and oi.order_id        = p_order_id
    and oi.deleted_at is null;

  select coalesce(jsonb_agg(
           jsonb_build_object(
             'method',         p.method,
             'status',         p.status,
             'amount_minor',   p.amount_minor,
             'tendered_minor', p.tendered_minor,
             'change_minor',   p.change_minor,
             'receipt_number', p.receipt_number,
             'created_at',     to_char(p.created_at at time zone v_zone, 'YYYY-MM-DD HH24:MI'))
           order by p.created_at, p.id), '[]'::jsonb)
    into v_payments
  from public.payments p
  where p.organization_id = p_organization_id
    and p.order_id        = p_order_id
    and p.deleted_at is null;

  return jsonb_build_object(
    'ok', true,
    'entity', 'owner_order_detail',
    'currency_code', v_currency,
    'order', v_order
      || jsonb_build_object('items', v_items, 'payments', v_payments)
  );
end;
$$;

comment on function app.owner_order_detail(uuid, uuid, uuid, uuid) is
  'ORDERS-HISTORY-001 (read-only; D-007/D-008/D-011/D-020): GUC-free single-order DETAIL for the owner/manager Dashboard details drawer + receipt / money-free kitchen-ticket previews. Same authorization as owner_order_history (actor_rank_in_scope; GUC-free financial-read allowlist; kitchen_staff -> permission_denied). Returns the order header (customer/table/staff/status/times), line items with captured modifier + meat_snapshot + prep_snapshot, and payments — all money integer minor read from stored snapshots (never recomputed; D-008). Scoped; an out-of-scope/missing order -> {ok:false,error:not_found} (no cross-tenant leak). No anon/service_role.';

-- ---------------------------------------------------------------------------
-- 3. Thin public SECURITY INVOKER wrappers (sales_summary / owner_report_range
--    pattern) — the PostgREST-reachable surface.
-- ---------------------------------------------------------------------------
create or replace function public.owner_order_history(
  p_organization_id uuid, p_restaurant_id uuid default null,
  p_branch_id uuid default null, p_range text default 'today',
  p_search text default null, p_status text default null,
  p_order_type text default null, p_payment text default null,
  p_limit int default 25, p_cursor text default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.owner_order_history(
  p_organization_id, p_restaurant_id, p_branch_id, p_range, p_search,
  p_status, p_order_type, p_payment, p_limit, p_cursor); $$;

create or replace function public.owner_order_detail(
  p_organization_id uuid, p_restaurant_id uuid default null,
  p_branch_id uuid default null, p_order_id uuid default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.owner_order_detail(p_organization_id, p_restaurant_id, p_branch_id, p_order_id); $$;

-- ---------------------------------------------------------------------------
-- 4. Grants: authenticated only (never anon / service_role; D-011).
-- ---------------------------------------------------------------------------
revoke all on function app.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text)    from public;
grant execute on function app.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text) to authenticated;
revoke all on function public.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text)    from public;
grant execute on function public.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text) to authenticated;

revoke all on function app.owner_order_detail(uuid, uuid, uuid, uuid)    from public;
grant execute on function app.owner_order_detail(uuid, uuid, uuid, uuid) to authenticated;
revoke all on function public.owner_order_detail(uuid, uuid, uuid, uuid)    from public;
grant execute on function public.owner_order_detail(uuid, uuid, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Supporting index for the history keyset scan: branch-scoped, newest-first
--    ordering over LIVE rows (the ORDER BY (created_at desc, id desc) + org/branch
--    equality the list uses). Partial on deleted_at IS NULL (the only rows read).
-- ---------------------------------------------------------------------------
create index if not exists orders_history_keyset_idx
  on public.orders (organization_id, branch_id, created_at desc, id desc)
  where deleted_at is null;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop index if exists public.orders_history_keyset_idx;
--   drop function if exists public.owner_order_detail(uuid, uuid, uuid, uuid);
--   drop function if exists app.owner_order_detail(uuid, uuid, uuid, uuid);
--   drop function if exists public.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text);
--   drop function if exists app.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text);
-- ============================================================================
