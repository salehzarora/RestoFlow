-- ============================================================================
-- ACTIVE-ORDERS-002 — operational QUEUES + server-side SORT + keyset pagination
-- for the read-only active-orders board.
--
-- WHY: in production the board shows ~133 active orders of which ~127 are
-- `served` (awaiting close) and ~0 are `ready`. The board therefore LOOKS like
-- Order History, and the six orders actually moving through preparation are
-- buried. It is also OLDEST-first and CAPPED at 100, so the operator sees the
-- oldest 100 of 133 and the 33 NEWEST orders are never fetched at all.
--
-- A client-side re-sort CANNOT fix that: reversing the returned page would only
-- reverse the oldest 100 — the newest 33 are not in the payload. Sorting must be
-- AUTHORITATIVE and SERVER-SIDE. Same for the queues: the existing `p_status` is
-- a SINGLE-VALUE equality filter and cannot express a status GROUP.
--
-- THIS MIGRATION (read-only; no write path, no new audit action):
--   * p_queue  — in_progress (submitted/accepted/preparing/ready)
--                awaiting_close (served)
--                all_active (all five) — the default, so every existing caller
--                keeps its exact behaviour.
--   * p_sort   — 'newest' (created_at desc, id desc) | 'oldest' (asc, asc).
--   * p_cursor — keyset continuation, TAGGED WITH ITS SORT ("<sort>|<ts>|<id>"),
--                so a cursor minted under one direction can NEVER be replayed
--                under the other (it is rejected, not silently mis-paged).
--   * summary  — now also carries the explicit in_progress / awaiting_close
--                counts the queue cards render. Still SCOPE-wide (never the page,
--                never the filters), so the cards stay stable while the operator
--                narrows the list.
--   * has_more / next_cursor — the board can now page BEYOND the cap instead of
--                silently ending at 100.
--
-- The three new parameters are APPENDED AFTER p_limit with backward-compatible
-- defaults, so every existing positional caller and every existing pgTAP
-- assertion keeps its meaning. Postgres cannot add parameters to an existing
-- function in place (the arity changes), so the old signature is DROPPED and the
-- new one created — the repo's established DROP+recreate rule for a widened RPC.
-- There is NO second, competing active-orders RPC.
--
-- UNCHANGED: the canonical ACTIVE set (submitted/accepted/preparing/ready/served;
-- terminal completed/cancelled/voided and local-only draft excluded), the
-- authorization block, the safe column projection, integer-minor money, the
-- branch-timezone resolution, the page-size cap, and the authenticated-only /
-- anon-revoked ACL. No table, column, CHECK, RLS policy, trigger, index, order
-- row, payment row, audit writer or lifecycle transition is touched.
--
-- Additive / forward-only. PENDING: RISK R-003 sign-off. NOT applied to hosted.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Drop the ACTIVE-ORDERS-001 signature (the arity changes; see the header).
-- ---------------------------------------------------------------------------
drop function if exists public.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int);
drop function if exists app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int);

-- ---------------------------------------------------------------------------
-- 2. app.owner_active_orders — queues + server-side sort + keyset pagination.
-- ---------------------------------------------------------------------------
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

  select o.default_currency into v_currency
    from public.organizations o
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
               'payment_method',    n.payment_method,
               'payment_status',    case when n.is_paid then 'paid' else 'unpaid' end,
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

comment on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text) is
  'ACTIVE-ORDERS-001 + ACTIVE-ORDERS-002 (READ-ONLY; D-007/D-008/D-011/D-018/D-020/D-025): the owner/manager Dashboard active-order operations board. Returns orders in the CANONICAL ACTIVE set (submitted/accepted/preparing/ready/served; terminal completed/cancelled/voided and local-only draft excluded) in the caller''s scope, with NO date window. QUEUES (a presentation grouping OVER the canonical states, not a new taxonomy): p_queue = in_progress (submitted/accepted/preparing/ready) | awaiting_close (served) | all_active (default; every existing caller is unchanged). SORT is AUTHORITATIVE and SERVER-SIDE: p_sort = newest (created_at desc, id desc; the Dashboard default) | oldest (asc, asc) — a client can never re-sort a capped page, because the un-fetched rows are not in the payload. KEYSET pagination: p_cursor is TAGGED with its sort ("<sort>|<created_at>|<id>") and is REJECTED (22023) if replayed under the other direction; id breaks ties so equal timestamps paginate stably; has_more/next_cursor page beyond the cap; p_limit CAPPED 1..200. A p_status filter must be an active status AND sit inside p_queue (else 22023). Same authorization as owner_order_history (actor_rank_in_scope over the PASSED scope, 0 -> 42501; GUC-free financial-read allowlist; kitchen_staff -> permission_denied). `summary` (total / unpaid / in_progress / awaiting_close / by_status) covers the SCOPE — never the page and never the filters — so the queue cards stay stable. `matching` is the FULL filtered count, never the loaded page. Money is integer minor units read from the stored snapshot. Payment status is a SEPARATE axis (D-025): a paid order stays active, and an unpaid served order belongs to awaiting_close. Returns created_at (branch-local) + created_at_utc (absolute) + timezone for ELAPSED time; there is NO promised/due field in the schema, so this NEVER reports "late" and ranks by nothing but time. Safe columns only. Scope-safe; no anon/service_role.';

-- ---------------------------------------------------------------------------
-- 3. Thin public SECURITY INVOKER wrapper — the PostgREST-reachable surface.
-- ---------------------------------------------------------------------------
create or replace function public.owner_active_orders(
  p_organization_id uuid, p_restaurant_id uuid default null,
  p_branch_id uuid default null, p_status text default null,
  p_order_type text default null, p_payment text default null,
  p_search text default null, p_limit int default 100,
  p_queue text default 'all_active', p_sort text default 'newest',
  p_cursor text default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.owner_active_orders(
  p_organization_id, p_restaurant_id, p_branch_id, p_status,
  p_order_type, p_payment, p_search, p_limit, p_queue, p_sort, p_cursor); $$;

-- ---------------------------------------------------------------------------
-- 4. Grants: authenticated ONLY. `anon` is revoked EXPLICITLY on both (a
--    revoke-from-PUBLIC does NOT remove the grant hosted Supabase's ALTER
--    DEFAULT PRIVILEGES hands to anon at CREATE time). Never service_role (D-011).
-- ---------------------------------------------------------------------------
revoke all on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text)    from public;
revoke all on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text)    from anon;
grant execute on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text) to authenticated;

revoke all on function public.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text)    from public;
revoke all on function public.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text)    from anon;
grant execute on function public.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text) to authenticated;

-- The ACTIVE-ORDERS-001 partial index already serves this board exactly:
--   orders_active_ops_idx (organization_id, branch_id, created_at, id)
--     WHERE deleted_at IS NULL AND status IN (the five active values)
-- A btree scans backwards, so the SAME index serves BOTH sort directions. No new
-- index is added.

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists public.owner_active_orders(uuid,uuid,uuid,text,text,text,text,int,text,text,text);
--   drop function if exists app.owner_active_orders(uuid,uuid,uuid,text,text,text,text,int,text,text,text);
--   -- then restore the 8-arg ACTIVE-ORDERS-001 signature from 20260712090000.
-- ============================================================================
