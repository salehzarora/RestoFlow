-- ============================================================================
-- KIOSK-PRINT-114B.6B — the kitchen dispatch payload emits each item's
-- modifiers in the AUTHORITATIVE dashboard order.
--
-- WHY. The 114B.6 audit found the kiosk initial kitchen ticket (claimed
-- dispatch) and the POS printer-only drain printing an item's sub-lines
-- shuffled while the POS direct ticket and the POS manual reprint printed them
-- in dashboard order. Root cause: app.kitchen_dispatch_payload_initial /
-- _round aggregated modifiers `order by om.created_at, om.id`; every modifier
-- row of one submit shares created_at (the transaction time), so the tie-break
-- fell to the random UUID id. The payload carries no ordering key, so the
-- client cannot repair this without guessing — the fix belongs here.
--
-- WHAT (byte-faithful re-emit of the 20260809090000 (019) bodies; the ONLY
-- change is the modifier aggregate's ORDER BY, now the exact expression
-- app.pos_order_detail already uses — the MENU-ORDER-001 trigger-stamped
-- snapshots, then insertion order, then the old keys as final tie-breaks):
--
--     order by om.modifier_group_display_order_snapshot asc,
--              om.modifier_option_display_order_snapshot asc,
--              om.line_position asc,
--              om.created_at asc, om.id asc
--
-- Historical rows: the snapshot columns are NOT NULL DEFAULT 0 (never NULL);
-- a legacy/unknown option carries rank 0 and orders by line_position
-- (insertion order) — deterministic, the same fallback pos_order_detail
-- prints, no backfill, nothing re-derived from the live menu (D-008).
--
-- UNCHANGED: signatures, LANGUAGE sql STABLE, search_path='', payload shape
-- and keys, item ordering, prep/meat projections, money-free contract, the
-- INTERNAL-ONLY ACL (no public wrapper, no anon/authenticated execute). No
-- table/column/index/policy change. No new RPC.
-- ============================================================================

create or replace function app.kitchen_dispatch_payload_initial(
  p_organization_id uuid,
  p_order_id        uuid
)
  returns jsonb
  language sql
  stable
  set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'v', 1,
    'kind', 'initial_order',
    'order_code', '#' || upper(right(replace(o.id::text, '-', ''), 6)),
    'order_type', o.order_type,
    'table_label', tbl.label,
    'customer_display_name', nullif(left(btrim(coalesce(o.customer_name, '')), 80), ''),
    'order_note', nullif(left(btrim(coalesce(o.notes, '')), 500), ''),
    'created_at', o.created_at,
    'items', (
      select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
               'qty', oi.quantity,
               'name', oi.menu_item_name_snapshot,
               'note', nullif(left(btrim(coalesce(oi.notes, '')), 500), ''),
               'prep', app.kitchen_prep_projection(oi.prep_snapshot),
               'modifiers', (
                 select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                          'qty', om.quantity,
                          'name', om.option_name_snapshot,
                          'prep', app.kitchen_modifier_prep_projection(om.meat_snapshot)))
                        -- 114B.6B: the AUTHORITATIVE dashboard order — exactly
                        -- what app.pos_order_detail emits (MENU-ORDER-001).
                        order by om.modifier_group_display_order_snapshot asc,
                                 om.modifier_option_display_order_snapshot asc,
                                 om.line_position asc,
                                 om.created_at asc, om.id asc), '[]'::jsonb)
                 from public.order_item_modifiers om
                 where om.organization_id = oi.organization_id
                   and om.order_item_id = oi.id
                   and om.deleted_at is null)))
             order by coalesce(oi.category_display_order_snapshot, 0),
                      coalesce(oi.item_display_order_snapshot, 0),
                      coalesce(oi.line_position, 0),
                      oi.created_at, oi.id), '[]'::jsonb)
      from public.order_items oi
      where oi.organization_id = o.organization_id
        and oi.order_id = o.id
        and oi.service_round_id is null
        and oi.deleted_at is null)))
  from public.orders o
  left join public.tables tbl
    on tbl.organization_id = o.organization_id and tbl.id = o.table_id
  where o.organization_id = p_organization_id and o.id = p_order_id;
$$;

comment on function app.kitchen_dispatch_payload_initial(uuid, uuid) is
  'KITCHEN-MODE-001C1 INTERNAL + 017 + 019 + KIOSK-PRINT-114B.6B: the money-free INITIAL-ORDER dispatch payload snapshot. Items order by the CANONICAL MENU ORDER (category_display_order_snapshot, item_display_order_snapshot, line_position, created_at, id); each item''s MODIFIERS order by the AUTHORITATIVE dashboard order (modifier_group_display_order_snapshot, modifier_option_display_order_snapshot, line_position, created_at, id) — the exact expression app.pos_order_detail uses, so the kiosk claimed print, the POS drain, the POS direct ticket and the POS manual reprint print identical sub-lines. Item prep carries the 016 classifier triple through app.kitchen_prep_projection; each modifier''s own contribution + classifier through app.kitchen_modifier_prep_projection. A modifier with no contribution emits no prep key.';

create or replace function app.kitchen_dispatch_payload_round(
  p_organization_id uuid,
  p_order_id        uuid,
  p_round_id        uuid
)
  returns jsonb
  language sql
  stable
  set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'v', 1,
    'kind', 'service_round',
    'order_code', '#' || upper(right(replace(o.id::text, '-', ''), 6)),
    'order_type', o.order_type,
    'table_label', tbl.label,
    'round_id', r.id,
    'round_number', r.round_number,
    'created_at', r.created_at,
    'items', (
      select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
               'qty', oi.quantity,
               'name', oi.menu_item_name_snapshot,
               'note', nullif(left(btrim(coalesce(oi.notes, '')), 500), ''),
               'prep', app.kitchen_prep_projection(oi.prep_snapshot),
               'modifiers', (
                 select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                          'qty', om.quantity,
                          'name', om.option_name_snapshot,
                          'prep', app.kitchen_modifier_prep_projection(om.meat_snapshot)))
                        -- 114B.6B: the AUTHORITATIVE dashboard order — exactly
                        -- what app.pos_order_detail emits (MENU-ORDER-001).
                        order by om.modifier_group_display_order_snapshot asc,
                                 om.modifier_option_display_order_snapshot asc,
                                 om.line_position asc,
                                 om.created_at asc, om.id asc), '[]'::jsonb)
                 from public.order_item_modifiers om
                 where om.organization_id = oi.organization_id
                   and om.order_item_id = oi.id
                   and om.deleted_at is null)))
             order by coalesce(oi.category_display_order_snapshot, 0),
                      coalesce(oi.item_display_order_snapshot, 0),
                      coalesce(oi.line_position, 0),
                      oi.created_at, oi.id), '[]'::jsonb)
      from public.order_items oi
      where oi.organization_id = o.organization_id
        and oi.order_id = o.id
        and oi.service_round_id = r.id
        and oi.deleted_at is null)))
  from public.orders o
  join public.order_service_rounds r
    on r.organization_id = o.organization_id and r.id = p_round_id and r.order_id = o.id
  left join public.tables tbl
    on tbl.organization_id = o.organization_id and tbl.id = o.table_id
  where o.organization_id = p_organization_id and o.id = p_order_id;
$$;

comment on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) is
  'KITCHEN-MODE-001C1 INTERNAL + 017 + 019 + KIOSK-PRINT-114B.6B: the money-free SERVICE-ROUND (Add-items) dispatch payload snapshot. Items order by the CANONICAL MENU ORDER; each item''s MODIFIERS order by the AUTHORITATIVE dashboard order (modifier_group_display_order_snapshot, modifier_option_display_order_snapshot, line_position, created_at, id) exactly as app.pos_order_detail does. Item prep carries the 016 classifier triple; each modifier''s own contribution + classifier through app.kitchen_modifier_prep_projection. Round scope is unchanged: only this round''s own items.';

-- INTERNAL-ONLY posture re-asserted (idempotent; create-or-replace preserves
-- existing ACLs, these restate the contract explicitly).
revoke all on function app.kitchen_dispatch_payload_initial(uuid, uuid) from public;
revoke all on function app.kitchen_dispatch_payload_initial(uuid, uuid) from anon;
revoke all on function app.kitchen_dispatch_payload_initial(uuid, uuid) from authenticated;
revoke all on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) from public;
revoke all on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) from anon;
revoke all on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) from authenticated;
