-- ============================================================================
-- KITCHEN-DISPATCH-HARDEN-001 — fail-closed kitchen dispatch creation; dispatch
-- payloads carry live lines only. ORDER-EDIT slice 1, a precursor for
-- DECISION D-044 (API_CONTRACT §4.45.9, DECISIONS D-044 point 10).
--
-- WHY. Two latent hazards in the printer-only dispatch ledger (KITCHEN-MODE-001C1)
-- become reachable once ORDER-EDIT-001A adds the `order_edit` dispatch type and
-- writes voided/cancelled lines onto LIVE orders:
--   1. app.create_kitchen_dispatch derived the idempotency key with
--      `else 'void:' || p_order_id`, so ANY type other than initial_order /
--      service_round — including a future one — would take the order's VOID
--      key. ON CONFLICT DO NOTHING would then silently return the real VOID
--      dispatch's id (or squat the VOID key before a real void), writing nothing.
--   2. app.kitchen_dispatch_payload_initial / _round never filtered item status,
--      so a voided or cancelled line would print on kitchen paper.
--
-- WHAT (byte-faithful re-emits; every other byte of each body is unchanged):
--   * app.create_kitchen_dispatch (live body: 20260725090000, the only
--     definition): the key CASE gains an explicit `when 'void'` arm and loses
--     its ELSE; a NULL key (an unsupported type, a missing order id for
--     initial_order / void, or a missing round id for service_round) RAISES
--     22023 BEFORE any write. Audit, supersession and idempotency are
--     untouched.
--   * app.kitchen_dispatch_payload_initial / app.kitchen_dispatch_payload_round
--     (live bodies: 20260827090000, 114B.6B): the item subquery gains
--     `and oi.status not in ('voided', 'cancelled')` — the same live-line idiom
--     app.apply_discount / app.void_order already use.
--
-- NO BEHAVIOUR CHANGE TODAY. Every caller passes initial_order / service_round
-- / void with a non-NULL order id (and a round id for service_round), and the
-- table's dispatch_type CHECK already rejected any other type. The builders run
-- only inside the submit / add-items / kiosk-submit transactions (and the
-- same-transaction customer-name rebuild in app.sync_push), where every line of
-- the order (initial) or round (round) was just written live; no writer voids or
-- cancels a single line of a live order today (app.void_order voids the whole
-- order and builds its slip through app.kitchen_dispatch_payload_void, which is
-- NOT changed — the VOID slip carries no item list, and its affected_item_count
-- must still count every non-deleted line of the order, voided and cancelled
-- included).
--
-- UNCHANGED: signatures, LANGUAGE / volatility / SECURITY / search_path='',
-- payload shape and keys, item and modifier ordering, prep/meat projections,
-- the money-free contract, the INTERNAL-ONLY ACL (no public wrapper, no
-- anon/authenticated execute). No table/column/index/policy change. No new RPC.
-- ============================================================================

create or replace function app.create_kitchen_dispatch(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid,
  p_order_id        uuid,
  p_round_id        uuid,
  p_dispatch_type   text,
  p_payload         jsonb,
  p_actor_employee_profile_id uuid,
  p_actor_membership_id       uuid,
  p_device_id       uuid
)
  returns uuid
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_key   text;
  v_id    uuid;
  v_code  text;
begin
  -- KITCHEN-DISPATCH-HARDEN-001: fail closed. Every supported type has its
  -- own explicit arm; anything else, or a NULL key (a missing order id for
  -- initial_order / void, a missing round id for service_round), RAISES
  -- before any write. The old ELSE mapped
  -- ANY other type to 'void:<order>', where it would silently collide with
  -- the order's real VOID dispatch (ON CONFLICT DO NOTHING would hand back
  -- the VOID's id and write nothing). Unreachable from today's callers.
  v_key := case p_dispatch_type
             when 'initial_order' then 'initial:' || p_order_id::text
             when 'service_round' then 'round:' || p_round_id::text
             when 'void'          then 'void:' || p_order_id::text
           end;

  if v_key is null then
    raise exception 'create_kitchen_dispatch: unsupported dispatch type % or missing key id (fail closed)',
      coalesce(p_dispatch_type, '<null>')
      using errcode = '22023';
  end if;

  insert into public.kitchen_print_dispatches
    (organization_id, restaurant_id, branch_id, order_id, service_round_id,
     dispatch_type, money_free_payload, idempotency_key)
  values
    (p_organization_id, p_restaurant_id, p_branch_id, p_order_id, p_round_id,
     p_dispatch_type, p_payload, v_key)
  on conflict (organization_id, idempotency_key) do nothing
  returning id into v_id;

  -- Idempotent retry: the logical dispatch already exists — reuse it, never
  -- duplicate, never audit twice.
  if v_id is null then
    select d.id into v_id from public.kitchen_print_dispatches d
      where d.organization_id = p_organization_id and d.idempotency_key = v_key;
    return v_id;
  end if;

  if p_dispatch_type = 'void' then
    -- CORRECTION-001: once a VOID exists, NO earlier dispatch for this order
    -- may ever become newly claimable or reclaimable — the void supersedes
    -- EVERY unresolved prior (unclaimed, actively claimed, failed_retryable,
    -- blocked_configuration, possibly_printed alike), preserving each row''s
    -- status/claim/observability untouched. A claim holder may still finish
    -- acknowledging what it already imported; the pull feed and stale-claim
    -- recovery skip superseded rows permanently. COMPLETED dispatches stay
    -- unlinked history: their paper may exist, and the VOID slip corrects it.
    update public.kitchen_print_dispatches d
      set superseded_by_dispatch_id = v_id, updated_at = now()
      where d.organization_id = p_organization_id
        and d.order_id = p_order_id
        and d.id <> v_id
        and d.completed_at is null
        and d.superseded_by_dispatch_id is null;
  end if;

  v_code := '#' || upper(right(replace(p_order_id::text, '-', ''), 6));
  insert into public.audit_events
    (organization_id, restaurant_id, branch_id, actor_app_user_id,
     actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values
    (p_organization_id, p_restaurant_id, p_branch_id, null,
     p_actor_employee_profile_id, p_device_id,
     case when p_dispatch_type = 'void'
          then 'kitchen.dispatch_void_created' else 'kitchen.dispatch_created' end,
     null, null,
     jsonb_build_object(
       'order_code', v_code,
       'dispatch_type', p_dispatch_type,
       'resolved_membership_id', p_actor_membership_id));

  return v_id;
end;
$$;

comment on function app.create_kitchen_dispatch(uuid, uuid, uuid, uuid, uuid, text, jsonb, uuid, uuid, uuid) is
  'KITCHEN-MODE-001C1 INTERNAL: creates ONE logical kitchen dispatch per authoritative event (idempotency key initial:<order>/round:<round>/void:<order>; ON CONFLICT DO NOTHING => retries reuse the same row and never re-audit). On void, supersedes EVERY unresolved prior dispatch of the order (CORRECTION-001 — unclaimed, claimed, failed_retryable, blocked_configuration and possibly_printed alike; statuses/claims/observability preserved; completed history stays unlinked), so no original can ever print after its void. Audits kitchen.dispatch_created/_void_created with the PIN-session actor (D-013). Runs INSIDE the caller''s transaction — a failure aborts the mutation (fail closed); a rollback leaves nothing. NEVER granted to client roles. KITCHEN-DISPATCH-HARDEN-001: FAIL CLOSED — explicit initial_order / service_round / void arms; any other type, or a NULL key (a missing order id for initial_order / void, a missing round id for service_round), RAISES 22023 before any write (the old ELSE silently mapped unknown types onto the void:<order> key).';

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
        and oi.deleted_at is null
        -- KITCHEN-DISPATCH-HARDEN-001: live lines only — a voided or
        -- cancelled line never reaches kitchen paper.
        and oi.status not in ('voided', 'cancelled'))))
  from public.orders o
  left join public.tables tbl
    on tbl.organization_id = o.organization_id and tbl.id = o.table_id
  where o.organization_id = p_organization_id and o.id = p_order_id;
$$;

comment on function app.kitchen_dispatch_payload_initial(uuid, uuid) is
  'KITCHEN-MODE-001C1 INTERNAL + 017 + 019 + KIOSK-PRINT-114B.6B: the money-free INITIAL-ORDER dispatch payload snapshot. Items order by the CANONICAL MENU ORDER (category_display_order_snapshot, item_display_order_snapshot, line_position, created_at, id); each item''s MODIFIERS order by the AUTHORITATIVE dashboard order (modifier_group_display_order_snapshot, modifier_option_display_order_snapshot, line_position, created_at, id) — the exact expression app.pos_order_detail uses, so the kiosk claimed print, the POS drain, the POS direct ticket and the POS manual reprint print identical sub-lines. Item prep carries the 016 classifier triple through app.kitchen_prep_projection; each modifier''s own contribution + classifier through app.kitchen_modifier_prep_projection. A modifier with no contribution emits no prep key. KITCHEN-DISPATCH-HARDEN-001: LIVE LINES ONLY — voided and cancelled lines are excluded (oi.status not in (''voided'', ''cancelled'')).';

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
        and oi.deleted_at is null
        -- KITCHEN-DISPATCH-HARDEN-001: live lines only — a voided or
        -- cancelled line never reaches kitchen paper.
        and oi.status not in ('voided', 'cancelled'))))
  from public.orders o
  join public.order_service_rounds r
    on r.organization_id = o.organization_id and r.id = p_round_id and r.order_id = o.id
  left join public.tables tbl
    on tbl.organization_id = o.organization_id and tbl.id = o.table_id
  where o.organization_id = p_organization_id and o.id = p_order_id;
$$;

comment on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) is
  'KITCHEN-MODE-001C1 INTERNAL + 017 + 019 + KIOSK-PRINT-114B.6B: the money-free SERVICE-ROUND (Add-items) dispatch payload snapshot. Items order by the CANONICAL MENU ORDER; each item''s MODIFIERS order by the AUTHORITATIVE dashboard order (modifier_group_display_order_snapshot, modifier_option_display_order_snapshot, line_position, created_at, id) exactly as app.pos_order_detail does. Item prep carries the 016 classifier triple; each modifier''s own contribution + classifier through app.kitchen_modifier_prep_projection. Round scope is unchanged: only this round''s own items. KITCHEN-DISPATCH-HARDEN-001: LIVE LINES ONLY — voided and cancelled lines are excluded (oi.status not in (''voided'', ''cancelled'')).';

-- INTERNAL-ONLY posture re-asserted (idempotent; create-or-replace preserves
-- existing ACLs, these restate the contract explicitly).
revoke all on function app.create_kitchen_dispatch(uuid, uuid, uuid, uuid, uuid, text, jsonb, uuid, uuid, uuid) from public;
revoke all on function app.create_kitchen_dispatch(uuid, uuid, uuid, uuid, uuid, text, jsonb, uuid, uuid, uuid) from anon;
revoke all on function app.create_kitchen_dispatch(uuid, uuid, uuid, uuid, uuid, text, jsonb, uuid, uuid, uuid) from authenticated;
revoke all on function app.kitchen_dispatch_payload_initial(uuid, uuid) from public;
revoke all on function app.kitchen_dispatch_payload_initial(uuid, uuid) from anon;
revoke all on function app.kitchen_dispatch_payload_initial(uuid, uuid) from authenticated;
revoke all on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) from public;
revoke all on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) from anon;
revoke all on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) from authenticated;
