-- ============================================================================
-- MENU-ORDER-001 — menu-configured PRINT ordering: order-time display-order
-- snapshots + the drag-and-drop reorder RPC.
--
-- Every print surface (customer receipt, POS + KDS kitchen tickets, and every
-- reprint) must list items in the owner's DASHBOARD-CONFIGURED order:
--     1. category display order,
--     2. item display order within that category,
--     3. the order line's original position (line_position, 001D) as a
--        deterministic tie-breaker,
-- and an item's modifiers in:
--     1. modifier-group display order,
--     2. modifier-option display order,
--     3. the modifier's original position (line_position) as a tie-breaker.
-- Cart insertion order is NO LONGER the primary print order.
--
-- To make that order stable + IMMUTABLE (D-008: never re-derive from the live
-- menu at print time, which may have been reordered since), the configured
-- ranks are SNAPSHOTTED onto each order line + modifier at submit, server-side,
-- from the authoritative menu/category records — NEVER from client-supplied
-- values. Populated by BEFORE INSERT triggers so EVERY production insert path
-- (app.submit_order, app.add_order_items, service-round inserts, any future
-- path) is covered without touching those large RPCs (no stacked-definition
-- rewrite). Those RPCs insert order_items + order_item_modifiers ROW BY ROW, so
-- the modifier line_position tie-breaker's max()+1 is per-row correct.
--
--   PART 1  order_items.category_display_order_snapshot + item_display_order_snapshot
--   PART 2  order_item_modifiers.modifier_group_display_order_snapshot +
--           modifier_option_display_order_snapshot (+ the line_position ordinal)
--   PART 3  app.menu_reorder — atomic display_order rewrite for a sibling set
--
-- Additive + forward-only. No reset, no destructive backfill, no change to any
-- shipped migration. Historical order rows keep the new columns at 0 (a legacy
-- sentinel) and are UNTOUCHED; readers fall back to line_position + original
-- input order for those. The already-shipped 20260730090000
-- order_items.line_position migration is NOT modified. app.sync_pull returns
-- whole rows (`to_jsonb(t)`), so the new snapshot columns flow to the KDS with
-- NO change to the sync contract or the (updated_at, id) cursor.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PART 1. order_items: snapshot the item's CATEGORY rank + ITEM-within-category
--         rank at submit -> the primary + secondary keys of the menu-configured
--         print order (line_position, 001D, is the tie-breaker).
-- ----------------------------------------------------------------------------
alter table public.order_items
  add column if not exists category_display_order_snapshot integer not null default 0;
alter table public.order_items
  add column if not exists item_display_order_snapshot integer not null default 0;

comment on column public.order_items.category_display_order_snapshot is
  'MENU-ORDER-001: snapshot of the item''s category rank '
  '(menu_categories.display_order) at submit, assigned by the '
  'assign_order_item_display_order_snapshot trigger. 0 = legacy/unknown. PRIMARY '
  'key of the menu-configured PRINT order (then item_display_order_snapshot, '
  'then line_position). Immutable; never re-derived from the live menu at print '
  'time (D-008). Non-money.';
comment on column public.order_items.item_display_order_snapshot is
  'MENU-ORDER-001: snapshot of the item''s rank within its category '
  '(menu_items.display_order) at submit. 0 = legacy/unknown. SECONDARY key of '
  'the menu-configured PRINT order. Non-money.';

create or replace function app.assign_order_item_display_order_snapshot()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_item_order integer;
  v_cat_order  integer;
begin
  -- ALWAYS derive server-side from the authoritative menu (D-008: never trust a
  -- client-supplied display order). submit_order already holds this menu_items
  -- row (FOR UPDATE availability check) in the same transaction. Scoped to
  -- (organization_id, menu_item_id); a missing item/category yields 0 (the
  -- legacy sentinel -> readers fall back to line_position + original input
  -- order). Runs on EVERY order_items insert (submit / add_order_items / rounds).
  select mi.display_order, mc.display_order
    into v_item_order, v_cat_order
    from public.menu_items mi
    left join public.menu_categories mc
      on mc.organization_id = mi.organization_id
     and mc.id = mi.menu_category_id
   where mi.organization_id = new.organization_id
     and mi.id = new.menu_item_id
   limit 1;
  new.item_display_order_snapshot := coalesce(v_item_order, 0);
  new.category_display_order_snapshot := coalesce(v_cat_order, 0);
  return new;
end;
$$;

comment on function app.assign_order_item_display_order_snapshot() is
  'MENU-ORDER-001: BEFORE INSERT trigger fn — snapshots the item''s category + '
  'within-category menu ranks onto order_items at submit. Non-money; never a key.';

revoke all on function app.assign_order_item_display_order_snapshot() from public;

-- Defensive: drop the earlier (unshipped) single-rank trigger/fn name if a prior
-- local apply of THIS migration created it, so exactly one snapshot trigger runs.
drop trigger if exists assign_order_item_menu_display_order on public.order_items;
drop function if exists app.assign_order_item_menu_display_order();
drop trigger if exists assign_order_item_display_order_snapshot on public.order_items;
create trigger assign_order_item_display_order_snapshot
  before insert on public.order_items
  for each row
  execute function app.assign_order_item_display_order_snapshot();

-- ----------------------------------------------------------------------------
-- PART 2. order_item_modifiers: snapshot the modifier GROUP rank + OPTION rank,
--         plus a stable per-item modifier ordinal (line_position) tie-breaker,
--         so every surface prints an item's modifiers in Dashboard group/option
--         order regardless of the sequence the writer inserted them.
-- ----------------------------------------------------------------------------
alter table public.order_item_modifiers
  add column if not exists line_position integer not null default 0;
alter table public.order_item_modifiers
  add column if not exists modifier_group_display_order_snapshot integer not null default 0;
alter table public.order_item_modifiers
  add column if not exists modifier_option_display_order_snapshot integer not null default 0;

comment on column public.order_item_modifiers.line_position is
  'MENU-ORDER-001: stable per-order-item modifier ordinal (1-based) in insertion '
  'order, assigned by assign_order_item_modifier_order_snapshot. 0 = legacy row. '
  'TIE-BREAKER of the modifier PRINT order (after group + option display order). '
  'Non-money.';
comment on column public.order_item_modifiers.modifier_group_display_order_snapshot is
  'MENU-ORDER-001: snapshot of the modifier GROUP rank (modifiers.display_order) '
  'at submit. 0 = legacy/unknown. PRIMARY key of the modifier PRINT order. '
  'Immutable; never re-derived at print time (D-008). Non-money.';
comment on column public.order_item_modifiers.modifier_option_display_order_snapshot is
  'MENU-ORDER-001: snapshot of the modifier OPTION rank '
  '(modifier_options.display_order) at submit. 0 = legacy/unknown. SECONDARY key '
  'of the modifier PRINT order. Non-money.';

create or replace function app.assign_order_item_modifier_order_snapshot()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_opt_order   integer;
  v_group_order integer;
begin
  -- 1) the stable per-item ordinal (insertion order) -> the TIE-BREAKER. ALWAYS
  --    server-derived: ANY client-supplied line_position is IGNORED (never trust
  --    a submitted ordering field). Lock the PARENT order_items row FOR UPDATE
  --    first, so concurrent modifier inserts for the SAME item cannot receive a
  --    duplicate ordinal; different order_items never contend (row-level lock).
  --    max()+1 then serializes correctly. (Within one submit txn the parent was
  --    just inserted, so the lock is instant.)
  perform 1 from public.order_items oi
    where oi.organization_id = new.organization_id
      and oi.id             = new.order_item_id
    for update;
  new.line_position := coalesce(
    (select max(oim.line_position)
       from public.order_item_modifiers oim
      where oim.organization_id = new.organization_id
        and oim.order_item_id   = new.order_item_id),
    0) + 1;
  -- 2) the group + option menu ranks, ALWAYS derived server-side from the
  --    authoritative menu (never a client-supplied value; D-008). A missing
  --    option/group yields 0 (readers fall back to line_position).
  select mo.display_order, m.display_order
    into v_opt_order, v_group_order
    from public.modifier_options mo
    left join public.modifiers m
      on m.organization_id = mo.organization_id
     and m.id = mo.modifier_id
   where mo.organization_id = new.organization_id
     and mo.id = new.modifier_option_id
   limit 1;
  new.modifier_option_display_order_snapshot := coalesce(v_opt_order, 0);
  new.modifier_group_display_order_snapshot := coalesce(v_group_order, 0);
  return new;
end;
$$;

comment on function app.assign_order_item_modifier_order_snapshot() is
  'MENU-ORDER-001: BEFORE INSERT trigger fn — assigns '
  'order_item_modifiers.line_position (insertion order) + snapshots the group/'
  'option menu ranks. Non-money.';

revoke all on function app.assign_order_item_modifier_order_snapshot() from public;

-- Defensive: drop the earlier (unshipped) line_position-only trigger/fn name.
drop trigger if exists assign_order_item_modifier_line_position on public.order_item_modifiers;
drop function if exists app.assign_order_item_modifier_line_position();
drop trigger if exists assign_order_item_modifier_order_snapshot on public.order_item_modifiers;
create trigger assign_order_item_modifier_order_snapshot
  before insert on public.order_item_modifiers
  for each row
  execute function app.assign_order_item_modifier_order_snapshot();

-- ----------------------------------------------------------------------------
-- PART 3. app.menu_reorder — atomic display_order rewrite for a complete
--         sibling set (menu_category / menu_item / modifier / modifier_option).
--
-- SECURITY + CONCURRENCY (Codex MENU-ORDER-001 review, 2nd/3rd correction):
--  * REAL PRODUCTION AUTH CONTRACT (identical to the 7 menu_upsert_* RPCs, the
--    RF-109/MVP D-033 pattern): identity = app.current_app_user_id() (auth.uid()
--    for real JWTs, GUC only in tests); authority = app.menu_guard() ->
--    app.actor_rank_in_scope() over the CALLER-PASSED (org, restaurant, branch)
--    scope. NO app.current_org_id()/GUC (no production client sets it) and NO
--    hand-rolled memberships/role query. The scope is a PARAMETER, so the guard
--    runs BEFORE any id is inspected.
--  * NO EXISTENCE ORACLE: every id-level failure (foreign tenant / other
--    restaurant / other branch / other parent / missing / deleted / incomplete /
--    mixed / duplicate) raises ONE generic 'invalid request' (42501). The caller
--    NEVER sees a matched count, an expected sibling count, a parent id, or an
--    "exists but unauthorized" distinction. A covering member below manager gets
--    {ok:false, error:'permission_denied'} + a server-only audit row.
--  * PostgreSQL-17 SAFE: NO min(uuid)/max(uuid). The sibling PARENT is resolved
--    deterministically (order by id limit 1) WITHIN the authorized scope.
--  * NO STALE FOUND: PL/pgSQL FOUND is NOT set by EXECUTE, so every dynamic
--    statement reports through EXECUTE ... INTO a variable that is then tested
--    explicitly (v_parent is null / v_found <> v_n). No `if not found` anywhere.
--  * CONCURRENCY SAFE: a TRANSACTION-scoped advisory lock keyed on the EXACT
--    sibling scope (org + entity + resolved parent + branch) serializes two
--    overlapping reorders of the SAME list into one gap-free 1..N, while
--    unrelated category/item/group/option lists proceed independently. Auto-
--    released at commit/rollback; never a global or restaurant-wide lock.
--    (Advisory rather than a parent-row FOR UPDATE because a branch-scoped
--    sibling set has no single owning row that cleanly represents it.)
-- Write roles: org_owner / restaurant_owner / manager only (D-031/D-028).
-- SECURITY DEFINER, search_path=''.
-- ----------------------------------------------------------------------------
create or replace function app.menu_reorder(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid,
  p_entity          text,
  p_ids             uuid[]
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_table         text;
  v_parent_col    text;   -- the FK column that defines a sibling set
  v_actor         uuid;
  v_n             int;
  v_found         int;
  v_sibling_total int;
  v_parent        uuid;
begin
  -- entity -> (child table, sibling-grouping parent column)
  case p_entity
    when 'menu_category'   then v_table := 'menu_categories';  v_parent_col := 'restaurant_id';
    when 'menu_item'       then v_table := 'menu_items';       v_parent_col := 'menu_category_id';
    when 'modifier'        then v_table := 'modifiers';        v_parent_col := 'menu_item_id';
    when 'modifier_option' then v_table := 'modifier_options'; v_parent_col := 'modifier_id';
    else raise exception 'menu_reorder: invalid request' using errcode = '42501';
  end case;

  -- (1) AUTHENTICATE + AUTHORIZE THE PASSED SCOPE, before any id is inspected,
  --     via the SAME contract as menu_upsert_* (app.menu_guard). Unauthenticated
  --     / non-member / cross-org / out-of-scope -> menu_guard raises 42501; a
  --     covering member below manager -> FALSE -> permission_denied + audit.
  v_actor := app.current_app_user_id();
  if v_actor is null then
    raise exception 'menu_reorder: invalid request' using errcode = '42501';
  end if;
  if not app.menu_guard(p_organization_id, p_restaurant_id, p_branch_id) then
    perform app.menu_audit(p_organization_id, p_restaurant_id, p_branch_id,
      'menu.' || p_entity || '.reorder_denied', null,
      jsonb_build_object('entity', p_entity));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', p_entity);
  end if;

  -- input shape (generic error; the caller learns nothing about ids).
  v_n := coalesce(array_length(p_ids, 1), 0);
  if v_n = 0 then
    raise exception 'menu_reorder: invalid request' using errcode = '42501';
  end if;
  if (select count(distinct u) from unnest(p_ids) u) <> v_n then
    raise exception 'menu_reorder: invalid request' using errcode = '42501';
  end if;

  -- (2) Resolve the sibling PARENT deterministically from the submitted ids,
  --     CONSTRAINED to the AUTHORIZED (org, restaurant, branch) scope. PG17-safe
  --     (order by id limit 1; no min(uuid)). EXECUTE ... INTO (never FOUND):
  --     nothing resolving in-scope -> v_parent is null -> generic 42501 (foreign
  --     / missing / deleted / cross-scope are indistinguishable).
  execute format($q$
    select %1$I
      from public.%2$I
     where organization_id = $1
       and restaurant_id   = $2
       and branch_id is not distinct from $3
       and id = any($4)
       and deleted_at is null
     order by id
     limit 1
  $q$, v_parent_col, v_table)
    into v_parent
    using p_organization_id, p_restaurant_id, p_branch_id, p_ids;
  if v_parent is null then
    raise exception 'menu_reorder: invalid request' using errcode = '42501';
  end if;

  -- (3) SERIALIZE the exact sibling scope with a TRANSACTION-scoped advisory
  --     lock (org + entity + resolved parent + branch). Two overlapping reorders
  --     of the SAME list serialize; unrelated lists never block. Auto-released at
  --     commit/rollback. Never a global/restaurant-wide lock.
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || '|' || p_entity || '|' ||
    v_parent::text || '|' || coalesce(p_branch_id::text, ''), 0));

  -- (4) Under the lock: EVERY submitted id must belong to the authorized scope
  --     AND the one resolved sibling parent. EXECUTE ... INTO a count, tested
  --     explicitly. Any mismatch -> generic 42501 (no count disclosed).
  execute format($q$
    select count(*)
      from public.%1$I
     where organization_id = $1
       and restaurant_id   = $2
       and branch_id is not distinct from $3
       and %2$I            = $4
       and id = any($5)
       and deleted_at is null
  $q$, v_table, v_parent_col)
    into v_found
    using p_organization_id, p_restaurant_id, p_branch_id, v_parent, p_ids;
  if v_found <> v_n then
    raise exception 'menu_reorder: invalid request' using errcode = '42501';
  end if;

  -- (5) The ids must be the COMPLETE non-deleted sibling set for that scope, so
  --     the rewrite yields a gap-free 1..N (no orphaned rows). The sibling total
  --     is NEVER disclosed to the caller (no oracle) -> generic 42501 on a miss.
  execute format($q$
    select count(*)
      from public.%1$I
     where organization_id = $1
       and restaurant_id   = $2
       and branch_id is not distinct from $3
       and %2$I            = $4
       and deleted_at is null
  $q$, v_table, v_parent_col)
    into v_sibling_total
    using p_organization_id, p_restaurant_id, p_branch_id, v_parent;
  if v_sibling_total <> v_n then
    raise exception 'menu_reorder: invalid request' using errcode = '42501';
  end if;

  -- (6) Atomic set-based rewrite: display_order = 1..N in p_ids order. This is
  --     the ONLY sanctioned writer of display_order — PART 5's guard trigger
  --     reverts any display_order change from any OTHER path (a normal
  --     menu_upsert edit) UNLESS this flag is on. The flag is set ONLY around this
  --     UPDATE and reset immediately after, so it can never leak to a later
  --     statement in the SAME transaction (set_config(...,true) is
  --     transaction-scoped, not statement-scoped) — belt-and-suspenders even
  --     though every production RPC is already its own transaction.
  perform set_config('app.menu_reordering', 'on', true);
  execute format($q$
    update public.%1$I t
       set display_order = v.ord
      from (select id, ord from unnest($1::uuid[]) with ordinality as u(id, ord)) v
     where t.id = v.id and t.organization_id = $2
  $q$, v_table)
    using p_ids, p_organization_id;
  perform set_config('app.menu_reordering', 'off', true);

  perform app.menu_audit(p_organization_id, p_restaurant_id, p_branch_id,
    'menu.' || p_entity || '.reordered', null,
    jsonb_build_object('entity', p_entity, 'ids', to_jsonb(p_ids)));
  return jsonb_build_object('ok', true, 'entity', p_entity, 'count', v_n, 'action', 'reordered');
end;
$$;

-- Thin public SECURITY INVOKER wrapper (RF-064 / RF-122 pattern) — same
-- (org, restaurant, branch, entity, ids) contract as the menu_upsert_* wrappers.
create or replace function public.menu_reorder(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid,
  p_entity text, p_ids uuid[])
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.menu_reorder(p_organization_id, p_restaurant_id, p_branch_id, p_entity, p_ids); $$;

-- Grants: authenticated only, on both the app function and the public wrapper.
revoke all on function app.menu_reorder(uuid, uuid, uuid, text, uuid[]) from public;
grant execute on function app.menu_reorder(uuid, uuid, uuid, text, uuid[]) to authenticated;
revoke all on function public.menu_reorder(uuid, uuid, uuid, text, uuid[]) from public;
grant execute on function public.menu_reorder(uuid, uuid, uuid, text, uuid[]) to authenticated;

-- ----------------------------------------------------------------------------
-- PART 4. Redefine app.pos_order_detail so the SERVER-BACKED reprint carries +
--         returns items/modifiers in the menu-configured PRINT order. The
--         shipped function (20260722090000) builds items[]/modifiers[] with an
--         EXPLICIT jsonb_build_object list (not to_jsonb), so the new snapshot
--         columns do NOT auto-appear: this create-or-replace ADDS them to the
--         item object and ORDERS BY them (created_at/id kept as the legacy-0
--         fallback), and orders each item's modifiers by their snapshots too.
--         ONLY section (d) changes; every auth check, scope rule, envelope and
--         the signature are reproduced VERBATIM (stacked-definition convention).
--         The shipped public.pos_order_detail SECURITY INVOKER wrapper is
--         unchanged (its delegate's signature is identical). No shipped migration
--         is edited; grants/signature are unchanged.
-- ----------------------------------------------------------------------------
create or replace function app.pos_order_detail(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_order_id       uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_org         uuid;
  v_rest        uuid;
  v_branch      uuid;
  v_dsid        uuid;
  v_membership  uuid;
  v_ds_device   uuid;
  v_ds_active   boolean;
  v_ds_revoked  timestamptz;
  v_pairing     text;
  v_role        text;
  v_m_status    text;
  v_m_deleted   timestamptz;
  v_device_type text;
  v_order       jsonb;
  v_items       jsonb;
  v_rounds      jsonb;
  v_payment     jsonb;
begin
  -- (a) THE CANONICAL PIN-SESSION PREAMBLE (pos_order_snapshots parity):
  --     every structural failure collapses to ONE indistinguishable envelope.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_membership
    from public.pin_sessions ps
    where ps.id = p_pin_session_id;
  if not found or not app.is_pin_session_valid(p_pin_session_id) then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'order_detail');
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found
     or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active')
     or v_ds_device is distinct from p_device_id then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'order_detail');
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m
    where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'order_detail');
  end if;

  -- (b) POS-class device + price-capable POS role (this read carries money).
  select d.device_type into v_device_type
    from public.devices d
    where d.id = p_device_id and d.organization_id = v_org;
  if v_device_type is distinct from 'pos' then
    return jsonb_build_object('ok', false, 'error', 'invalid_device_type', 'entity', 'order_detail');
  end if;
  if v_role not in ('cashier', 'manager', 'restaurant_owner', 'org_owner') then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'order_detail');
  end if;

  -- (c) the order — SESSION org+branch scope only. A nonexistent and a
  --     foreign-scope order collapse to the SAME envelope (no oracle, R-003).
  select jsonb_build_object(
           'order_id',             o.id,
           'order_code',           '#' || upper(right(replace(o.id::text, '-', ''), 6)),
           'order_type',           o.order_type,
           'status',               o.status,
           'revision',             o.revision,
           'table_label',          tbl.label,
           'customer_name',        o.customer_name,
           'currency_code',        o.currency_code,
           'subtotal_minor',       o.subtotal_minor,
           'discount_total_minor', o.discount_total_minor,
           'tax_total_minor',      o.tax_total_minor,
           'grand_total_minor',    o.grand_total_minor,
           'receipt_number',       o.receipt_number,
           'created_at',           o.created_at,
           'updated_at',           o.updated_at)
    into v_order
    from public.orders o
    left join public.tables tbl
      on  tbl.organization_id = o.organization_id
      and tbl.id              = o.table_id
    where o.id              = p_order_id
      and o.organization_id = v_org
      and o.branch_id       = v_branch
      and o.deleted_at is null;
  if v_order is null then
    return jsonb_build_object('ok', false, 'error', 'order_not_found', 'entity', 'order_detail');
  end if;

  -- (d) every ACTIVE customer-visible item, with modifiers and round
  --     membership (NULL service_round_id = the original submission).
  --     MENU-ORDER-001: carries + orders by the menu-configured print snapshots.
  select coalesce(jsonb_agg(jsonb_build_object(
           'order_item_id',             oi.id,
           'menu_item_id',              oi.menu_item_id,
           'menu_item_name_snapshot',   oi.menu_item_name_snapshot,
           'quantity',                  oi.quantity,
           'unit_price_minor_snapshot', oi.unit_price_minor_snapshot,
           'line_discount_minor',       oi.line_discount_minor,
           'line_total_minor',          oi.line_total_minor,
           -- MENU-ORDER-001: the menu-configured print-order snapshots so a
           -- cross-device reprint matches the live receipt (the client sorts too).
           'category_display_order_snapshot', oi.category_display_order_snapshot,
           'item_display_order_snapshot',     oi.item_display_order_snapshot,
           'line_position',             oi.line_position,
           'status',                    oi.status,
           'notes',                     oi.notes,
           'item_size_snapshot',        oi.item_size_snapshot,
           'item_variant_snapshot',     oi.item_variant_snapshot,
           'service_round_id',          oi.service_round_id,
           'round_number',              r.round_number,
           'modifiers',                 coalesce(mods.list, '[]'::jsonb)
         ) order by oi.category_display_order_snapshot asc,
                    oi.item_display_order_snapshot asc,
                    oi.line_position asc,
                    oi.created_at asc, oi.id asc), '[]'::jsonb)
    into v_items
    from public.order_items oi
    left join public.order_service_rounds r
      on  r.organization_id = oi.organization_id
      and r.id              = oi.service_round_id
    left join lateral (
      select jsonb_agg(jsonb_build_object(
               'modifier_name_snapshot', m.modifier_name_snapshot,
               'option_name_snapshot',   m.option_name_snapshot,
               'price_minor_snapshot',   m.price_minor_snapshot,
               'quantity',               m.quantity
             ) order by m.modifier_group_display_order_snapshot asc,
                        m.modifier_option_display_order_snapshot asc,
                        m.line_position asc,
                        m.created_at asc, m.id asc) as list
        from public.order_item_modifiers m
        where m.organization_id = oi.organization_id
          and m.order_item_id   = oi.id
          and m.deleted_at is null
    ) mods on true
    where oi.organization_id = v_org
      and oi.order_id        = p_order_id
      and oi.deleted_at is null
      and oi.status not in ('voided', 'cancelled');

  -- (e) the round list (voided rounds included — status says so).
  select coalesce(jsonb_agg(jsonb_build_object(
           'round_id',     r.id,
           'round_number', r.round_number,
           'status',       r.status,
           'ready_at',     r.ready_at,
           'created_at',   r.created_at
         ) order by r.round_number asc), '[]'::jsonb)
    into v_rounds
    from public.order_service_rounds r
    where r.organization_id = v_org
      and r.order_id        = p_order_id
      and r.deleted_at is null;

  -- (f) the (at most one) completed payment — enough for a faithful reprint.
  select jsonb_build_object(
           'payment_id',     p.id,
           'payment_status', p.status,
           'method',         p.method,
           'amount_minor',   p.amount_minor,
           'tendered_minor', p.tendered_minor,
           'change_minor',   p.change_minor,
           'receipt_number', p.receipt_number,
           'created_at',     p.created_at)
    into v_payment
    from public.payments p
    where p.organization_id = v_org
      and p.order_id        = p_order_id
      and p.status          = 'completed'
      and p.deleted_at is null
    limit 1;

  return jsonb_build_object(
    'ok', true, 'entity', 'order_detail', 'server_ts', now(),
    'order',   v_order,
    'items',   v_items,
    'rounds',  v_rounds,
    'payment', v_payment);
end;
$$;

-- ----------------------------------------------------------------------------
-- PART 5. DISPLAY_ORDER GUARD (Codex #6): app.menu_reorder is the ONLY sanctioned
--   writer of display_order for categories / items / modifier groups / modifier
--   options. A normal menu_upsert_* EDIT that happens to carry a (possibly STALE,
--   pre-reorder) display_order must NOT overwrite the live drag-set order — the
--   exact race Codex flagged: "a stale edit overwrite a newer drag order."
--
--   This BEFORE UPDATE trigger reverts ANY display_order change back to the OLD
--   value UNLESS the transaction-local flag `app.menu_reordering = 'on'` is set —
--   which is set ONLY inside app.menu_reorder (PART 3, step 6), local to that
--   transaction (set_config(..., true) resets at commit/rollback). So the database
--   UPDATE leaves display_order untouched unless the dedicated reorder operation
--   is executing, regardless of what value the client sends. INSERTs (new rows)
--   are unaffected (BEFORE UPDATE only). Sizes/variants are deliberately NOT
--   guarded — their numeric ordering is out of this drag-order phase.
--
--   Defence-in-depth: the flag GUC is settable only inside the SECURITY DEFINER
--   menu_reorder; the PostgREST data API exposes no arbitrary SET, so a client
--   calling menu_upsert_* can never turn the guard off.
-- ----------------------------------------------------------------------------
create or replace function app.preserve_menu_display_order()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  if new.display_order is distinct from old.display_order
     and coalesce(current_setting('app.menu_reordering', true), '') <> 'on' then
    new.display_order := old.display_order;
  end if;
  return new;
end;
$$;

comment on function app.preserve_menu_display_order() is
  'MENU-ORDER-001 (Codex #6): reverts any display_order change on menu_categories/menu_items/modifiers/modifier_options UNLESS app.menu_reordering=on (set only inside app.menu_reorder). Makes drag-reorder the sole writer of display_order so a stale menu_upsert edit cannot clobber the live order. INSERT-neutral; sizes/variants excluded.';

revoke all on function app.preserve_menu_display_order() from public;

drop trigger if exists preserve_menu_display_order on public.menu_categories;
create trigger preserve_menu_display_order
  before update on public.menu_categories
  for each row execute function app.preserve_menu_display_order();

drop trigger if exists preserve_menu_display_order on public.menu_items;
create trigger preserve_menu_display_order
  before update on public.menu_items
  for each row execute function app.preserve_menu_display_order();

drop trigger if exists preserve_menu_display_order on public.modifiers;
create trigger preserve_menu_display_order
  before update on public.modifiers
  for each row execute function app.preserve_menu_display_order();

drop trigger if exists preserve_menu_display_order on public.modifier_options;
create trigger preserve_menu_display_order
  before update on public.modifier_options
  for each row execute function app.preserve_menu_display_order();
