-- OPS-043 Phase 2 (MENU-ADMIN-CURRENCY-OPS-043-PHASE2A-045)
-- Per-row currency on the two order LIST reads + a per-currency report
-- breakdown. ADDITIVE ONLY.
--
-- WHY
--   Phase 1 made `restaurants.currency_override` writable, so one organization
--   can now hold restaurants operating in different currencies, and every order
--   is stored with the currency it was actually taken in (`orders.currency_code`,
--   priced from coalesce(currency_override, default_currency)).
--
--   Two consequences the server had to answer first:
--     1. RELABELLING. `owner_order_history` and `owner_active_orders` emitted no
--        per-row currency at all, only one envelope code, so the dashboard
--        stamped today's currency onto yesterday's stored money. D3 forbids
--        that: historical rows keep their own currency, always.
--     2. SUMMING UNLIKE CURRENCIES. Every report RPC labels one merged total
--        with one code. Adding two currencies together is worse than
--        mislabelling one, so the client needs a way to SEE that a range is
--        mixed before it renders a single figure.
--
-- WHAT THIS DOES
--   * CREATE OR REPLACE of `app.owner_order_history` and `app.owner_active_orders`
--     with UNCHANGED signatures - so no DROP, no re-GRANT, no PostgREST overload
--     hazard, and every existing envelope key keeps its meaning. Each gains one
--     ADDITIVE row key, `currency_code`, and labels its envelope with the
--     effective currency instead of the org default.
--   * a NEW function `app.owner_report_currency_breakdown` (+ its `public.`
--     wrapper) returning per-currency totals for an explicit date window. It is
--     additive by construction: no existing RPC's shape moves at all. The
--     dashboard calls it beside the report it already loads and refuses to show
--     a single merged total when it comes back with more than one currency.
--
-- WHAT THIS DOES NOT DO
--   * No data is read, written, transformed or backfilled. Zero rows change.
--   * No column, table, index, policy or grant is added, altered or dropped.
--   * No currency is converted anywhere. Ever. (D2: no FX in this program.)
--   * No existing function signature changes, so no ACL is lost.
--
-- ROLLBACK
--   Re-running the two prior migrations' function bodies restores the previous
--   definitions; dropping `app.owner_report_currency_breakdown` and its wrapper
--   removes the new surface. Neither touches data.

-- ===========================================================================
-- REPLACED (same signature): app.owner_order_history
-- ===========================================================================
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

  -- OPS-043 Phase 2: the EFFECTIVE currency, not the organization default.
  -- Phase 1 made restaurants.currency_override writable, and the menu/POS
  -- path already prices in coalesce(currency_override, default_currency),
  -- so labelling this payload with the org default contradicted both the
  -- Settings screen and the currency the orders were actually taken in.
  -- An ORG-WIDE call (no restaurant in scope) keeps the org default: there
  -- is no single restaurant whose override could apply, and the per-row
  -- currency_code below carries the truth for a mixed scope.
  select coalesce(r.currency_override, o.default_currency) into v_currency
    from public.organizations o
    left join public.restaurants r
      on r.id              = p_restaurant_id
     and r.organization_id = o.id
     and r.deleted_at is null
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
           -- OPS-043 Phase 2: the ORDER's OWN currency travels with the row.
           -- Without it the client had only the envelope code and stamped it
           -- onto every row, relabelling a stored ILS order as USD the moment
           -- the restaurant switched. Historical money is never relabelled.
           o.currency_code,
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
               'currency_code',        n.currency_code,
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

-- ===========================================================================
-- REPLACED (same signature): app.owner_active_orders
-- ===========================================================================
create or replace function app.owner_active_orders(
  p_organization_id uuid,
  p_restaurant_id   uuid default null,
  p_branch_id       uuid default null,
  p_status          text default null,   -- one ACTIVE status (must sit INSIDE p_queue)
  p_order_type      text default null,   -- 'dine_in' | 'takeaway'
  p_payment         text default null,   -- 'paid' | 'unpaid' | 'cash'
  p_search          text default null,   -- order code / customer / table / receipt
  p_limit           int  default 100,
  -- ACTIVE-ORDERS-002 (appended, backward-compatible defaults):
  p_queue           text default 'all_active',  -- in_progress | awaiting_close | all_active
  p_sort            text default 'newest',      -- newest | oldest
  p_cursor          text default null           -- "<sort>|<created_at>|<id>"
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
  v_limit      integer := least(greatest(coalesce(p_limit, 100), 1), 200);
  v_search     text    := nullif(btrim(coalesce(p_search, '')), '');
  v_queue      text    := coalesce(nullif(btrim(coalesce(p_queue, '')), ''), 'all_active');
  v_sort       text    := coalesce(nullif(btrim(coalesce(p_sort,  '')), ''), 'newest');
  -- The canonical OPERATIONALLY ACTIVE set (D-018). Terminal states
  -- (completed/cancelled/voided) and the local-only `draft` are excluded.
  v_active     text[]  := array['submitted', 'accepted', 'preparing', 'ready', 'served'];
  -- The QUEUES. These are a PRESENTATION grouping OVER the canonical states —
  -- not a new taxonomy: every member is one of the five canonical active states.
  v_in_prog    text[]  := array['submitted', 'accepted', 'preparing', 'ready'];
  v_awaiting   text[]  := array['served'];
  v_queue_set  text[];
  v_newest     boolean;
  v_cursor_ts  timestamptz;
  v_cursor_id  uuid;
  v_summary    jsonb;
  v_rows       jsonb;
  v_matching   bigint;
  v_fetched    bigint;
  v_more       boolean;
  v_next       text;
begin
  if v_actor is null then
    raise exception 'owner_active_orders: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_active_orders: organization_id is required' using errcode = '42501';
  end if;

  -- ---- ENUM-VALIDATED controls. An unknown token is a BAD REQUEST (22023) —
  --      never a silently-empty board, and NOTHING is interpolated into SQL.
  case v_queue
    when 'in_progress'    then v_queue_set := v_in_prog;
    when 'awaiting_close' then v_queue_set := v_awaiting;
    when 'all_active'     then v_queue_set := v_active;
    else raise exception 'owner_active_orders: unknown queue %', v_queue using errcode = '22023';
  end case;

  if v_sort not in ('newest', 'oldest') then
    raise exception 'owner_active_orders: unknown sort %', v_sort using errcode = '22023';
  end if;
  v_newest := (v_sort = 'newest');

  -- A status filter must be an ACTIVE status AND must sit INSIDE the selected
  -- queue — otherwise the two controls would silently contradict each other.
  if p_status is not null then
    if not (p_status = any (v_active)) then
      raise exception 'owner_active_orders: % is not an active order status', p_status using errcode = '22023';
    end if;
    if not (p_status = any (v_queue_set)) then
      raise exception 'owner_active_orders: status % is not in queue %', p_status, v_queue using errcode = '22023';
    end if;
  end if;

  if p_order_type is not null and p_order_type not in ('dine_in', 'takeaway') then
    raise exception 'owner_active_orders: unknown order_type %', p_order_type using errcode = '22023';
  end if;
  if p_payment is not null and p_payment not in ('paid', 'unpaid', 'cash') then
    raise exception 'owner_active_orders: unknown payment filter %', p_payment using errcode = '22023';
  end if;

  -- ---- The keyset cursor is TAGGED with the sort it was minted under:
  --      "<sort>|<created_at>|<id>". Replaying a cursor under the OTHER direction
  --      would silently skip or duplicate rows, so it is REJECTED outright.
  if p_cursor is not null and btrim(p_cursor) <> '' then
    if split_part(p_cursor, '|', 1) <> v_sort then
      raise exception 'owner_active_orders: cursor was issued for sort % but sort % was requested',
        split_part(p_cursor, '|', 1), v_sort using errcode = '22023';
    end if;
    begin
      v_cursor_ts := split_part(p_cursor, '|', 2)::timestamptz;
      v_cursor_id := split_part(p_cursor, '|', 3)::uuid;
    exception when others then
      raise exception 'owner_active_orders: invalid cursor' using errcode = '22023';
    end;
  end if;

  -- ---- authority over the PASSED scope (downward-only); 0 => not a member.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_active_orders: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  -- FINANCIAL-READ allowlist (GUC-free); kitchen_staff DENIED (the board carries totals).
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

  -- OPS-043 Phase 2: the EFFECTIVE currency, not the organization default.
  -- Phase 1 made restaurants.currency_override writable, and the menu/POS
  -- path already prices in coalesce(currency_override, default_currency),
  -- so labelling this payload with the org default contradicted both the
  -- Settings screen and the currency the orders were actually taken in.
  -- An ORG-WIDE call (no restaurant in scope) keeps the org default: there
  -- is no single restaurant whose override could apply, and the per-row
  -- currency_code below carries the truth for a mixed scope.
  select coalesce(r.currency_override, o.default_currency) into v_currency
    from public.organizations o
    left join public.restaurants r
      on r.id              = p_restaurant_id
     and r.organization_id = o.id
     and r.deleted_at is null
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'owner_active_orders: organization not found (or deleted)' using errcode = '42501';
  end if;

  with scoped as (
    -- EVERY active order in scope (all five canonical states), regardless of the
    -- selected queue — this is what the SUMMARY counts, so the cards stay stable
    -- while the operator switches queues. Deliberately NO date window: an order
    -- still open across midnight must never vanish from an operations board.
    -- LEFT joins (+ a 'UTC' fallback) so a tz-less or soft-deleted branch can
    -- never silently DROP a live order.
    select o.id,
           o.status,
           o.order_type,
           o.customer_name,
           o.customer_phone,
           o.receipt_number,
           o.grand_total_minor,
           -- OPS-043 Phase 2: the ORDER's OWN currency travels with the row.
           -- Without it the client had only the envelope code and stamped it
           -- onto every row, relabelling a stored ILS order as USD the moment
           -- the restaurant switched. Historical money is never relabelled.
           o.currency_code,
           o.created_at,
           o.table_id,
           o.opened_by_employee_profile_id,
           coalesce(b.timezone, r.timezone, 'UTC') as zone,
           b.name                                  as branch_name,
           pay.method                              as payment_method,
           pay.amount_minor                        as paid_amount_minor,
           -- MONEY-SETTLEMENT-CONSISTENCY-001: SETTLEMENT, not a marker. `is_paid` now
           -- answers "does this order still owe money?" via THE one canonical predicate,
           -- so a NON-CHARGEABLE zero-total order is settled (it was reported UNPAID
           -- forever before, because there is no payment row to find) and an UNDER-COVERED
           -- order is NOT settled (it was reported PAID before). `payment_method` and
           -- `paid_amount_minor` still come from the payment row: they DISPLAY what was
           -- actually taken, and are legitimately null when nothing was.
           app.order_is_fully_settled(o.organization_id, o.id) as is_paid,
           (o.grand_total_minor > 0)               as is_chargeable
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
    -- The QUEUE + the list filters. This is the set `matching` counts and the
    -- page is drawn from.
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
    where s.status = any (v_queue_set)
      and (p_status     is null or s.status     = p_status)
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
    -- SERVER-SIDE sort + keyset continuation. `id` breaks ties so equal
    -- timestamps order stably and paginate without duplicates or gaps.
    -- One extra row is fetched to decide has_more without a second count.
    select m.*
    from matched m
    where p_cursor is null
       or v_cursor_ts is null
       or (v_newest and (m.created_at, m.id) < (v_cursor_ts, v_cursor_id))
       or (not v_newest and (m.created_at, m.id) > (v_cursor_ts, v_cursor_id))
    order by
      case when v_newest then m.created_at end desc,
      case when v_newest then m.id         end desc,
      case when not v_newest then m.created_at end asc,
      case when not v_newest then m.id         end asc
    limit v_limit + 1
  ),
  numbered as (
    select p.*,
           row_number() over (
             order by
               case when v_newest then p.created_at end desc,
               case when v_newest then p.id         end desc,
               case when not v_newest then p.created_at end asc,
               case when not v_newest then p.id         end asc
           ) as rn
    from page p
  )
  select
    jsonb_build_object(
      'total',  (select count(*) from scoped),
      'unpaid', (select count(*) from scoped where not is_paid),
      -- The QUEUE counters the cards render — scope-wide, never the page.
      'in_progress',    (select count(*) from scoped where status = any (v_in_prog)),
      'awaiting_close', (select count(*) from scoped where status = any (v_awaiting)),
      'by_status', jsonb_build_object(
        'submitted', (select count(*) from scoped where status = 'submitted'),
        'accepted',  (select count(*) from scoped where status = 'accepted'),
        'preparing', (select count(*) from scoped where status = 'preparing'),
        'ready',     (select count(*) from scoped where status = 'ready'),
        'served',    (select count(*) from scoped where status = 'served'))),
    (select count(*) from matched),
    -- The EXTRA row fetched (limit v_limit + 1) is what decides has_more. It must
    -- NOT be derived from `matching`, which counts the WHOLE filtered set: on the
    -- last page of a paginated read, `matching` still exceeds the page size even
    -- though nothing remains after it.
    (select count(*) from numbered),
    coalesce((
      select jsonb_agg(jsonb_build_object(
               'order_id',          n.id,
               'order_code',        '#' || upper(right(replace(n.id::text, '-', ''), 6)),
               'receipt_number',    n.receipt_number,
               'status',            n.status,
               'order_type',        n.order_type,
               'customer_name',     n.customer_name,
               'customer_phone',    n.customer_phone,
               'table_label',       n.table_label,
               'branch_name',       n.branch_name,
               'staff_name',        n.staff_name,
               -- Branch-local DISPLAY string + the ABSOLUTE instant the client
               -- needs for elapsed time, plus the resolved zone. Storage is UTC.
               'created_at',        to_char(n.created_at at time zone n.zone, 'YYYY-MM-DD HH24:MI'),
               'created_at_utc',    to_char(n.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
               'timezone',          n.zone,
               'item_count',        n.item_count,
               'grand_total_minor', n.grand_total_minor,
               'currency_code',     n.currency_code,
               'payment_method',    n.payment_method,
               -- THREE honest states. Saying "paid" for an order that was never charged
               -- would be a lie, and "unpaid" would imply money is owed when none is —
               -- the Activity Log already records exactly this as `not_chargeable`.
               'payment_status',    case when not n.is_chargeable then 'not_chargeable'
                                         when n.is_paid           then 'paid'
                                         else                          'unpaid' end,
               'paid_amount_minor', n.paid_amount_minor)
             order by n.rn)
      from numbered n
      where n.rn <= v_limit), '[]'::jsonb),
    -- The continuation, TAGGED with this sort so it can never be replayed under
    -- the other direction.
    (select v_sort || '|' || n.created_at::text || '|' || n.id::text
       from numbered n where n.rn = v_limit)
    into v_summary, v_matching, v_fetched, v_rows, v_next;

  -- More rows exist AFTER this page iff the extra (v_limit + 1)-th row came back.
  v_more := v_fetched > v_limit;

  return jsonb_build_object(
    'ok', true,
    'entity', 'owner_active_orders',
    'currency_code', v_currency,
    'queue', v_queue,
    'sort', v_sort,
    'limit', v_limit,
    'count', jsonb_array_length(v_rows),
    -- the FULL filtered count — never the loaded page. The client renders the
    -- honest "showing the newest N of M" from it.
    'matching', v_matching,
    'has_more',    v_more,
    'truncated',   v_more,
    'next_cursor', case when v_more then v_next else null end,
    'summary', v_summary,
    'orders', v_rows
  );
end;
$$;

-- ===========================================================================
-- NEW: app.owner_report_currency_breakdown
-- ===========================================================================
-- Per-currency totals over an EXPLICIT branch-local date window.
--
-- It deliberately takes `p_start` / `p_end` rather than a preset: the dashboard
-- already receives `range_start` / `range_end` from `owner_report_range`, so
-- passing them back guarantees this breakdown describes exactly the window the
-- headline figures came from. Duplicating the preset arithmetic would have been
-- a second place for the window to drift.
--
-- Same authorization as the rest of the owner report family: a covering active
-- membership, financial-read roles only (kitchen_staff denied).
create or replace function app.owner_report_currency_breakdown(
  p_organization_id uuid,
  p_restaurant_id   uuid  default null,
  p_branch_id       uuid  default null,
  p_start           date  default null,
  p_end             date  default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor  uuid := app.current_app_user_id();
  v_rank   int;
  v_result jsonb;
begin
  if v_actor is null then
    raise exception 'owner_report_currency_breakdown: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_report_currency_breakdown: organization_id is required' using errcode = '42501';
  end if;
  if p_start is null or p_end is null or p_end < p_start then
    raise exception 'owner_report_currency_breakdown: a valid start/end date pair is required' using errcode = '42501';
  end if;

  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_report_currency_breakdown: caller has no active membership covering the requested scope' using errcode = '42501';
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
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_report_currency_breakdown');
  end if;

  with branch_tz as (
    -- branch-local zone (RF-075): COALESCE(branch, restaurant); tz-less excluded.
    -- ORG-SCOPED at the source: SECURITY DEFINER bypasses RLS, so this filter is
    -- what keeps the CTE single-tenant (D-001 / RISK R-003).
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
  order_win as (
    -- billed orders in the window: NOT voided / cancelled / draft, exactly the
    -- set `owner_report_range`'s `sales` CTE counts.
    select o.id as order_id,
           o.currency_code,
           o.status,
           o.subtotal_minor,
           o.discount_total_minor
    from public.orders o
    join branch_tz t
      on t.organization_id = o.organization_id
     and t.branch_id       = o.branch_id
    where o.organization_id = p_organization_id
      and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or o.branch_id     = p_branch_id)
      and o.deleted_at is null
      and o.status not in ('voided', 'cancelled', 'draft')
      and (o.created_at at time zone t.zone)::date between p_start and p_end
  ),
  item_rollup as (
    -- LIVE LINES ONLY, mirroring owner_report_range: a line struck off a live
    -- bill was not sold, so gross and the item-discount component must describe
    -- the same set of lines or the identity gross - discount = net breaks.
    select oi.order_id,
           sum(oi.line_total_minor + oi.line_discount_minor) as gross_minor,
           sum(oi.line_discount_minor)                       as item_discount_minor
    from public.order_items oi
    where oi.deleted_at is null
      and oi.status not in ('voided', 'cancelled')
      and oi.order_id in (select ow.order_id from order_win ow)
    group by oi.order_id
  ),
  order_cur as (
    select ow.currency_code,
           count(*)::bigint                                                      as order_count,
           count(*) filter (where ow.status = 'completed')::bigint               as completed_count,
           coalesce(sum(ir.gross_minor), 0)::bigint                              as gross_minor,
           (coalesce(sum(ir.item_discount_minor), 0)
             + coalesce(sum(ow.discount_total_minor), 0))::bigint                as discount_minor,
           coalesce(sum(ow.subtotal_minor - ow.discount_total_minor), 0)::bigint as net_minor
    from order_win ow
    left join item_rollup ir on ir.order_id = ow.order_id
    group by ow.currency_code
  ),
  pay_cur as (
    -- completed payments on live orders, grouped by the PAYMENT's own currency
    -- (a payment row carries its own code; it is not assumed to match the order).
    select p.currency_code,
           coalesce(sum(p.amount_minor), 0)::bigint                                          as collected_minor,
           coalesce(sum(p.amount_minor) filter (where p.method = 'cash'), 0)::bigint         as cash_minor
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
      and (p.created_at at time zone t.zone)::date between p_start and p_end
    group by p.currency_code
  ),
  codes as (
    select currency_code from order_cur
    union
    select currency_code from pay_cur
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'currency_code',    c.currency_code,
           'order_count',      coalesce(oc.order_count, 0),
           'completed_count',  coalesce(oc.completed_count, 0),
           'gross_minor',      coalesce(oc.gross_minor, 0),
           'discount_minor',   coalesce(oc.discount_minor, 0),
           'net_minor',        coalesce(oc.net_minor, 0),
           'collected_minor',  coalesce(pc.collected_minor, 0),
           'cash_minor',       coalesce(pc.cash_minor, 0))
         order by c.currency_code), '[]'::jsonb)
    into v_result
  from codes c
  left join order_cur oc on oc.currency_code = c.currency_code
  left join pay_cur   pc on pc.currency_code = c.currency_code;

  return jsonb_build_object(
    'ok',           true,
    'entity',       'owner_report_currency_breakdown',
    'range_start',  to_char(p_start, 'YYYY-MM-DD'),
    'range_end',    to_char(p_end,   'YYYY-MM-DD'),
    'by_currency',  v_result
  );
end;
$$;

create or replace function public.owner_report_currency_breakdown(
  p_organization_id uuid,
  p_restaurant_id   uuid default null,
  p_branch_id       uuid default null,
  p_start           date default null,
  p_end             date default null
)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.owner_report_currency_breakdown(p_organization_id, p_restaurant_id, p_branch_id, p_start, p_end) $$;

-- Same ACL posture as the rest of the owner report family: nothing for PUBLIC or
-- anon; execute for authenticated only.
revoke all on function app.owner_report_currency_breakdown(uuid, uuid, uuid, date, date) from public;
revoke all on function public.owner_report_currency_breakdown(uuid, uuid, uuid, date, date) from public;
revoke all on function app.owner_report_currency_breakdown(uuid, uuid, uuid, date, date) from anon;
revoke all on function public.owner_report_currency_breakdown(uuid, uuid, uuid, date, date) from anon;
grant execute on function public.owner_report_currency_breakdown(uuid, uuid, uuid, date, date) to authenticated;
