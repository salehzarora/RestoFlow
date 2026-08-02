-- KITCHEN-MODIFIER-PREP-CLASSIFIER-019 — durable dispatch carries a MODIFIER
-- OPTION's kitchen preparation contribution (and its classifier).
--
-- WHY
--   Saleh's real menu shape: the burger's meat quantity is NOT a fixed
--   product-level preparation resource. It comes from the selected SIZE option
--   (120g -> 1 Meat piece, 240g -> 2, 360g -> 3, 480g -> 4) through the existing
--   KITCHEN-MEAT-001 per-option contribution (`modifier_options.kitchen_meat` ->
--   `order_item_modifiers.meat_snapshot`). A separate Cheese option decides
--   whether those pieces are reported "with Cheese" or "without Cheese".
--
--   The KDS and the POS direct print already aggregate meat_snapshot. The
--   DURABLE dispatch does NOT: app.kitchen_dispatch_payload_initial / _round
--   project each modifier as {qty, name} only, so a modifier's preparation
--   contribution has never reached the encrypted local spool. Moving the meat
--   onto the size option would therefore make it VANISH from the printer-only
--   ticket the kitchen actually receives after a crash or a retry — precisely
--   the failure mode KITCHEN-PREP-MODIFIER-SPLIT-CODEX-FIX-017 fixed for the
--   product-level resources.
--
-- WHAT
--   1. NEW app.kitchen_modifier_prep_projection(jsonb) — a STRICT ALLOWLIST
--      projection of order_item_modifiers.meat_snapshot, mirroring 017's
--      app.kitchen_prep_projection rules exactly.
--   2. app.kitchen_dispatch_payload_initial / _round — re-emitted VERBATIM apart
--      from ONE added key on each modifier object: 'prep', carrying that
--      projection. The canonical menu ordering installed by 017 is preserved
--      byte for byte.
--
-- ADDITIVE AND REVERSIBLE IN MEANING
--   No table, column, constraint, policy, grant or signature changes. No money
--   field is added — the projection cannot emit one (see the allowlist). A
--   modifier with no contribution projects no 'prep' key at all, so an existing
--   payload is byte-identical to before. Rollback is re-running the
--   20260808090000 builder definitions.
--
--   NOT APPLIED HOSTED BY THIS TASK.
--
-- ROLLBACK (manual, deliberate):
--   -- re-run the app.kitchen_dispatch_payload_initial / _round definitions from
--   -- 20260808090000_kitchen_prep_classifier_dispatch_projection_017.sql, then
--   -- drop function if exists app.kitchen_modifier_prep_projection(jsonb);

-- ---------------------------------------------------------------------------
-- 1. The modifier-contribution projection.
-- ---------------------------------------------------------------------------
-- A meat_snapshot is {quantity, unit} plus the OPTIONAL 019 classifier triple.
-- Exactly five keys can ever survive, so no client-controlled key reaches a
-- dispatch payload and no arbitrary JSON type is forwarded.
--
-- TYPE SAFETY (the 017 rules, applied to this shape):
--   * quantity               — only as a real JSON NUMBER, and only when > 0
--   * unit                   — a non-empty JSON STRING (trimmed, <= 40 chars)
--   * classifier_option_id   — a non-empty JSON STRING (trimmed, <= 64 chars)
--   * classifier_option_name — a non-empty JSON STRING (trimmed, <= 120 chars)
--   * classifier_selected    — a real JSON BOOLEAN
-- An object/array/wrong-typed value in any position is DROPPED, never
-- serialized to JSON text, so {"classifier_option_id": {"amount_minor": 5}}
-- can neither smuggle a structured value through as text nor crash the build.
--
-- ALL OR NOTHING for the classifier: the triple is emitted only when all three
-- parts survive. A partial set is not a classification, so it degrades to an
-- ORDINARY UNSPLIT contribution rather than printing a bucket the owner never
-- configured.
--
-- FAIL SAFE: a non-positive/absent quantity yields NULL — the modifier then
-- carries no 'prep' key and prints exactly as it always has. Malformed
-- classifier metadata can never suppress a valid contribution.
create or replace function app.kitchen_modifier_prep_projection(p_meat jsonb)
  returns jsonb
  language sql
  immutable
  set search_path = ''
as $$
  select case
    when p_meat is null or jsonb_typeof(p_meat) <> 'object' then null
    else nullif(
      jsonb_strip_nulls(jsonb_build_object(
        'quantity', case when jsonb_typeof(p_meat -> 'quantity') = 'number'
                          and (p_meat ->> 'quantity')::numeric > 0
                         then p_meat -> 'quantity' end,
        'unit',     case when jsonb_typeof(p_meat -> 'unit') = 'string'
                         then nullif(left(btrim(p_meat ->> 'unit'), 40), '') end,
        'classifier_option_id',
          case when c.ok then c.cid end,
        'classifier_option_name',
          case when c.ok then c.cname end,
        'classifier_selected',
          case when c.ok then c.csel end)),
      '{}'::jsonb)
  end
  from (
    select r.cid, r.cname, r.csel,
           (r.cid is not null and r.cname is not null and r.csel is not null) as ok
    from (
      select case when jsonb_typeof(p_meat -> 'classifier_option_id') = 'string'
                  then nullif(left(btrim(p_meat ->> 'classifier_option_id'), 64), '') end as cid,
             case when jsonb_typeof(p_meat -> 'classifier_option_name') = 'string'
                  then nullif(left(btrim(p_meat ->> 'classifier_option_name'), 120), '') end as cname,
             case when jsonb_typeof(p_meat -> 'classifier_selected') = 'boolean'
                  then p_meat -> 'classifier_selected' end as csel
    ) r
  ) c;
$$;

comment on function app.kitchen_modifier_prep_projection(jsonb) is
  'KITCHEN-MODIFIER-PREP-CLASSIFIER-019 INTERNAL: allowlisted kitchen projection of order_item_modifiers.meat_snapshot — the per-option preparation contribution that carries Saleh''s meat (a 240g size option contributes 2 Meat pieces). Five keys can survive: {quantity (JSON number > 0), unit (string<=40)} and the OPTIONAL classifier triple {classifier_option_id (string<=64), classifier_option_name (string<=120), classifier_selected (boolean)} — forwarded ONLY when all three are present with those exact JSON types, so malformed or partial classifier metadata degrades to an ordinary unsplit contribution instead of crashing dispatch or leaking arbitrary JSON. Unknown client keys are dropped and can never reach a dispatch payload; no money field is representable; an absent/non-positive quantity collapses to NULL so the modifier omits the prep key entirely.';

revoke all on function app.kitchen_modifier_prep_projection(jsonb) from public;
revoke all on function app.kitchen_modifier_prep_projection(jsonb) from anon;
revoke all on function app.kitchen_modifier_prep_projection(jsonb) from authenticated;

-- ---------------------------------------------------------------------------
-- 2. The two item-carrying payload builders — re-emitted from 20260808090000.
-- ---------------------------------------------------------------------------
-- The ONLY change is ONE added key on each modifier object:
--     'prep', app.kitchen_modifier_prep_projection(om.meat_snapshot)
-- so the durable spool finally receives the contribution the KDS and the POS
-- direct print already show. jsonb_strip_nulls on the enclosing item object
-- means a modifier with no contribution emits no 'prep' key — an existing
-- payload is byte-identical.
--
-- Everything else is verbatim from 017, INCLUDING its canonical menu ordering
-- (category_display_order_snapshot, item_display_order_snapshot, line_position,
-- created_at, id) and the modifier ordering (created_at, id). Money-free by
-- construction: no money column is read.
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
  'KITCHEN-MODE-001C1 INTERNAL + KITCHEN-PREP-MODIFIER-SPLIT-CODEX-FIX-017 + KITCHEN-MODIFIER-PREP-CLASSIFIER-019: the money-free INITIAL-ORDER dispatch payload snapshot. Items order by the CANONICAL MENU ORDER (category_display_order_snapshot, item_display_order_snapshot, line_position, created_at, id) — the SAME order the POS receipt, the POS direct kitchen ticket and the KDS ticket use. Item prep components carry the 016 classifier triple through app.kitchen_prep_projection; 019 adds each MODIFIER''s own preparation contribution (order_item_modifiers.meat_snapshot — the size option''s Meat pieces) and its classifier through app.kitchen_modifier_prep_projection, so the durable spool ticket finally shows what the KDS and the direct print already show. A modifier with no contribution emits no prep key (payload byte-identical to before).';

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
  'KITCHEN-MODE-001C1 INTERNAL + KITCHEN-PREP-MODIFIER-SPLIT-CODEX-FIX-017 + KITCHEN-MODIFIER-PREP-CLASSIFIER-019: the money-free SERVICE-ROUND (Add-items) dispatch payload snapshot. Items order by the CANONICAL MENU ORDER, exactly as the POS and KDS do. Item prep carries the 016 classifier triple; 019 adds each MODIFIER''s own preparation contribution + classifier through app.kitchen_modifier_prep_projection. Round scope is unchanged: only this round''s own items.';

-- INTERNAL-ONLY posture re-asserted (idempotent; create-or-replace preserves
-- existing ACLs, these restate the contract explicitly).
revoke all on function app.kitchen_dispatch_payload_initial(uuid, uuid) from public;
revoke all on function app.kitchen_dispatch_payload_initial(uuid, uuid) from anon;
revoke all on function app.kitchen_dispatch_payload_initial(uuid, uuid) from authenticated;
revoke all on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) from public;
revoke all on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) from anon;
revoke all on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) from authenticated;
