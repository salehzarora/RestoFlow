-- ============================================================================
-- ORDER-EDIT-001A (2 of 3) — app.edit_order (sync op order.edit) and
-- app.kitchen_ack_order_edit (sync op order.edit_ack), with their internal
-- helpers and the paper-channel order_edit dispatch.
-- Contract: API_CONTRACT §4.45 (steps 1-20, landing matrix, envelope, refusals)
-- and §4.46; money: MONEY_AND_TAX_SPEC §9.2 (M1-M13); decisions D-043 / D-044.
--
-- NORMATIVE (§4.45.1): every refusal is decided BEFORE the first write.
-- app.sync_push commits a RETURNed envelope and rolls back only on a RAISE, so
-- validation (steps 1-11) writes nothing but the refusal's own
-- order.edit_denied audit row.
--
-- WHAT THIS MIGRATION ADDS (all INTERNAL — no client grant, no public wrapper;
-- both RPCs are reached ONLY through the SECURITY DEFINER app.sync_push, so a
-- direct call can never bypass the D-022 sync_operations ledger):
--   app.order_item_is_legacy_priced   — the M1a legacy-price predicate (shared
--                                       with app.pos_order_detail in 001B)
--   app.edit_tax_minor                — M7 tax recompute (exclusive only)
--   app.edit_reanswer_prep            — classifier_selected re-answered against
--                                       a replacement's FULL option set (frozen
--                                       link, never the live menu)
--   app.edit_json_int / edit_try_uuid — strict payload parsers (no raise)
--   app.edit_canonical_change / edit_canonical_modifiers
--                                     — one canonical (lower-case) id spelling
--   app.edit_validate_new_line        — the add_order_items per-line shape +
--                                       arithmetic block, copied (submit, add
--                                       items and the kiosk are NOT refactored)
--   app.edit_order_deny               — the order.edit_denied audit + envelope
--   app.kitchen_dispatch_item_projection / app.kitchen_dispatch_payload_order_edit
--                                     — the money-free change-slip payload
--   app.create_order_edit_dispatch    — the NEW internal creator (the pinned
--                                       10-argument app.create_kitchen_dispatch
--                                       is untouched)
--   app.edit_order, app.kitchen_ack_order_edit
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

-- M1a: a line is LEGACY (pre-002A per-line pricing) iff its stored amounts do
-- not reproduce under the per-unit formula. Derived from the stored row only.
create or replace function app.order_item_is_legacy_priced(
  p_organization_id uuid,
  p_order_item_id   uuid
)
  returns boolean
  language sql
  stable
  set search_path = ''
as $$
  select oi.line_total_minor + oi.line_discount_minor
         <> oi.quantity::bigint * (oi.unit_price_minor_snapshot + coalesce((
              select sum(m.price_minor_snapshot * m.quantity)
                from public.order_item_modifiers m
               where m.organization_id = oi.organization_id
                 and m.order_item_id   = oi.id
                 and m.deleted_at is null), 0))
    from public.order_items oi
   where oi.organization_id = p_organization_id
     and oi.id              = p_order_item_id;
$$;

comment on function app.order_item_is_legacy_priced(uuid, uuid) is
  'ORDER-EDIT-001A (MONEY_AND_TAX_SPEC §9.2 M1a): TRUE iff line_total_minor + line_discount_minor <> quantity x (unit_price_minor_snapshot + SUM(price_minor_snapshot x quantity over the line''s live modifiers)) — a pre-002A per-line-priced row, which an edit may only remove. Rows where both pricing epochs agree are not legacy. The ONE server-side definition (app.edit_order step 6; app.pos_order_detail in ORDER-EDIT-001B); clients only read the flag. NULL for an unknown row. INTERNAL.';

-- M7: tax on base = subtotal - discount from the branch's CURRENT settings.
-- Disabled or 0 bp -> 0; exclusive -> round-half-away(base x bp / 10000),
-- byte-matching apps/pos/lib/src/format/tax_math.dart; inclusive -> NULL (the
-- caller refuses tax_mode_unsupported, Q-043).
create or replace function app.edit_tax_minor(
  p_base_minor  bigint,
  p_tax_enabled boolean,
  p_tax_rate_bp integer,
  p_tax_mode    text
)
  returns bigint
  language sql
  immutable
  set search_path = ''
as $$
  select case
    when not coalesce(p_tax_enabled, false) or coalesce(p_tax_rate_bp, 0) <= 0 then 0::bigint
    when p_tax_mode = 'exclusive' then round((p_base_minor::numeric * p_tax_rate_bp) / 10000)::bigint
    else null
  end;
$$;

comment on function app.edit_tax_minor(bigint, boolean, integer, text) is
  'ORDER-EDIT-001A (MONEY_AND_TAX_SPEC §9.2 M7): tax_total_minor of an edited order from the branch''s CURRENT tax settings on base = subtotal - discount. Tax disabled or rate 0 -> 0; exclusive -> round-half-away-from-zero(base x rate_bp / 10000) on a numeric transient (POS tax_math parity); inclusive -> NULL, which app.edit_order refuses as tax_mode_unsupported (fail closed, Q-043). Integer minor units only (D-007). INTERNAL.';

-- Re-answers every frozen classifier_selected against the presence of its
-- classifier_option_id in a replacement's FULL modifier array — the presence
-- rule of app.trusted_modifier_prep_snapshot / app.trusted_item_prep_snapshot,
-- applied to the FROZEN link (never the live menu). Accepts one object (a
-- modifier meat_snapshot) or an array of components (an item prep_snapshot);
-- any other value, and any element without a string classifier id and a
-- classifier_selected key, is returned unchanged.
create or replace function app.edit_reanswer_prep(
  p_snapshot           jsonb,
  p_selected_modifiers jsonb
)
  returns jsonb
  language sql
  immutable
  set search_path = ''
as $$
  with sel as (
    select lower(btrim(s ->> 'modifier_option_id')) as id
      from jsonb_array_elements(
             case when jsonb_typeof(p_selected_modifiers) = 'array'
                  then p_selected_modifiers else '[]'::jsonb end) s
     where jsonb_typeof(s) = 'object'
       and s ->> 'modifier_option_id' is not null
  )
  select case jsonb_typeof(p_snapshot)
    when 'object' then
      case when jsonb_typeof(p_snapshot -> 'classifier_option_id') = 'string'
                and p_snapshot ? 'classifier_selected'
           then p_snapshot || jsonb_build_object('classifier_selected',
                  exists (select 1 from sel where sel.id = lower(btrim(p_snapshot ->> 'classifier_option_id'))))
           else p_snapshot end
    when 'array' then (
      select coalesce(jsonb_agg(
               case when jsonb_typeof(e.elem) = 'object'
                         and jsonb_typeof(e.elem -> 'classifier_option_id') = 'string'
                         and e.elem ? 'classifier_selected'
                    then e.elem || jsonb_build_object('classifier_selected',
                           exists (select 1 from sel where sel.id = lower(btrim(e.elem ->> 'classifier_option_id'))))
                    else e.elem end
               order by e.ord), '[]'::jsonb)
        from jsonb_array_elements(p_snapshot) with ordinality as e(elem, ord))
    else p_snapshot
  end;
$$;

comment on function app.edit_reanswer_prep(jsonb, jsonb) is
  'ORDER-EDIT-001A (API_CONTRACT §4.45.2 step 8): copies a FROZEN prep snapshot (an item prep_snapshot array or a modifier meat_snapshot object) with every classifier_selected re-answered by the presence of its classifier_option_id in the replacement''s FULL modifier array — the app.trusted_*_prep_snapshot presence rule applied to the frozen link, never the live menu (D-008). Everything else is copied unchanged. Pure. INTERNAL.';

-- Strict JSON integer parser: the value when p is a JSON number written as a
-- plain non-negative integer within [p_min, p_max]; otherwise NULL (no raise).
create or replace function app.edit_json_int(p jsonb, p_min bigint, p_max bigint)
  returns bigint
  language sql
  immutable
  set search_path = ''
as $$
  select case
    when jsonb_typeof(p) = 'number' and (p::text) ~ '^[0-9]{1,18}$' then
      case when (p::text)::bigint between p_min and p_max then (p::text)::bigint end
  end;
$$;

comment on function app.edit_json_int(jsonb, bigint, bigint) is
  'ORDER-EDIT-001A: strict, non-raising JSON integer parser for the order.edit payload — the integer when the value is a JSON number written as a plain non-negative integer within [p_min, p_max], else NULL. INTERNAL.';

-- Strict uuid parser: the uuid when p is the canonical 8-4-4-4-12 text, else
-- NULL (no raise).
create or replace function app.edit_try_uuid(p text)
  returns uuid
  language sql
  immutable
  set search_path = ''
as $$
  select case
    when p ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then p::uuid
  end;
$$;

comment on function app.edit_try_uuid(text) is
  'ORDER-EDIT-001A: strict, non-raising uuid parser for the order.edit payload (canonical 8-4-4-4-12 text only), else NULL. INTERNAL.';

-- The add_order_items per-line block (shape + 002A per-unit arithmetic),
-- COPIED for an added line of an edit. Returns {ok:true, line_total_minor} or
-- {ok:false, error:'invalid_item_payload', detail}. Numeric parse failures keep
-- the structural app.order_parse_minor raise (42501), exactly as add items.
create or replace function app.edit_validate_new_line(p_item jsonb)
  returns jsonb
  language plpgsql
  immutable
  set search_path = ''
as $$
declare
  v_modifier  jsonb;
  v_qty       bigint;
  v_unit      bigint;
  v_mod_qty   bigint;
  v_mod_price bigint;
  v_mod_sum   bigint := 0;
  v_line      bigint;
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'invalid_item_payload', 'detail', 'item_required');
  end if;
  if (p_item ->> 'menu_item_id') is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_item_payload', 'detail', 'menu_item_id_required');
  end if;
  if app.edit_try_uuid(p_item ->> 'menu_item_id') is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_item_payload', 'detail', 'menu_item_id_invalid');
  end if;
  if (p_item ->> 'menu_item_name_snapshot') is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_item_payload', 'detail', 'menu_item_name_snapshot_required');
  end if;
  if (p_item ? 'line_discount_minor') and jsonb_typeof(p_item -> 'line_discount_minor') <> 'null'
     and app.order_parse_minor(p_item -> 'line_discount_minor', 'order_items[].line_discount_minor') <> 0 then
    return jsonb_build_object('ok', false, 'error', 'invalid_item_payload', 'detail', 'line_discount_not_allowed');
  end if;
  v_qty := app.order_parse_minor(p_item -> 'quantity', 'order_items[].quantity');
  if v_qty <= 0 or v_qty > 2147483647 then
    raise exception 'edit_order: order_items[].quantity must be between 1 and 2147483647' using errcode = '42501';
  end if;
  v_unit := app.order_parse_minor(p_item -> 'unit_price_minor_snapshot', 'order_items[].unit_price_minor_snapshot');
  if (p_item ? 'modifiers') and jsonb_typeof(p_item -> 'modifiers') = 'array' then
    for v_modifier in select * from jsonb_array_elements(p_item -> 'modifiers')
    loop
      if (v_modifier ->> 'modifier_option_id') is null then
        return jsonb_build_object('ok', false, 'error', 'invalid_item_payload', 'detail', 'modifier_option_id_required');
      end if;
      if app.edit_try_uuid(v_modifier ->> 'modifier_option_id') is null then
        return jsonb_build_object('ok', false, 'error', 'invalid_item_payload', 'detail', 'modifier_option_id_invalid');
      end if;
      if (v_modifier ->> 'option_name_snapshot') is null then
        return jsonb_build_object('ok', false, 'error', 'invalid_item_payload', 'detail', 'option_name_snapshot_required');
      end if;
      v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
      v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                          then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                          else 1 end;
      if v_mod_qty <= 0 or v_mod_qty > 2147483647 then
        raise exception 'edit_order: modifiers[].quantity must be between 1 and 2147483647' using errcode = '42501';
      end if;
      v_mod_sum := v_mod_sum + v_mod_price * v_mod_qty;
    end loop;
  end if;
  v_line := v_qty * (v_unit + v_mod_sum);
  if v_line < 0 then
    raise exception 'edit_order: computed line_total_minor is negative' using errcode = '42501';
  end if;
  return jsonb_build_object('ok', true, 'line_total_minor', v_line);
end;
$$;

comment on function app.edit_validate_new_line(jsonb) is
  'ORDER-EDIT-001A (API_CONTRACT §4.45.2 step 8): the app.add_order_items per-line shape + 002A per-unit arithmetic block, copied for a line ADDED by an edit (submit_order, add_order_items and the kiosk are not refactored). Returns {ok:true, line_total_minor} or {ok:false, error:invalid_item_payload, detail}; numeric parse failures keep the structural 42501 raise of app.order_parse_minor. Sellability, the 003D option ownership and the 021 prep-staleness checks run in app.edit_order under its locks. Pure. INTERNAL.';

-- Canonical id spelling. app.edit_try_uuid accepts upper- and lower-case hex,
-- but every comparison downstream (the locked-line map, kept-option matching,
-- the continuation test, the classifier presence rule) compares TEXT, and the
-- server's own ids are lower-case uuid::text. Step 2 therefore rewrites every
-- id of a validated change to lower case once, so a client spelling can never
-- change a lookup's outcome.
create or replace function app.edit_canonical_modifiers(p_holder jsonb)
  returns jsonb
  language sql
  immutable
  set search_path = ''
as $$
  select case
    when jsonb_typeof(p_holder) = 'object' and jsonb_typeof(p_holder -> 'modifiers') = 'array' then
      p_holder || jsonb_build_object('modifiers', (
        select coalesce(jsonb_agg(
                 case when jsonb_typeof(m.e) = 'object' and jsonb_typeof(m.e -> 'modifier_option_id') = 'string'
                      then m.e || jsonb_build_object('modifier_option_id', lower(m.e ->> 'modifier_option_id'))
                               || case when jsonb_typeof(m.e -> 'meat_snapshot') = 'object'
                                            and jsonb_typeof(m.e -> 'meat_snapshot' -> 'classifier_option_id') = 'string'
                                       then jsonb_build_object('meat_snapshot', (m.e -> 'meat_snapshot')
                                              || jsonb_build_object('classifier_option_id',
                                                   lower(m.e -> 'meat_snapshot' ->> 'classifier_option_id')))
                                       else '{}'::jsonb end
                      else m.e end
                 order by m.o), '[]'::jsonb)
          from jsonb_array_elements(p_holder -> 'modifiers') with ordinality as m(e, o)))
    else p_holder
  end;
$$;

comment on function app.edit_canonical_modifiers(jsonb) is
  'ORDER-EDIT-001A: lower-cases every modifiers[].modifier_option_id (and a client meat_snapshot.classifier_option_id) of one replacement / added item (non-string or malformed values are left for validation to refuse). Pure. INTERNAL.';

create or replace function app.edit_canonical_change(p_change jsonb)
  returns jsonb
  language sql
  immutable
  set search_path = ''
as $$
  select case
    when jsonb_typeof(p_change) <> 'object' then p_change
    else p_change
      || case when jsonb_typeof(p_change -> 'order_item_id') = 'string'
              then jsonb_build_object('order_item_id', lower(p_change ->> 'order_item_id'))
              else '{}'::jsonb end
      || case when jsonb_typeof(p_change -> 'replacements') = 'array'
              then jsonb_build_object('replacements', (
                     select coalesce(jsonb_agg(app.edit_canonical_modifiers(r.e) order by r.o), '[]'::jsonb)
                       from jsonb_array_elements(p_change -> 'replacements') with ordinality as r(e, o)))
              else '{}'::jsonb end
      || case when jsonb_typeof(p_change -> 'item') = 'object'
              then jsonb_build_object('item', app.edit_canonical_modifiers(
                     (p_change -> 'item')
                     || case when jsonb_typeof(p_change -> 'item' -> 'menu_item_id') = 'string'
                             then jsonb_build_object('menu_item_id', lower(p_change -> 'item' ->> 'menu_item_id'))
                             else '{}'::jsonb end))
              else '{}'::jsonb end
  end;
$$;

comment on function app.edit_canonical_change(jsonb) is
  'ORDER-EDIT-001A: the canonical spelling of one order.edit change — order_item_id, item.menu_item_id and every modifier_option_id lower-cased, so every text comparison in app.edit_order (locked-line lookup, kept-option matching, continuation test, classifier presence) is spelling-independent. Pure. INTERNAL.';

-- One RETURNed refusal: writes the order.edit_denied audit row (the ONLY write
-- a refusal makes) and returns the flat envelope app.sync_push passes through
-- verbatim.
create or replace function app.edit_order_deny(
  p_org            uuid,
  p_rest           uuid,
  p_branch         uuid,
  p_emp            uuid,
  p_device_id      uuid,
  p_order_id       uuid,
  p_role           text,
  p_device_type    text,
  p_order_status   text,
  p_error          text,
  p_detail         text,
  p_denied_reason  text,
  p_envelope_extra jsonb default '{}'::jsonb,
  p_audit_extra    jsonb default '{}'::jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values (p_org, p_rest, p_branch, null, p_emp, p_device_id, 'order.edit_denied', null, null,
          jsonb_strip_nulls(jsonb_build_object(
            'attempted_action', 'edit_order',
            'order_id', p_order_id,
            'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
            'role', p_role,
            'device_type', p_device_type,
            'order_status', p_order_status,
            'denied_reason', p_denied_reason))
          || coalesce(p_audit_extra, '{}'::jsonb));
  return jsonb_strip_nulls(jsonb_build_object(
           'ok', false, 'error', p_error, 'detail', p_detail, 'order_id', p_order_id))
         || coalesce(p_envelope_extra, '{}'::jsonb)
         || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.edit_order_deny(uuid, uuid, uuid, uuid, uuid, uuid, text, text, text, text, text, text, jsonb, jsonb) is
  'ORDER-EDIT-001A: one RETURNed app.edit_order refusal — writes the append-only order.edit_denied audit row {attempted_action:edit_order, order_id, order_code, role, device_type, order_status?, denied_reason} (+ extras) with the PIN-session actor, and returns {ok:false, error, detail?, order_id, ...extras, server_ts, idempotency_replay:false}. denied_reason is the detail token for the shared error/detail pairs (permission_denied / invalid_discount) so existing Activity-log labels are reused. INTERNAL.';

-- The money-free kitchen projection of ONE order line (the exact item shape of
-- app.kitchen_dispatch_payload_initial / _round).
create or replace function app.kitchen_dispatch_item_projection(
  p_organization_id uuid,
  p_order_item_id   uuid
)
  returns jsonb
  language sql
  stable
  set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
           'qty', oi.quantity,
           'name', oi.menu_item_name_snapshot,
           'note', nullif(left(btrim(coalesce(oi.notes, '')), 500), ''),
           'prep', app.kitchen_prep_projection(oi.prep_snapshot),
           'modifiers', (
             select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                      'qty', om.quantity,
                      'name', om.option_name_snapshot,
                      'prep', app.kitchen_modifier_prep_projection(om.meat_snapshot)))
                    order by om.modifier_group_display_order_snapshot asc,
                             om.modifier_option_display_order_snapshot asc,
                             om.line_position asc,
                             om.created_at asc, om.id asc), '[]'::jsonb)
             from public.order_item_modifiers om
             where om.organization_id = oi.organization_id
               and om.order_item_id = oi.id
               and om.deleted_at is null)))
    from public.order_items oi
   where oi.organization_id = p_organization_id
     and oi.id              = p_order_item_id;
$$;

comment on function app.kitchen_dispatch_item_projection(uuid, uuid) is
  'ORDER-EDIT-001A: the money-free kitchen projection of ONE order line — {qty, name, note?, prep?, modifiers[{qty, name, prep?}]} with modifiers in the authoritative dashboard order — the exact item shape of app.kitchen_dispatch_payload_initial / _round. INTERNAL.';

-- The paper-channel change slip (D-044; PRINTERS / API_CONTRACT §4.45.9). Keys
-- avoid the hostile vocabulary (no change/total/price/... token): edit_lines,
-- op, was, now, now_qty, order_now.
--   edit_lines[] (request order): {op:'remove', was} | {op:'set_quantity',
--     was, now_qty} | {op:'modify', was, now[]} | {op:'add', now[]}
--   order_now[]: EVERY live line of the order, canonical menu order — the list
--     that supersedes every earlier ticket of the order.
create or replace function app.kitchen_dispatch_payload_order_edit(
  p_organization_id uuid,
  p_order_id        uuid,
  p_order_edit_id   uuid,
  p_edit_lines      jsonb
)
  returns jsonb
  language sql
  stable
  set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'v', 1,
    'kind', 'order_edit',
    'order_code', '#' || upper(right(replace(o.id::text, '-', ''), 6)),
    'order_type', o.order_type,
    'table_label', tbl.label,
    'customer_display_name', nullif(left(btrim(coalesce(o.customer_name, '')), 80), ''),
    'order_note', nullif(left(btrim(coalesce(o.notes, '')), 500), ''),
    'created_at', e.created_at,
    'edit_number', e.edit_number,
    'reason_code', e.reason_code,
    'reason', nullif(left(btrim(coalesce(e.reason_text, '')), 200), ''),
    'staff_name', nullif(left(split_part(btrim(coalesce(ep.display_name, '')), ' ', 1), 40), ''),
    'edit_lines', (
      select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
               'op', c.elem ->> 'kind',
               'was', case when app.edit_try_uuid(c.elem ->> 'order_item_id') is not null
                           then app.kitchen_dispatch_item_projection(
                                  p_organization_id, (c.elem ->> 'order_item_id')::uuid) end,
               'now_qty', case when c.elem ->> 'kind' = 'set_quantity'
                               then app.edit_json_int(c.elem -> 'quantity', 1, 999) end,
               'now', case when c.elem ->> 'kind' in ('modify', 'add') then (
                        select coalesce(jsonb_agg(
                                 app.kitchen_dispatch_item_projection(p_organization_id, n.id::uuid)
                                 order by n.ord), '[]'::jsonb)
                          from jsonb_array_elements_text(
                                 case when jsonb_typeof(c.elem -> 'new_order_item_ids') = 'array'
                                      then c.elem -> 'new_order_item_ids' else '[]'::jsonb end)
                               with ordinality as n(id, ord)) end))
             order by c.ord), '[]'::jsonb)
        from jsonb_array_elements(
               case when jsonb_typeof(p_edit_lines) = 'array' then p_edit_lines else '[]'::jsonb end)
             with ordinality as c(elem, ord)),
    'order_now', (
      select coalesce(jsonb_agg(app.kitchen_dispatch_item_projection(p_organization_id, oi.id)
             order by coalesce(oi.category_display_order_snapshot, 0),
                      coalesce(oi.item_display_order_snapshot, 0),
                      coalesce(oi.line_position, 0),
                      oi.created_at, oi.id), '[]'::jsonb)
      from public.order_items oi
      where oi.organization_id = o.organization_id
        and oi.order_id = o.id
        and oi.deleted_at is null
        and oi.status not in ('voided', 'cancelled'))))
  from public.orders o
  join public.order_edits e
    on e.organization_id = o.organization_id and e.order_id = o.id and e.id = p_order_edit_id
  left join public.tables tbl
    on tbl.organization_id = o.organization_id and tbl.id = o.table_id
  left join public.employee_profiles ep
    on ep.organization_id = e.organization_id and ep.id = e.employee_profile_id
  where o.organization_id = p_organization_id and o.id = p_order_id;
$$;

comment on function app.kitchen_dispatch_payload_order_edit(uuid, uuid, uuid, jsonb) is
  'ORDER-EDIT-001A (D-044; API_CONTRACT §4.45.9): the MONEY-FREE order_edit change-slip payload — {v:1, kind:order_edit, order_code, order_type, table_label?, customer_display_name?, order_note?, created_at (the edit''s), edit_number, reason_code?, reason?, staff_name? (first name), edit_lines[{op, was?, now_qty?, now?}] in request order, order_now[] = EVERY live line of the order in canonical menu order}; every item is app.kitchen_dispatch_item_projection. Keys avoid the hostile vocabulary; the 32KB cap and key scan of the ledger guard still apply (fail closed). INTERNAL.';

-- The NEW internal creator for the paper-channel order_edit dispatch: key
-- edit:<order_edit_id>, created ALREADY CLAIMED by the acting POS (the
-- KIOSK-PRINT-114B.1 claim-at-submit lease, 10 minutes), superseding every
-- unresolved earlier initial / round / edit dispatch of the order, audited
-- kitchen.dispatch_created. Idempotent on the key (a retry re-reads the row and
-- never re-audits). Runs inside the caller's transaction (fail closed).
create or replace function app.create_order_edit_dispatch(
  p_organization_id           uuid,
  p_restaurant_id             uuid,
  p_branch_id                 uuid,
  p_order_id                  uuid,
  p_order_edit_id             uuid,
  p_payload                   jsonb,
  p_actor_employee_profile_id uuid,
  p_actor_membership_id       uuid,
  p_device_id                 uuid
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_key     text;
  v_id      uuid;
  v_expires timestamptz;
begin
  if p_order_id is null or p_order_edit_id is null or p_device_id is null then
    raise exception 'create_order_edit_dispatch: order, order edit and device are required (fail closed)'
      using errcode = '22023';
  end if;
  v_key := 'edit:' || p_order_edit_id::text;

  insert into public.kitchen_print_dispatches
    (organization_id, restaurant_id, branch_id, order_id, service_round_id,
     dispatch_type, order_edit_id, money_free_payload, idempotency_key,
     claimed_at, claimed_by_device_id, claim_expires_at)
  values
    (p_organization_id, p_restaurant_id, p_branch_id, p_order_id, null,
     'order_edit', p_order_edit_id, p_payload, v_key,
     now(), p_device_id, now() + interval '10 minutes')
  on conflict (organization_id, idempotency_key) do nothing
  returning id, claim_expires_at into v_id, v_expires;

  if v_id is null then
    select d.id, d.claim_expires_at into v_id, v_expires
      from public.kitchen_print_dispatches d
      where d.organization_id = p_organization_id and d.idempotency_key = v_key;
    return jsonb_build_object('id', v_id, 'claim_expires_at', v_expires);
  end if;

  -- The change slip's ORDER NOW list is authoritative: every unresolved
  -- earlier initial / round / edit dispatch of this order is superseded so
  -- stale paper never prints after it (statuses, claims and observability
  -- preserved; completed history stays unlinked; a void is never superseded).
  update public.kitchen_print_dispatches d
    set superseded_by_dispatch_id = v_id, updated_at = now()
    where d.organization_id = p_organization_id
      and d.order_id = p_order_id
      and d.id <> v_id
      and d.dispatch_type in ('initial_order', 'service_round', 'order_edit')
      and d.completed_at is null
      and d.superseded_by_dispatch_id is null;

  insert into public.audit_events
    (organization_id, restaurant_id, branch_id, actor_app_user_id,
     actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values
    (p_organization_id, p_restaurant_id, p_branch_id, null,
     p_actor_employee_profile_id, p_device_id, 'kitchen.dispatch_created', null, null,
     jsonb_build_object(
       'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
       'dispatch_type', 'order_edit',
       'resolved_membership_id', p_actor_membership_id));

  return jsonb_build_object('id', v_id, 'claim_expires_at', v_expires);
end;
$$;

comment on function app.create_order_edit_dispatch(uuid, uuid, uuid, uuid, uuid, jsonb, uuid, uuid, uuid) is
  'ORDER-EDIT-001A INTERNAL (D-044; API_CONTRACT §4.45.9): creates the ONE order_edit kitchen dispatch of a paper-channel edit (idempotency key edit:<order_edit_id>; ON CONFLICT DO NOTHING => a retry returns the same row and never re-audits), born CLAIMED by the acting POS (claimed_at = now(), claimed_by_device_id = the device, claim_expires_at = now() + 10 minutes), superseding every unresolved earlier initial_order / service_round / order_edit dispatch of the order. Audits kitchen.dispatch_created {order_code, dispatch_type: order_edit, resolved_membership_id}. Returns {id, claim_expires_at}. Runs INSIDE the caller''s transaction (fail closed). The pinned 10-argument app.create_kitchen_dispatch is untouched. NEVER granted to client roles.';

-- ----------------------------------------------------------------------------
-- app.edit_order — sync op order.edit (API_CONTRACT §4.45)
-- ----------------------------------------------------------------------------
create or replace function app.edit_order(
  p_pin_session_id     uuid,
  p_order_id           uuid,
  p_device_id          uuid,
  p_local_operation_id text,
  p_payload            jsonb,
  p_client_created_at  timestamptz default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  -- (session)
  v_org          uuid;
  v_rest         uuid;
  v_branch       uuid;
  v_dsid         uuid;
  v_emp          uuid;
  v_membership   uuid;
  v_ds_device    uuid;
  v_ds_active    boolean;
  v_ds_revoked   timestamptz;
  v_pairing      text;
  v_role         text;
  v_m_status     text;
  v_m_deleted    timestamptz;
  v_m_perms      jsonb;
  v_device_type  text;
  v_order_code   text := '#' || upper(right(replace(p_order_id::text, '-', ''), 6));
  -- (payload)
  v_changes      jsonb;
  v_change       jsonb;
  v_rep          jsonb;
  v_mod          jsonb;
  v_op           text;
  v_n            integer;
  v_i            integer;
  v_j            integer;
  v_shape        text;
  v_ref          uuid;
  v_ref_ids      uuid[] := '{}'::uuid[];
  v_reason_code  text;
  v_reason_text  text;
  v_bill_at      timestamptz;
  v_exp_sub      bigint;
  v_exp_tax      bigint;
  v_exp_grand    bigint;
  v_qty          bigint;
  -- (replay)
  v_ex_order     uuid;
  v_ex_result    jsonb;
  -- (order + branch, under the locks)
  v_o_status     text;
  v_o_type       text;
  v_o_rev        integer;
  v_o_sub        bigint;
  v_o_disc       bigint;
  v_o_tax        bigint;
  v_o_grand      bigint;
  v_o_dispatch   text;
  v_o_edit_count integer;
  v_b_enabled    boolean;
  v_b_ff_manager boolean;
  v_b_mode       text;
  v_b_tax_on     boolean;
  v_b_tax_bp     integer;
  v_b_tax_mode   text;
  v_channel      text;
  -- (lines + plan)
  v_lines        jsonb;
  v_line         jsonb;
  v_stale        jsonb;
  v_old_mods     jsonb;
  v_stage        text;
  v_ukey         text;
  v_unit_status  jsonb;
  v_unit_count   jsonb;
  v_has_removing boolean := false;
  v_may_void     boolean;
  v_may_comp     boolean;
  v_outcome      text;
  v_retire       jsonb := '[]'::jsonb;
  v_rows         jsonb := '[]'::jsonb;
  v_chg          jsonb := '[]'::jsonb;
  v_sell         jsonb := '[]'::jsonb;
  v_newopts      jsonb := '[]'::jsonb;
  v_comp_mods    jsonb;
  v_rep_mods     jsonb;
  v_kept         jsonb;
  v_landing      text;
  v_finished     boolean;
  v_waiting      boolean;
  v_unit_price   bigint;
  v_mod_sum      bigint;
  v_line_total   bigint;
  v_old_pairs    jsonb;
  v_new_pairs    jsonb;
  v_is_cont      boolean;
  v_changed_qty  bigint;
  v_budget       bigint;
  v_take         bigint;
  v_excess       bigint;
  v_rep_total    bigint;
  v_take_changed bigint;
  v_pass         integer;
  v_after_qty    bigint;
  v_after_total  bigint;
  v_valid        jsonb;
  v_menu_ids     uuid[];
  v_unavailable  jsonb;
  v_bad_mods     jsonb;
  v_stale_mods   jsonb;
  v_need_round   boolean := false;
  v_ack_required boolean := false;
  v_live_before  integer;
  v_live_total   bigint;
  v_retired_total bigint := 0;
  v_new_total    bigint := 0;
  v_new_count    integer := 0;
  v_new_sub      bigint;
  v_new_tax      bigint;
  v_new_grand    bigint;
  v_closed_rounds uuid[] := '{}'::uuid[];
  v_unit1_closed boolean := false;
  -- (writes)
  v_edit_id      uuid;
  v_edit_number  integer;
  v_round_id     uuid;
  v_round_no     integer;
  v_row          jsonb;
  v_new_id       uuid;
  v_row_ids      jsonb := '{}'::jsonb;
  v_new_rev      integer;
  v_new_status   text;
  v_dispatch     jsonb;
  v_auto         jsonb;
  v_env_changes  jsonb;
  v_audit_changes jsonb;
  v_rounds_closed jsonb;
  v_result       jsonb;
  v_final_rev    integer;
  v_final_status text;
begin
  -- ==========================================================================
  -- STEP 1 — the canonical PIN-session preamble (add_order_items parity):
  -- every structural failure RAISES 42501. Scope comes ONLY from the session.
  -- ==========================================================================
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'edit_order: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'edit_order: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'edit_order: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'edit_order: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at, m.permissions
    into v_role, v_m_status, v_m_deleted, v_m_perms
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'edit_order: resolved membership is not active' using errcode = '42501';
  end if;
  if p_local_operation_id is null or btrim(p_local_operation_id) = '' then
    raise exception 'edit_order: local_operation_id is required' using errcode = '42501';
  end if;

  -- Device class: only a POS edits orders (never the KDS, a kiosk or the
  -- Dashboard) — refused exactly as app.add_order_items refuses it.
  select d.device_type into v_device_type
    from public.devices d
    where d.id = p_device_id and d.organization_id = v_org;
  if v_device_type is distinct from 'pos' then
    return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
      v_role, coalesce(v_device_type, 'unknown'), null,
      'invalid_device_type', null, 'invalid_device_type');
  end if;
  if v_role not in ('cashier', 'manager', 'restaurant_owner', 'org_owner') then
    return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
      v_role, v_device_type, null, 'permission_denied', null, 'permission_denied');
  end if;

  -- ==========================================================================
  -- STEP 2 — payload shape (no lock, no write).
  -- ==========================================================================
  v_shape := null;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    v_shape := 'invalid_payload';
  else
    v_changes := p_payload -> 'changes';
    if v_changes is null or jsonb_typeof(v_changes) <> 'array' then
      v_shape := 'invalid_payload';
    elsif jsonb_array_length(v_changes) = 0 then
      v_shape := 'no_changes';
    elsif jsonb_array_length(v_changes) > 100 then
      v_shape := 'too_many_changes';
    end if;
  end if;

  if v_shape is null then
    v_n := jsonb_array_length(v_changes);
    for v_i in 0 .. v_n - 1 loop
      v_change := v_changes -> v_i;
      if jsonb_typeof(v_change) is distinct from 'object'
         or jsonb_typeof(v_change -> 'op') is distinct from 'string'
         or coalesce(v_change ->> 'op', '') not in ('remove', 'set_quantity', 'modify', 'add') then
        v_shape := 'invalid_payload';
        exit;
      end if;
      v_op := v_change ->> 'op';
      if v_op in ('remove', 'set_quantity', 'modify') then
        v_ref := case when jsonb_typeof(v_change -> 'order_item_id') = 'string'
                      then app.edit_try_uuid(v_change ->> 'order_item_id') end;
        if v_ref is null then
          v_shape := 'invalid_payload';
          exit;
        end if;
        if v_ref = any (v_ref_ids) then
          v_shape := 'duplicate_line_reference';
          exit;
        end if;
        v_ref_ids := v_ref_ids || v_ref;
      end if;
      if v_op = 'set_quantity' and app.edit_json_int(v_change -> 'quantity', 1, 999) is null then
        v_shape := 'invalid_payload';
        exit;
      end if;
      if v_op = 'modify' then
        if (case when jsonb_typeof(v_change -> 'replacements') is distinct from 'array' then true
                 when jsonb_array_length(v_change -> 'replacements') not between 1 and 20 then true
                 else false end) then
          v_shape := 'invalid_payload';
          exit;
        end if;
        for v_rep in select * from jsonb_array_elements(v_change -> 'replacements')
        loop
          if jsonb_typeof(v_rep) is distinct from 'object'
             or app.edit_json_int(v_rep -> 'quantity', 1, 999) is null
             or (v_rep ? 'notes' and coalesce(jsonb_typeof(v_rep -> 'notes'), '') not in ('string', 'null'))
             or (v_rep ? 'modifiers' and coalesce(jsonb_typeof(v_rep -> 'modifiers'), '') not in ('array', 'null')) then
            v_shape := 'invalid_payload';
            exit;
          end if;
          if jsonb_typeof(v_rep -> 'modifiers') = 'array' then
            for v_mod in select * from jsonb_array_elements(v_rep -> 'modifiers')
            loop
              if jsonb_typeof(v_mod) is distinct from 'object'
                 or jsonb_typeof(v_mod -> 'modifier_option_id') is distinct from 'string'
                 or app.edit_try_uuid(v_mod ->> 'modifier_option_id') is null
                 or (v_mod ? 'quantity' and jsonb_typeof(v_mod -> 'quantity') <> 'null'
                     and app.edit_json_int(v_mod -> 'quantity', 1, 2147483647) is null)
                 or (v_mod ? 'price_minor_snapshot' and jsonb_typeof(v_mod -> 'price_minor_snapshot') <> 'null'
                     and app.edit_json_int(v_mod -> 'price_minor_snapshot', 0, 999999999999) is null) then
                v_shape := 'invalid_payload';
                exit;
              end if;
            end loop;
          end if;
          exit when v_shape is not null;
        end loop;
        exit when v_shape is not null;
      end if;
      if v_op = 'add' and jsonb_typeof(v_change -> 'item') is distinct from 'object' then
        v_shape := 'invalid_payload';
        exit;
      end if;
      -- the validated change, with every id in its canonical (lower-case) form.
      v_changes := jsonb_set(v_changes, array[v_i::text], app.edit_canonical_change(v_change));
    end loop;
  end if;

  if v_shape is null then
    if jsonb_typeof(p_payload -> 'expected') is distinct from 'object' then
      v_shape := 'expected_totals_required';
    else
      v_exp_sub   := app.edit_json_int(p_payload -> 'expected' -> 'subtotal_minor', 0, 999999999999999999);
      v_exp_tax   := app.edit_json_int(p_payload -> 'expected' -> 'tax_total_minor', 0, 999999999999999999);
      v_exp_grand := app.edit_json_int(p_payload -> 'expected' -> 'grand_total_minor', 0, 999999999999999999);
      if v_exp_sub is null or v_exp_tax is null or v_exp_grand is null then
        v_shape := 'expected_totals_required';
      end if;
    end if;
  end if;

  if v_shape is null then
    if p_payload ? 'reason_code' and jsonb_typeof(p_payload -> 'reason_code') <> 'null' then
      if jsonb_typeof(p_payload -> 'reason_code') <> 'string'
         or (p_payload ->> 'reason_code') not in
            ('customer_changed_mind', 'entry_mistake', 'item_unavailable', 'kitchen_issue', 'other') then
        v_shape := 'invalid_payload';
      else
        v_reason_code := p_payload ->> 'reason_code';
      end if;
    end if;
    if p_payload ? 'reason_text' and jsonb_typeof(p_payload -> 'reason_text') <> 'null' then
      if jsonb_typeof(p_payload -> 'reason_text') <> 'string' then
        v_shape := 'invalid_payload';
      else
        v_reason_text := nullif(btrim(p_payload ->> 'reason_text'), '');
        if char_length(v_reason_text) > 200 then
          v_shape := 'invalid_payload';
        end if;
      end if;
    end if;
    if p_payload ? 'bill_presented_at' and jsonb_typeof(p_payload -> 'bill_presented_at') <> 'null' then
      if jsonb_typeof(p_payload -> 'bill_presented_at') <> 'string' then
        v_shape := 'invalid_payload';
      else
        begin
          -- one wire format: an RFC 3339 instant with an explicit Z / +-HH:MM
          -- offset (the storefront paused_until rule), so the stored instant
          -- never depends on the session time zone or a relative word.
          if (p_payload ->> 'bill_presented_at')
             !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}(:[0-9]{2}(\.[0-9]{1,6})?)?(Z|[+-][0-9]{2}:[0-9]{2})$' then
            v_shape := 'invalid_payload';
          else
            v_bill_at := (p_payload ->> 'bill_presented_at')::timestamptz;
          end if;
        exception when others then
          v_shape := 'invalid_payload';
        end;
      end if;
    end if;
  end if;

  if v_shape is not null then
    return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
      v_role, v_device_type, null, v_shape, null, v_shape);
  end if;

  -- ==========================================================================
  -- STEP 3 — business replay (D-022): the same (org, device, operation id) on
  -- the SAME order returns the stored envelope; on ANOTHER order RAISE 40001.
  -- ==========================================================================
  select e.order_id into v_ex_order
    from public.order_edits e
    where e.organization_id    = v_org
      and e.device_id          = p_device_id
      and e.local_operation_id = p_local_operation_id;
  if found then
    if v_ex_order <> p_order_id then
      raise exception 'edit_order: idempotency key already used for a different order (%, not %)', v_ex_order, p_order_id using errcode = '40001';
    end if;
    select oo.result into v_ex_result
      from public.order_operations oo
      where oo.organization_id    = v_org
        and oo.device_id          = p_device_id
        and oo.local_operation_id = p_local_operation_id
        and oo.action             = 'edit_order';
    if v_ex_result is null then
      raise exception 'edit_order: stored edit envelope missing (state inconsistency)';
    end if;
    return v_ex_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', true);
  end if;

  -- ==========================================================================
  -- STEP 4 — locks: orders FOR UPDATE FIRST (anti-oracle: a nonexistent and a
  -- foreign order RAISE the same 42501, R-003), then the order's rounds, then
  -- the referenced items, each in ascending id order (menu items in step 8).
  -- ==========================================================================
  select o.status, o.order_type, o.revision, o.subtotal_minor, o.discount_total_minor,
         o.tax_total_minor, o.grand_total_minor, o.dispatch_mode, o.edit_count
    into v_o_status, v_o_type, v_o_rev, v_o_sub, v_o_disc,
         v_o_tax, v_o_grand, v_o_dispatch, v_o_edit_count
    from public.orders o
    where o.id = p_order_id
      and o.organization_id = v_org
      and o.restaurant_id   = v_rest
      and o.branch_id       = v_branch
      and o.deleted_at is null
    for update;
  if not found then
    raise exception 'edit_order: order_not_found_or_not_accessible' using errcode = '42501';
  end if;

  perform 1 from public.order_service_rounds r
    where r.organization_id = v_org and r.order_id = p_order_id
    order by r.id
    for update;
  perform 1 from public.order_items oi
    where oi.organization_id = v_org and oi.order_id = p_order_id and oi.id = any (v_ref_ids)
    order by oi.id
    for update;

  -- ==========================================================================
  -- STEP 5 — gates. The branch row is share-locked (after the order, the
  -- apply_direct_print_dispatch order) so the kitchen mode and the switches
  -- cannot move under this edit.
  -- ==========================================================================
  select b.order_edit_enabled, b.order_edit_finished_food_manager_only, b.kitchen_workflow_mode,
         b.tax_enabled, b.tax_rate_bp, b.tax_mode
    into v_b_enabled, v_b_ff_manager, v_b_mode, v_b_tax_on, v_b_tax_bp, v_b_tax_mode
    from public.branches b
    where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null
    for share;
  if not found then
    raise exception 'edit_order: branch row unavailable (state inconsistency)';
  end if;

  if not coalesce(v_b_enabled, false) then
    return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
      v_role, v_device_type, v_o_status, 'feature_disabled', null, 'feature_disabled');
  end if;
  if v_o_type not in ('dine_in', 'takeaway')
     or v_o_status not in ('submitted', 'accepted', 'preparing', 'ready', 'served') then
    return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
      v_role, v_device_type, v_o_status, 'order_not_editable', null, 'order_not_editable',
      jsonb_build_object('order_status', v_o_status));
  end if;
  if exists (
       select 1 from public.payments p
       where p.organization_id = v_org
         and p.order_id = p_order_id
         and p.status = 'completed'
         and p.deleted_at is null) then
    return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
      v_role, v_device_type, v_o_status, 'order_already_settled', null, 'order_already_settled');
  end if;
  -- Kitchen channel: paper iff the branch is printer_only; a direct_print order
  -- on a branch that has since switched to KDS has no resolvable channel.
  if v_b_mode = 'printer_only' then
    v_channel := 'paper';
  elsif coalesce(v_o_dispatch, 'kds') = 'direct_print' then
    return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
      v_role, v_device_type, v_o_status, 'kitchen_mode_changed', null, 'kitchen_mode_changed');
  else
    v_channel := 'kds';
  end if;

  -- ==========================================================================
  -- STEP 6 — every referenced id must be a LIVE line of THIS order. A foreign,
  -- a retired and a missing id all return the same line_changed.
  -- ==========================================================================
  select coalesce(jsonb_object_agg(oi.id::text, jsonb_build_object(
           'id', oi.id,
           'status', oi.status,
           'quantity', oi.quantity,
           'menu_item_id', oi.menu_item_id,
           'name', oi.menu_item_name_snapshot,
           'unit', oi.unit_price_minor_snapshot,
           'size', oi.item_size_snapshot,
           'variant', oi.item_variant_snapshot,
           'line_discount', oi.line_discount_minor,
           'line_total', oi.line_total_minor,
           'notes', oi.notes,
           'prep', oi.prep_snapshot,
           'round_id', oi.service_round_id,
           'line_position', oi.line_position,
           'unit_stage', case when oi.service_round_id is null then v_o_status else r.status end,
           'legacy', app.order_item_is_legacy_priced(v_org, oi.id))), '{}'::jsonb)
    into v_lines
    from public.order_items oi
    left join public.order_service_rounds r
      on r.organization_id = oi.organization_id and r.id = oi.service_round_id
    where oi.organization_id = v_org
      and oi.order_id = p_order_id
      and oi.id = any (v_ref_ids)
      and oi.deleted_at is null
      and oi.status not in ('voided', 'cancelled');

  select jsonb_agg(x.id order by x.id) into v_stale
    from unnest(v_ref_ids) as x(id)
    where not (v_lines ? x.id::text);
  if v_stale is not null then
    return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
      v_role, v_device_type, v_o_status, 'line_changed', null, 'line_changed',
      jsonb_build_object('stale_ids', v_stale));
  end if;

  for v_i in 0 .. v_n - 1 loop
    v_change := v_changes -> v_i;
    if (v_change ->> 'op') in ('modify', 'set_quantity') then
      v_line := v_lines -> (v_change ->> 'order_item_id');
      if v_line is null then
        raise exception 'edit_order: locked line lookup failed (state inconsistency)';
      end if;
      if (v_line ->> 'line_discount')::bigint <> 0 then
        return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
          v_role, v_device_type, v_o_status, 'line_has_discount', null, 'line_has_discount');
      end if;
      if (v_line ->> 'legacy')::boolean then
        return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
          v_role, v_device_type, v_o_status, 'legacy_line_not_editable', null, 'legacy_line_not_editable');
      end if;
      if (v_change ->> 'op') = 'set_quantity'
         and app.edit_json_int(v_change -> 'quantity', 1, 999) = (v_line ->> 'quantity')::bigint then
        -- a no-op quantity change is not an edit.
        return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
          v_role, v_device_type, v_o_status, 'invalid_payload', null, 'invalid_payload');
      end if;
    end if;
  end loop;

  -- ==========================================================================
  -- STEP 6a — authority and reason (needs the locked line). A remove, a modify
  -- or a quantity REDUCTION is a removing change; an add or an INCREASE is an
  -- adding change and needs neither void_order nor a reason.
  -- ==========================================================================
  for v_i in 0 .. v_n - 1 loop
    v_change := v_changes -> v_i;
    v_op := v_change ->> 'op';
    if v_op in ('remove', 'modify')
       or (v_op = 'set_quantity'
           and app.edit_json_int(v_change -> 'quantity', 1, 999)
               < coalesce(((v_lines -> (v_change ->> 'order_item_id')) ->> 'quantity')::bigint, 0)) then
      v_has_removing := true;
    end if;
  end loop;
  v_may_void := v_role in ('manager', 'restaurant_owner', 'org_owner')
                or app.cashier_capability_allowed(v_role, v_m_perms, 'void_order');
  if v_has_removing and not v_may_void then
    return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
      v_role, v_device_type, v_o_status, 'permission_denied', 'removal_not_permitted', 'removal_not_permitted');
  end if;
  if (v_has_removing and v_reason_code is null)
     or (v_reason_code = 'other' and v_reason_text is null) then
    return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
      v_role, v_device_type, v_o_status, 'reason_required', null, 'reason_required');
  end if;

  -- ==========================================================================
  -- STEP 7 — finished food (KDS channel only): a cashier removing, reducing
  -- or modifying a line of a ready/served unit while the switch is ON.
  -- ==========================================================================
  if v_channel = 'kds' and coalesce(v_b_ff_manager, false) and v_role = 'cashier' then
    for v_i in 0 .. v_n - 1 loop
      v_change := v_changes -> v_i;
      v_op := v_change ->> 'op';
      continue when v_op = 'add';
      v_line := v_lines -> (v_change ->> 'order_item_id');
      continue when v_op = 'set_quantity'
                    and app.edit_json_int(v_change -> 'quantity', 1, 999) > (v_line ->> 'quantity')::bigint;
      if (v_line ->> 'unit_stage') in ('ready', 'served') then
        return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
          v_role, v_device_type, v_o_status, 'permission_denied', 'finished_food_needs_manager', 'finished_food_needs_manager');
      end if;
    end loop;
  end if;

  -- ==========================================================================
  -- STEPS 8 + 9 — the plan, in memory: each old line's outcome, every new row
  -- (remainder / delta / continuation / replacement / excess / added) and its
  -- landing (§4.45.4), at most one new round. Snapshots of continuation,
  -- replacement and delta rows are COPIED server-side from the old row (D-008).
  -- ==========================================================================
  for v_i in 0 .. v_n - 1 loop
    v_change := v_changes -> v_i;
    v_op := v_change ->> 'op';

    if v_op = 'add' then
      v_valid := app.edit_validate_new_line(v_change -> 'item');
      if not (v_valid ->> 'ok')::boolean then
        return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
          v_role, v_device_type, v_o_status, 'invalid_item_payload', v_valid ->> 'detail', 'invalid_item_payload');
      end if;
      -- add: into the ORIGINAL ticket while it is still Waiting on the KDS
      -- channel; otherwise into the edit's round.
      v_landing := case when v_channel = 'kds' and v_o_status = 'submitted' then 'original' else 'edit_round' end;
      v_need_round := v_need_round or v_landing = 'edit_round';
      select coalesce(jsonb_agg(jsonb_build_object(
               'modifier_option_id', m ->> 'modifier_option_id',
               'modifier_name_snapshot', m ->> 'modifier_name_snapshot',
               'option_name_snapshot', m ->> 'option_name_snapshot',
               'price_minor_snapshot', app.order_parse_minor(m -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot'),
               'quantity', case when (m ? 'quantity') and jsonb_typeof(m -> 'quantity') <> 'null'
                                then app.order_parse_minor(m -> 'quantity', 'modifiers[].quantity') else 1 end,
               'meat_snapshot', app.kitchen_modifier_prep_projection(m -> 'meat_snapshot'),
               'kept', false) order by o.ord), '[]'::jsonb)
        into v_comp_mods
        from jsonb_array_elements(
               case when jsonb_typeof(v_change -> 'item' -> 'modifiers') = 'array'
                    then v_change -> 'item' -> 'modifiers' else '[]'::jsonb end)
             with ordinality as o(m, ord);
      v_rows := v_rows || jsonb_build_array(jsonb_build_object(
        'ci', v_i, 'role', 'added', 'landing', v_landing, 'round_id', null,
        'replaces', null, 'restore_from', null, 'status', 'pending', 'line_position', 0,
        'menu_item_id', v_change -> 'item' ->> 'menu_item_id',
        'name', v_change -> 'item' ->> 'menu_item_name_snapshot',
        'unit', app.order_parse_minor(v_change -> 'item' -> 'unit_price_minor_snapshot', 'order_items[].unit_price_minor_snapshot'),
        'size', v_change -> 'item' -> 'item_size_snapshot',
        'variant', v_change -> 'item' -> 'item_variant_snapshot',
        'qty', app.order_parse_minor(v_change -> 'item' -> 'quantity', 'order_items[].quantity'),
        'notes', v_change -> 'item' ->> 'notes',
        'prep', v_change -> 'item' -> 'prep_snapshot',
        'line_total', (v_valid ->> 'line_total_minor')::bigint,
        'modifiers', v_comp_mods));
      v_sell := v_sell || jsonb_build_array(jsonb_build_object(
        'menu_item_id', v_change -> 'item' ->> 'menu_item_id',
        'name', v_change -> 'item' ->> 'menu_item_name_snapshot'));
      select v_newopts || coalesce(jsonb_agg(jsonb_build_object(
               'menu_item_id', v_change -> 'item' ->> 'menu_item_id',
               'modifier_option_id', m ->> 'modifier_option_id',
               'option_name_snapshot', m ->> 'option_name_snapshot',
               'meat_snapshot', m -> 'meat_snapshot',
               'full', v_change -> 'item' -> 'modifiers')), '[]'::jsonb)
        into v_newopts
        from jsonb_array_elements(
               case when jsonb_typeof(v_change -> 'item' -> 'modifiers') = 'array'
                    then v_change -> 'item' -> 'modifiers' else '[]'::jsonb end) m;
      v_chg := v_chg || jsonb_build_array(jsonb_build_object(
        'ci', v_i, 'kind', 'add', 'order_item_id', null,
        'outcome_status', 'added',
        'unit_stage', case when v_channel = 'paper' then 'printed' else v_o_status end,
        'remake', false, 'name', v_change -> 'item' ->> 'menu_item_name_snapshot',
        'before_quantity', null, 'before_total_minor', null,
        'after_quantity', app.order_parse_minor(v_change -> 'item' -> 'quantity', 'order_items[].quantity'),
        'after_total_minor', (v_valid ->> 'line_total_minor')::bigint));
      continue;
    end if;

    -- remove / set_quantity / modify: the locked old line and its modifiers.
    v_line  := v_lines -> (v_change ->> 'order_item_id');
    if v_line is null then
      raise exception 'edit_order: locked line lookup failed (state inconsistency)';
    end if;
    v_stage := v_line ->> 'unit_stage';
    v_waiting  := v_channel = 'kds' and v_stage = 'submitted';
    v_finished := v_channel = 'paper' or v_stage in ('ready', 'served');
    select coalesce(jsonb_agg(jsonb_build_object(
             'modifier_option_id', m.modifier_option_id,
             'modifier_name_snapshot', m.modifier_name_snapshot,
             'option_name_snapshot', m.option_name_snapshot,
             'price_minor_snapshot', m.price_minor_snapshot,
             'quantity', m.quantity,
             'meat_snapshot', m.meat_snapshot,
             'kept', true)
             order by m.modifier_group_display_order_snapshot, m.modifier_option_display_order_snapshot,
                      m.line_position, m.created_at, m.id), '[]'::jsonb)
      into v_old_mods
      from public.order_item_modifiers m
      where m.organization_id = v_org
        and m.order_item_id = (v_line ->> 'id')::uuid
        and m.deleted_at is null;
    select coalesce(sum((m ->> 'price_minor_snapshot')::bigint * (m ->> 'quantity')::bigint), 0)
      into v_mod_sum from jsonb_array_elements(v_old_mods) m;
    v_unit_price := (v_line ->> 'unit')::bigint + v_mod_sum;
    v_qty := app.edit_json_int(v_change -> 'quantity', 1, 999);

    -- INCREASE: the old line is KEPT; a +N delta row (no replaces) lands in
    -- place while the unit is Waiting / In kitchen, else in the edit's round.
    if v_op = 'set_quantity' and v_qty > (v_line ->> 'quantity')::bigint then
      v_landing := case when v_channel = 'kds' and v_stage in ('submitted', 'accepted', 'preparing')
                        then 'in_place' else 'edit_round' end;
      v_need_round := v_need_round or v_landing = 'edit_round';
      v_rows := v_rows || jsonb_build_array(v_line - 'id' - 'status' - 'quantity' - 'legacy' - 'line_total'
        || jsonb_build_object(
          'ci', v_i, 'role', 'delta', 'landing', v_landing,
          'replaces', null, 'restore_from', v_line ->> 'id',
          'status', case when v_landing = 'in_place' then v_line ->> 'status' else 'pending' end,
          'line_position', case when v_landing = 'in_place' then (v_line ->> 'line_position')::int else 0 end,
          'qty', v_qty - (v_line ->> 'quantity')::bigint,
          'line_total', (v_qty - (v_line ->> 'quantity')::bigint) * v_unit_price,
          'modifiers', v_old_mods));
      v_sell := v_sell || jsonb_build_array(jsonb_build_object(
        'menu_item_id', v_line ->> 'menu_item_id', 'name', v_line ->> 'name'));
      v_chg := v_chg || jsonb_build_array(jsonb_build_object(
        'ci', v_i, 'kind', 'set_quantity', 'order_item_id', v_line ->> 'id',
        'outcome_status', 'kept',
        'unit_stage', case when v_channel = 'paper' then 'printed' else v_stage end,
        'remake', false, 'name', v_line ->> 'name', 'quantity', v_qty,
        'before_quantity', (v_line ->> 'quantity')::bigint,
        'before_total_minor', (v_line ->> 'line_total')::bigint,
        'after_quantity', v_qty,
        'after_total_minor', (v_line ->> 'line_total')::bigint
                             + (v_qty - (v_line ->> 'quantity')::bigint) * v_unit_price));
      continue;
    end if;

    -- remove / reduce / modify RETIRE the old line: cancelled iff its unit is
    -- still Waiting on the KDS channel, otherwise voided (paper: always voided,
    -- stage printed).
    v_outcome := case when v_waiting then 'cancelled' else 'voided' end;
    v_retire := v_retire || jsonb_build_array(jsonb_build_object(
      'old_id', v_line ->> 'id',
      'outcome', v_outcome,
      'stage', case when v_channel = 'paper' then 'printed' else v_stage end,
      'unit', coalesce(v_line ->> 'round_id', 'original'),
      'line_total', (v_line ->> 'line_total')::bigint));

    if v_op = 'remove' then
      v_chg := v_chg || jsonb_build_array(jsonb_build_object(
        'ci', v_i, 'kind', 'remove', 'order_item_id', v_line ->> 'id',
        'outcome_status', v_outcome,
        'unit_stage', case when v_channel = 'paper' then 'printed' else v_stage end,
        'remake', false, 'name', v_line ->> 'name',
        'before_quantity', (v_line ->> 'quantity')::bigint,
        'before_total_minor', (v_line ->> 'line_total')::bigint,
        'after_quantity', 0, 'after_total_minor', 0));
      continue;
    end if;

    if v_op = 'set_quantity' then
      -- REDUCE: the remainder is written in place (nothing is re-cooked).
      v_rows := v_rows || jsonb_build_array(v_line - 'id' - 'status' - 'quantity' - 'legacy' - 'line_total'
        || jsonb_build_object(
          'ci', v_i, 'role', 'remainder', 'landing', 'in_place',
          'replaces', v_line ->> 'id', 'restore_from', v_line ->> 'id',
          'status', v_line ->> 'status',
          'line_position', (v_line ->> 'line_position')::int,
          'qty', v_qty, 'line_total', v_qty * v_unit_price,
          'modifiers', v_old_mods));
      v_chg := v_chg || jsonb_build_array(jsonb_build_object(
        'ci', v_i, 'kind', 'set_quantity', 'order_item_id', v_line ->> 'id',
        'outcome_status', v_outcome,
        'unit_stage', case when v_channel = 'paper' then 'printed' else v_stage end,
        'remake', false, 'name', v_line ->> 'name', 'quantity', v_qty,
        'before_quantity', (v_line ->> 'quantity')::bigint,
        'before_total_minor', (v_line ->> 'line_total')::bigint,
        'after_quantity', v_qty, 'after_total_minor', v_qty * v_unit_price));
      continue;
    end if;

    -- MODIFY: modifiers and note only — size, variant and base price are
    -- copied from the old row. Each replacement is composed first; an
    -- unchanged replacement (same option set + quantities, same note) is a
    -- CONTINUATION.
    select coalesce(jsonb_agg(jsonb_build_array(m ->> 'modifier_option_id', (m ->> 'quantity')::bigint)
             order by m ->> 'modifier_option_id', (m ->> 'quantity')::bigint), '[]'::jsonb)
      into v_old_pairs from jsonb_array_elements(v_old_mods) m;

    -- pass 1: compose every replacement; collect the changed quantity (the old
    -- dishes the changed replacements consume).
    v_changed_qty := 0;
    v_rep_total := 0;
    v_after_qty := 0;
    for v_j in 0 .. jsonb_array_length(v_change -> 'replacements') - 1 loop
      v_rep := v_change -> 'replacements' -> v_j;
      v_rep_mods := case when jsonb_typeof(v_rep -> 'modifiers') = 'array' then v_rep -> 'modifiers' else '[]'::jsonb end;
      v_comp_mods := '[]'::jsonb;
      for v_mod in select * from jsonb_array_elements(v_rep_mods)
      loop
        select k into v_kept
          from jsonb_array_elements(v_old_mods) k
          where k ->> 'modifier_option_id' = (v_mod ->> 'modifier_option_id')
          limit 1;
        if v_kept is not null then
          -- KEPT option: the old row's price / name snapshots; its frozen meat
          -- link re-answered against the replacement's FULL option set.
          v_comp_mods := v_comp_mods || jsonb_build_array(v_kept || jsonb_build_object(
            'quantity', coalesce(app.edit_json_int(v_mod -> 'quantity', 1, 2147483647), (v_kept ->> 'quantity')::bigint),
            'meat_snapshot', app.edit_reanswer_prep(v_kept -> 'meat_snapshot', v_rep_mods)));
        else
          -- NEW option: carries its full client snapshot (validated in step 8).
          if (v_mod ->> 'option_name_snapshot') is null then
            return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
              v_role, v_device_type, v_o_status, 'invalid_item_payload', 'option_name_snapshot_required', 'invalid_item_payload');
          end if;
          if app.edit_json_int(v_mod -> 'price_minor_snapshot', 0, 999999999999) is null then
            return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
              v_role, v_device_type, v_o_status, 'invalid_item_payload', 'price_minor_snapshot_required', 'invalid_item_payload');
          end if;
          v_comp_mods := v_comp_mods || jsonb_build_array(jsonb_build_object(
            'modifier_option_id', v_mod ->> 'modifier_option_id',
            'modifier_name_snapshot', v_mod ->> 'modifier_name_snapshot',
            'option_name_snapshot', v_mod ->> 'option_name_snapshot',
            'price_minor_snapshot', app.edit_json_int(v_mod -> 'price_minor_snapshot', 0, 999999999999),
            'quantity', coalesce(app.edit_json_int(v_mod -> 'quantity', 1, 2147483647), 1),
            'meat_snapshot', app.kitchen_modifier_prep_projection(v_mod -> 'meat_snapshot'),
            'kept', false));
          v_newopts := v_newopts || jsonb_build_array(jsonb_build_object(
            'menu_item_id', v_line ->> 'menu_item_id',
            'modifier_option_id', v_mod ->> 'modifier_option_id',
            'option_name_snapshot', v_mod ->> 'option_name_snapshot',
            'meat_snapshot', v_mod -> 'meat_snapshot',
            'full', v_rep_mods));
        end if;
      end loop;
      select coalesce(jsonb_agg(jsonb_build_array(m ->> 'modifier_option_id', (m ->> 'quantity')::bigint)
               order by m ->> 'modifier_option_id', (m ->> 'quantity')::bigint), '[]'::jsonb)
        into v_new_pairs from jsonb_array_elements(v_comp_mods) m;
      v_is_cont := v_new_pairs = v_old_pairs
                   and nullif(btrim(coalesce(v_rep ->> 'notes', '')), '')
                       is not distinct from nullif(btrim(coalesce(v_line ->> 'notes', '')), '');
      select coalesce(sum((m ->> 'price_minor_snapshot')::bigint * (m ->> 'quantity')::bigint), 0)
        into v_mod_sum from jsonb_array_elements(v_comp_mods) m;
      v_change := jsonb_set(v_change, array['replacements', v_j::text],
        v_rep || jsonb_build_object('_mods', v_comp_mods, '_cont', v_is_cont,
                                    '_unit', (v_line ->> 'unit')::bigint + v_mod_sum));
      if not v_is_cont then
        v_changed_qty := v_changed_qty + (v_rep ->> 'quantity')::bigint;
      end if;
    end loop;

    -- A modify changes modifiers and note only: one whose replacements are ALL
    -- unchanged changes nothing a modify may change — the same total is a
    -- no-op, and any other total is a quantity change, which is a
    -- set_quantity. Both are refused invalid_payload.
    if v_changed_qty = 0 then
      return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
        v_role, v_device_type, v_o_status, 'invalid_payload', null, 'invalid_payload');
    end if;

    -- pass 2: landing (§4.45.4). The old line's Q dishes are allotted to the
    -- UNCHANGED replacements first, so finished food the guest keeps is never
    -- taken back and remade:
    --  * a continuation (an unchanged replacement) stays in place for as many
    --    dishes as remain; its further dishes are a +N DELTA (no
    --    replaces_order_item_id) that lands like a set_quantity increase;
    --  * a CHANGED replacement replaces the old dishes still left — in place
    --    while the unit is Waiting / In kitchen on the KDS channel, in the
    --    edit's round on a Ready / Served unit (REMAKE) or on paper (CHANGE);
    --    its dishes beyond the old quantity are NEW dishes (no
    --    replaces_order_item_id, reported as added) that land like a
    --    set_quantity increase.
    v_landing := case when v_finished then 'edit_round' else 'in_place' end;
    v_budget := (v_line ->> 'quantity')::bigint;
    v_take_changed := 0;
    for v_pass in 1 .. 2 loop
      for v_j in 0 .. jsonb_array_length(v_change -> 'replacements') - 1 loop
        v_rep := v_change -> 'replacements' -> v_j;
        continue when (v_pass = 1) <> (v_rep ->> '_cont')::boolean;
        v_qty    := (v_rep ->> 'quantity')::bigint;
        v_take   := least(v_qty, v_budget);
        v_budget := v_budget - v_take;
        v_excess := v_qty - v_take;
        if v_take > 0 then
          if v_pass = 1 then
            v_rows := v_rows || jsonb_build_array(v_line - 'id' - 'status' - 'quantity' - 'legacy' - 'line_total' - 'notes' - 'prep'
              || jsonb_build_object(
                'ci', v_i, 'role', 'continuation', 'landing', 'in_place',
                'replaces', v_line ->> 'id', 'restore_from', v_line ->> 'id',
                'status', v_line ->> 'status',
                'line_position', (v_line ->> 'line_position')::int,
                'qty', v_take, 'line_total', v_take * (v_rep ->> '_unit')::bigint,
                'notes', v_line ->> 'notes',
                'prep', app.edit_reanswer_prep(v_line -> 'prep', v_rep -> 'modifiers'),
                'modifiers', v_rep -> '_mods'));
          else
            v_take_changed := v_take_changed + v_take;
            v_need_round := v_need_round or v_landing = 'edit_round';
            v_rows := v_rows || jsonb_build_array(v_line - 'id' - 'status' - 'quantity' - 'legacy' - 'line_total' - 'notes' - 'prep'
              || jsonb_build_object(
                'ci', v_i, 'role', 'replacement', 'landing', v_landing,
                'replaces', v_line ->> 'id', 'restore_from', v_line ->> 'id',
                'status', case when v_landing = 'in_place' then v_line ->> 'status' else 'pending' end,
                'line_position', case when v_landing = 'in_place' then (v_line ->> 'line_position')::int else 0 end,
                'qty', v_take, 'line_total', v_take * (v_rep ->> '_unit')::bigint,
                'notes', v_rep ->> 'notes',
                'prep', app.edit_reanswer_prep(v_line -> 'prep', v_rep -> 'modifiers'),
                'modifiers', v_rep -> '_mods'));
          end if;
        end if;
        if v_excess > 0 then
          v_need_round := v_need_round or v_landing = 'edit_round';
          v_rows := v_rows || jsonb_build_array(v_line - 'id' - 'status' - 'quantity' - 'legacy' - 'line_total' - 'notes' - 'prep'
            || jsonb_build_object(
              'ci', v_i, 'role', 'delta', 'landing', v_landing,
              'replaces', null, 'restore_from', v_line ->> 'id',
              'status', case when v_landing = 'in_place' then v_line ->> 'status' else 'pending' end,
              'line_position', case when v_landing = 'in_place' then (v_line ->> 'line_position')::int else 0 end,
              'qty', v_excess, 'line_total', v_excess * (v_rep ->> '_unit')::bigint,
              'notes', case when v_pass = 1 then v_line ->> 'notes' else v_rep ->> 'notes' end,
              'prep', app.edit_reanswer_prep(v_line -> 'prep', v_rep -> 'modifiers'),
              'modifiers', v_rep -> '_mods'));
        end if;
        v_after_qty := v_after_qty + v_qty;
        v_rep_total := v_rep_total + v_qty * (v_rep ->> '_unit')::bigint;
      end loop;
    end loop;

    -- sellability is re-checked when the modify raises the total quantity.
    if v_after_qty > (v_line ->> 'quantity')::bigint then
      v_sell := v_sell || jsonb_build_array(jsonb_build_object(
        'menu_item_id', v_line ->> 'menu_item_id', 'name', v_line ->> 'name'));
    end if;
    v_chg := v_chg || jsonb_build_array(jsonb_build_object(
      'ci', v_i, 'kind', 'modify', 'order_item_id', v_line ->> 'id',
      'outcome_status', v_outcome,
      'unit_stage', case when v_channel = 'paper' then 'printed' else v_stage end,
      -- REMAKE: only when a CHANGED replacement REPLACES finished dishes of a
      -- Ready / Served KDS unit (continuations and new dishes are not remakes).
      'remake', v_channel = 'kds' and v_stage in ('ready', 'served') and v_take_changed > 0,
      'name', v_line ->> 'name',
      'before_quantity', (v_line ->> 'quantity')::bigint,
      'before_total_minor', (v_line ->> 'line_total')::bigint,
      'after_quantity', v_after_qty, 'after_total_minor', v_rep_total));
  end loop;

  -- STEP 8 (cont.) — sellability + availability under ascending-id FOR UPDATE
  -- menu locks (the add_order_items predicate), for adds, increases and a
  -- modify that raises the quantity.
  if jsonb_array_length(v_sell) > 0 then
    select array_agg(distinct app.edit_try_uuid(s ->> 'menu_item_id'))
      into v_menu_ids from jsonb_array_elements(v_sell) s;
    perform 1
      from public.menu_items i
      where i.organization_id = v_org
        and i.id = any (v_menu_ids)
      order by i.id
      for update;
    select jsonb_agg(jsonb_build_object(
             'menu_item_id', blocked.menu_item_id,
             'name',         blocked.name,
             'reason',       blocked.reason)
             order by blocked.menu_item_id)
      into v_unavailable
      from (
        select li.menu_item_id,
               li.name,
               coalesce(a.reason, 'unavailable') as reason
          from (
            select app.edit_try_uuid(s ->> 'menu_item_id') as menu_item_id,
                   min(s ->> 'name') as name
              from jsonb_array_elements(v_sell) s
              group by 1
          ) li
          left join public.menu_items i
            on i.id = li.menu_item_id
           and i.organization_id = v_org
           and i.restaurant_id   = v_rest
           and i.is_active
           and i.deleted_at is null
           and (i.branch_id is null or i.branch_id = v_branch)
          left join public.menu_categories c
            on c.id = i.menu_category_id
           and c.organization_id = v_org
           and c.restaurant_id   = v_rest
           and c.is_active
           and c.deleted_at is null
           and (c.branch_id is null or c.branch_id = v_branch)
          left join public.menu_item_branch_availability a
            on a.organization_id = v_org
           and a.branch_id       = v_branch
           and a.menu_item_id    = li.menu_item_id
           and a.availability    = 'unavailable'
          where i.id is null
             or c.id is null
             or a.menu_item_id is not null
      ) blocked;
    if v_unavailable is not null then
      return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
        v_role, v_device_type, v_o_status, 'item_unavailable', null, 'item_unavailable',
        jsonb_build_object('entity', 'order', 'items', v_unavailable));
    end if;
  end if;

  -- 003D — a NEW option must belong to the line's menu item inside this
  -- organization (one uniform code: nonexistent, foreign, wrong-item; R-003).
  select jsonb_agg(bad order by bad ->> 'menu_item_id', bad ->> 'option_name_snapshot')
    into v_bad_mods
    from (
      select distinct jsonb_build_object(
               'menu_item_id',         n ->> 'menu_item_id',
               'option_name_snapshot', n ->> 'option_name_snapshot') as bad
        from jsonb_array_elements(v_newopts) n
       where not exists (
           select 1
             from public.modifier_options mo
             join public.modifiers mg
               on  mg.organization_id = mo.organization_id
               and mg.id              = mo.modifier_id
            where mo.organization_id = v_org
              and mo.id              = app.edit_try_uuid(n ->> 'modifier_option_id')
              and mg.menu_item_id    = app.edit_try_uuid(n ->> 'menu_item_id'))
    ) offenders;
  if v_bad_mods is not null then
    return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
      v_role, v_device_type, v_o_status, 'modifier_option_not_in_scope', null, 'modifier_option_not_in_scope',
      jsonb_build_object('entity', 'order', 'modifiers', v_bad_mods));
  end if;

  -- 021 — a NEW option's frozen prep snapshot must still match the menu,
  -- derived against the line's FULL modifier array.
  select jsonb_agg(bad order by bad ->> 'menu_item_id', bad ->> 'option_name_snapshot')
    into v_stale_mods
    from (
      select distinct jsonb_build_object(
               'menu_item_id',         n ->> 'menu_item_id',
               'option_name_snapshot', n ->> 'option_name_snapshot') as bad
        from jsonb_array_elements(v_newopts) n
       where app.kitchen_modifier_prep_projection(n -> 'meat_snapshot')
             is distinct from
             app.trusted_modifier_prep_snapshot(
               v_org,
               app.edit_try_uuid(n ->> 'menu_item_id'),
               app.edit_try_uuid(n ->> 'modifier_option_id'),
               n -> 'full')
    ) offenders;
  if v_stale_mods is not null then
    return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
      v_role, v_device_type, v_o_status, 'modifier_prep_snapshot_stale', null, 'modifier_prep_snapshot_stale',
      jsonb_build_object('entity', 'order', 'modifiers', v_stale_mods),
      jsonb_build_object('modifiers', v_stale_mods));
  end if;

  -- STEP 9 (cont.) — emptied units and the kitchen confirmation. Units are
  -- the ORIGINAL ticket (stage = orders.status) and each service round (its
  -- own status), read under the locks.
  select coalesce(jsonb_object_agg(r.id::text, r.status), '{}'::jsonb)
           || jsonb_build_object('original', v_o_status)
    into v_unit_status
    from public.order_service_rounds r
    where r.organization_id = v_org and r.order_id = p_order_id;
  select coalesce(jsonb_object_agg(s.k, s.n), '{}'::jsonb), coalesce(sum(s.n), 0)::int, coalesce(sum(s.t), 0)
    into v_unit_count, v_live_before, v_live_total
    from (
      select coalesce(oi.service_round_id::text, 'original') as k,
             count(*)::int as n, sum(oi.line_total_minor) as t
        from public.order_items oi
       where oi.organization_id = v_org and oi.order_id = p_order_id
         and oi.deleted_at is null and oi.status not in ('voided', 'cancelled')
       group by 1
    ) s;

  for v_row in select * from jsonb_array_elements(v_retire)
  loop
    v_ukey := v_row ->> 'unit';
    v_unit_count := jsonb_set(v_unit_count, array[v_ukey],
                      to_jsonb(coalesce((v_unit_count ->> v_ukey)::int, 0) - 1));
    v_retired_total := v_retired_total + (v_row ->> 'line_total')::bigint;
    if v_channel = 'kds' and (v_unit_status ->> v_ukey) in ('submitted', 'accepted', 'preparing', 'ready') then
      v_ack_required := true;
    end if;
  end loop;
  for v_row in select * from jsonb_array_elements(v_rows)
  loop
    v_new_count := v_new_count + 1;
    v_new_total := v_new_total + (v_row ->> 'line_total')::bigint;
    if (v_row ->> 'landing') in ('in_place', 'original') then
      v_ukey := case when (v_row ->> 'landing') = 'original' then 'original'
                     else coalesce(v_row ->> 'round_id', 'original') end;
      v_unit_count := jsonb_set(v_unit_count, array[v_ukey],
                        to_jsonb(coalesce((v_unit_count ->> v_ukey)::int, 0) + 1));
      if v_channel = 'kds' and (v_unit_status ->> v_ukey) in ('submitted', 'accepted', 'preparing', 'ready') then
        v_ack_required := true;
      end if;
    end if;
  end loop;

  -- STEP 10 — never empty: that is a cancellation (the Cancel order flow).
  if v_live_before - jsonb_array_length(v_retire) + v_new_count <= 0 then
    return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
      v_role, v_device_type, v_o_status, 'edit_would_empty_order', null, 'edit_would_empty_order');
  end if;

  -- Emptied units still in submitted..ready close (rounds -> voided by the
  -- edit; the original ticket -> the order moves to served, step 16).
  select coalesce(array_agg(u.k::uuid), '{}'::uuid[])
    into v_closed_rounds
    from (select distinct r ->> 'unit' as k from jsonb_array_elements(v_retire) r) u
   where u.k <> 'original'
     and coalesce((v_unit_count ->> u.k)::int, 0) = 0
     and (v_unit_status ->> u.k) in ('submitted', 'accepted', 'preparing', 'ready');
  v_unit1_closed := exists (select 1 from jsonb_array_elements(v_retire) r where r ->> 'unit' = 'original')
                    and coalesce((v_unit_count ->> 'original')::int, 0) = 0
                    and v_o_status in ('submitted', 'accepted', 'preparing', 'ready');

  -- ==========================================================================
  -- STEP 11 — the money plan (MONEY_AND_TAX_SPEC §9.2): subtotal RE-ROLLED as
  -- the sum of live line totals; the absolute order discount kept (never
  -- clamped); tax recomputed from the branch's CURRENT settings; the zero-out
  -- guard; the mandatory expected totals.
  -- ==========================================================================
  v_new_sub := v_live_total - v_retired_total + v_new_total;
  if v_new_sub is null or v_new_sub < 0 then
    raise exception 'edit_order: subtotal plan is undefined (state inconsistency)';
  end if;
  if v_o_disc > v_new_sub then
    return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
      v_role, v_device_type, v_o_status, 'invalid_discount', 'discount_exceeds_order_total', 'discount_exceeds_order_total');
  end if;
  v_new_tax := app.edit_tax_minor(v_new_sub - v_o_disc, v_b_tax_on, v_b_tax_bp, v_b_tax_mode);
  if v_new_tax is null then
    return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
      v_role, v_device_type, v_o_status, 'tax_mode_unsupported', null, 'tax_mode_unsupported');
  end if;
  v_new_grand := v_new_sub - v_o_disc + v_new_tax;
  v_may_comp := v_role in ('manager', 'restaurant_owner', 'org_owner')
                or app.cashier_capability_granted(v_role, v_m_perms, 'apply_full_comp');
  if v_o_grand > 0 and v_new_grand = 0 and not v_may_comp then
    return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
      v_role, v_device_type, v_o_status, 'permission_denied', 'full_comp_permission_required', 'full_comp_permission_required');
  end if;
  if v_exp_sub is distinct from v_new_sub or v_exp_tax is distinct from v_new_tax
     or v_exp_grand is distinct from v_new_grand then
    return app.edit_order_deny(v_org, v_rest, v_branch, v_emp, p_device_id, p_order_id,
      v_role, v_device_type, v_o_status, 'totals_mismatch', null, 'totals_mismatch',
      jsonb_build_object('totals', jsonb_build_object(
        'subtotal_minor', v_new_sub, 'discount_total_minor', v_o_disc,
        'tax_total_minor', v_new_tax, 'grand_total_minor', v_new_grand)));
  end if;

  -- ==========================================================================
  -- WRITES — steps 12..20, one transaction. Nothing above wrote anything.
  -- ==========================================================================
  -- 12. the edit row.
  v_edit_number := v_o_edit_count + 1;
  insert into public.order_edits (
    organization_id, restaurant_id, branch_id, order_id, edit_number,
    device_id, local_operation_id, pin_session_id, employee_profile_id, membership_id,
    reason_code, reason_text, kitchen_channel, kitchen_ack_required,
    bill_presented_at, client_created_at)
  values (
    v_org, v_rest, v_branch, p_order_id, v_edit_number,
    p_device_id, p_local_operation_id, p_pin_session_id, v_emp, v_membership,
    v_reason_code, v_reason_text, v_channel, v_channel = 'kds' and v_ack_required,
    v_bill_at, p_client_created_at)
  returning id into v_edit_id;

  -- 13. the edit's round (at most one), numbered like any round (never reused).
  if v_need_round then
    select coalesce(max(r.round_number), 1) + 1
      into v_round_no
      from public.order_service_rounds r
      where r.organization_id = v_org
        and r.order_id        = p_order_id;
    v_round_id := gen_random_uuid();
    insert into public.order_service_rounds (
      id, organization_id, restaurant_id, branch_id, order_id, round_number,
      status, device_id, opened_by_employee_profile_id, local_operation_id,
      revision, client_created_at, edit_id)
    values (
      v_round_id, v_org, v_rest, v_branch, p_order_id, v_round_no,
      'submitted', p_device_id, v_emp, null,
      1, p_client_created_at, v_edit_id);
  end if;

  -- 14. retire the old lines (provenance is write-once; status leaves the sums).
  update public.order_items oi
    set status                = r.outcome,
        void_reason           = 'order_edit:' || v_reason_code,
        removed_by_edit_id    = v_edit_id,
        removed_kitchen_stage = r.stage
    from jsonb_to_recordset(v_retire) as r(old_id uuid, outcome text, stage text)
    where oi.organization_id = v_org
      and oi.order_id        = p_order_id
      and oi.id              = r.old_id;

  -- 15. the new rows + their modifiers; then the display-order snapshots of
  --     continuation / replacement / delta rows are restored from the old row
  --     (the MENU-ORDER-001 insert triggers always re-derive them).
  v_j := 0;
  for v_row in select * from jsonb_array_elements(v_rows)
  loop
    insert into public.order_items (
      organization_id, restaurant_id, branch_id, order_id, menu_item_id,
      status, quantity, menu_item_name_snapshot, unit_price_minor_snapshot,
      item_size_snapshot, item_variant_snapshot, line_discount_minor, line_total_minor,
      notes, prep_snapshot, service_round_id, line_position, edit_id, replaces_order_item_id)
    values (
      v_org, v_rest, v_branch, p_order_id, (v_row ->> 'menu_item_id')::uuid,
      v_row ->> 'status', (v_row ->> 'qty')::int, v_row ->> 'name', (v_row ->> 'unit')::bigint,
      case when jsonb_typeof(v_row -> 'size') = 'null' then null else v_row -> 'size' end,
      case when jsonb_typeof(v_row -> 'variant') = 'null' then null else v_row -> 'variant' end,
      0, (v_row ->> 'line_total')::bigint,
      v_row ->> 'notes',
      case when jsonb_typeof(v_row -> 'prep') = 'null' then null else v_row -> 'prep' end,
      case v_row ->> 'landing'
        when 'in_place'   then (v_row ->> 'round_id')::uuid
        when 'edit_round' then v_round_id
        else null end,
      coalesce((v_row ->> 'line_position')::int, 0),
      v_edit_id,
      (v_row ->> 'replaces')::uuid)
    returning id into v_new_id;

    for v_mod in select * from jsonb_array_elements(v_row -> 'modifiers')
    loop
      insert into public.order_item_modifiers (
        organization_id, restaurant_id, branch_id, order_item_id, modifier_option_id,
        modifier_name_snapshot, option_name_snapshot, price_minor_snapshot, quantity, meat_snapshot)
      values (
        v_org, v_rest, v_branch, v_new_id, (v_mod ->> 'modifier_option_id')::uuid,
        v_mod ->> 'modifier_name_snapshot', v_mod ->> 'option_name_snapshot',
        (v_mod ->> 'price_minor_snapshot')::bigint, (v_mod ->> 'quantity')::int,
        case when jsonb_typeof(v_mod -> 'meat_snapshot') = 'null' then null else v_mod -> 'meat_snapshot' end);
    end loop;

    if (v_row ->> 'restore_from') is not null then
      update public.order_items n
        set item_display_order_snapshot     = o.item_display_order_snapshot,
            category_display_order_snapshot = o.category_display_order_snapshot
        from public.order_items o
        where n.id = v_new_id
          and o.organization_id = v_org
          and o.id = (v_row ->> 'restore_from')::uuid;
      update public.order_item_modifiers nm
        set modifier_group_display_order_snapshot  = om.modifier_group_display_order_snapshot,
            modifier_option_display_order_snapshot = om.modifier_option_display_order_snapshot
        from (
          select distinct on (m.modifier_option_id)
                 m.modifier_option_id, m.modifier_group_display_order_snapshot,
                 m.modifier_option_display_order_snapshot
            from public.order_item_modifiers m
           where m.organization_id = v_org
             and m.order_item_id = (v_row ->> 'restore_from')::uuid
             and m.deleted_at is null
           order by m.modifier_option_id, m.line_position, m.created_at, m.id
        ) om
        where nm.organization_id = v_org
          and nm.order_item_id = v_new_id
          and nm.modifier_option_id = om.modifier_option_id;
    end if;

    v_row_ids := jsonb_set(v_row_ids, array[v_row ->> 'ci'],
                   coalesce(v_row_ids -> (v_row ->> 'ci'), '[]'::jsonb) || to_jsonb(v_new_id));
    v_j := v_j + 1;
  end loop;

  -- 16. close emptied units: rounds -> voided (by this edit; ready_at kept);
  --     the original ticket -> the order moves to served below WITHOUT
  --     stamping ready_at (NULL stays NULL; a ready stamp is kept).
  if cardinality(v_closed_rounds) > 0 then
    update public.order_service_rounds r
      set status = 'voided', void_reason = 'order_edit:' || v_reason_code,
          voided_by_edit_id = v_edit_id, revision = r.revision + 1
      where r.organization_id = v_org
        and r.order_id = p_order_id
        and r.id = any (v_closed_rounds);
  end if;

  -- 17. the order: totals, revision + 1, edit_count + 1 (+ served jump).
  v_new_rev    := v_o_rev + 1;
  v_new_status := case when v_unit1_closed then 'served' else v_o_status end;
  update public.orders
    set subtotal_minor    = v_new_sub,
        tax_total_minor   = v_new_tax,
        grand_total_minor = v_new_grand,
        revision          = v_new_rev,
        edit_count        = v_edit_number
    where id = p_order_id and organization_id = v_org;
  -- status is written ONLY for the served jump: an UPDATE OF status fires
  -- orders_clear_reservation_on_seat, which must not run on an ordinary edit.
  if v_unit1_closed then
    update public.orders
      set status = 'served'
      where id = p_order_id and organization_id = v_org;
  end if;

  -- The per-change summaries (envelope + audit) now carry the new row ids.
  select coalesce(jsonb_agg(c || jsonb_build_object(
           'new_order_item_ids', coalesce(v_row_ids -> (c ->> 'ci'), '[]'::jsonb),
           'landing', case
             when c ->> 'kind' = 'remove' then 'removed'
             when c ->> 'kind' = 'add' then
               case when jsonb_array_length(coalesce(v_row_ids -> (c ->> 'ci'), '[]'::jsonb)) > 0
                         and exists (select 1 from jsonb_array_elements(v_rows) r
                                      where r ->> 'ci' = c ->> 'ci' and r ->> 'landing' = 'original')
                    then 'original_ticket' else 'edit_round' end
             else (select case
                            when bool_and(r ->> 'landing' = 'in_place') then 'in_place'
                            when bool_and(r ->> 'landing' = 'edit_round') then 'edit_round'
                            else 'mixed' end
                     from jsonb_array_elements(v_rows) r where r ->> 'ci' = c ->> 'ci')
           end) order by (c ->> 'ci')::int), '[]'::jsonb)
    into v_chg
    from jsonb_array_elements(v_chg) c;
  select coalesce(jsonb_agg(jsonb_build_object(
           'kind', c ->> 'kind',
           'order_item_id', c -> 'order_item_id',
           'outcome_status', c ->> 'outcome_status',
           'new_order_item_ids', c -> 'new_order_item_ids',
           'landing', c ->> 'landing',
           'unit_stage', c ->> 'unit_stage',
           'remake', (c ->> 'remake')::boolean) order by (c ->> 'ci')::int), '[]'::jsonb),
         coalesce(jsonb_agg(jsonb_build_object(
           'kind', c ->> 'kind',
           'order_item_id', c -> 'order_item_id',
           'name', c ->> 'name',
           'before_quantity', c -> 'before_quantity',
           'after_quantity', c -> 'after_quantity',
           'before_total_minor', c -> 'before_total_minor',
           'after_total_minor', c -> 'after_total_minor',
           'unit_stage', c ->> 'unit_stage',
           'landing', c ->> 'landing',
           'outcome_status', c ->> 'outcome_status',
           'remake', (c ->> 'remake')::boolean,
           'new_order_item_ids', c -> 'new_order_item_ids') order by (c ->> 'ci')::int), '[]'::jsonb)
    into v_env_changes, v_audit_changes
    from jsonb_array_elements(v_chg) c;
  select coalesce(jsonb_agg(jsonb_build_object('round_id', r.id, 'round_number', r.round_number)
           order by r.round_number), '[]'::jsonb)
    into v_rounds_closed
    from public.order_service_rounds r
    where r.organization_id = v_org and r.order_id = p_order_id and r.id = any (v_closed_rounds);

  -- 18. paper channel only: the order_edit dispatch, born CLAIMED by this POS.
  if v_channel = 'paper' then
    v_dispatch := app.create_order_edit_dispatch(
      v_org, v_rest, v_branch, p_order_id, v_edit_id,
      app.kitchen_dispatch_payload_order_edit(v_org, p_order_id, v_edit_id,
        (select coalesce(jsonb_agg(jsonb_build_object(
                  'kind', c ->> 'kind',
                  'order_item_id', c -> 'order_item_id',
                  'quantity', c -> 'quantity',
                  'new_order_item_ids', c -> 'new_order_item_ids') order by (c ->> 'ci')::int), '[]'::jsonb)
           from jsonb_array_elements(v_chg) c)),
      v_emp, v_membership, p_device_id);
  end if;

  -- 19. audit order.edited — the tamper-evident per-line record (D-013).
  insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.edited', v_reason_text,
          jsonb_build_object(
            'order_id', p_order_id, 'revision', v_o_rev, 'order_status', v_o_status,
            'edit_count', v_o_edit_count,
            'subtotal_minor', v_o_sub, 'discount_total_minor', v_o_disc,
            'tax_total_minor', v_o_tax, 'grand_total_minor', v_o_grand,
            'discount_ratio_bp', case when v_o_sub > 0 then round(v_o_disc::numeric * 10000 / v_o_sub)::int end),
          jsonb_strip_nulls(jsonb_build_object(
            'order_id', p_order_id, 'order_code', v_order_code,
            'edit_number', v_edit_number, 'order_edit_id', v_edit_id,
            'order_status', v_new_status, 'revision', v_new_rev,
            'role', v_role, 'device_type', v_device_type,
            'reason_code', v_reason_code,
            'kitchen_channel', v_channel,
            'kitchen_ack_required', v_channel = 'kds' and v_ack_required,
            'removed_item_count', (select count(*) from jsonb_array_elements(v_chg) c where c ->> 'kind' = 'remove'),
            'modified_item_count', (select count(*) from jsonb_array_elements(v_chg) c where c ->> 'kind' in ('modify', 'set_quantity')),
            'added_item_count', (select count(*) from jsonb_array_elements(v_chg) c where c ->> 'kind' = 'add'),
            'new_round_number', v_round_no,
            'unit1_closed', v_unit1_closed,
            'rounds_closed_count', cardinality(v_closed_rounds),
            'subtotal_minor', v_new_sub, 'discount_total_minor', v_o_disc,
            'tax_total_minor', v_new_tax, 'grand_total_minor', v_new_grand,
            'discount_ratio_bp', case when v_new_sub > 0 then round(v_o_disc::numeric * 10000 / v_new_sub)::int end,
            'bill_presented', v_bill_at is not null,
            'local_operation_id', p_local_operation_id,
            'resolved_membership_id', v_membership))
          || jsonb_build_object('changes', v_audit_changes));

  -- 20. completion under the held order lock (no new lock, no new order).
  v_auto := app.try_auto_complete_order(
    v_org, v_rest, v_branch, p_order_id, 'order_edited',
    null, v_emp, v_membership, v_role, p_device_id, p_local_operation_id);
  v_final_rev    := coalesce((v_auto ->> 'revision')::integer, v_new_rev);
  v_final_status := case when coalesce((v_auto ->> 'completed')::boolean, false)
                         then 'completed' else v_new_status end;

  v_result := jsonb_build_object(
    'ok', true,
    'order_id', p_order_id,
    'order_code', v_order_code,
    'order_edit_id', v_edit_id,
    'edit_number', v_edit_number,
    'revision', v_final_rev,
    'order_status', v_final_status,
    'auto_completed', coalesce((v_auto ->> 'completed')::boolean, false),
    'kitchen_channel', v_channel,
    'kitchen_ack_required', v_channel = 'kds' and v_ack_required,
    'new_round_id', v_round_id,
    'new_round_number', v_round_no,
    'unit1_closed', v_unit1_closed,
    'rounds_closed', v_rounds_closed,
    'before', jsonb_build_object(
      'subtotal_minor', v_o_sub, 'discount_total_minor', v_o_disc,
      'tax_total_minor', v_o_tax, 'grand_total_minor', v_o_grand),
    'totals', jsonb_build_object(
      'subtotal_minor', v_new_sub, 'discount_total_minor', v_o_disc,
      'tax_total_minor', v_new_tax, 'grand_total_minor', v_new_grand),
    'changes', v_env_changes)
    || case when v_dispatch is not null
            then jsonb_build_object('kitchen_dispatch', v_dispatch) else '{}'::jsonb end;

  insert into public.order_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, order_id, result)
    values (v_org, v_rest, v_branch, p_device_id, p_local_operation_id, 'edit_order', p_order_id, v_result);

  return v_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.edit_order(uuid, uuid, uuid, text, jsonb, timestamptz) is
  'ORDER-EDIT-001A (D-043/D-044; API_CONTRACT §4.45): edits a SENT, open, unpaid dine_in/takeaway order IN PLACE (same orders row, #code, table, shift, report bucket). Reached ONLY through app.sync_push (order.edit, an online-only direct op); actor/org/restaurant/branch from the PIN session. Steps 1-11 (preamble, shape, business replay, locks orders->rounds->items->menu items, gates, live lines, authority+reason, finished food, new lines, plan, never-empty, money plan) write NOTHING but the refusal''s order.edit_denied audit; steps 12-20 write order_edits, at most one edit round, retire lines (cancelled/voided with removed_by_edit_id + removed_kitchen_stage), insert remainder/delta/continuation/replacement/added rows (snapshots copied server-side, D-008; display ranks restored), close emptied units, re-roll the subtotal / keep the absolute discount / recompute exclusive tax from current settings, bump revision + edit_count, create the claimed order_edit dispatch on the paper channel, audit order.edited, and run app.try_auto_complete_order under the held lock. The success envelope is stored in order_operations (action edit_order) and replayed for the same (org, device, local_operation_id) on the same order; another order RAISES 40001. Money in integer minor units (D-007). INTERNAL: no client grant, no public wrapper.';

-- ----------------------------------------------------------------------------
-- app.kitchen_ack_order_edit — sync op order.edit_ack (API_CONTRACT §4.46)
-- ----------------------------------------------------------------------------
create or replace function app.kitchen_ack_order_edit(
  p_pin_session_id     uuid,
  p_order_id           uuid,
  p_device_id          uuid,
  p_local_operation_id text,
  p_up_to_edit_number  integer
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org         uuid;
  v_rest        uuid;
  v_branch      uuid;
  v_dsid        uuid;
  v_emp         uuid;
  v_membership  uuid;
  v_ds_device   uuid;
  v_ds_active   boolean;
  v_ds_revoked  timestamptz;
  v_pairing     text;
  v_role        text;
  v_m_status    text;
  v_m_deleted   timestamptz;
  v_device_type text;
  v_o_status    text;
  v_o_edits     integer;
  v_count       integer;
  v_order_code  text := '#' || upper(right(replace(p_order_id::text, '-', ''), 6));
  v_deny        text;
begin
  -- (a) the canonical PIN preamble — every structural failure RAISES 42501.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'kitchen_ack_order_edit: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'kitchen_ack_order_edit: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'kitchen_ack_order_edit: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'kitchen_ack_order_edit: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'kitchen_ack_order_edit: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) ANTI-ORACLE order lock (R-003): a nonexistent and a foreign order
  --     raise the SAME 42501.
  select o.status, o.edit_count
    into v_o_status, v_o_edits
    from public.orders o
    where o.id = p_order_id
      and o.organization_id = v_org
      and o.restaurant_id   = v_rest
      and o.branch_id       = v_branch
      and o.deleted_at is null
    for update;
  if not found then
    raise exception 'kitchen_ack_order_edit: order_not_found_or_not_accessible' using errcode = '42501';
  end if;

  -- (c) KDS-class device; (d) the kitchen role set (kitchen_ack_void parity);
  -- (e) the edit number; (f) the voided-order rule.
  select d.device_type into v_device_type
    from public.devices d
    where d.id = p_device_id and d.organization_id = v_org;
  v_deny := case
    when coalesce(v_device_type, '') <> 'kds' then 'invalid_device_type'
    when v_role not in ('kitchen_staff', 'manager', 'restaurant_owner', 'org_owner') then 'permission_denied'
    when p_up_to_edit_number is null or p_up_to_edit_number < 1
         or p_up_to_edit_number > v_o_edits then 'invalid_edit_number'
    when v_o_status = 'voided' then 'order_voided'
  end;
  if v_deny is not null then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.edit_ack_denied', null, null,
            jsonb_build_object('attempted_action', 'kitchen_ack_order_edit', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role,
                               'device_type', coalesce(v_device_type, 'unknown'),
                               'order_status', v_o_status,
                               'denied_reason', v_deny));
    return jsonb_build_object('ok', false, 'error', v_deny, 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false)
           || case when v_deny = 'order_voided'
                   then jsonb_build_object('order_status', v_o_status) else '{}'::jsonb end;
  end if;

  -- (g) stamp the write-once triple on EVERY pending required edit <= N. No
  --     write to orders and no revision bump (MONEY M11).
  update public.order_edits e
    set kitchen_ack_at                     = now(),
        kitchen_ack_by_employee_profile_id = v_emp,
        kitchen_ack_device_id              = p_device_id
    where e.organization_id = v_org
      and e.order_id        = p_order_id
      and e.edit_number    <= p_up_to_edit_number
      and e.kitchen_ack_required
      and e.kitchen_ack_at is null;
  get diagnostics v_count = row_count;

  if v_count > 0 then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.edit_acknowledged', null,
            jsonb_build_object('order_id', p_order_id),
            jsonb_build_object('order_id', p_order_id, 'order_code', v_order_code,
                               'up_to_edit_number', p_up_to_edit_number,
                               'acknowledged_count', v_count,
                               'order_status', v_o_status,
                               'role', v_role, 'device_type', v_device_type,
                               'local_operation_id', p_local_operation_id,
                               'resolved_membership_id', v_membership));
  end if;

  return jsonb_build_object(
    'ok', true, 'entity', 'order', 'order_id', p_order_id, 'order_code', v_order_code,
    'up_to_edit_number', p_up_to_edit_number, 'acknowledged_count', v_count,
    'server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.kitchen_ack_order_edit(uuid, uuid, uuid, text, integer) is
  'ORDER-EDIT-001A (D-044; API_CONTRACT §4.46): the kitchen''s one-tap "Got it" for order edits. Reached ONLY through app.sync_push (order.edit_ack; payload {order_id, up_to_edit_number}; target_id must equal payload.order_id). Canonical PIN preamble (42501); anti-oracle order lock (42501 for a nonexistent or foreign order); refusals RETURNed + audited order.edit_ack_denied: invalid_device_type (KDS-class device only), permission_denied (kitchen_staff/manager/restaurant_owner/org_owner only), invalid_edit_number (N missing, < 1 or > edit_count), order_voided (the whole-order void supersedes pending edits). Every other status, including served and completed, is accepted. Stamps the write-once acknowledgement triple on EVERY pending required edit with edit_number <= N; idempotent (nothing pending => ok, acknowledged_count 0, no audit); NO write to orders and NO revision bump. Audits order.edit_acknowledged on a stamp. INTERNAL: no client grant, no public wrapper.';

-- ----------------------------------------------------------------------------
-- ACL — every function here is INTERNAL. edit_order and kitchen_ack_order_edit
-- are reached ONLY through the SECURITY DEFINER app.sync_push (owner-executed),
-- so no client role holds EXECUTE: a direct call would bypass the D-022 ledger.
-- ----------------------------------------------------------------------------
revoke all on function app.order_item_is_legacy_priced(uuid, uuid) from public;
revoke all on function app.order_item_is_legacy_priced(uuid, uuid) from anon;
revoke all on function app.order_item_is_legacy_priced(uuid, uuid) from authenticated;
revoke all on function app.edit_tax_minor(bigint, boolean, integer, text) from public;
revoke all on function app.edit_tax_minor(bigint, boolean, integer, text) from anon;
revoke all on function app.edit_tax_minor(bigint, boolean, integer, text) from authenticated;
revoke all on function app.edit_reanswer_prep(jsonb, jsonb) from public;
revoke all on function app.edit_reanswer_prep(jsonb, jsonb) from anon;
revoke all on function app.edit_reanswer_prep(jsonb, jsonb) from authenticated;
revoke all on function app.edit_json_int(jsonb, bigint, bigint) from public;
revoke all on function app.edit_json_int(jsonb, bigint, bigint) from anon;
revoke all on function app.edit_json_int(jsonb, bigint, bigint) from authenticated;
revoke all on function app.edit_try_uuid(text) from public;
revoke all on function app.edit_try_uuid(text) from anon;
revoke all on function app.edit_try_uuid(text) from authenticated;
revoke all on function app.edit_canonical_modifiers(jsonb) from public;
revoke all on function app.edit_canonical_modifiers(jsonb) from anon;
revoke all on function app.edit_canonical_modifiers(jsonb) from authenticated;
revoke all on function app.edit_canonical_change(jsonb) from public;
revoke all on function app.edit_canonical_change(jsonb) from anon;
revoke all on function app.edit_canonical_change(jsonb) from authenticated;
revoke all on function app.edit_validate_new_line(jsonb) from public;
revoke all on function app.edit_validate_new_line(jsonb) from anon;
revoke all on function app.edit_validate_new_line(jsonb) from authenticated;
revoke all on function app.edit_order_deny(uuid, uuid, uuid, uuid, uuid, uuid, text, text, text, text, text, text, jsonb, jsonb) from public;
revoke all on function app.edit_order_deny(uuid, uuid, uuid, uuid, uuid, uuid, text, text, text, text, text, text, jsonb, jsonb) from anon;
revoke all on function app.edit_order_deny(uuid, uuid, uuid, uuid, uuid, uuid, text, text, text, text, text, text, jsonb, jsonb) from authenticated;
revoke all on function app.kitchen_dispatch_item_projection(uuid, uuid) from public;
revoke all on function app.kitchen_dispatch_item_projection(uuid, uuid) from anon;
revoke all on function app.kitchen_dispatch_item_projection(uuid, uuid) from authenticated;
revoke all on function app.kitchen_dispatch_payload_order_edit(uuid, uuid, uuid, jsonb) from public;
revoke all on function app.kitchen_dispatch_payload_order_edit(uuid, uuid, uuid, jsonb) from anon;
revoke all on function app.kitchen_dispatch_payload_order_edit(uuid, uuid, uuid, jsonb) from authenticated;
revoke all on function app.create_order_edit_dispatch(uuid, uuid, uuid, uuid, uuid, jsonb, uuid, uuid, uuid) from public;
revoke all on function app.create_order_edit_dispatch(uuid, uuid, uuid, uuid, uuid, jsonb, uuid, uuid, uuid) from anon;
revoke all on function app.create_order_edit_dispatch(uuid, uuid, uuid, uuid, uuid, jsonb, uuid, uuid, uuid) from authenticated;
revoke all on function app.edit_order(uuid, uuid, uuid, text, jsonb, timestamptz) from public;
revoke all on function app.edit_order(uuid, uuid, uuid, text, jsonb, timestamptz) from anon;
revoke all on function app.edit_order(uuid, uuid, uuid, text, jsonb, timestamptz) from authenticated;
revoke all on function app.kitchen_ack_order_edit(uuid, uuid, uuid, text, integer) from public;
revoke all on function app.kitchen_ack_order_edit(uuid, uuid, uuid, text, integer) from anon;
revoke all on function app.kitchen_ack_order_edit(uuid, uuid, uuid, text, integer) from authenticated;
