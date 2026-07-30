-- DEFERRED-ORDER-AMENDMENTS-001 — takeaway amendments + mode-aware manual close.
--
-- FORWARD-ONLY. No shipped migration is edited. Exactly TWO functions are
-- re-emitted, each from its LATEST shipped body, with the smallest approved
-- change and nothing else:
--
--   1. app.add_order_items
--      Source: 20260725090000_kitchen_mode_001c1_dispatch_ledger.sql (verbatim).
--      CHANGE (one line, the order-type eligibility gate only):
--          - if v_o_type <> 'dine_in' then
--          + if v_o_type not in ('dine_in', 'takeaway') then
--      Everything else is byte-identical: locking, authorization, org/branch/
--      device scope, target_id validation, local_operation_id idempotency,
--      fingerprint + replay, totals, revision, service-round creation, item
--      snapshots, the kitchen dispatch ledger row, auditing, typed errors and
--      the search_path/security posture.
--      NOT changed: no table is required for takeaway, and the delta dispatch
--      payload is untouched. delivery/other types keep the EXISTING typed
--      refusal `order_not_dine_in` and its audited denial contract — the wire
--      code is part of the shipped contract, so it is deliberately NOT renamed.
--
--   2. app.apply_order_status_transition
--      Source: 20260722090000_psc_001c_service_rounds.sql (verbatim).
--      CHANGE (the manual-completion rounds gate only): the gate now consults
--      the authoritative branches.kitchen_workflow_mode, fail-closed to 'kds',
--      using the SAME read app.try_auto_complete_order performs. In 'kds' the
--      behaviour is byte-equivalent to before; in 'printer_only' the KDS
--      service-round gate is skipped. Plus one new local variable for the mode.
--      NOT changed: no round status is written, no round is auto-served, no KDS
--      completion is fabricated, payment requirements are untouched, and
--      app.try_auto_complete_order / app.order_rounds_all_served /
--      app.update_round_status are NOT modified by this migration.
--
-- Every line of both bodies below was extracted programmatically from the
-- shipped files rather than retyped, so the diff is provably minimal.


create or replace function app.add_order_items(
  p_pin_session_id     uuid,
  p_order_id           uuid,
  p_device_id          uuid,
  p_local_operation_id text,
  p_order_items        jsonb,
  p_client_created_at  timestamptz default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org           uuid;
  v_rest          uuid;
  v_branch        uuid;
  v_dsid          uuid;
  v_emp           uuid;
  v_membership    uuid;
  v_ds_device     uuid;
  v_ds_active     boolean;
  v_ds_revoked    timestamptz;
  v_pairing       text;
  v_role          text;
  v_m_status      text;
  v_m_deleted     timestamptz;
  v_device_type   text;
  v_o_status      text;
  v_o_type        text;
  v_o_rev         integer;
  v_o_sub         bigint;
  v_o_disc        bigint;
  v_o_tax         bigint;
  v_item          jsonb;
  v_modifier      jsonb;
  v_item_id       uuid;
  v_qty           bigint;
  v_unit          bigint;
  v_mod_qty       bigint;
  v_mod_price     bigint;
  v_mod_sum       bigint;
  v_line_total    bigint;
  v_delta         bigint := 0;
  v_new_sub       bigint;
  v_new_grand     bigint;
  v_item_count    integer := 0;
  v_mod_count     integer := 0;
  v_unavailable   jsonb;
  v_item_ids      uuid[];
  v_round_id      uuid;
  v_kitchen_mode  text;  -- KITCHEN-MODE-001C1: branch workflow mode (dispatch gate)
  v_round_no      integer;
  v_new_rev       integer;
  v_ex_round      uuid;
  v_ex_order      uuid;
  v_ex_number     integer;
  v_ex_count      integer;
  v_shape_error   text;
  v_order_code    text := '#' || upper(right(replace(p_order_id::text, '-', ''), 6));
begin
  -- (a) THE CANONICAL PIN PREAMBLE (submit_order parity): session exists+valid,
  --     backing device session/pairing active, device match, membership active.
  --     Every structural failure raises 42501. Scope derived HERE, never payload.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'add_order_items: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'add_order_items: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'add_order_items: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'add_order_items: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'add_order_items: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) DEVICE CLASS: additions are a POS act (the mirror of kitchen_ack_void's
  --     KDS-only rule). A KDS device is refused regardless of role.
  select d.device_type into v_device_type
    from public.devices d
    where d.id = p_device_id and d.organization_id = v_org;
  if v_device_type is distinct from 'pos' then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role,
                               'device_type', coalesce(v_device_type, 'unknown'),
                               'denied_reason', 'invalid_device_type'));
    return jsonb_build_object('ok', false, 'error', 'invalid_device_type', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (c) ROLE: cashier+ may add items (submit_order parity — no new capability;
  --     kitchen_staff/accountant denied).
  if v_role not in ('cashier', 'manager', 'restaurant_owner', 'org_owner') then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role, 'device_type', v_device_type,
                               'denied_reason', 'permission_denied'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) payload envelope shape (structural, submit_order parity).
  if p_order_items is null or jsonb_typeof(p_order_items) <> 'array' or jsonb_array_length(p_order_items) < 1 then
    raise exception 'add_order_items: order_items must be a non-empty jsonb array' using errcode = '42501';
  end if;

  -- (e) PER-LINE SHAPE + ARITHMETIC — the submit_order recompute loop (D-008),
  --     replicated (see the header). Two deliberate deltas for ADDED lines:
  --       * NO order-level client totals exist to cross-check — the deltas are
  --         computed HERE and applied to the parent (server-authoritative);
  --       * a nonzero line_discount_minor is REJECTED (typed) — an addition
  --         never carries a hidden price cut.
  --     Missing identity/name fields are the TYPED invalid_item_payload refusal
  --     (the POS names the broken line); numeric parse failures keep the
  --     structural app.order_parse_minor raise (submit parity).
  v_shape_error := null;
  for v_item in select * from jsonb_array_elements(p_order_items)
  loop
    if (v_item ->> 'menu_item_id') is null then
      v_shape_error := 'menu_item_id_required';
      exit;
    end if;
    if (v_item ->> 'menu_item_name_snapshot') is null then
      v_shape_error := 'menu_item_name_snapshot_required';
      exit;
    end if;
    if (v_item ? 'line_discount_minor') and jsonb_typeof(v_item -> 'line_discount_minor') <> 'null'
       and app.order_parse_minor(v_item -> 'line_discount_minor', 'order_items[].line_discount_minor') <> 0 then
      v_shape_error := 'line_discount_not_allowed';
      exit;
    end if;
    v_qty := app.order_parse_minor(v_item -> 'quantity', 'order_items[].quantity');
    if v_qty <= 0 or v_qty > 2147483647 then
      raise exception 'add_order_items: order_items[].quantity must be between 1 and 2147483647' using errcode = '42501';
    end if;
    v_unit := app.order_parse_minor(v_item -> 'unit_price_minor_snapshot', 'order_items[].unit_price_minor_snapshot');

    v_mod_sum := 0;
    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        if (v_modifier ->> 'modifier_option_id') is null then
          v_shape_error := 'modifier_option_id_required';
          exit;
        end if;
        if (v_modifier ->> 'option_name_snapshot') is null then
          v_shape_error := 'option_name_snapshot_required';
          exit;
        end if;
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        if v_mod_qty <= 0 or v_mod_qty > 2147483647 then
          raise exception 'add_order_items: modifiers[].quantity must be between 1 and 2147483647' using errcode = '42501';
        end if;
        v_mod_sum := v_mod_sum + v_mod_price * v_mod_qty;
      end loop;
      if v_shape_error is not null then
        exit;
      end if;
    end if;

    v_line_total := v_qty * v_unit + v_mod_sum;
    if v_line_total < 0 then
      raise exception 'add_order_items: computed line_total_minor is negative' using errcode = '42501';
    end if;
    v_delta := v_delta + v_line_total;
  end loop;
  if v_shape_error is not null then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role, 'device_type', v_device_type,
                               'denied_reason', 'invalid_item_payload'));
    return jsonb_build_object('ok', false, 'error', 'invalid_item_payload', 'detail', v_shape_error,
                              'order_id', p_order_id, 'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (f) IDEMPOTENCY REPLAY (submit_order parity: after full payload validation,
  --     before the time-varying checks): the SAME (org, device, local_operation_id)
  --     returns the SAME round — no duplicate round, no duplicate items — even if
  --     the parent's state has since moved on. The same key on a DIFFERENT order
  --     is a conflict (40001), mirroring record_payment.
  select r.id, r.order_id, r.round_number
    into v_ex_round, v_ex_order, v_ex_number
    from public.order_service_rounds r
    where r.organization_id = v_org
      and r.device_id = p_device_id
      and r.local_operation_id = p_local_operation_id
    limit 1;
  if found then
    if v_ex_order <> p_order_id then
      raise exception 'add_order_items: idempotency key already used for a different order (%, not %)', v_ex_order, p_order_id using errcode = '40001';
    end if;
    select count(*)::int into v_ex_count
      from public.order_items oi
      where oi.organization_id = v_org and oi.service_round_id = v_ex_round;
    select o.revision into v_o_rev from public.orders o where o.id = p_order_id and o.organization_id = v_org;
    return jsonb_build_object(
      'ok', true, 'order_id', p_order_id, 'round_id', v_ex_round, 'round_number', v_ex_number,
      'added_item_count', v_ex_count, 'revision', v_o_rev,
      'server_ts', now(), 'idempotency_replay', true);
  end if;

  -- (g) ONE SCOPED PARENT LOOKUP, FOR UPDATE — the FIRST lock (the same first
  --     lock payment/void/status/discount take). ANTI-ORACLE (R-003, the
  --     PSC-001D F1 pattern): a nonexistent order and a foreign-tenant order
  --     raise the SAME structural 42501.
  select o.status, o.order_type, o.revision, o.subtotal_minor, o.discount_total_minor, o.tax_total_minor
    into v_o_status, v_o_type, v_o_rev, v_o_sub, v_o_disc, v_o_tax
    from public.orders o
    where o.id = p_order_id
      and o.organization_id = v_org
      and o.restaurant_id   = v_rest
      and o.branch_id       = v_branch
      and o.deleted_at is null
    for update;
  if not found then
    raise exception 'add_order_items: order_not_found_or_not_accessible' using errcode = '42501';
  end if;

  -- (h) ELIGIBILITY (typed RETURN-refusals, each audited).
  if v_o_type not in ('dine_in', 'takeaway') then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role, 'device_type', v_device_type,
                               'order_type', v_o_type, 'denied_reason', 'order_not_dine_in'));
    return jsonb_build_object('ok', false, 'error', 'order_not_dine_in', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;
  if v_o_status not in ('submitted', 'accepted', 'preparing', 'ready', 'served') then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role, 'device_type', v_device_type,
                               'order_status', v_o_status, 'denied_reason', 'order_not_eligible'));
    return jsonb_build_object('ok', false, 'error', 'order_not_eligible', 'order_id', p_order_id,
                              'order_status', v_o_status, 'server_ts', now(), 'idempotency_replay', false);
  end if;
  -- The PAYMENT FREEZE (apply_discount precedent): a live COMPLETED payment
  -- froze the bill it covered. record_payment allows at most ONE completed
  -- payment and always charges the CURRENT total, so a post-payment addition
  -- could never be settled — and the numbered receipt's total must stay true.
  -- (A zero-total order with NO completed payment falls through: still open,
  -- still eligible, and the addition simply makes it chargeable again.)
  if exists (
       select 1 from public.payments p
       where p.organization_id = v_org
         and p.order_id = p_order_id
         and p.status = 'completed'
         and p.deleted_at is null) then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role, 'device_type', v_device_type,
                               'order_status', v_o_status, 'denied_reason', 'order_already_settled'));
    return jsonb_build_object('ok', false, 'error', 'order_already_settled', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (i) SELLABILITY + AVAILABILITY under ascending-id FOR UPDATE menu locks —
  --     the submit_order accept-2 block, replicated verbatim (same predicate,
  --     same TOCTOU serialization point, same uniform refusal — R-003).
  select array_agg(distinct (e ->> 'menu_item_id')::uuid)
    into v_item_ids
    from jsonb_array_elements(p_order_items) e;
  perform 1
    from public.menu_items i
    where i.organization_id = v_org
      and i.id = any (v_item_ids)
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
          select (e ->> 'menu_item_id')::uuid as menu_item_id,
                 min(e ->> 'menu_item_name_snapshot') as name
            from jsonb_array_elements(p_order_items) e
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
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role, 'device_type', v_device_type,
                               'order_status', v_o_status, 'denied_reason', 'item_unavailable'));
    return jsonb_build_object('ok', false, 'error', 'item_unavailable',
                              'entity', 'order', 'items', v_unavailable,
                              'order_id', p_order_id, 'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (j) ALLOCATE the round number under the held parent lock: max(round_number)
  --     across ALL rows of this order (voided/deleted INCLUDED — a number is
  --     NEVER reused), +1; the very first addition is ROUND 2 (the original
  --     order is kitchen work unit 1). Serialized by the parent lock; the
  --     per-order unique constraint is the layer-4 backstop.
  select coalesce(max(r.round_number), 1) + 1
    into v_round_no
    from public.order_service_rounds r
    where r.organization_id = v_org
      and r.order_id        = p_order_id;

  v_round_id := gen_random_uuid();
  insert into public.order_service_rounds (
    id, organization_id, restaurant_id, branch_id, order_id, round_number,
    status, device_id, opened_by_employee_profile_id, local_operation_id,
    revision, client_created_at)
  values (
    v_round_id, v_org, v_rest, v_branch, p_order_id, v_round_no,
    'submitted', p_device_id, v_emp, p_local_operation_id,
    1, p_client_created_at);

  -- (k) insert the ADDED items (status 'pending', submit_order parity) with
  --     their round membership, + modifiers. line_discount_minor is FORCED 0
  --     (validated above).
  for v_item in select * from jsonb_array_elements(p_order_items)
  loop
    v_qty  := app.order_parse_minor(v_item -> 'quantity', 'order_items[].quantity');
    v_unit := app.order_parse_minor(v_item -> 'unit_price_minor_snapshot', 'order_items[].unit_price_minor_snapshot');
    v_mod_sum := 0;
    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        v_mod_sum := v_mod_sum + v_mod_price * v_mod_qty;
      end loop;
    end if;
    v_line_total := v_qty * v_unit + v_mod_sum;

    insert into public.order_items (
      organization_id, restaurant_id, branch_id, order_id, menu_item_id,
      status, quantity, menu_item_name_snapshot, unit_price_minor_snapshot,
      item_size_snapshot, item_variant_snapshot, line_discount_minor, line_total_minor,
      notes, prep_snapshot, service_round_id)
    values (
      v_org, v_rest, v_branch, p_order_id, (v_item ->> 'menu_item_id')::uuid,
      'pending', v_qty::int, v_item ->> 'menu_item_name_snapshot', v_unit,
      v_item -> 'item_size_snapshot', v_item -> 'item_variant_snapshot', 0, v_line_total,
      v_item ->> 'notes', v_item -> 'prep_snapshot', v_round_id)
    returning id into v_item_id;

    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        insert into public.order_item_modifiers (
          organization_id, restaurant_id, branch_id, order_item_id, modifier_option_id,
          modifier_name_snapshot, option_name_snapshot, price_minor_snapshot, quantity, meat_snapshot)
        values (
          v_org, v_rest, v_branch, v_item_id, (v_modifier ->> 'modifier_option_id')::uuid,
          v_modifier ->> 'modifier_name_snapshot', v_modifier ->> 'option_name_snapshot', v_mod_price, v_mod_qty::int, v_modifier -> 'meat_snapshot');
        v_mod_count := v_mod_count + 1;
      end loop;
    end if;
    v_item_count := v_item_count + 1;
  end loop;

  -- (l) PARENT TOTALS (server-authoritative, D-007): subtotal grows by the
  --     recomputed delta; the ABSOLUTE prior discount and the stored tax stay
  --     EXACTLY as they were (locked: never silently re-scaled); the grand
  --     follows the ONE canonical formula. The parent status is NEVER moved.
  v_new_sub   := v_o_sub + v_delta;
  v_new_grand := v_new_sub - v_o_disc + v_o_tax;
  if v_new_grand < 0 then
    raise exception 'add_order_items: computed grand_total_minor is negative' using errcode = '42501';
  end if;
  v_new_rev := v_o_rev + 1;
  update public.orders
    set subtotal_minor = v_new_sub, grand_total_minor = v_new_grand, revision = v_new_rev
    where id = p_order_id;

  -- (m) audit order.items_added (D-013): safe scalars only — and MONEY-FREE
  -- (PSC-001C correction, Finding 6): the approved contract for the four new
  -- service-round actions carries NO monetary field. What was added and to
  -- which order is the operational record; the money moved is derivable from
  -- the order's own authoritative rows, never from this trail.
  insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_added', null,
          jsonb_build_object('order_id', p_order_id, 'revision', v_o_rev),
          jsonb_build_object('order_id', p_order_id, 'order_code', v_order_code,
                             'round_number', v_round_no, 'added_item_count', v_item_count,
                             'order_status', v_o_status, 'role', v_role,
                             'device_type', v_device_type,
                             'revision', v_new_rev,
                             'local_operation_id', p_local_operation_id,
                             'resolved_membership_id', v_membership));

  -- KITCHEN-MODE-001C1 (DORMANT): a printer-only branch gets ONE durable
  -- service-round dispatch in this SAME transaction — the ROUND DELTA only,
  -- idempotent by round id, nothing for kds branches, and nothing survives a
  -- rollback. A dispatch failure fails the addition (fail closed).
  -- CORRECTION-001: a missing branch row here is a state inconsistency (the
  -- liveness chain proved it live at ingest) — never a silent kds fallback.
  select b.kitchen_workflow_mode into v_kitchen_mode
    from public.branches b
    where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;
  if v_kitchen_mode is null then
    raise exception 'add_order_items: branch row unavailable during the kitchen dispatch gate (state inconsistency)';
  end if;
  if v_kitchen_mode = 'printer_only' then
    perform app.create_kitchen_dispatch(
      v_org, v_rest, v_branch, p_order_id, v_round_id, 'service_round',
      app.kitchen_dispatch_payload_round(v_org, p_order_id, v_round_id),
      v_emp, v_membership, p_device_id);
  end if;

  return jsonb_build_object(
    'ok', true, 'order_id', p_order_id, 'round_id', v_round_id, 'round_number', v_round_no,
    'added_item_count', v_item_count, 'revision', v_new_rev,
    'server_ts', now(), 'idempotency_replay', false);
end;
$$;

create or replace function app.apply_order_status_transition(
  p_order_id                  uuid,
  p_new_status                text,
  p_actor_org                 uuid,
  p_actor_restaurant          uuid,
  p_actor_branch              uuid,
  p_actor_role                text,
  p_actor_app_user_id         uuid,      -- JWT actor  (null on the device path)
  p_actor_employee_profile_id uuid,      -- PIN actor  (null on the JWT path)
  p_actor_membership_id       uuid,
  p_device_id                 uuid,      -- null on the JWT path
  p_local_operation_id        text,      -- null on the JWT path
  p_expected_revision         integer default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_o_org      uuid;
  v_o_branch   uuid;
  v_o_status   text;
  v_o_rev      integer;
  v_legal      boolean;
  v_new_rev    integer;
  v_paid       boolean;
  v_o_total    bigint;   -- the order's CURRENT total: chargeable vs not_chargeable
  v_auto       jsonb;
  v_kitchen_mode text;   -- DEFERRED-ORDER-AMENDMENTS-001: authoritative branch mode
  v_order_code text := '#' || upper(right(replace(p_order_id::text, '-', ''), 6));
begin
  -- (a) load the order FOR UPDATE (serializes concurrent status pushes); it MUST
  --     be in the actor's organization AND branch. Cross-tenant -> fail-closed
  --     raise, no write.
  select o.organization_id, o.branch_id, o.status, o.revision, o.grand_total_minor
    into v_o_org, v_o_branch, v_o_status, v_o_rev, v_o_total
    from public.orders o where o.id = p_order_id
    for update;
  if not found then
    raise exception 'update_order_status: order not found' using errcode = '42501';
  end if;
  if v_o_org <> p_actor_org or v_o_branch <> p_actor_branch then
    raise exception 'update_order_status: order is not in the caller scope' using errcode = '42501';
  end if;

  -- (b) OPTIMISTIC CONCURRENCY (opt-in; the PIN front passes null, preserving its
  --     exact behaviour). A stale client that read revision N cannot overwrite a
  --     newer state: it gets the documented `revision_mismatch` with the server's
  --     revision so it can re-read. (API_CONTRACT §2 error model.)
  if p_expected_revision is not null and p_expected_revision <> v_o_rev then
    return jsonb_build_object('ok', false, 'error', 'revision_mismatch',
                              'order_id', p_order_id, 'status', v_o_status,
                              'server_revision', v_o_rev,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (c) transition legality: SINGLE-STEP forward only over the FROZEN states
  --     (D-018, STATE_MACHINES §1.1). Skips, backwards, terminal sources
  --     (completed/cancelled/voided), unknown targets, and from==to are all
  --     invalid_transition (returned, not raised — a permanent per-op rejection
  --     through sync_push; no state change). The client can NEVER choose an
  --     arbitrary next status: only these five (from, to) pairs exist.
  v_legal := case
    when v_o_status = 'submitted' and p_new_status = 'accepted'  then true
    when v_o_status = 'accepted'  and p_new_status = 'preparing' then true
    when v_o_status = 'preparing' and p_new_status = 'ready'     then true
    when v_o_status = 'ready'     and p_new_status = 'served'    then true
    when v_o_status = 'served'    and p_new_status = 'completed' then true
    else false end;
  if not v_legal then
    return jsonb_build_object('ok', false, 'error', 'invalid_transition',
                              'from', v_o_status, 'to', p_new_status, 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) role authorization: the production + service steps (->accepted/->preparing/
  --     ->ready/->served — the last is the KDS "bump") allow kitchen_staff + cashier
  --     + manager + restaurant_owner + org_owner; the settlement step (->completed)
  --     EXCLUDES kitchen_staff. A denial is audited (order.status_update_denied —
  --     NO money fields) and RETURNED (no raise, so the audit persists), with NO
  --     state change.
  if p_actor_role not in ('kitchen_staff', 'cashier', 'manager', 'restaurant_owner', 'org_owner')
     or (p_actor_role = 'kitchen_staff' and p_new_status = 'completed') then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (p_actor_org, p_actor_restaurant, p_actor_branch, p_actor_app_user_id, p_actor_employee_profile_id, p_device_id,
            'order.status_update_denied', null, null,
            jsonb_build_object('attempted_action', 'update_order_status', 'order_id', p_order_id,
                               'order_code', v_order_code,
                               'role', p_actor_role, 'from', v_o_status, 'to', p_new_status,
                               'local_operation_id', p_local_operation_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied',
                              'order_id', p_order_id, 'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (e) D-025 PAYMENT GATE (ORDER-COMPLETION-001) — an order reaches `completed`
  --     only when payment is `completed`. Derived, never fabricated: "paid" is the
  --     existence of a completed, live payments row (the SAME derivation the
  --     reports and owner_active_orders use). This creates NO payment and changes
  --     NO payments row. A business rejection, NOT an authorization denial, so —
  --     like invalid_transition — it is RETURNED and deliberately NOT audited (the
  --     denied-attempt audit is reserved for authorization failures).
  if p_new_status = 'completed' then
    -- ORDER-AUTO-COMPLETION-001: the ONE authoritative settlement test (integer
    -- minor units). Replaces the bare exists()-a-completed-payment MARKER test:
    -- app.apply_discount can re-base grand_total_minor after a payment is taken, so
    -- a marker could report a partially-settled order as paid. Identical to the old
    -- test in every normal case (the stored amount IS the order total).
    v_paid := app.order_is_fully_settled(v_o_org, p_order_id);
    if not v_paid then
      return jsonb_build_object('ok', false, 'error', 'order_not_paid',
                                'order_id', p_order_id, 'from', v_o_status, 'to', p_new_status,
                                'server_ts', now(), 'idempotency_replay', false);
    end if;
    -- PSC-001C: the MANUAL completion gate additionally requires EVERY
    -- additional service round to be served (app.order_rounds_all_served —
    -- zero rounds passes trivially). A business rejection like order_not_paid:
    -- RETURNED, deliberately not audited (the denied-attempt audit is reserved
    -- for authorization failures).
    -- DEFERRED-ORDER-AMENDMENTS-001: the rounds gate is KDS-MODE ONLY.
    -- The ONE mode read, FAIL-CLOSED to 'kds' exactly as
    -- app.try_auto_complete_order does it (a missing or soft-deleted branch row
    -- can only ever produce the historical behaviour, never the widened
    -- printer-only path). The branch is the ORDER's own authoritative
    -- branch_id, already proven equal to the caller scope in (a).
    select b.kitchen_workflow_mode into v_kitchen_mode
      from public.branches b
      where b.id              = v_o_branch
        and b.organization_id = v_o_org
        and b.deleted_at is null;
    v_kitchen_mode := coalesce(v_kitchen_mode, 'kds');
    -- printer_only: there is no KDS to walk a round to `served`, so holding
    -- manual completion on it would strand every added-to order forever. The
    -- gate is SKIPPED — never satisfied by fabricating a round status.
    -- kds: byte-equivalent to the pre-DEFERRED-ORDER-AMENDMENTS-001 behaviour.
    if v_kitchen_mode <> 'printer_only'
       and not app.order_rounds_all_served(v_o_org, p_order_id) then
      return jsonb_build_object('ok', false, 'error', 'rounds_not_served',
                                'order_id', p_order_id, 'from', v_o_status, 'to', p_new_status,
                                'server_ts', now(), 'idempotency_replay', false);
    end if;
  end if;

  -- (f) mutate: status forward one step; bump revision (updated_at bumps via the
  --     RF-052 set_updated_at trigger, feeding the sync_pull change cursor).
  --     orders.status + orders.revision are the ONLY columns written. No payment,
  --     no shift, no table, no receipt, no total is touched.
  v_new_rev := v_o_rev + 1;
  update public.orders
    set status   = p_new_status,
        revision = v_new_rev,
        -- PSC-001C: the WRITE-ONCE durable ready stamp for the INITIAL kitchen
        -- work unit (the ready-feed source). Stamped exactly when a transition
        -- lands on `ready`; never cleared or re-stamped afterwards (the
        -- single-step matrix makes `ready` reachable once, and the case-guard
        -- keeps the stamp idempotent regardless).
        ready_at = case when p_new_status = 'ready' and ready_at is null then now() else ready_at end
    where id = p_order_id;

  -- (g) audit order.status_updated (D-013) — old/new STATUS + revision + actor
  --     linkage + the SAFE order_code, plus the derived payment_status on a
  --     completion. Deliberately NO money fields: a kitchen actor drives the
  --     production steps of this path and must never put a money figure on the
  --     wire or in its audit (T-003).
  insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values (p_actor_org, p_actor_restaurant, p_actor_branch, p_actor_app_user_id, p_actor_employee_profile_id, p_device_id,
          'order.status_updated', null,
          jsonb_build_object('order_id', p_order_id, 'status', v_o_status, 'revision', v_o_rev),
          jsonb_build_object('order_id', p_order_id, 'order_code', v_order_code,
                             'status', p_new_status, 'revision', v_new_rev,
                             'resolved_membership_id', p_actor_membership_id, 'role', p_actor_role,
                             'local_operation_id', p_local_operation_id)
          -- THE AUDIT MUST NOT LIE (D-013): a ZERO-TOTAL order is completed WITHOUT a
          -- payment row, so 'paid' would assert a payment that was never taken. State
          -- the truth — there was nothing to pay.
          || case when p_new_status = 'completed'
                  then jsonb_build_object('payment_status',
                                          case when v_o_total = 0 then 'not_chargeable'
                                               else 'paid' end,
                                          'completion_mode', 'manual')
                  else '{}'::jsonb end);

  -- (h) TRIGGER DIRECTION A (ORDER-AUTO-COMPLETION-001): the order just reached
  --     `served`. If it is ALREADY fully paid, complete it now — in this same
  --     transaction, under the order row lock we already hold. The `served`
  --     transition above stands on its own and is NEVER failed by this: an unpaid
  --     order simply stays served (and stays visible in Awaiting close). The helper
  --     never raises, and it does not re-run the role gate — the kitchen actor was
  --     already authorized to make THIS transition, and the completion is a
  --     system-rule consequence of it, not a second human decision.
  if p_new_status = 'served' then
    v_auto := app.try_auto_complete_order(
      p_actor_org, p_actor_restaurant, p_actor_branch, p_order_id,
      'order_served',
      p_actor_app_user_id, p_actor_employee_profile_id, p_actor_membership_id,
      p_actor_role, p_device_id, p_local_operation_id);
    if (v_auto ->> 'completed')::boolean then
      -- Report the FINAL state, so the caller (and the sync ledger) never records a
      -- status the order is no longer in.
      return jsonb_build_object('ok', true, 'entity', 'order', 'order_id', p_order_id,
                                'order_code', v_order_code,
                                'status', 'completed',
                                'revision', (v_auto ->> 'revision')::integer,
                                'auto_completed', true,
                                'completion_trigger', 'order_served',
                                'server_ts', now(), 'idempotency_replay', false);
    end if;
  end if;

  return jsonb_build_object('ok', true, 'entity', 'order', 'order_id', p_order_id,
                            'order_code', v_order_code,
                            'status', p_new_status, 'revision', v_new_rev,
                            'auto_completed', false,
                            'server_ts', now(), 'idempotency_replay', false);
end;
$$;

-- ---------------------------------------------------------------------------
-- Security / grant posture: UNCHANGED from the shipped definitions. Re-emitting
-- a function with `create or replace` preserves existing privileges, but these
-- are restated so the posture is explicit and cannot drift.
--
--  * app.add_order_items                 — SECURITY DEFINER, search_path = '',
--    revoked from public + anon, EXECUTE granted to authenticated (it is the
--    order.items_add front the PIN/device path calls).
--  * app.apply_order_status_transition    — SECURITY DEFINER, search_path = '',
--    revoked from public + anon + authenticated: it is INTERNAL and is only ever
--    called by its own authenticated fronts. No privilege is broadened here.
-- ---------------------------------------------------------------------------
revoke all on function app.add_order_items(uuid, uuid, uuid, text, jsonb, timestamptz) from public;
revoke all on function app.add_order_items(uuid, uuid, uuid, text, jsonb, timestamptz) from anon;
grant execute on function app.add_order_items(uuid, uuid, uuid, text, jsonb, timestamptz) to authenticated;

revoke all on function app.apply_order_status_transition(uuid, text, uuid, uuid, uuid, text, uuid, uuid, uuid, uuid, text, integer) from public;
revoke all on function app.apply_order_status_transition(uuid, text, uuid, uuid, uuid, text, uuid, uuid, uuid, uuid, text, integer) from anon;
revoke all on function app.apply_order_status_transition(uuid, text, uuid, uuid, uuid, text, uuid, uuid, uuid, uuid, text, integer) from authenticated;
