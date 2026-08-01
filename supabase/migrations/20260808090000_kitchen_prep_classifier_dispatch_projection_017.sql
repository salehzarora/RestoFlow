-- KITCHEN-PREP-MODIFIER-SPLIT-CODEX-FIX-017 — Codex BLOCKER #1 + MEDIUM #4.
--
-- WHY
--   KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016 lets a modifier option CLASSIFY a
--   preparation resource, so the kitchen summary reads "Meat pieces with Cheese"
--   / "Meat pieces without Cheese". The order-time answer rides inside
--   order_items.prep_snapshot, whose CHECK already permits extra non-money keys.
--
--   But app.kitchen_prep_projection (20260725090000) is a STRICT ALLOWLIST that
--   keeps only {name, quantity, unit}. Every DURABLE dispatch — the printer-only
--   initial ticket and the Add-items round ticket, which are built from that
--   projection and then encrypted into the local spool — therefore silently lost
--   the classification. The cashier's direct print showed the split; the durable
--   copy the kitchen actually receives after a crash/retry did not.
--
--   Codex also found the two payload builders order items by (created_at, id)
--   while every other kitchen surface orders by the CANONICAL MENU ORDER —
--   category rank, then item-within-category rank, then the cart line position.
--   Aggregation row order follows input order, so the spool could print the same
--   totals in a different sequence than the POS and the KDS.
--
-- WHAT
--   1. app.kitchen_prep_projection — re-emitted, still a STRICT ALLOWLIST, now
--      forwarding the three optional classifier fields under hard type guards.
--   2. app.kitchen_dispatch_payload_initial / _round — re-emitted VERBATIM apart
--      from the item ORDER BY, which is now the canonical menu order so the
--      durable ticket, the POS direct print and the KDS agree.
--
-- ADDITIVE AND REVERSIBLE IN MEANING
--   No table, column, constraint, policy, grant or signature changes. No money
--   field is added — the projection cannot emit one (see the allowlist). Legacy
--   snapshots contain none of the new keys and project byte-identically to
--   before. Rollback is re-running the 20260725090000 definitions.
--
--   NOT APPLIED HOSTED BY THIS TASK.
--
-- ROLLBACK (manual, deliberate):
--   -- re-run the app.kitchen_prep_projection / app.kitchen_dispatch_payload_*
--   -- definitions from 20260725090000_kitchen_mode_001c1_dispatch_ledger.sql.

-- ---------------------------------------------------------------------------
-- 1. The projection — {name, quantity, unit} + the optional classifier triple.
-- ---------------------------------------------------------------------------
-- STILL AN ALLOWLIST: exactly six keys can ever survive, so no client-controlled
-- key reaches a dispatch payload and no arbitrary JSON type is forwarded.
--
-- TYPE SAFETY (Codex): each classifier field survives ONLY as its own JSON type
--   * classifier_option_id   — a non-empty JSON STRING (trimmed, <= 64 chars)
--   * classifier_option_name — a non-empty JSON STRING (trimmed, <= 120 chars)
--   * classifier_selected    — a real JSON BOOLEAN
-- An object/array/number/null in any of those positions is DROPPED, never
-- serialized to JSON text — the same rule the existing name/unit guards apply,
-- so {"classifier_option_id": {"amount_minor": 5}} can neither smuggle a
-- structured value through as text nor crash the dispatch build.
--
-- ALL OR NOTHING: the triple is only emitted when all three parts survive. A
-- partial set is not a classification, so it degrades to an ORDINARY UNSPLIT
-- resource rather than printing a bucket the owner never configured.
--
-- FAIL SAFE: name, quantity and unit are projected exactly as before and are
-- never affected by malformed classifier metadata — a preparation resource the
-- kitchen needs can never be suppressed by a bad optional field.
create or replace function app.kitchen_prep_projection(p_prep jsonb)
  returns jsonb
  language sql
  immutable
  set search_path = ''
as $$
  select case
    when p_prep is null or jsonb_typeof(p_prep) <> 'array' then null
    else (
      select nullif(coalesce(jsonb_agg(proj order by ord), '[]'::jsonb), '[]'::jsonb)
      from (
        select e.ord,
               jsonb_strip_nulls(jsonb_build_object(
                 'name',     case when jsonb_typeof(e.elem -> 'name') = 'string'
                                  then nullif(left(btrim(e.elem ->> 'name'), 120), '') end,
                 'quantity', case when jsonb_typeof(e.elem -> 'quantity') = 'number'
                                  then e.elem -> 'quantity' end,
                 'unit',     case when jsonb_typeof(e.elem -> 'unit') = 'string'
                                  then nullif(left(btrim(e.elem ->> 'unit'), 40), '') end,
                 -- 017: forwarded only as a COMPLETE, well-typed triple.
                 'classifier_option_id',
                   case when c.ok then c.cid end,
                 'classifier_option_name',
                   case when c.ok then c.cname end,
                 'classifier_selected',
                   case when c.ok then c.csel end)) as proj
        from jsonb_array_elements(p_prep) with ordinality as e(elem, ord)
        cross join lateral (
          select r.cid, r.cname, r.csel,
                 (r.cid is not null and r.cname is not null and r.csel is not null) as ok
          from (
            select case when jsonb_typeof(e.elem -> 'classifier_option_id') = 'string'
                        then nullif(left(btrim(e.elem ->> 'classifier_option_id'), 64), '') end as cid,
                   case when jsonb_typeof(e.elem -> 'classifier_option_name') = 'string'
                        then nullif(left(btrim(e.elem ->> 'classifier_option_name'), 120), '') end as cname,
                   case when jsonb_typeof(e.elem -> 'classifier_selected') = 'boolean'
                        then e.elem -> 'classifier_selected' end as csel
          ) r
        ) c
        where jsonb_typeof(e.elem) = 'object'
      ) s
      where s.proj <> '{}'::jsonb
    )
  end;
$$;

comment on function app.kitchen_prep_projection(jsonb) is
  'KITCHEN-MODE-001C1-CORRECTION-001 + KITCHEN-PREP-MODIFIER-SPLIT-CODEX-FIX-017 INTERNAL: allowlisted kitchen projection of order_items.prep_snapshot. Six keys can survive: the operational {name, quantity, unit} (name<=120 / unit<=40 trimmed text, quantity only as a JSON number) and the OPTIONAL 016 classifier triple {classifier_option_id (string<=64), classifier_option_name (string<=120), classifier_selected (boolean)} — forwarded ONLY when all three are present with those exact JSON types, so a malformed or partial classifier degrades to an ordinary unsplit resource instead of crashing dispatch or leaking arbitrary JSON. Unknown client keys are still dropped and can never reach a dispatch payload; no money field is representable; empty results collapse to NULL so the payload omits the prep key entirely.';

revoke all on function app.kitchen_prep_projection(jsonb) from public;
revoke all on function app.kitchen_prep_projection(jsonb) from anon;
revoke all on function app.kitchen_prep_projection(jsonb) from authenticated;

-- ---------------------------------------------------------------------------
-- 2. The two item-carrying payload builders — re-emitted from 20260725090000.
-- ---------------------------------------------------------------------------
-- The ONLY change is the item ORDER BY, which is now the CANONICAL MENU ORDER
-- every other kitchen surface already uses (MENU-ORDER-001 + PRINT-LAYOUT-001D):
--
--   1. category_display_order_snapshot  — the menu category rank
--   2. item_display_order_snapshot      — the item's rank within its category
--   3. line_position                    — the cart ordinal, and ONLY a tie-break
--                                         inside an equal menu-order group
--   4. created_at, 5. id                — deterministic final tie-breakers
--
-- 018 (Codex MEDIUM #3): 017 shipped with `line_position` LEADING, which is not
-- the canonical order — a cart where a later-category product was rung up first
-- would print its durable ticket in cart order while the POS receipt and the KDS
-- printed it in menu order. The two snapshot ranks are the PRIMARY keys, exactly
-- as `sortByMenuPrintOrder` applies them client-side.
--
-- All three ordinals are NOT NULL DEFAULT 0 columns; the coalesce is defensive
-- and matches the client's tolerant int-or-0 pluck. A legacy row carries 0 in
-- all three and therefore keeps its historical (created_at, id) position — no
-- existing order is reordered.
--
-- Everything else is verbatim: the same money-free scalar plucks, the same
-- 500-char note display caps (dispatch COPY only; the stored order is never
-- modified), the same modifier subquery, the same scope predicates. Money-free
-- by construction: no money column is read.
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
                 select coalesce(jsonb_agg(jsonb_build_object(
                          'qty', om.quantity,
                          'name', om.option_name_snapshot)
                        order by om.created_at, om.id), '[]'::jsonb)
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
  'KITCHEN-MODE-001C1 INTERNAL + KITCHEN-PREP-MODIFIER-SPLIT-CODEX-FIX-017: the money-free INITIAL-ORDER dispatch payload snapshot, re-emitted verbatim except that items now order by the CANONICAL MENU ORDER (category_display_order_snapshot, item_display_order_snapshot, line_position, created_at, id) — the SAME order the POS receipt, the POS direct kitchen ticket and the KDS ticket use — so the durable spool ticket cannot list the whole-order preparation summary in a different sequence. line_position is only a tie-break inside an equal menu-order group. Prep components carry the 016 classifier triple through app.kitchen_prep_projection.';

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
                 select coalesce(jsonb_agg(jsonb_build_object(
                          'qty', om.quantity,
                          'name', om.option_name_snapshot)
                        order by om.created_at, om.id), '[]'::jsonb)
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
  'KITCHEN-MODE-001C1 INTERNAL + KITCHEN-PREP-MODIFIER-SPLIT-CODEX-FIX-017: the money-free SERVICE-ROUND (Add-items) dispatch payload snapshot, re-emitted verbatim except that items now order by the CANONICAL MENU ORDER (category_display_order_snapshot, item_display_order_snapshot, line_position, created_at, id) — the SAME order the POS and KDS use. Prep components carry the 016 classifier triple through app.kitchen_prep_projection. Round scope is unchanged: only this round''s own items.';

-- INTERNAL-ONLY posture re-asserted (idempotent; create-or-replace preserves
-- existing ACLs, these restate the 20260725090000 contract explicitly).
revoke all on function app.kitchen_dispatch_payload_initial(uuid, uuid) from public;
revoke all on function app.kitchen_dispatch_payload_initial(uuid, uuid) from anon;
revoke all on function app.kitchen_dispatch_payload_initial(uuid, uuid) from authenticated;
revoke all on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) from public;
revoke all on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) from anon;
revoke all on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) from authenticated;
