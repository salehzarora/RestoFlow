-- ============================================================================
-- ORDER-EDIT-001G (2 of 2) — the Dashboard ORDER reads and the branch-switch
-- reader (API_CONTRACT §4.47a; ORDER_EDIT_DESIGN §8.6; DECISION D-043 /
-- D-044). DB only; every change is ADDITIVE and READ-ONLY.
--
-- Each re-emitted body is copied mechanically from its LIVE definition
-- (20261008170200_order_edit_001a_reemits, ORDER-EDIT-001A) and changed ONLY
-- where noted; every other byte (including the historical mis-encoded comment
-- bytes of the owner_active_orders body) is preserved.
--
--   1. app.owner_active_orders  — every row + edit_count and has_active_round.
--   2. app.owner_order_history  — every row + edit_count and has_active_round.
--   3. app.owner_order_detail   — order + edit_count, has_active_round,
--      active_rounds_ready and edits[] (money-free, oldest first).
--   4. NEW app.get_branch_order_edit_settings + its public SECURITY INVOKER
--      wrapper — the Dashboard reader of the two §4.45.8 switches (plus the
--      branch's kitchen_workflow_mode).
--
-- has_active_round is the app.void_order live-round predicate (any
-- order_service_rounds row of the order with deleted_at null and status in
-- submitted..ready), probed for the returned page rows only — the predicate
-- pos_order_detail and pos_order_snapshots use since ORDER-EDIT-001B. On a
-- printer_only branch nothing advances a round, so it stays TRUE until the
-- order completes (§4.30c).
--
-- Signatures, volatility, SECURITY DEFINER, search_path, authorization,
-- filters, summaries, queues and paging of the re-emitted readers are
-- unchanged (CREATE OR REPLACE keeps their ACLs; they are re-stated). The new
-- reader's scope check is the MEMBER rank (app.actor_rank_in_scope), never the
-- ADMIN-126B support read rank. No table, column, index, RLS policy, trigger or
-- row write; reads write no audit event (D-013); no service_role (D-011).
--
-- ROLLBACK: re-apply the three ORDER-EDIT-001A bodies (20261008170200
-- sections 6, 6b and 7, with their comments), then drop function
-- public.get_branch_order_edit_settings(uuid, uuid, uuid) and
-- app.get_branch_order_edit_settings(uuid, uuid, uuid). Old Dashboard builds
-- ignore the new keys.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. app.owner_active_orders — re-emitted from its LIVE body
--    (20261008170200_order_edit_001a_reemits section 7) with ONLY: o.edit_count
--    in the scoped CTE, and edit_count + has_active_round on every row.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.owner_active_orders(p_organization_id uuid, p_restaurant_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid, p_status text DEFAULT NULL::text, p_order_type text DEFAULT NULL::text, p_payment text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_limit integer DEFAULT 100, p_queue text DEFAULT 'all_active'::text, p_sort text DEFAULT 'newest'::text, p_cursor text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  -- The QUEUES. These are a PRESENTATION grouping OVER the canonical states â€”
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

  -- ---- ENUM-VALIDATED controls. An unknown token is a BAD REQUEST (22023) â€”
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
  -- queue â€” otherwise the two controls would silently contradict each other.
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
    -- selected queue â€” this is what the SUMMARY counts, so the cards stay stable
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
           o.edit_count,                           -- ORDER-EDIT-001G
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
           (o.grand_total_minor > 0)               as is_chargeable,
           -- STALE-TABLE-ORDER-RECOVERY-001 (display-only operational facts;
           -- the read never mutates): originating shift state + live kitchen work
           case when sh.status in ('closed', 'reconciled') then 'closed'
                when sh.status is null then null
                else 'open' end                  as shift_status,
           ((coalesce(b.kitchen_workflow_mode, 'kds') = 'kds'
               and o.status in ('submitted', 'accepted', 'preparing', 'ready'))
            or exists (select 1 from public.kitchen_print_dispatches k
                        where k.organization_id = o.organization_id and k.order_id = o.id
                          and k.completed_at is null and k.superseded_by_dispatch_id is null)
            or exists (select 1 from public.order_service_rounds r
                        where r.organization_id = o.organization_id and r.order_id = o.id
                          and r.deleted_at is null and r.status not in ('served', 'voided')))
                                                   as kitchen_work_open
    from public.orders o
    left join public.shifts sh
      on sh.organization_id = o.organization_id
     and sh.id              = o.shift_id
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
        -- ORDER-EDIT-001A: a line RETIRED by an order edit is replaced by its
        -- remainder / replacement rows; counting both would inflate the count.
        and oi.removed_by_edit_id is null
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
      -- The QUEUE counters the cards render â€” scope-wide, never the page.
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
               -- would be a lie, and "unpaid" would imply money is owed when none is â€”
               -- the Activity Log already records exactly this as `not_chargeable`.
               'payment_status',    case when not n.is_chargeable then 'not_chargeable'
                                         when n.is_paid           then 'paid'
                                         else                          'unpaid' end,
               'paid_amount_minor', n.paid_amount_minor,
               -- STALE-TABLE-ORDER-RECOVERY-001: additive operational flags
               'shift_status',      n.shift_status,
               'kitchen_work_open', n.kitchen_work_open,
               -- ORDER-EDIT-001G (API_CONTRACT §4.47a): additive, money-free.
               -- has_active_round = any live service round of the order in
               -- submitted..ready (the app.void_order live-round predicate),
               -- probed for the page rows only.
               'edit_count',        n.edit_count,
               'has_active_round',  exists (
                                      select 1 from public.order_service_rounds ar
                                       where ar.organization_id = p_organization_id
                                         and ar.order_id        = n.id
                                         and ar.deleted_at is null
                                         and ar.status in ('submitted', 'accepted', 'preparing', 'ready')))
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
    -- the FULL filtered count â€” never the loaded page. The client renders the
    -- honest "showing the newest N of M" from it.
    'matching', v_matching,
    'has_more',    v_more,
    'truncated',   v_more,
    'next_cursor', case when v_more then v_next else null end,
    'summary', v_summary,
    'orders', v_rows
  );
end;
$function$;
do $do$
begin
  execute format('comment on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, integer, text, text, text) is %L',
    coalesce(obj_description('app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, integer, text, text, text)'::regprocedure, 'pg_proc') || ' ', '')
    || 'ORDER-EDIT-001G (API_CONTRACT §4.47a): every row also carries edit_count (orders.edit_count) and has_active_round (any live service round of the order in submitted..ready, the app.void_order predicate; probed for page rows only). Nothing else changed.');
end;
$do$;

-- ACLs re-stated VERBATIM from 20261008170200 (REPORT-123: the app.* body sits
-- behind a SECURITY INVOKER public wrapper, so authenticated keeps EXECUTE).
revoke all on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text)    from public;
revoke all on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text)    from anon;
grant execute on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 2. app.owner_order_history — re-emitted from its LIVE body
--    (20261008170200_order_edit_001a_reemits section 6) with ONLY: o.edit_count
--    in the matched CTE, and edit_count + has_active_round on every row.
-- ----------------------------------------------------------------------------
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
           o.edit_count,                                         -- ORDER-EDIT-001G
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
        -- ORDER-EDIT-001A: a line RETIRED by an order edit is replaced by its
        -- remainder / replacement rows; counting both would inflate the count.
        and oi.removed_by_edit_id is null
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
               'paid_amount_minor',    n.paid_amount_minor,
               -- ORDER-EDIT-001G (API_CONTRACT §4.47a): additive, money-free.
               -- has_active_round = any live service round of the order in
               -- submitted..ready (the app.void_order live-round predicate),
               -- probed for the page rows only.
               'edit_count',           n.edit_count,
               'has_active_round',     exists (
                                         select 1 from public.order_service_rounds ar
                                          where ar.organization_id = p_organization_id
                                            and ar.order_id        = n.id
                                            and ar.deleted_at is null
                                            and ar.status in ('submitted', 'accepted', 'preparing', 'ready')))
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
do $do$
begin
  execute format('comment on function app.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, integer, text, date, date) is %L',
    coalesce(obj_description('app.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, integer, text, date, date)'::regprocedure, 'pg_proc') || ' ', '')
    || 'ORDER-EDIT-001G (API_CONTRACT §4.47a): every row also carries edit_count (orders.edit_count) and has_active_round (any live service round of the order in submitted..ready, the app.void_order predicate; probed for page rows only). Nothing else changed.');
end;
$do$;

revoke all on function app.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text, date, date) from public;
revoke all on function app.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text, date, date) from anon;
grant execute on function app.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text, date, date) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. app.owner_order_detail — re-emitted from its LIVE body
--    (20261008170200_order_edit_001a_reemits section 6b) with ONLY: order +
--    edit_count, has_active_round, active_rounds_ready and edits[]. The items
--    list (lines without removed_by_edit_id) is unchanged.
-- ----------------------------------------------------------------------------
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
  v_edits    jsonb;   -- ORDER-EDIT-001G: the order's edits
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
      'customer_phone',       o.customer_phone,
      'table_label',          tbl.label,
      'branch_name',          b.name,
      'staff_name',           ep.display_name,
      'notes',                o.notes,
      'created_at',           to_char(o.created_at at time zone coalesce(b.timezone, r.timezone, 'UTC'), 'YYYY-MM-DD HH24:MI'),
      'currency_code',        o.currency_code,
      'subtotal_minor',       o.subtotal_minor,
      'discount_total_minor', o.discount_total_minor,
      'tax_total_minor',      o.tax_total_minor,
      'grand_total_minor',    o.grand_total_minor,
      -- ORDER-EDIT-001G (API_CONTRACT §4.47a): additive, money-free.
      -- has_active_round = any live service round of the order in
      -- submitted..ready (the app.void_order live-round predicate);
      -- active_rounds_ready = there is one, and every such round is ready
      -- (the drawer then says Ready where the lists say In kitchen).
      'edit_count',           o.edit_count,
      'has_active_round',     exists (
                                select 1 from public.order_service_rounds ar
                                 where ar.organization_id = o.organization_id
                                   and ar.order_id        = o.id
                                   and ar.deleted_at is null
                                   and ar.status in ('submitted', 'accepted', 'preparing', 'ready')),
      'active_rounds_ready',  exists (
                                select 1 from public.order_service_rounds ar
                                 where ar.organization_id = o.organization_id
                                   and ar.order_id        = o.id
                                   and ar.deleted_at is null
                                   and ar.status in ('submitted', 'accepted', 'preparing', 'ready'))
                              and not exists (
                                select 1 from public.order_service_rounds ar
                                 where ar.organization_id = o.organization_id
                                   and ar.order_id        = o.id
                                   and ar.deleted_at is null
                                   and ar.status in ('submitted', 'accepted', 'preparing')))
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
    and oi.deleted_at is null
    -- ORDER-EDIT-001A: a line RETIRED by an order edit is replaced by its
    -- remainder / replacement rows; listing both would double the lines and
    -- make the line totals disagree with the order subtotal.
    and oi.removed_by_edit_id is null;

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

  -- ORDER-EDIT-001G (API_CONTRACT §4.47a): the order's edits, oldest first.
  -- Money-free, and no order_edit_id, staff, device, session or membership
  -- identifier. Times are branch-local display strings (the drawer's
  -- convention). kitchen_ack_pending is the ORDER-EDIT-001B rule: a required
  -- kitchen confirmation not yet given, FALSE on a voided order (§4.46).
  select coalesce(jsonb_agg(jsonb_build_object(
           'edit_number',          e.edit_number,
           'created_at',           to_char(e.created_at at time zone v_zone, 'YYYY-MM-DD HH24:MI'),
           'reason_code',          e.reason_code,
           'reason_text',          e.reason_text,
           'kitchen_channel',      e.kitchen_channel,
           'kitchen_ack_required', e.kitchen_ack_required,
           'kitchen_ack_at',       to_char(e.kitchen_ack_at at time zone v_zone, 'YYYY-MM-DD HH24:MI'),
           'kitchen_ack_pending',  e.kitchen_ack_required
                                   and e.kitchen_ack_at is null
                                   and (v_order ->> 'status') <> 'voided'
         ) order by e.edit_number asc), '[]'::jsonb)
    into v_edits
  from public.order_edits e
  where e.organization_id = p_organization_id
    and e.order_id        = p_order_id
    and e.deleted_at is null;

  return jsonb_build_object(
    'ok', true,
    'entity', 'owner_order_detail',
    'currency_code', v_currency,
    'order', v_order
      || jsonb_build_object('items', v_items, 'payments', v_payments, 'edits', v_edits)
  );
end;
$$;
do $do$
begin
  execute format('comment on function app.owner_order_detail(uuid, uuid, uuid, uuid) is %L',
    coalesce(obj_description('app.owner_order_detail(uuid, uuid, uuid, uuid)'::regprocedure, 'pg_proc') || ' ', '')
    || 'ORDER-EDIT-001G (API_CONTRACT §4.47a): order also carries edit_count, has_active_round (any live service round in submitted..ready), active_rounds_ready (there is one and every such round is ready) and edits[] {edit_number, created_at, reason_code, reason_text, kitchen_channel, kitchen_ack_required, kitchen_ack_at, kitchen_ack_pending}, oldest first, branch-local times, money-free and with no order_edit_id or staff / device / session / membership id. Nothing else changed.');
end;
$do$;

revoke all on function app.owner_order_detail(uuid, uuid, uuid, uuid) from public;
revoke all on function app.owner_order_detail(uuid, uuid, uuid, uuid) from anon;
grant execute on function app.owner_order_detail(uuid, uuid, uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 4. NEW app.get_branch_order_edit_settings — member READ of the two §4.45.8
--    switches (plus kitchen_workflow_mode, for the printer-only note), the
--    get_branch_kitchen_workflow_mode shape (KITCHEN-MODE-001A). Any active
--    membership covering the branch may read; the setter stays owner-gated.
--    A null argument, no covering membership (another tenant's branch
--    included), a nonexistent branch and a deleted branch or restaurant all
--    return the SAME not_found (no existence oracle, RISK R-003).
-- ----------------------------------------------------------------------------
create or replace function app.get_branch_order_edit_settings(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor   uuid := app.current_app_user_id();
  v_rank    integer;
  v_enabled boolean;
  v_ff      boolean;
  v_mode    text;
begin
  if v_actor is null then
    raise exception 'get_branch_order_edit_settings: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    -- no membership covering this scope (incl. cross-tenant): reveal nothing.
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  select b.order_edit_enabled, b.order_edit_finished_food_manager_only, b.kitchen_workflow_mode
    into v_enabled, v_ff, v_mode
    from public.branches b
    join public.restaurants r
      on r.organization_id = b.organization_id
     and r.id              = b.restaurant_id
     and r.deleted_at is null
    where b.id = p_branch_id and b.organization_id = p_organization_id
      and b.restaurant_id = p_restaurant_id and b.deleted_at is null;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  return jsonb_build_object('ok', true, 'entity', 'branch', 'branch_id', p_branch_id,
                            'order_edit_enabled',                    v_enabled,
                            'order_edit_finished_food_manager_only', v_ff,
                            'kitchen_workflow_mode',                 v_mode);
end;
$$;

comment on function app.get_branch_order_edit_settings(uuid, uuid, uuid) is
  'ORDER-EDIT-001G (D-043/D-044; API_CONTRACT §4.47a): member READ of branches.order_edit_enabled, branches.order_edit_finished_food_manager_only and branches.kitchen_workflow_mode for the Dashboard settings toggles. Any active membership covering the branch (app.actor_rank_in_scope > 0) may read; unauthenticated => 42501; a null argument, no covering membership (cross-tenant included), a nonexistent or a deleted branch or restaurant => the same {ok:false, error:not_found, entity:branch} (no existence oracle). READ-ONLY; the writer is app.set_branch_order_edit_settings (owner-gated).';

create or replace function public.get_branch_order_edit_settings(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.get_branch_order_edit_settings(p_organization_id, p_restaurant_id, p_branch_id); $$;

comment on function public.get_branch_order_edit_settings(uuid, uuid, uuid) is
  'ORDER-EDIT-001G: thin SECURITY INVOKER wrapper over app.get_branch_order_edit_settings. authenticated only; PUBLIC and anon revoked (D-037).';

revoke all on function app.get_branch_order_edit_settings(uuid, uuid, uuid) from public;
revoke all on function app.get_branch_order_edit_settings(uuid, uuid, uuid) from anon;
grant execute on function app.get_branch_order_edit_settings(uuid, uuid, uuid) to authenticated;
revoke all on function public.get_branch_order_edit_settings(uuid, uuid, uuid) from public;
revoke all on function public.get_branch_order_edit_settings(uuid, uuid, uuid) from anon;
grant execute on function public.get_branch_order_edit_settings(uuid, uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- The re-emits and the new reader never broaden either global public surface
-- (D-037). These assertions match ORDER-EDIT-001A / 001B and pending #288 in
-- either apply order.
-- ----------------------------------------------------------------------------
do $$
declare
  v_anon_set text;
  v_defs text;
begin
  select coalesce(string_agg(regexp_replace(p.oid::regprocedure::text, '^public\.', ''), ', '
    order by regexp_replace(p.oid::regprocedure::text, '^public\.', '')), '')
    into v_anon_set from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
      and has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_anon_set <> 'storefront_menu(text)' then
    raise exception 'ORDER-EDIT-001G: unexpected anon public surface [%]', v_anon_set;
  end if;
  select coalesce(string_agg(regexp_replace(p.oid::regprocedure::text, '^public\.', ''), ', '
    order by regexp_replace(p.oid::regprocedure::text, '^public\.', '')), '')
    into v_defs from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') and p.prosecdef;
  if v_defs <> 'storefront_menu(text)' then
    raise exception 'ORDER-EDIT-001G: unexpected public DEFINER surface [%]', v_defs;
  end if;
  if has_schema_privilege('anon', 'app', 'USAGE') then
    raise exception 'ORDER-EDIT-001G: anon has app schema usage';
  end if;
end;
$$;
