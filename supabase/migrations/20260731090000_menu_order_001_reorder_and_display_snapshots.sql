-- ============================================================================
-- MENU-ORDER-001 — drag-and-drop menu ordering + order-time display-order
-- snapshots.
--
-- This one forward-only, ADDITIVE migration does three things:
--
--   PART 1 (order_items.menu_display_order) — snapshot the item's configured
--     menu rank (menu_items.display_order) at submit. Captured for future
--     menu-order grouping / reporting. It DELIBERATELY does NOT re-sort items:
--     PRINT-LAYOUT-001D's order_items.line_position (cart order) remains the
--     printed item sequence on every surface. Non-money.
--
--   PART 2 (order_item_modifiers.line_position) — the modifier-level twin of
--     PRINT-LAYOUT-001D. Today an item's modifiers print in MENU order on the
--     cashier receipt & POS kitchen ticket (the POS dialog emits selections by
--     group→option display order), but the KDS builds from `app.sync_pull`
--     rows paged `ORDER BY (updated_at, id)`, which for a freshly submitted
--     order collapses to random-uuid id order — so KDS modifier order diverges.
--     A stable per-order-item ordinal, assigned in submit-array (menu) order,
--     lets the KDS reproduce the receipt's modifier sequence. Non-money.
--
--   PART 3 (app.menu_reorder) — the minimal atomic reorder RPC backing
--     drag-and-drop for menu categories, menu items, modifier groups, and
--     modifier options. The existing menu_upsert_* RPCs are FULL-STATE (they
--     rewrite name/price/attributes on every call), so a reorder cannot reuse
--     them without clobbering; this rewrites ONLY display_order for a complete
--     sibling set, atomically, under the existing app.menu_guard authorization.
--
-- Both snapshots are populated by BEFORE INSERT triggers (mirroring the 001D
-- line_position trigger) so the large app.submit_order / app.add_order_items
-- RPCs are NOT touched (no stacked-definition rewrite). Those RPCs insert
-- order_items and order_item_modifiers ROW BY ROW in submit-array order
-- (`for … in jsonb_array_elements(…) loop insert`), so `max(…)+1` reproduces
-- the presented (cart / menu) sequence.
--
-- No data reset, no destructive backfill, no change to any shipped migration.
-- Existing rows keep the new columns at 0 (a legacy sentinel) and are
-- untouched; readers fall back to their prior wire order for those. `sync_pull`
-- returns whole rows (`to_jsonb(t)`), so both new columns flow to the KDS with
-- NO change to the sync contract or the (updated_at, id) cursor.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PART 1. order_items.menu_display_order — the item's menu rank at submit.
-- ----------------------------------------------------------------------------
alter table public.order_items
  add column if not exists menu_display_order integer not null default 0;

comment on column public.order_items.menu_display_order is
  'MENU-ORDER-001: snapshot of the item''s configured menu rank '
  '(menu_items.display_order) captured at submit by the '
  'assign_order_item_menu_display_order trigger. 0 = legacy/unknown item. '
  'Captured for menu-order grouping/reporting; it does NOT override the '
  'PRINT-LAYOUT-001D cart order (line_position) used to print items. Non-money.';

create or replace function app.assign_order_item_menu_display_order()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  -- Only derive when the caller left the default 0 (no caller sends this
  -- column today, so it is always derived). Read the live menu rank as the
  -- SECURITY DEFINER owner; submit_order already holds these menu_items rows
  -- (FOR UPDATE availability check) in the same transaction. A missing/soft
  -- reference yields 0 — the same sentinel as a legacy row. Scoped to
  -- (organization_id, menu_item_id): never cross-tenant.
  if new.menu_display_order = 0 then
    new.menu_display_order := coalesce(
      (select mi.display_order
         from public.menu_items mi
        where mi.organization_id = new.organization_id
          and mi.id              = new.menu_item_id
        limit 1),
      0);
  end if;
  return new;
end;
$$;

comment on function app.assign_order_item_menu_display_order() is
  'MENU-ORDER-001: BEFORE INSERT trigger fn — snapshots menu_items.display_order '
  'onto order_items.menu_display_order at submit. Non-money; never a business key.';

revoke all on function app.assign_order_item_menu_display_order() from public;

drop trigger if exists assign_order_item_menu_display_order on public.order_items;
create trigger assign_order_item_menu_display_order
  before insert on public.order_items
  for each row
  execute function app.assign_order_item_menu_display_order();

-- ----------------------------------------------------------------------------
-- PART 2. order_item_modifiers.line_position — a stable per-item modifier
--         ordinal in submit-array (menu display) order, so the KDS prints an
--         item's modifiers in the SAME order as the cashier receipt.
-- ----------------------------------------------------------------------------
alter table public.order_item_modifiers
  add column if not exists line_position integer not null default 0;

comment on column public.order_item_modifiers.line_position is
  'MENU-ORDER-001: stable per-order-item modifier ordinal (1-based) in '
  'submit-array (menu display) insertion order, assigned by the '
  'assign_order_item_modifier_line_position trigger. 0 = a legacy row created '
  'before this feature (falls back to wire order). Used to print an item''s '
  'modifiers in cashier-receipt order on the KDS. Non-money.';

create or replace function app.assign_order_item_modifier_line_position()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  -- submit_order / add_order_items insert an item's modifiers row-by-row in
  -- payload (menu display) order within one transaction, so this max() sees the
  -- item's earlier modifiers and yields 1,2,3,… in that order. Scoped to
  -- (organization_id, order_item_id) — never cross-item or cross-tenant. An
  -- explicit non-zero (should a future caller set one) is respected.
  if new.line_position = 0 then
    new.line_position := coalesce(
      (select max(oim.line_position)
         from public.order_item_modifiers oim
        where oim.organization_id = new.organization_id
          and oim.order_item_id   = new.order_item_id),
      0) + 1;
  end if;
  return new;
end;
$$;

comment on function app.assign_order_item_modifier_line_position() is
  'MENU-ORDER-001: BEFORE INSERT trigger fn — assigns '
  'order_item_modifiers.line_position sequentially per (organization_id, '
  'order_item_id) in insert (menu display) order.';

revoke all on function app.assign_order_item_modifier_line_position() from public;

drop trigger if exists assign_order_item_modifier_line_position on public.order_item_modifiers;
create trigger assign_order_item_modifier_line_position
  before insert on public.order_item_modifiers
  for each row
  execute function app.assign_order_item_modifier_line_position();

-- ----------------------------------------------------------------------------
-- PART 3. app.menu_reorder — atomic display_order rewrite for a complete
--         sibling set (menu_category / menu_item / modifier / modifier_option).
--
-- Authorization mirrors menu_soft_delete: resolve the rows' real scope as the
-- SECURITY DEFINER owner, then app.menu_guard against THAT scope (never a
-- client-supplied scope). Structural failures RAISE 42501 (rolled back, no
-- audit); a covered-but-no-write-role caller writes a committed
-- 'menu.<entity>.reorder_denied' audit and RETURNS permission_denied (the
-- RF-053 return-not-raise pattern). Write roles: org_owner / restaurant_owner /
-- manager only (D-031/D-028). display_order becomes 1..N in p_ids order.
-- ----------------------------------------------------------------------------
create or replace function app.menu_reorder(
  p_organization_id uuid,
  p_entity          text,
  p_ids             uuid[]
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_table          text;
  v_parent_col     text;   -- the FK column that defines a sibling set
  v_n              int;
  v_found          int;
  v_distinct_group int;
  v_sibling_total  int;
  v_rest           uuid;
  v_branch         uuid;
  v_parent         uuid;
begin
  -- entity -> (table, sibling-grouping parent column). Exactly the four
  -- drag-and-drop entities (MENU-ORDER-001 scope); anything else is rejected.
  case p_entity
    when 'menu_category'   then v_table := 'menu_categories';  v_parent_col := 'restaurant_id';
    when 'menu_item'       then v_table := 'menu_items';       v_parent_col := 'menu_category_id';
    when 'modifier'        then v_table := 'modifiers';        v_parent_col := 'menu_item_id';
    when 'modifier_option' then v_table := 'modifier_options'; v_parent_col := 'modifier_id';
    else raise exception 'menu_reorder: unknown entity %', p_entity using errcode = '42501';
  end case;

  v_n := coalesce(array_length(p_ids, 1), 0);
  if v_n = 0 then
    raise exception 'menu_reorder: ids required' using errcode = '42501';
  end if;
  if (select count(distinct u) from unnest(p_ids) u) <> v_n then
    raise exception 'menu_reorder: duplicate ids' using errcode = '42501';
  end if;

  -- Resolve, as the DEFINER owner (RLS-bypassing), how many of the ids exist in
  -- this org (non-deleted) and whether they all share ONE scope + parent
  -- (siblings). count(distinct (restaurant_id, branch_id, <parent>)) treats a
  -- NULL branch_id (restaurant-scope) as equal, so a single-scope set = 1.
  execute format($q$
    select count(*),
           count(distinct (restaurant_id, branch_id, %1$I)),
           min(restaurant_id), min(branch_id), min(%1$I)
      from public.%2$I
     where organization_id = $1 and id = any($2) and deleted_at is null
  $q$, v_parent_col, v_table)
    into v_found, v_distinct_group, v_rest, v_branch, v_parent
    using p_organization_id, p_ids;

  if v_found <> v_n then
    raise exception 'menu_reorder: some ids were not found in this organization'
      using errcode = '42501';
  end if;
  if v_distinct_group <> 1 then
    raise exception 'menu_reorder: all ids must be siblings in a single scope'
      using errcode = '42501';
  end if;

  -- The ids must be the COMPLETE non-deleted sibling set for that scope+parent,
  -- so the rewrite yields a gap-free, collision-free 1..N with no orphaned rows.
  execute format($q$
    select count(*)
      from public.%1$I
     where organization_id = $1
       and restaurant_id is not distinct from $2
       and branch_id     is not distinct from $3
       and %2$I          is not distinct from $4
       and deleted_at is null
  $q$, v_table, v_parent_col)
    into v_sibling_total
    using p_organization_id, v_rest, v_branch, v_parent;

  if v_sibling_total <> v_n then
    raise exception 'menu_reorder: ids must be the complete sibling set (% of %)',
      v_n, v_sibling_total using errcode = '42501';
  end if;

  -- Gate against the ROW's actual scope (return-not-raise on role denial).
  if not app.menu_guard(p_organization_id, v_rest, v_branch) then
    perform app.menu_audit(p_organization_id, v_rest, v_branch,
      'menu.' || p_entity || '.reorder_denied', null,
      jsonb_build_object('entity', p_entity, 'ids', to_jsonb(p_ids)));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', p_entity);
  end if;

  -- Atomic set-based rewrite: display_order = 1..N in p_ids order.
  execute format($q$
    update public.%1$I t
       set display_order = v.ord
      from (select id, ord from unnest($1::uuid[]) with ordinality as u(id, ord)) v
     where t.id = v.id and t.organization_id = $2
  $q$, v_table)
    using p_ids, p_organization_id;

  perform app.menu_audit(p_organization_id, v_rest, v_branch,
    'menu.' || p_entity || '.reordered', null,
    jsonb_build_object('entity', p_entity, 'ids', to_jsonb(p_ids)));
  return jsonb_build_object('ok', true, 'entity', p_entity, 'count', v_n, 'action', 'reordered');
end;
$$;

-- Thin public SECURITY INVOKER wrapper (RF-064 / RF-122 pattern).
create or replace function public.menu_reorder(
  p_organization_id uuid, p_entity text, p_ids uuid[])
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.menu_reorder(p_organization_id, p_entity, p_ids); $$;

-- Grants: authenticated only, on both the app function and the public wrapper.
revoke all on function app.menu_reorder(uuid, text, uuid[]) from public;
grant execute on function app.menu_reorder(uuid, text, uuid[]) to authenticated;
revoke all on function public.menu_reorder(uuid, text, uuid[]) from public;
grant execute on function public.menu_reorder(uuid, text, uuid[]) to authenticated;
