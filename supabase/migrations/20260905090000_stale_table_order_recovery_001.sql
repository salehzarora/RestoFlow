-- ============================================================================
-- STALE-TABLE-ORDER-RECOVERY-001 - stale active dine-in orders must stay
-- RECOVERABLE, never silently freed.
--
-- INCIDENT (2026-09-04): two kiosk dine-in orders (#8DD505, #4D068F) sat in
-- `submitted`, unpaid, for days and kept their tables occupied. Occupancy is
-- DERIVED from orders (correctly, with no age cutoff) - but the POS's only
-- order surface is a today+yesterday window (pos_order_snapshots window +
-- local prune), so once an unsettled order aged past yesterday the cashier saw
-- "1 open order" on the table with NO way to identify, open, pay or cancel it.
-- The Dashboard could list it but has no void, and `owner_complete_order` is
-- an illegal transition from `submitted`.
--
-- THE FIX IS READ-SIDE ONLY. No new mutation, no age cutoff, no automatic
-- release, no table_id / tables.status edits. Two ADDITIVE JSON keys:
--
--   * app.pos_tables rows gain `active_orders` - the SAME rows that make
--     `active_order_count`, projected (money-free) so the cashier can OPEN
--     them through the existing by-id snapshot fetch (pos_order_snapshots with
--     p_order_ids bypasses the window) and then use the CANONICAL operations:
--     app.void_order (unpaid + authorized) or app.record_payment (which
--     auto-completes on full settlement). The table frees as a CONSEQUENCE.
--   * app.owner_active_orders rows gain `shift_status` + `kitchen_work_open`
--     so the Dashboard can FLAG stale / closed-shift / paid-not-completed /
--     no-kitchen-work orders. Display only; the read never mutates.
--
-- Both functions are re-emitted from their LIVE bodies with ONLY the marked
-- additions; every existing key, predicate, ordering and ACL is unchanged.
-- ============================================================================

CREATE OR REPLACE FUNCTION app.pos_tables(p_pin_session_id uuid, p_device_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_org        uuid;
  v_rest       uuid;
  v_branch     uuid;
  v_dsid       uuid;
  v_emp        uuid;
  v_membership uuid;
  v_ds_device  uuid;
  v_ds_active  boolean;
  v_ds_revoked timestamptz;
  v_pairing    text;
  v_role       text;
  v_m_status   text;
  v_m_deleted  timestamptz;
  v_tables     jsonb;
  v_elements   jsonb;
  v_kitchen_mode text;  -- STALE-TABLE-ORDER-RECOVERY-001: for kitchen_work_open
begin
  -- (a) PIN session + backing device session/pairing active; device match (A8).
  --     Scope (org/restaurant/branch) + actor + role are derived HERE, never from payload.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'pos_tables: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'pos_tables: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'pos_tables: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'pos_tables: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'pos_tables: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) the SESSION branch's live, active tables. Money-free by nature â€” every
  --     PIN role (kitchen included) receives the same rows (no redaction).
  --     RESTAURANT-OPERATIONS-V1-001: active_order_count = DERIVED occupancy.
  --     TABLE-FLOOR-LAYOUT-021: section_id/section_name/section_display_order
  --     + layout_x/layout_y ADDED (all nullable; a legacy row simply carries
  --     nulls and the client keeps its area-text fallback zone). The joined
  --     section is live-only: a tombstoned section can no longer be referenced
  --     (delete detaches), so the join is belt-and-braces.
  --     118: visual_preset + section_floor_preset (nullable presentation keys).
  --     120: visual_material (nullable; NULL = Auto).
  --     121: section_room_frame_preset (nullable; NULL = Standard room).
  -- STALE-TABLE-ORDER-RECOVERY-001: the branch's kitchen workflow mode, read
  -- ONCE; a missing row fails CLOSED to 'kds' (the historical behavior).
  select b.kitchen_workflow_mode into v_kitchen_mode
    from public.branches b
    where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;
  v_kitchen_mode := coalesce(v_kitchen_mode, 'kds');

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'label', t.label, 'seats', t.seats, 'area', t.area, 'status', t.status,
           'active_order_count', coalesce(oc.n, 0),
           'effective_state', app.table_effective_state(t.status, coalesce(oc.n, 0)),
           'group_id', gm.group_id,
           'section_id', t.section_id,
           'section_name', s.name,
           'section_display_order', s.display_order,
           'layout_x', t.layout_x,
           'layout_y', t.layout_y,
           'visual_preset', t.visual_preset,
           'visual_material', t.visual_material,
           'section_floor_preset', s.floor_preset,
           'section_room_frame_preset', s.room_frame_preset,
           -- STALE-TABLE-ORDER-RECOVERY-001: the SAME rows that make
           -- active_order_count, projected so a cashier can IDENTIFY and OPEN
           -- them. MONEY-FREE on purpose (every PIN role reads pos_tables):
           -- ids/codes/state only; amounts come from pos_order_snapshots.
           'active_orders', coalesce(ao.orders, '[]'::jsonb))
           order by t.label, t.id), '[]'::jsonb)
    into v_tables
    from public.tables t
    left join public.table_group_members gm
      on gm.organization_id = t.organization_id and gm.table_id = t.id
    left join public.table_sections s
      on s.id = t.section_id and s.organization_id = t.organization_id
     and s.deleted_at is null
    left join (
      select o.table_id, count(*)::int as n
        from public.orders o
        where o.organization_id = v_org
          and o.branch_id       = v_branch
          -- REVIEW CORRECTION (B1): only DINE-IN orders occupy a table.
          -- Historical takeaway rows may carry a table_id from the pre-phase
          -- contract; they must never count toward floor occupancy.
          and o.order_type      = 'dine_in'
          and o.table_id is not null
          and o.deleted_at is null
          and o.status in ('submitted', 'accepted', 'preparing', 'ready', 'served')
        group by o.table_id
    ) oc on oc.table_id = t.id
    left join (
      -- STALE-TABLE-ORDER-RECOVERY-001: byte-identical occupancy predicate to
      -- `oc` above (dine-in, table set, live, ACTIVE status; NO age cutoff).
      select o.table_id,
             jsonb_agg(jsonb_build_object(
               'order_id',   o.id,
               'order_code', '#' || upper(right(replace(o.id::text, '-', ''), 6)),
               'status',     o.status,
               'order_type', o.order_type,
               'revision',   o.revision,
               'created_at', to_char(o.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
               -- the ONE settlement predicate (never a client flag); the three
               -- honest states owner_active_orders already uses
               'payment_status', case when not (o.grand_total_minor > 0) then 'not_chargeable'
                                      when app.order_is_fully_settled(o.organization_id, o.id) then 'paid'
                                      else 'unpaid' end,
               -- originating shift state (NULL: no shift, e.g. a kiosk order);
               -- record_payment settles under the paying device's CURRENT open
               -- shift, so a closed originating shift never blocks recovery
               'shift_status', sh.status,
               -- is the kitchen still holding this order? kds mode: any
               -- in-progress status is a live KDS ticket; any mode: an
               -- unresolved print dispatch or a service round not yet served
               'kitchen_work_open',
                 (v_kitchen_mode = 'kds' and o.status in ('submitted', 'accepted', 'preparing', 'ready'))
                 or exists (select 1 from public.kitchen_print_dispatches k
                             where k.organization_id = o.organization_id and k.order_id = o.id
                               and k.completed_at is null and k.superseded_by_dispatch_id is null)
                 or exists (select 1 from public.order_service_rounds r
                             where r.organization_id = o.organization_id and r.order_id = o.id
                               and r.deleted_at is null and r.status not in ('served', 'voided')))
               order by o.created_at, o.id) as orders
        from public.orders o
        left join public.shifts sh
          on sh.organization_id = o.organization_id and sh.id = o.shift_id
        where o.organization_id = v_org
          and o.branch_id       = v_branch
          and o.order_type      = 'dine_in'
          and o.table_id is not null
          and o.deleted_at is null
          and o.status in ('submitted', 'accepted', 'preparing', 'ready', 'served')
        group by o.table_id
    ) ao on ao.table_id = t.id
    where t.organization_id = v_org
      and t.restaurant_id   = v_rest
      and t.branch_id       = v_branch
      and t.is_active
      and t.deleted_at is null;

  -- TABLE-FLOOR-MAP-POLISH-027: the branch's live fixtures ride along as a
  -- CATALOG array (visual-only; money-free; same rows for every PIN role).
  -- Live-section join is belt-and-braces: section delete tombstones fixtures.
  -- 120: + visual_style.
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', e.id, 'section_id', e.section_id, 'kind', e.kind,
           'layout_x', e.layout_x, 'layout_y', e.layout_y,
           'width_norm', e.width_norm, 'height_norm', e.height_norm,
           'orientation_quarter_turns', e.orientation_quarter_turns,
           'label', e.label,
           'visual_style', e.visual_style)
           order by e.created_at, e.id), '[]'::jsonb)
    into v_elements
    from public.table_floor_elements e
    join public.table_sections s
      on s.id = e.section_id and s.organization_id = e.organization_id
     and s.deleted_at is null
    where e.organization_id = v_org
      and e.restaurant_id   = v_rest
      and e.branch_id       = v_branch
      and e.deleted_at is null;

  return jsonb_build_object(
    'ok', true,
    'entity', 'tables',
    'tables', v_tables,
    'floor_elements', v_elements,
    'server_ts', now());
end;
$function$;

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
           sh.status                               as shift_status,
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
               'kitchen_work_open', n.kitchen_work_open)
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

-- ACLs: re-stated VERBATIM from the owning migrations (mvp_dining_tables for
-- pos_tables; active_orders_002 for owner_active_orders). Both app.* bodies
-- sit behind SECURITY INVOKER public wrappers, so `authenticated` MUST keep
-- EXECUTE on the app.* functions (REPORT-123: an ungranted inner behind an
-- invoker wrapper is a silent 42501 for every caller).
revoke all on function app.pos_tables(uuid, uuid)    from public;
grant execute on function app.pos_tables(uuid, uuid) to authenticated;
revoke all on function public.pos_tables(uuid, uuid)    from public;
grant execute on function public.pos_tables(uuid, uuid) to authenticated;

revoke all on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text)    from public;
revoke all on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text)    from anon;
grant execute on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text) to authenticated;
revoke all on function public.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text)    from public;
revoke all on function public.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text)    from anon;
grant execute on function public.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text) to authenticated;
