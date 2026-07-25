-- ============================================================================
-- PRINT-LAYOUT-001D — a STABLE per-order item ordinal so the kitchen ticket
-- prints items in the SAME sequence as the cashier receipt.
--
-- The cashier receipt (and the POS-direct kitchen ticket) print items in the
-- CART insertion order — the order the cashier added them. The KDS builds its
-- ticket from `order_items` rows delivered by `app.sync_pull`, which pages every
-- entity `ORDER BY (updated_at, id)`. For a freshly submitted order every
-- `order_items` row shares one transaction timestamp (`now()`), so that cursor
-- collapses to random-uuid `id` order, and a per-item status bump reshuffles it
-- again. There is no persisted column that reproduces the cart order, so the KDS
-- item sequence diverges from the receipt (PRINT-LAYOUT-001D root cause).
--
-- This migration is ADDITIVE and FORWARD-ONLY:
--   * a new `order_items.line_position` integer ordinal (default 0), and
--   * a BEFORE INSERT trigger that assigns it sequentially per order in INSERT
--     order.
-- `app.submit_order` and `app.add_order_items` both insert `order_items` ROW BY
-- ROW in submit-array (cart) order (a `for … in jsonb_array_elements(…) loop`),
-- so `max(line_position)+1` reproduces the cart sequence, and an added service
-- round's items sort AFTER the order's existing lines.
--
-- No data reset, no destructive backfill, no change to any shipped migration.
-- Existing rows keep `line_position = 0` (a legacy sentinel) and are untouched —
-- readers fall back to their prior `(created_at, id)` / wire order for those.
-- `app.sync_pull` returns whole rows (`to_jsonb(t)`), so the new column flows to
-- the KDS with NO change to the sync contract or the (updated_at, id) cursor.
-- ============================================================================

alter table public.order_items
  add column if not exists line_position integer not null default 0;

comment on column public.order_items.line_position is
  'PRINT-LAYOUT-001D: stable per-order line ordinal (1-based) in submit-array '
  '(cart) insertion order, assigned by the assign_order_item_line_position '
  'trigger. 0 = a legacy row created before this feature (falls back to '
  'created_at/id ordering). Used to print items in cashier-receipt order on the '
  'KDS. Non-money; never a business/routing key.';

-- ----------------------------------------------------------------------------
-- Trigger: assign the next per-order ordinal on insert (in INSERT order).
-- ----------------------------------------------------------------------------
create or replace function app.assign_order_item_line_position()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  -- Only auto-assign when the caller left the default 0, so an explicit ordinal
  -- (should a future caller ever set one) is respected. submit_order /
  -- add_order_items insert row-by-row within one transaction, so this max() sees
  -- the order's earlier lines and yields 1,2,3,… in cart order; a later round's
  -- lines continue after the existing max. Scoped to (organization_id,
  -- order_id) — never cross-order or cross-tenant.
  if new.line_position = 0 then
    new.line_position := coalesce(
      (select max(oi.line_position)
         from public.order_items oi
        where oi.organization_id = new.organization_id
          and oi.order_id        = new.order_id),
      0) + 1;
  end if;
  return new;
end;
$$;

comment on function app.assign_order_item_line_position() is
  'PRINT-LAYOUT-001D: BEFORE INSERT trigger fn — assigns order_items.line_position '
  'sequentially per (organization_id, order_id) in insert (cart) order.';

revoke all on function app.assign_order_item_line_position() from public;

drop trigger if exists assign_order_item_line_position on public.order_items;
create trigger assign_order_item_line_position
  before insert on public.order_items
  for each row
  execute function app.assign_order_item_line_position();
