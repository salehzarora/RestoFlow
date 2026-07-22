-- ============================================================================
-- KITCHEN-PRINT-DUAL-001C — direct_print DISPATCH MODE (forward-only, additive).
--
-- Problem: a restaurant operating WITHOUT a KDS device dispatches the kitchen
-- ticket straight from the POS printer. Such an order must NOT enter the active
-- KDS workflow (no Accept/Preparing/Ready), yet it must still close through the
-- NORMAL, UNCHANGED payment/settlement rule (D-025). The shipped contract cannot
-- express this (single-step forward state machine; `completed` is settlement-
-- gated; no create-in-final-state op), so this migration adds the smallest
-- forward-only mechanism. Human-approved WITHOUT bypassing payment settlement or
-- changing payment/customer-receipt behavior.
--
-- Additive changes:
--   1. public.orders.dispatch_mode  ('kds' default | 'direct_print') — a closed
--      dispatch enum. Existing rows default to 'kds' (the normal KDS workflow);
--      `to_jsonb(orders)` in app.sync_pull_changes auto-propagates it to the KDS.
--   2. app.apply_direct_print_dispatch(...) — the ONE server step that routes a
--      just-submitted order OUT of the KDS active workflow, IN THE SAME sync_push
--      transaction (no puller can observe an intermediate active state): it
--      promotes the fresh `submitted` order to `served` (its kitchen dispatch IS
--      the printed ticket — it skips the KDS accept/prepare/ready states),
--      stamps dispatch_mode='direct_print', dispatches its items, writes one
--      money-free order.status_updated audit, and then runs the UNCHANGED
--      app.try_auto_complete_order — so a ZERO-TOTAL (non-chargeable) order
--      auto-completes now and a CHARGEABLE one stays `served` until the normal
--      payment settles it. Settlement is NEVER bypassed; no payment is created.
--   3. app.sync_push — the order.submit case gains a 4-line call to the helper
--      when the op payload carries dispatch_mode='direct_print' (byte-faithful
--      re-emit of the 20260725 body; only that call is added, mirroring the
--      existing post-submit customer_name stamp seam).
--   4. app.audit_safe_detail — the allowlist gains the closed 'dispatch_mode'
--      state key so the Activity Log can name a direct_print dispatch (money-free,
--      never an identifier — T-003 holds).
--
-- KDS containment is enforced additionally CLIENT-SIDE in KdsTicketMapper (a
-- direct_print order is excluded from the active board regardless of status).
--
-- SECURITY: apply_direct_print_dispatch is INTERNAL (granted to no client role);
-- it is only ever called by app.sync_push, which has already authenticated the
-- actor + scope. It never re-runs the role gate (the submit already authorized
-- the actor) and never raises on the completion step (try_auto_complete_order is
-- fail-soft). Idempotent: only a FRESH `submitted`/`kds` order is dispatched, so
-- an offline replay of order.submit (which re-returns the same order_id) is a
-- structural no-op — no duplicate transition, no duplicate audit.
-- ============================================================================

alter table public.orders
  add column dispatch_mode text not null default 'kds'
    check (dispatch_mode in ('kds', 'direct_print'));

comment on column public.orders.dispatch_mode is
  'KITCHEN-PRINT-DUAL-001C: how this order is dispatched to the kitchen. ''kds'' (default) = the normal KDS active workflow. ''direct_print'' = dispatched via the POS kitchen printer; routed OUT of the KDS active board (KdsTicketMapper excludes it) and rested at ''served'' by app.apply_direct_print_dispatch. Closed enum; never money, never an identifier (T-003).';

-- ----------------------------------------------------------------------------
-- app.apply_direct_print_dispatch — the ONE direct_print server step.
-- ----------------------------------------------------------------------------
create or replace function app.apply_direct_print_dispatch(
  p_organization_id           uuid,
  p_restaurant_id             uuid,
  p_branch_id                 uuid,
  p_order_id                  uuid,
  p_actor_employee_profile_id uuid,
  p_actor_membership_id       uuid,
  p_device_id                 uuid,
  p_local_operation_id        text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_status   text;
  v_mode     text;
  v_rev      integer;
  v_new_rev  integer;
  v_role     text;
  v_auto     jsonb;
  v_order_code text := '#' || upper(right(replace(p_order_id::text, '-', ''), 6));
begin
  -- Lock the order app.submit_order just created (same sync_push transaction).
  select o.status, o.dispatch_mode, o.revision
    into v_status, v_mode, v_rev
    from public.orders o
    where o.id = p_order_id
      and o.organization_id = p_organization_id
      and o.deleted_at is null
    for update;

  -- IDEMPOTENT: dispatch ONLY a fresh submitted KDS order. A replay of the
  -- order.submit op (same order_id, already dispatched -> served/completed, or
  -- already direct_print) is a structural no-op: no duplicate transition/audit.
  if not found or v_status <> 'submitted' or v_mode <> 'kds' then
    return jsonb_build_object('dispatched', false, 'reason', 'not_eligible');
  end if;

  -- Resolve the actor role for the audit context ONLY (submit already authorized
  -- the actor; this does NOT re-run the role gate).
  select m.role into v_role
    from public.memberships m
    where m.id = p_actor_membership_id and m.organization_id = p_organization_id;

  v_new_rev := v_rev + 1;

  -- Route OUT of the KDS active workflow: the kitchen dispatch IS the printed
  -- ticket, so the order skips the KDS accept/prepare/ready states and rests at
  -- `served`. Stamp the closed dispatch enum + a write-once ready_at.
  update public.orders
    set status        = 'served',
        dispatch_mode  = 'direct_print',
        ready_at       = coalesce(ready_at, now()),
        revision       = v_new_rev
    where id = p_order_id;

  -- Its items are dispatched too (no KDS bump will ever advance them).
  update public.order_items
    set status = 'served'
    where order_id        = p_order_id
      and organization_id = p_organization_id
      and status          = 'pending';

  -- ONE money-free order.status_updated audit (D-013): submitted -> served via
  -- the direct_print dispatch. dispatch_mode is a closed STATE enum (T-003).
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    p_organization_id, p_restaurant_id, p_branch_id,
    null, p_actor_employee_profile_id, p_device_id,
    'order.status_updated', null,
    jsonb_build_object('order_status', 'submitted'),
    jsonb_build_object(
      'order_status',  'served',
      'from_status',   'submitted',
      'to_status',     'served',
      'dispatch_mode', 'direct_print',
      'order_code',    v_order_code,
      'role',          v_role));

  -- Completion follows the UNCHANGED served+paid rule: a ZERO-TOTAL
  -- (non-chargeable) order auto-completes now; a CHARGEABLE one stays `served`
  -- until the NORMAL payment settles it (D-025). Settlement is NEVER bypassed,
  -- no payment is created, and the helper NEVER raises (fail-soft).
  v_auto := app.try_auto_complete_order(
    p_organization_id, p_restaurant_id, p_branch_id, p_order_id,
    'order_served', null, p_actor_employee_profile_id, p_actor_membership_id,
    v_role, p_device_id, p_local_operation_id);

  -- Re-read the FINAL committed state (served, or completed if the zero-total
  -- auto-completion just fired) so app.sync_push can merge an HONEST envelope.
  select o.status, o.revision into v_status, v_new_rev
    from public.orders o where o.id = p_order_id;
  return jsonb_build_object(
    'dispatched',     true,
    'auto_completed', coalesce((v_auto ->> 'completed')::boolean, false),
    'order_status',   v_status,
    'revision',       v_new_rev);
end;
$$;

comment on function app.apply_direct_print_dispatch(uuid, uuid, uuid, uuid, uuid, uuid, uuid, text) is
  'KITCHEN-PRINT-DUAL-001C SECURITY DEFINER helper: routes a just-submitted order OUT of the KDS active workflow for a printer-dispatched (no-KDS) restaurant. In the SAME app.sync_push transaction it promotes the FRESH submitted order to served (skipping the KDS accept/prepare/ready states — the kitchen dispatch is the POS printed ticket), stamps dispatch_mode=direct_print + a write-once ready_at, dispatches the items to served, writes ONE money-free order.status_updated audit, then runs the UNCHANGED app.try_auto_complete_order so a zero-total order auto-completes and a chargeable one stays served until the NORMAL payment settles it (D-025 NEVER bypassed; no payment created). IDEMPOTENT: only a submitted/kds order is acted on, so an order.submit replay is a no-op. INTERNAL: not granted to any client role; only app.sync_push calls it, after it has authenticated the actor + scope.';

revoke all on function app.apply_direct_print_dispatch(uuid, uuid, uuid, uuid, uuid, uuid, uuid, text) from public;
revoke all on function app.apply_direct_print_dispatch(uuid, uuid, uuid, uuid, uuid, uuid, uuid, text) from anon;
revoke all on function app.apply_direct_print_dispatch(uuid, uuid, uuid, uuid, uuid, uuid, uuid, text) from authenticated;


-- ----------------------------------------------------------------------------
-- app.audit_safe_detail — allowlist gains the closed 'dispatch_mode' state key.
-- Byte-faithful re-emit of the 20260726090000 body; ONLY the key is added.
-- ----------------------------------------------------------------------------
create or replace function app.audit_safe_detail(p_action text, p_values jsonb)
  returns jsonb
  language plpgsql
  immutable
  set search_path = ''
as $$
declare
  v_out  jsonb := '{}'::jsonb;
  v_caps jsonb;
  v_key  text;
begin
  -- Unknown / unsupported action -> no payload details.
  if not app.audit_action_has_detail(p_action) then
    return '{}'::jsonb;
  end if;
  -- Malformed / missing / non-object payload -> empty safe detail (never throws).
  if p_values is null or jsonb_typeof(p_values) <> 'object' then
    return '{}'::jsonb;
  end if;

  -- Canonical SAFE SCALAR allowlist. A key is emitted ONLY when it is on this
  -- list AND its value is a scalar (string/number/boolean) — nested objects,
  -- arrays, and every un-listed key (secret OR merely unknown) are dropped.
  foreach v_key in array array[
    'status','order_status','scope','discount_type','value','attempted_action','order_type',
    'role','from_role','to_role','target_role',
    'discount_total_minor','grand_total_minor','subtotal_minor','line_total_minor','line_discount_minor',
    'amount_minor','tendered_minor','change_minor','opening_float_minor',
    'expected_cash_minor','counted_cash_minor','cash_variance_minor','variance_minor',
    'voided_item_count','failed_attempt_count','locked',
    'timezone','name','receipt_prefix',
    'order_code','payment_status',
    'dispatch_mode',   -- KITCHEN-PRINT-DUAL-001C: closed dispatch enum (kds|direct_print); money-free state (T-003)
    -- ORDER-AUTO-COMPLETION-001: how, and why, an order was completed. Both are
    -- STATES ('automatic'/'manual', 'order_served'/'payment_recorded'), not money
    -- and not identifiers — T-003 still holds.
    'completion_mode','completion_trigger',
    -- MONEY-SETTLEMENT-CONSISTENCY-001: WHY a mutation was denied. order.discount_denied
    -- and order.void_denied have always carried this, but it was never allowlisted — so
    -- the Activity Log showed THAT a discount was refused and never WHY. It is a closed
    -- enum of safe STATE tokens (order_has_completed_payment | full_comp_requires_manager),
    -- never money and never an identifier (T-003 holds).
    'denied_reason',
    -- FULL-COMP-PERMISSION-001: WHAT the mutation would have left the order as. A
    -- closed enum of STATE tokens ('not_chargeable') -- never money, never an
    -- identifier (T-003 holds).
    'resulting_charge_state',
    -- RESTAURANT-OPERATIONS-V1-001: branch availability (closed enums
    -- available|unavailable / sold_out|paused) + the menu item's display name,
    -- and table-move floor labels (human table names). Names/labels are tenant
    -- display text already shown on receipts/tickets — never money, never ids.
    'availability','availability_reason','item_name',
    'table_label','from_table_label','to_table_label',
    -- PILOT-OPERATIONS-CORRECTIONS-001: manual table status transition
    -- (closed enum available|reserved|occupied|out_of_service) + the combined
    -- group label (floor names). Never money, never identifiers (T-003 holds).
    'from_status','to_status','group_label',
    -- PSC-001D: void provenance + kitchen acknowledgement. voided_from_status
    -- is the closed order-status enum; device_type is the closed pos|kds enum;
    -- kitchen_ack_required is a boolean. Never money, never identifiers
    -- (T-003 holds).
    'voided_from_status','device_type','kitchen_ack_required',
    -- PSC-001C: service rounds. round_number and added_item_count are small
    -- integers (a position in the order and a line count) — never money,
    -- never identifiers (T-003 holds).
    'round_number','added_item_count',
    -- KITCHEN-MODE-001B: printer configuration scalars. display_name is tenant
    -- display text (the item_name/table_label class); the rest are closed
    -- enums/booleans. connection_config (host/port/addresses) is a NESTED
    -- OBJECT and is therefore structurally dropped by the scalar-only rule —
    -- endpoints never reach the Activity Log timeline.
    'display_name','paper_width','is_enabled','connection_type',
    -- KITCHEN-MODE-001C1: kitchen dispatch safe scalars (closed enum + the
    -- existing safe order_code class). The money_free_payload itself is
    -- NEVER projected into audit detail.
    'dispatch_type',
    -- KITCHEN-MODE-001C3A: the kitchen-mode family scalars. kitchen_workflow_mode
    -- is the closed kds|printer_only enum; kitchen_workflow_mode_revision is a
    -- small positive integer (never money, never an identifier — T-003 holds);
    -- resolution / reason_code are CLOSED safe state tokens written only by the
    -- future 001C3B owner setter + hold resolution (human-actor paths). NOTE:
    -- settings.branch.updated projects full branch-row snapshots, so the mode
    -- and revision now also surface there — both are safe display state, the
    -- timezone/name class.
    'kitchen_workflow_mode','kitchen_workflow_mode_revision','resolution','reason_code'
  ] loop
    -- PSC-001C correction (Finding 6): the four service-round actions are
    -- MONEY-FREE by approved contract — any *_minor key (hostile, manual, or
    -- accidental) is dropped for EXACTLY these actions, action-specifically:
    -- the approved money-carrying actions (payments / discounts / shifts /
    -- order.submitted / completion) keep their allowlisted money keys.
    if (p_action like 'order.items_add%' or p_action like 'order.round_status%'
        -- KITCHEN-MODE-001B: printer configuration is MONEY-FREE by contract —
        -- the same hostile-key hardening applies to the whole printer family.
        or p_action like 'printer.%'
        -- KITCHEN-MODE-001C1: kitchen dispatch events are MONEY-FREE too.
        or p_action like 'kitchen.%')
       and v_key like '%\_minor' escape '\' then
      continue;
    end if;
    if p_values ? v_key
       and jsonb_typeof(p_values -> v_key) in ('string','number','boolean') then
      v_out := v_out || jsonb_build_object(v_key, p_values -> v_key);
    end if;
  end loop;

  -- The ONLY allowlisted nested object: `capabilities`, kept to its four
  -- canonical boolean capability keys (unknown nested keys dropped).
  if jsonb_typeof(p_values -> 'capabilities') = 'object' then
    select coalesce(jsonb_object_agg(k, p_values -> 'capabilities' -> k), '{}'::jsonb)
      into v_caps
      from unnest(array['apply_discount','void_order','close_shift','apply_full_comp','manage_menu_availability','manage_table_operations']) as k
      where (p_values -> 'capabilities') ? k
        and jsonb_typeof(p_values -> 'capabilities' -> k) in ('string','number','boolean');
    if v_caps is distinct from '{}'::jsonb then
      v_out := v_out || jsonb_build_object('capabilities', v_caps);
    end if;
  end if;

  return v_out;
end;
$$;

comment on function app.audit_safe_detail(text, jsonb) is
  'ALLOWLIST projection of one audit payload to canonical safe fields (see 20260724090000 + 20260725090000) + KITCHEN-MODE-001C3A kitchen_workflow_mode / kitchen_workflow_mode_revision / resolution / reason_code (closed safe state scalars for the 001C3B setter + hold resolution). kitchen.% keeps the MONEY-FREE hostile-key hardening. Faithful re-creation otherwise; every un-listed key/structure dropped; malformed -> ''{}''; never throws.';

revoke all on function app.audit_safe_detail(text, jsonb) from public;
revoke all on function app.audit_safe_detail(text, jsonb) from anon;

-- ----------------------------------------------------------------------------
-- app.sync_push — the order.submit case gains ONE direct_print dispatch call.
-- Byte-faithful re-emit of the 20260725090000 body; ONLY the call is added,
-- mirroring the existing post-submit customer_name stamp seam.
-- ----------------------------------------------------------------------------
create or replace function app.sync_push(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_operations     jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
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
  v_op           jsonb;
  v_local_op     text;
  v_op_type      text;
  v_payload      jsonb;
  v_depends      jsonb;
  v_target_ent   text;
  v_target_id    uuid;
  v_client_ts    timestamptz;
  v_fingerprint  text;
  v_dep          text;
  v_dep_ok       boolean;
  v_ex_status    text;
  v_ex_result    jsonb;
  v_ex_optype    text;
  v_ex_fp        text;
  -- PSC-001C correction (Finding 1): the existing row's id when the atomic
  -- ledger claim loses, and whether this request ADOPTED a stale non-terminal
  -- row (the only case that bumps retry_count — the pre-fix contract).
  v_ex_id        uuid;
  v_adopted      boolean;
  v_so_id        uuid;
  v_dispatch     jsonb;
  v_dispatch_ok  boolean;
  v_caught_state text;
  v_caught_msg   text;
  v_results      jsonb := '[]'::jsonb;
  v_op_result    jsonb;
  v_device_revoked boolean := false;
  v_customer_name text;
  v_ack_order    uuid;
  v_ack_ok       boolean;
begin
  -- (0) batch shape + a conservative size cap (no frozen limit in docs; 100 is the
  --     interim cap, surfaced here and in the tests — keeps a push transaction bounded).
  if p_operations is null or jsonb_typeof(p_operations) <> 'array' then
    raise exception 'sync_push: p_operations must be a JSON array' using errcode = '42501';
  end if;
  if jsonb_array_length(p_operations) > 100 then
    raise exception 'sync_push: batch too large (max 100 operations, got %)', jsonb_array_length(p_operations) using errcode = '42501';
  end if;

  -- (a) PIN session + backing device session/pairing. Scope is derived here. The PIN
  --     session must exist + be valid (offline-window bounded, Q-009); a missing session
  --     or expired PIN still raises (cannot key/record safely without a session/window).
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'sync_push: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'sync_push: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found then
    raise exception 'sync_push: backing device session not found' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'sync_push: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  -- RF061-A1: a REVOKED / inactive device session or pairing no longer fails the whole
  -- batch with a silent raise. Instead each pushed op is RECORDED as rejected
  -- (revoked_device) and surfaced, so the offline-queued operations are not lost (R-007;
  -- AC1). Authorization is INGEST-TIME (the device is revoked NOW); client timestamps are
  -- never trusted. A previously-APPLIED op still replays its stored result (idempotency).
  if not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    v_device_revoked := true;
    for v_op in select * from jsonb_array_elements(p_operations)
    loop
      v_local_op   := v_op ->> 'local_operation_id';
      v_op_type    := v_op ->> 'operation_type';
      v_payload    := v_op -> 'payload';
      v_depends    := coalesce(v_op -> 'depends_on', '[]'::jsonb);
      v_target_ent := v_op ->> 'target_entity';
      -- PSC-001D correction (F3) + PSC-001C: for the three IDENTITY-HARDENED
      -- operations (order.void_ack, order.items_add, order.round_status) the
      -- target id is parsed inside a PROTECTED boundary — a malformed uuid
      -- must reject only ITS operation, never abort the whole batch. The 12
      -- prior operations keep their exact existing parse semantics.
      if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
        begin
          v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
        exception when others then
          v_target_id := null;
        end;
      else
        v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
      end if;
      v_client_ts  := nullif(v_op ->> 'client_created_at', '')::timestamptz;

      -- envelope validation (same as the valid path): malformed -> rejected result, NO ledger row
      if v_local_op is null or btrim(v_local_op) = '' then
        v_results := v_results || jsonb_build_object('ok', false, 'error', 'invalid_envelope',
          'detail', 'local_operation_id is required', 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
      if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink', 'order.void_ack', 'order.items_add', 'order.round_status') then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'ok', false,
          'error', 'unknown_operation_type', 'detail', coalesce(v_op_type, '<null>'), 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
      if v_payload is null or jsonb_typeof(v_payload) <> 'object' then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
          'ok', false, 'error', 'invalid_payload', 'detail', 'payload must be a JSON object', 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;

      -- PSC-001D correction (final pass) + PSC-001C: the SAME canonical
      -- identity contract as the valid path for ALL THREE hardened operations,
      -- enforced BEFORE the fingerprint, the terminal-replay lookup, the
      -- idempotency-conflict comparison and the ledger write. A revoked device
      -- must not gain permission to submit ambiguous or contradictory
      -- operation identity: a missing, malformed or CONTRADICTORY
      -- target/payload-identity pair (payload.order_id for order.void_ack and
      -- order.items_add; payload.round_id for order.round_status) is a hostile
      -- or malformed envelope — rejected with NO ledger row (the malformed-
      -- envelope convention), the batch continues. Only that op is affected.
      if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
        v_ack_ok := v_target_id is not null;
        begin
          v_ack_order := nullif(v_payload ->> (case when v_op_type = 'order.round_status' then 'round_id' else 'order_id' end), '')::uuid;
        exception when others then
          v_ack_order := null;
        end;
        if v_ack_order is null or not v_ack_ok or v_target_id <> v_ack_order then
          v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
            'ok', false, 'error', 'invalid_payload',
            'detail', v_op_type || ' requires matching uuid target_id and payload.'
                      || (case when v_op_type = 'order.round_status' then 'round_id' else 'order_id' end),
            'status', 'rejected', 'idempotency_replay', false);
          continue;
        end if;
      end if;

      -- PSC-001D correction (F2 + final pass) + PSC-001C: the SAME target-
      -- bound fingerprint SHAPE as the valid path for all three hardened
      -- operations — the target component is the PARSED uuid's text
      -- (guaranteed non-null and equal to the parsed payload identity by the
      -- check above), so a legitimately-applied op still replays its stored
      -- result after a revocation (identical identity -> identical
      -- fingerprint), while the 12 prior operations are unchanged.
      if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
        v_fingerprint := md5(v_op_type || '|' || v_payload::text || '|' || v_target_id::text);
      else
        v_fingerprint := md5(v_op_type || '|' || v_payload::text);
      end if;

      -- dedup/replay (PSC-001C correction, Finding 1 — ATOMIC CLAIM): the
      -- rejected/revoked_device recording is now claimed with ONE
      -- INSERT .. ON CONFLICT DO NOTHING on the transport identity. When the
      -- claim loses, the existing row is LOCKED (waiting out any concurrent
      -- claimant's COMMIT) and decided from its COMMITTED state: a TERMINAL
      -- row replays its stored result (a legitimately-APPLIED op before
      -- revocation is NOT re-rejected — and can no longer be OVERWRITTEN by
      -- this path racing a valid-device apply); a different identity is a
      -- conflict; only a genuinely stale NON-terminal row is re-recorded as
      -- rejected (the pre-fix retry contract, bump included).
      v_so_id := null;
      insert into public.sync_operations as so (
        organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type,
        target_entity, target_id, payload, payload_fingerprint, depends_on, status,
        last_error_code, last_error_class, rejection_reason,
        result, client_created_at)
      values (v_org, v_rest, v_branch, p_device_id, v_local_op, v_op_type,
              v_target_ent, v_target_id, v_payload, v_fingerprint, v_depends, 'rejected',
              'revoked_device', 'permanent', 'revoked_device',
              jsonb_build_object('ok', false, 'error', 'rejected', 'detail', 'revoked_device'), v_client_ts)
      on conflict (organization_id, device_id, local_operation_id) do nothing
      returning so.id into v_so_id;
      if v_so_id is null then
        select so.id, so.status, so.result, so.operation_type, so.payload_fingerprint
          into v_ex_id, v_ex_status, v_ex_result, v_ex_optype, v_ex_fp
          from public.sync_operations so
          where so.organization_id = v_org and so.device_id = p_device_id and so.local_operation_id = v_local_op
          for update;
        if v_ex_optype <> v_op_type or v_ex_fp <> v_fingerprint then
          insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
          values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_conflict', null, null,
                  jsonb_build_object('local_operation_id', v_local_op, 'stored_operation_type', v_ex_optype, 'pushed_operation_type', v_op_type,
                                     'stored_status', v_ex_status, 'reason', 'idempotency_key_reused_with_different_operation_or_payload'));
          v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
            'error', 'conflict', 'detail', 'idempotency key already used for a different operation/payload', 'status', 'conflict', 'idempotency_replay', false);
          continue;
        end if;
        if v_ex_status in ('applied', 'rejected', 'dead', 'conflict') then
          v_results := v_results || (coalesce(v_ex_result, '{}'::jsonb)
            || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', v_ex_status, 'idempotency_replay', true));
          continue;
        end if;
        -- a stale NON-terminal row: re-record it as rejected (revoked_device)
        -- under the held lock — the pre-fix on-conflict contract, verbatim.
        update public.sync_operations as so
          set status = 'rejected', last_error_code = 'revoked_device', last_error_class = 'permanent',
              rejection_reason = 'revoked_device',
              result = jsonb_build_object('ok', false, 'error', 'rejected', 'detail', 'revoked_device'),
              retry_count = so.retry_count + 1, updated_at = now()
          where so.id = v_ex_id;
      end if;
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected', 'revoked_device', null,
              jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'reason', 'revoked_device'));
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
        'error', 'rejected', 'detail', 'revoked_device', 'status', 'rejected', 'idempotency_replay', false);
    end loop;
    return jsonb_build_object('ok', true, 'results', v_results, 'server_ts', now(), 'device_revoked', true);
  end if;

  -- (b) per-operation loop (ordered) — VALID device path (unchanged from RF-056)
  for v_op in select * from jsonb_array_elements(p_operations)
  loop
    v_caught_state := null;
    v_caught_msg   := null;
    v_dispatch     := null;
    v_dispatch_ok  := null;
    v_so_id        := null;

    v_local_op   := v_op ->> 'local_operation_id';
    v_op_type    := v_op ->> 'operation_type';
    v_payload    := v_op -> 'payload';
    v_depends    := coalesce(v_op -> 'depends_on', '[]'::jsonb);
    v_target_ent := v_op ->> 'target_entity';
    -- PSC-001D correction (F3) + PSC-001C: protected parse for the three
    -- identity-hardened operations — a malformed target uuid rejects only ITS
    -- operation (below), never the batch. The 12 prior operations keep their
    -- exact existing semantics.
    if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
      begin
        v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
      exception when others then
        v_target_id := null;
      end;
    else
      v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
    end if;
    v_client_ts  := nullif(v_op ->> 'client_created_at', '')::timestamptz;

    -- (b1) envelope shape validation. Malformed envelopes are returned rejected
    --      WITHOUT a ledger row (they cannot be keyed/stored safely); they never dispatch.
    if v_local_op is null or btrim(v_local_op) = '' then
      v_results := v_results || jsonb_build_object('ok', false, 'error', 'invalid_envelope',
        'detail', 'local_operation_id is required', 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;
    if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink', 'order.void_ack', 'order.items_add', 'order.round_status') then
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'ok', false,
        'error', 'unknown_operation_type', 'detail', coalesce(v_op_type, '<null>'), 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;
    if v_payload is null or jsonb_typeof(v_payload) <> 'object' then
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
        'ok', false, 'error', 'invalid_payload', 'detail', 'payload must be a JSON object', 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;
    if jsonb_typeof(v_depends) <> 'array' then
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
        'ok', false, 'error', 'invalid_depends_on', 'detail', 'depends_on must be a JSON array', 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;

    -- (b1+) PSC-001D correction (F2/F3) + PSC-001C: CANONICAL TARGET IDENTITY
    -- for the three hardened operations, enforced BEFORE the fingerprint, the
    -- terminal-replay lookup and the dispatch. The envelope MUST carry a
    -- parseable target_id AND a parseable payload identity (payload.order_id
    -- for order.void_ack and order.items_add; payload.round_id for
    -- order.round_status) and they MUST be the same uuid — a missing,
    -- malformed or CONTRADICTORY pair is a hostile/malformed envelope:
    -- rejected with NO ledger row (the malformed-envelope convention), so a
    -- replayed local_operation_id with a swapped target can never reach the
    -- stored terminal result, mutate anything, or learn anything about
    -- another order or round. Only that operation is affected.
    if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
      v_ack_ok := v_target_id is not null;
      begin
        v_ack_order := nullif(v_payload ->> (case when v_op_type = 'order.round_status' then 'round_id' else 'order_id' end), '')::uuid;
      exception when others then
        v_ack_order := null;
      end;
      if v_ack_order is null or not v_ack_ok or v_target_id <> v_ack_order then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
          'ok', false, 'error', 'invalid_payload',
          'detail', v_op_type || ' requires matching uuid target_id and payload.'
                    || (case when v_op_type = 'order.round_status' then 'round_id' else 'order_id' end),
          'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
    end if;

    -- PSC-001D correction (F2) + PSC-001C: the fingerprint of every hardened
    -- operation BINDS the canonical target identity, so a terminal replay is
    -- valid only for the same local_operation_id + operation + payload +
    -- TARGET. The 12 prior operations keep their exact existing fingerprint
    -- semantics.
    if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
      v_fingerprint := md5(v_op_type || '|' || v_payload::text || '|' || v_target_id::text);
    else
      v_fingerprint := md5(v_op_type || '|' || v_payload::text);
    end if;

    -- (b2) ATOMIC LEDGER CLAIM (PSC-001C correction, Finding 1). The pre-fix
    -- shape read the ledger and only LATER upserted it, so two concurrent
    -- requests with the SAME (org, device, local_operation_id) + fingerprint
    -- could both pass the read; the loser's upsert then dragged the winner's
    -- COMMITTED terminal row back to in_flight, re-dispatched (now an
    -- invalid_transition), and finalized the previously-successful row as
    -- rejected. The claim is now ONE INSERT .. ON CONFLICT DO NOTHING on the
    -- transport identity, computed AFTER envelope validation + identity
    -- canonicalization + the fingerprint:
    --   * claim WON  -> this transaction owns dispatch (fresh row, in_flight,
    --     retry_count 0) and finalizes it exactly once at (b6);
    --   * claim LOST -> the existing row is LOCKED (FOR UPDATE — waiting out a
    --     concurrent claimant's COMMIT) and decided from COMMITTED state: a
    --     fingerprint/op mismatch keeps the exact idempotency-conflict
    --     contract; a TERMINAL row replays its stored result (and can never be
    --     overwritten or reset to in_flight again); only a genuinely stale
    --     NON-terminal row (pending / crashed in_flight) is ADOPTED — the
    --     pre-fix retry contract, bump included. A losing concurrent caller
    --     therefore converges on the winner's stored terminal result.
    v_adopted := false;
    v_so_id   := null;
    insert into public.sync_operations as so (
      organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type,
      target_entity, target_id, payload, payload_fingerprint, depends_on, status, client_created_at)
    values (v_org, v_rest, v_branch, p_device_id, v_local_op, v_op_type,
            v_target_ent, v_target_id, v_payload, v_fingerprint, v_depends, 'in_flight', v_client_ts)
    on conflict (organization_id, device_id, local_operation_id) do nothing
    returning so.id into v_so_id;

    if v_so_id is null then
      select so.id, so.status, so.result, so.operation_type, so.payload_fingerprint
        into v_ex_id, v_ex_status, v_ex_result, v_ex_optype, v_ex_fp
        from public.sync_operations so
        where so.organization_id = v_org and so.device_id = p_device_id and so.local_operation_id = v_local_op
        for update;
      if v_ex_optype <> v_op_type or v_ex_fp <> v_fingerprint then
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_conflict', null, null,
                jsonb_build_object('local_operation_id', v_local_op, 'stored_operation_type', v_ex_optype, 'pushed_operation_type', v_op_type,
                                   'stored_status', v_ex_status, 'reason', 'idempotency_key_reused_with_different_operation_or_payload'));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'conflict', 'detail', 'idempotency key already used for a different operation/payload', 'status', 'conflict', 'idempotency_replay', false);
        continue;
      end if;
      if v_ex_status in ('applied', 'rejected', 'dead', 'conflict') then
        v_results := v_results || (coalesce(v_ex_result, '{}'::jsonb)
          || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', v_ex_status, 'idempotency_replay', true));
        continue;
      end if;
      v_so_id   := v_ex_id;
      v_adopted := true;
    end if;

    -- (b3) dependency guard (still BEFORE any dispatch; the claimed/adopted
    -- row is parked as pending exactly like the pre-fix contract — a fresh
    -- claim keeps retry_count 0, an adopted re-attempt bumps it).
    v_dep_ok := true;
    for v_dep in select jsonb_array_elements_text(v_depends)
    loop
      if not exists (
        select 1 from public.sync_operations so
        where so.organization_id = v_org and so.device_id = p_device_id
          and so.local_operation_id = v_dep and so.status = 'applied'
      ) then
        v_dep_ok := false;
        exit;
      end if;
    end loop;

    if not v_dep_ok then
      update public.sync_operations as so
        set status = 'pending', last_error_code = 'dependency_not_ready', last_error_class = 'transient',
            retry_count = so.retry_count + (case when v_adopted then 1 else 0 end),
            updated_at = now()
        where so.id = v_so_id;
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
        'error', 'dependency_not_ready', 'retryable', true, 'status', 'pending', 'idempotency_replay', false);
      continue;
    end if;

    -- (b4) an ADOPTED stale re-attempt returns to in_flight with the retry
    -- bump (the pre-fix on-conflict contract); a fresh claim is already
    -- in_flight and is never re-written here.
    if v_adopted then
      update public.sync_operations as so
        set status = 'in_flight', retry_count = so.retry_count + 1, updated_at = now()
        where so.id = v_so_id;
    end if;

    -- (b5) dispatch to the matching business RPC inside a per-op EXCEPTION subtransaction.
    begin
      case v_op_type
        when 'shift.open' then
          v_dispatch := app.open_shift(
            p_pin_session_id,
            (v_payload ->> 'shift_id')::uuid,
            (v_payload ->> 'cash_drawer_session_id')::uuid,
            p_device_id,
            v_local_op,
            (v_payload ->> 'opening_float_minor')::bigint);
        when 'order.submit' then
          v_dispatch := app.submit_order(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'order_type',
            nullif(v_payload ->> 'table_id', '')::uuid,
            nullif(v_payload ->> 'shift_id', '')::uuid,
            v_payload ->> 'currency_code',
            v_payload ->> 'notes',
            v_payload -> 'order_items',
            (v_payload ->> 'subtotal_minor')::bigint,
            (v_payload ->> 'discount_total_minor')::bigint,
            (v_payload ->> 'tax_total_minor')::bigint,
            (v_payload ->> 'grand_total_minor')::bigint,
            v_client_ts);
          -- ORDER-CUSTOMER-001: stamp the OPTIONAL customer display name on the
          -- order app.submit_order just created. Kept OUT of submit_order so its
          -- validated INSERT stays byte-unchanged. Money-free display text: trim
          -- + empty->null + 80-char cap. Tenant-scoped by v_org; the
          -- `customer_name is null` guard makes it idempotent (a replay returns
          -- the same order_id, already stamped) and never overwrites.
          v_customer_name := left(btrim(coalesce(v_payload ->> 'customer_name', '')), 80);
          if v_customer_name <> '' then
            update public.orders
              set customer_name = v_customer_name
              where id = (v_dispatch ->> 'order_id')::uuid
                and organization_id = v_org
                and customer_name is null;
          end if;
          -- KITCHEN-MODE-001C1-CORRECTION-001: the initial kitchen dispatch
          -- payload is built inside app.submit_order BEFORE this stamp, so on
          -- the REAL push path customer_display_name was missing. Rebuild the
          -- COMPLETE normalized payload through the trusted internal server
          -- builder IN THIS SAME TRANSACTION — never by patching client JSON
          -- in, never after a client could have seen it (claimed / completed
          -- / superseded rows are left untouched; inside this first-apply
          -- transaction the row is not yet visible to any puller), never
          -- duplicating the dispatch or its audit row (no INSERT, no audit
          -- here). The row only exists for printer_only branches, so kds
          -- branches are a structural no-op; the guard trigger re-proves the
          -- rebuilt payload money-free on UPDATE.
          if v_customer_name <> '' then
            update public.kitchen_print_dispatches kd
              set money_free_payload = app.kitchen_dispatch_payload_initial(v_org, (v_dispatch ->> 'order_id')::uuid),
                  updated_at = now()
              where kd.organization_id = v_org
                and kd.order_id = (v_dispatch ->> 'order_id')::uuid
                and kd.dispatch_type = 'initial_order'
                and kd.claimed_at is null
                and kd.completed_at is null
                and kd.superseded_by_dispatch_id is null;
          end if;
          -- KITCHEN-PRINT-DUAL-001C: a direct_print order is dispatched to the
          -- kitchen via the POS printer (no KDS device). Route it OUT of the KDS
          -- active workflow IN THIS SAME transaction — a concurrent sync_pull can
          -- never observe an intermediate active state (sync_push commits once).
          -- Promotes the fresh submitted order to `served` + stamps dispatch_mode;
          -- the UNCHANGED served+paid rule still owns completion (settlement is
          -- NEVER bypassed). A 'kds' (default) order is a structural no-op here.
          if coalesce(v_payload ->> 'dispatch_mode', 'kds') = 'direct_print' then
            -- Merge the ADDITIVE outcome (order_status/revision/auto_completed)
            -- into the envelope so the client sees the FINAL committed state,
            -- exactly like the zero-total submit tail. A no-op replay merges only
            -- {dispatched:false} (submit_order's replay already re-reads the
            -- current revision), so the envelope stays correct.
            v_dispatch := v_dispatch || app.apply_direct_print_dispatch(
              v_org, v_rest, v_branch, (v_dispatch ->> 'order_id')::uuid,
              v_emp, v_membership, p_device_id, v_local_op);
          end if;
        when 'order.discount' then
          v_dispatch := app.apply_discount(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'scope',
            nullif(v_payload ->> 'order_item_id', '')::uuid,
            v_payload ->> 'discount_type',
            (v_payload ->> 'value')::bigint,
            v_payload ->> 'reason',
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'payment.create' then
          v_dispatch := app.record_payment(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'tender_type',
            (v_payload ->> 'amount_tendered_minor')::bigint,
            nullif(v_payload ->> 'provisional_receipt_number', ''),
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'shift.close' then
          v_dispatch := app.close_shift(
            p_pin_session_id,
            (v_payload ->> 'shift_id')::uuid,
            p_device_id,
            v_local_op,
            (v_payload ->> 'counted_amount_minor')::bigint,
            nullif(v_payload ->> 'reason', ''),
            nullif(v_payload ->> 'expected_revision', '')::integer);
        -- MVP addition: KDS/POS order-status updates ride the SAME outbox/ledger
        -- (D-010/D-022). Scope/actor come from the pin session + device passed
        -- through (A8); the payload contributes ONLY {order_id, new_status}.
        when 'order.status' then
          v_dispatch := app.update_order_status(
            p_pin_session_id,
            p_device_id,
            (v_payload ->> 'order_id')::uuid,
            v_payload ->> 'new_status',
            v_local_op);
        when 'order.void' then
          -- MONEY-VOID-001: role-gated void of a wrong UNPAID order. Mirrors the
          -- order.discount branch - actor/org/branch come from the PIN session
          -- (never the payload) and the op's local_operation_id threads
          -- app.void_order's own idempotency (D-022). app.void_order (RF-053,
          -- hardened by RF-062) enforces manager/restaurant_owner/org_owner (or a
          -- cashier with permissions.void_order='true'), a mandatory reason, legal
          -- source states (submitted/accepted/preparing/ready/served), and the
          -- completed-payment block (an order with a live completed payment
          -- returns permission_denied) - so paid orders are refused server-side.
          -- Money-free: it only sets orders.status='voided' + void_reason +
          -- revision and cascades items -> voided; no payment/total is touched.
          v_dispatch := app.void_order(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'reason',
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'order.table_move' then
          -- RESTAURANT-OPERATIONS-V1-001: atomic dine-in table move. Mirrors the
          -- order.void branch — actor/org/branch come from the PIN session
          -- (never the payload); the op's local_operation_id threads
          -- app.move_order_table's ORDER-BOUND idempotency (D-022); the payload
          -- contributes ONLY {order_id, table_id[, expected_revision]}. Typed
          -- refusals (table_not_allowed / invalid_transition+order_not_movable /
          -- table_not_available / permission_denied) RETURN through verbatim;
          -- a revision conflict raises 40001 -> the per-op 'conflict' status.
          -- Money-free: only orders.table_id + revision move.
          v_dispatch := app.move_order_table(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            nullif(v_payload ->> 'table_id', '')::uuid,
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'menu.availability_set' then
          -- PILOT-OPERATIONS-CORRECTIONS-001: a cashier (default-ON
          -- manage_menu_availability) or manager+ sets a menu item's per-branch
          -- availability from the POS. Actor/org/branch derive from the PIN
          -- session (NEVER the payload); the capability is enforced inside. The
          -- payload contributes ONLY {menu_item_id, availability, reason}. The
          -- setter is naturally idempotent (no-change re-applies the same state
          -- with no audit) and transport dedup (sync_operations) guards replay.
          -- Typed RETURN refusals (permission_denied / not_found) survive
          -- verbatim. MONEY-FREE.
          v_dispatch := app.pos_set_item_availability(
            p_pin_session_id,
            p_device_id,
            (v_payload ->> 'menu_item_id')::uuid,
            v_payload ->> 'availability',
            nullif(v_payload ->> 'reason', ''));
        when 'table.status_set' then
          -- PILOT-OPERATIONS-CORRECTIONS-001: manual table floor-state from the
          -- POS (manage_table_operations). Scope/actor from the session; payload
          -- {table_id, status}. Typed refusals survive verbatim. MONEY-FREE.
          v_dispatch := app.pos_set_table_status(
            p_pin_session_id, p_device_id,
            (v_payload ->> 'table_id')::uuid,
            v_payload ->> 'status');
        when 'table.link' then
          -- Link two same-branch tables into an operational group (no order/bill
          -- merge). Payload {table_id_a, table_id_b}. Deterministic lock order.
          v_dispatch := app.pos_link_tables(
            p_pin_session_id, p_device_id,
            (v_payload ->> 'table_id_a')::uuid,
            (v_payload ->> 'table_id_b')::uuid);
        when 'table.unlink' then
          -- Dissolve the group a table belongs to (orders untouched). Payload
          -- {table_id}.
          v_dispatch := app.pos_unlink_tables(
            p_pin_session_id, p_device_id,
            (v_payload ->> 'table_id')::uuid);
        when 'order.void_ack' then
          -- PSC-001D: the kitchen's cancellation acknowledgement. Mirrors the
          -- order.status branch — actor/org/branch come from the PIN session
          -- (never the payload); the payload contributes ONLY {order_id}.
          -- app.kitchen_ack_void enforces the KDS-class device, the kitchen
          -- role set, the voided + ack-required state, and the idempotent
          -- already-acknowledged replay; its flat typed refusals
          -- (invalid_device_type / permission_denied / order_not_voided /
          -- acknowledgement_not_required) RETURN through verbatim. TARGET-ID
          -- CONSISTENCY is enforced at (b1+) BEFORE the fingerprint and the
          -- terminal replay — by the time this arm runs, target_id and
          -- payload.order_id are guaranteed present, valid and equal. The
          -- check below is pure defence-in-depth and unreachable. MONEY-FREE.
          if v_target_id is null
             or v_target_id <> (v_payload ->> 'order_id')::uuid then
            raise exception 'sync_push: order.void_ack target_id does not match payload.order_id' using errcode = '42501';
          end if;
          v_dispatch := app.kitchen_ack_void(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op);
        when 'order.items_add' then
          -- PSC-001C: add items to an existing eligible dine-in order as ONE
          -- new authoritative service round. Actor/org/branch come from the
          -- PIN session; the payload contributes {order_id, order_items}.
          -- app.add_order_items enforces the POS-class device, the cashier+
          -- role set, eligibility (dine_in, open status, no completed
          -- payment), submit_order-parity pricing/sellability, and round-level
          -- idempotency; its flat typed refusals (invalid_device_type /
          -- permission_denied / order_not_dine_in / order_not_eligible /
          -- order_already_settled / item_unavailable / invalid_item_payload)
          -- RETURN through verbatim. TARGET-ID CONSISTENCY is enforced at
          -- (b1+) BEFORE the fingerprint and the terminal replay — the check
          -- below is pure defence-in-depth and unreachable.
          if v_target_id is null
             or v_target_id <> (v_payload ->> 'order_id')::uuid then
            raise exception 'sync_push: order.items_add target_id does not match payload.order_id' using errcode = '42501';
          end if;
          v_dispatch := app.add_order_items(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload -> 'order_items',
            v_client_ts);
        when 'order.round_status' then
          -- PSC-001C: the additional service round's own single-step
          -- lifecycle. Actor/org/branch come from the PIN session; the
          -- payload contributes {round_id, new_status}. app.update_round_status
          -- enforces the LOCKED device/role matrix (production steps KDS-only;
          -- ready->served KDS kitchen set or POS cashier set), the parent
          -- guards, single-step legality, the WRITE-ONCE ready_at stamp and
          -- the completion chain; its flat typed refusals RETURN through
          -- verbatim. TARGET-ID CONSISTENCY (against payload.round_id) is
          -- enforced at (b1+) — the check below is pure defence-in-depth and
          -- unreachable. MONEY-FREE.
          if v_target_id is null
             or v_target_id <> (v_payload ->> 'round_id')::uuid then
            raise exception 'sync_push: order.round_status target_id does not match payload.round_id' using errcode = '42501';
          end if;
          v_dispatch := app.update_round_status(
            p_pin_session_id,
            (v_payload ->> 'round_id')::uuid,
            p_device_id,
            v_payload ->> 'new_status',
            v_local_op);
      end case;
      v_dispatch_ok := coalesce((v_dispatch ->> 'ok')::boolean, false);
    exception
      when others then
        v_caught_state := SQLSTATE;
        v_caught_msg   := SQLERRM;
    end;

    -- (b6) finalize the operation outcome
    if v_caught_state is not null then
      if v_caught_state = '40001' then
        update public.sync_operations
          set status = 'conflict', last_error_code = v_caught_state, last_error_class = 'conflict',
              conflict_info = jsonb_build_object('sqlstate', v_caught_state, 'message', v_caught_msg),
              result = jsonb_build_object('ok', false, 'error', 'conflict', 'sqlstate', v_caught_state), updated_at = now()
          where id = v_so_id;
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_conflict', v_caught_msg, null,
                jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'sqlstate', v_caught_state));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'conflict', 'sqlstate', v_caught_state, 'status', 'conflict', 'idempotency_replay', false);
      else
        -- validation / state / business-rule failure -> permanent rejected. RF-061: a
        -- revoked-MEMBERSHIP op fails membership-active in the dispatched RPC; classify its
        -- rejection reason as 'revoked_employee' so the offline-revoked-employee case is clear.
        update public.sync_operations
          set status = 'rejected', last_error_code = v_caught_state, last_error_class = 'permanent',
              rejection_reason = case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee' else v_caught_msg end,
              result = jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', v_caught_state,
                         'detail', case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee' else null end), updated_at = now()
          where id = v_so_id;
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected',
                case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee' else v_caught_msg end, null,
                jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'sqlstate', v_caught_state));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'rejected', 'sqlstate', v_caught_state,
          'detail', case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee' else null end,
          'status', 'rejected', 'idempotency_replay', false);
      end if;
    elsif v_dispatch_ok then
      update public.sync_operations
        set status = 'applied', result = v_dispatch, applied_at = now(),
            target_id = coalesce(v_target_id, nullif(v_dispatch ->> 'order_id', '')::uuid, nullif(v_dispatch ->> 'shift_id', '')::uuid, nullif(v_dispatch ->> 'payment_id', '')::uuid),
            updated_at = now()
        where id = v_so_id;
      v_results := v_results || (v_dispatch
        || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', 'applied', 'idempotency_replay', false));
    else
      update public.sync_operations
        set status = 'rejected', last_error_code = coalesce(v_dispatch ->> 'error', 'rejected'), last_error_class = 'permanent',
            rejection_reason = coalesce(v_dispatch ->> 'error', 'rejected'), result = v_dispatch, updated_at = now()
        where id = v_so_id;
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected', coalesce(v_dispatch ->> 'error', 'rejected'), null,
              jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'error', coalesce(v_dispatch ->> 'error', 'rejected')));
      v_results := v_results || (v_dispatch
        || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', 'rejected', 'idempotency_replay', false));
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'results', v_results, 'server_ts', now());
end;
$$;

comment on function app.sync_push(uuid, uuid, jsonb) is
  'RF-056/RF-061 + ... + PSC-001D + PSC-001C (D-010/D-022) SECURITY DEFINER batch push — faithful re-creation of the 20260722090000 body; all 15 canonical operations, identity hardening, atomic ledger claim, batch cap, result ordering, dependency guard, per-op subtransactions, finalization and the customer_name stamp are verbatim. KITCHEN-MODE-001C1-CORRECTION-001 (order.submit only): immediately after the customer_name stamp, the order''s still-unclaimed initial kitchen dispatch payload is REBUILT through app.kitchen_dispatch_payload_initial in the SAME transaction, so the REAL push path carries customer_display_name exactly like the direct-call path; kds branches are a structural no-op and claimed/completed/superseded dispatches are never touched. Authorization INGEST-TIME; scope from the session, never the payload.';

-- ACL parity (CREATE OR REPLACE preserves grants; re-issued explicitly).
revoke all on function app.sync_push(uuid, uuid, jsonb) from public;
revoke all on function app.sync_push(uuid, uuid, jsonb) from anon;
grant execute on function app.sync_push(uuid, uuid, jsonb) to authenticated;


-- ============================================================================
-- KITCHEN-PRINT-DUAL-001C (KDS-SYNC-FILTER): exclude the direct_print order graph
-- from the KDS sync feed at the SERVER. Faithful re-creation of the current
-- authoritative app.sync_pull body (20260723090000 lines 865-1118) with the
-- KDS-only direct_print graph filter injected (device_type='kds', post-pager so
-- the cursor advances over examined rows). Extends THIS unshipped migration; no
-- migration already applied to hosted is modified. app.sync_pull_changes and the
-- public.sync_pull wrapper are UNCHANGED.
-- ============================================================================
create or replace function app.sync_pull(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_entities       text[]  default null,
  p_cursors        jsonb   default '{}'::jsonb,
  p_limit          integer default 500
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
  v_limit       integer;
  v_allowed     text[];
  v_requested   text[];
  v_include_ops boolean;
  v_entity      text;
  v_cur         jsonb;
  v_c_uat       timestamptz;
  v_c_id        uuid;
  v_changes     jsonb := '{}'::jsonb;
  v_op_rows     jsonb;
  v_op_count    integer;
  v_op_last     jsonb;
  v_op_statuses jsonb;
  v_kitchen_mode text;      -- KITCHEN-MODE-001A: branch workflow mode (kitchen gate)
  v_ops_suppressed boolean := false;  -- KITCHEN-MODE-001A (HIGH-1): op-status feed off for printer-only kitchen
  v_device_type text;                 -- KITCHEN-PRINT-DUAL-001C: kind of the session-backing device
  v_is_kds boolean := false;          -- KITCHEN-PRINT-DUAL-001C: caller is a KDS device (device_type='kds')
  c_financial   constant text[] := array['payments', 'shifts', 'cash_drawer_sessions'];
  c_business    constant text[] := array['orders', 'order_items', 'order_item_modifiers', 'order_service_rounds', 'payments', 'shifts', 'cash_drawer_sessions'];
  -- RF-109: the six menu reference entities. Price-capable roles only (menu rows carry money, T-003).
  c_menu        constant text[] := array['menu_categories', 'menu_items', 'item_sizes', 'item_variants', 'modifiers', 'modifier_options'];
  -- MVP: the money-free floor entity — EVERY device role may pull it (the KDS
  -- maps orders.table_id -> a human table label through this feed).
  c_floor       constant text[] := array['tables'];
begin
  -- (0) limit validation (A7): default 500, reject <=0 or >1000 (validation-error style).
  v_limit := coalesce(p_limit, 500);
  if v_limit <= 0 or v_limit > 1000 then
    raise exception 'sync_pull: p_limit must be between 1 and 1000 (got %)', v_limit using errcode = '42501';
  end if;
  if p_cursors is null or jsonb_typeof(p_cursors) <> 'object' then
    raise exception 'sync_pull: p_cursors must be a JSON object' using errcode = '42501';
  end if;

  -- (a) PIN session + backing device session/pairing active; device match (A8).
  --     Scope (org/restaurant/branch) + actor + role are derived HERE, never from payload.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'sync_pull: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'sync_pull: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'sync_pull: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'sync_pull: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'sync_pull: resolved membership is not active' using errcode = '42501';
  end if;

  -- KITCHEN-PRINT-DUAL-001C: resolve the TRUSTED device kind for the KDS filter.
  -- v_ds_device is the session-backing device (validated == p_device_id above), so
  -- devices.device_type here is server-owned and NOT client-spoofable; this mirrors
  -- the shipped KDS-class gate in app.kitchen_ack_void / app.update_round_status.
  select d.device_type into v_device_type
    from public.devices d
    where d.id = v_ds_device;
  v_is_kds := coalesce(v_device_type, '') = 'kds';

  -- (b) role-permitted entities (A5): kitchen_staff -> non-financial operational
  --     + the money-free `tables` floor entity (NO menu -- menu rows carry money,
  --     T-003). Price-capable roles -> operational business + RF-109 menu + tables.
  if v_role = 'kitchen_staff' then
    -- KITCHEN-MODE-001A: the AUTHORITATIVE kitchen exclusion. In a
    -- `printer_only` branch there is no kitchen board — the kitchen ticket is
    -- paper — so a kitchen_staff session is served NO actionable order
    -- entities (orders / order_items / order_item_modifiers /
    -- order_service_rounds are all withheld). Only the money-free `tables`
    -- floor entity remains, which is exactly enough for a safe, honest EMPTY
    -- board on any KDS that is (accidentally) paired to such a branch. An
    -- EXPLICIT request for an order entity rejects with the existing
    -- not-permitted-for-role 42501 in (c) below — fail closed, never a
    -- silently truncated feed dressed up as a full one. The mode read
    -- fail-closes to 'kds', so a missing branch row can only ever produce the
    -- historical allow-list. No other role's exposure changes.
    select b.kitchen_workflow_mode into v_kitchen_mode
      from public.branches b
      where b.id              = v_branch
        and b.organization_id = v_org
        and b.deleted_at is null;
    if coalesce(v_kitchen_mode, 'kds') = 'printer_only' then
      v_allowed := c_floor;
      -- KITCHEN-MODE-001A (HIGH-1): the paper-only kitchen does not consume
      -- order sync operations — the operation-status feed projects target_id,
      -- result and conflict_info, which carry order identifiers and
      -- money-shaped keys (e.g. change_due_minor) and must remain
      -- money-free and order-identifier-free on this surface. Suppressed
      -- authoritatively below (empty collection), even when explicitly
      -- requested.
      v_ops_suppressed := true;
    else
      -- KDS MODE (default) — BYTE-EQUIVALENT to the PSC-001C allow-list:
      -- order_service_rounds is MONEY-FREE by schema — the kitchen needs it
      -- to render Addition/Round N tickets with the round's own status.
      v_allowed := array['orders', 'order_items', 'order_item_modifiers', 'order_service_rounds'] || c_floor;
    end if;
  elsif v_role in ('cashier', 'manager', 'restaurant_owner', 'org_owner', 'accountant') then
    v_allowed := c_business || c_menu || c_floor;
  else
    v_allowed := array[]::text[];
  end if;

  -- (c) resolve the requested set. null -> all role-permitted + operation_statuses.
  --     Otherwise validate each name: unknown -> reject; not-permitted-for-role -> reject.
  if p_entities is null then
    v_requested   := v_allowed;
    v_include_ops := true;
  else
    v_requested   := array[]::text[];
    v_include_ops := false;
    foreach v_entity in array p_entities loop
      if v_entity = 'operation_statuses' then
        v_include_ops := true;
      elsif v_entity = any(c_business) or v_entity = any(c_menu) or v_entity = any(c_floor) then
        if not (v_entity = any(v_allowed)) then
          raise exception 'sync_pull: entity % is not permitted for role %', v_entity, v_role using errcode = '42501';
        end if;
        if not (v_entity = any(v_requested)) then
          v_requested := array_append(v_requested, v_entity);
        end if;
      else
        raise exception 'sync_pull: unknown entity %', v_entity using errcode = '42501';
      end if;
    end loop;
  end if;

  -- KITCHEN-MODE-001A (HIGH-1): the AUTHORITATIVE operation-status exclusion
  -- for the printer-only kitchen. Forcing v_include_ops off routes section (e)
  -- to its existing empty-collection branch — {rows: [], next_cursor: null,
  -- has_more: false} — a valid envelope carrying NO operation metadata, order
  -- identifier or money-shaped key. Backend-side by design: cosmetic
  -- client-side redaction would leave the wire payload exposed. kitchen_staff
  -- in kds mode and every other role keep the existing feed unchanged.
  if v_ops_suppressed then
    v_include_ops := false;
  end if;

  -- (d) page each requested entity by its per-entity (updated_at, id) cursor.
  foreach v_entity in array v_requested loop
    v_cur   := p_cursors -> v_entity;
    v_c_uat := nullif(v_cur ->> 'updated_at', '')::timestamptz;
    v_c_id  := nullif(v_cur ->> 'id', '')::uuid;
    v_changes := v_changes || jsonb_build_object(
      v_entity, app.sync_pull_changes(v_entity, v_org, v_branch, v_c_uat, v_c_id, v_limit));
  end loop;

  -- (d1) KITCHEN-PRINT-DUAL-001C: a KDS DEVICE never receives the graph of a
  --      direct_print order. Such an order is authoritatively finalized OUT of the
  --      active KDS workflow (the POS printed its ticket in app.sync_push), so its
  --      complete order graph must never enter KDS local state. The entity-generic
  --      pager (app.sync_pull_changes) ships full rows and has no dispatch awareness,
  --      so the exclusion is applied HERE, keyed on the TRUSTED device kind
  --      (v_is_kds), never the membership role (a manager may sit at a KDS;
  --      kitchen_staff may sit at a POS) nor the client p_device_id. It runs AFTER
  --      the pager has already computed each entity's next_cursor + has_more over the
  --      EXAMINED rows, and it DROPS ROWS ONLY (never touches next_cursor/has_more) —
  --      so the KDS cursor still advances PAST filtered direct_print rows (a branch
  --      that runs direct_print as its primary workflow never stalls or re-scans the
  --      backlog) and pagination is preserved verbatim. The graph is the four order
  --      entities a KDS can pull: orders (dispatch_mode inline), order_items +
  --      order_service_rounds (direct order_id), order_item_modifiers (TRANSITIVE via
  --      its parent order_item). Money/menu entities are role-gated out of a KDS, so
  --      these four are the complete KDS-visible graph. Non-KDS callers are untouched.
  if v_is_kds then
    select coalesce(
             jsonb_object_agg(
               ent,
               case
                 when jsonb_typeof(val -> 'rows') <> 'array' then val
                 when ent = 'orders' then
                   jsonb_set(val, '{rows}', coalesce((
                     select jsonb_agg(r)
                       from jsonb_array_elements(val -> 'rows') as r
                      where coalesce(r ->> 'dispatch_mode', 'kds') <> 'direct_print'), '[]'::jsonb))
                 when ent in ('order_items', 'order_service_rounds') then
                   jsonb_set(val, '{rows}', coalesce((
                     select jsonb_agg(r)
                       from jsonb_array_elements(val -> 'rows') as r
                      where not exists (
                        select 1 from public.orders o
                         where o.organization_id = v_org
                           and o.id = (r ->> 'order_id')::uuid
                           and coalesce(o.dispatch_mode, 'kds') = 'direct_print')), '[]'::jsonb))
                 when ent = 'order_item_modifiers' then
                   jsonb_set(val, '{rows}', coalesce((
                     select jsonb_agg(r)
                       from jsonb_array_elements(val -> 'rows') as r
                      where not exists (
                        select 1 from public.order_items oi
                          join public.orders o
                            on o.organization_id = oi.organization_id and o.id = oi.order_id
                         where oi.organization_id = v_org
                           and oi.id = (r ->> 'order_item_id')::uuid
                           and coalesce(o.dispatch_mode, 'kds') = 'direct_print')), '[]'::jsonb))
                 else val
               end),
             '{}'::jsonb)
      into v_changes
      from jsonb_each(v_changes) as ec(ent, val);
  end if;

  -- (d2) KITCHEN MONEY REDACTION (RF-059, A3/T-003): kitchen_staff must receive NO money figure.
  --      Preserved verbatim. (Kitchen never reaches the paging loop for a menu entity -- a menu
  --      request is rejected in (c) -- so this strips money only from the operational rows kitchen
  --      legitimately receives; it remains a defence-in-depth backstop for any *_minor key.
  --      `tables` rows are money-free, so redact_money is a harmless no-op on them.)
  if v_role = 'kitchen_staff' then
    select coalesce(
             jsonb_object_agg(
               ent,
               case when jsonb_typeof(val -> 'rows') = 'array'
                 then jsonb_set(val, '{rows}',
                        coalesce((select jsonb_agg(app.redact_money(r))
                                  from jsonb_array_elements(val -> 'rows') as r), '[]'::jsonb))
                 else val end),
             '{}'::jsonb)
      into v_changes
      from jsonb_each(v_changes) as ec(ent, val);
  end if;

  -- (e) current-device operation-status feed (A4): sync_operations for THIS org + THIS device
  --     only. Projects status/conflict fields; excludes raw payload. Empty when not requested.
  if v_include_ops then
    v_cur   := p_cursors -> 'operation_statuses';
    v_c_uat := nullif(v_cur ->> 'updated_at', '')::timestamptz;
    v_c_id  := nullif(v_cur ->> 'id', '')::uuid;
    with look as (
      select so.id as _id, so.updated_at as _uat,
             jsonb_build_object(
               'id',                 so.id,
               'local_operation_id', so.local_operation_id,
               'operation_type',     so.operation_type,
               'target_entity',      so.target_entity,
               'target_id',          so.target_id,
               'status',             so.status,
               'result',             so.result,
               'last_error_code',    so.last_error_code,
               'last_error_class',   so.last_error_class,
               'conflict_info',      so.conflict_info,
               'rejection_reason',   so.rejection_reason,
               'retry_count',        so.retry_count,
               'updated_at',         so.updated_at,
               'applied_at',         so.applied_at,
               'server_received_at', so.server_received_at) as _row,
             row_number() over (order by so.updated_at asc, so.id asc) as _rn
      from public.sync_operations so
      where so.organization_id = v_org
        and so.device_id = p_device_id
        and (v_c_uat is null or so.updated_at > v_c_uat or (so.updated_at = v_c_uat and so.id > v_c_id))
      order by so.updated_at asc, so.id asc
      limit v_limit + 1
    ),
    page as (
      select _id, _uat, _row from look where _rn <= v_limit
    )
    select coalesce(jsonb_agg(_row order by _uat asc, _id asc), '[]'::jsonb),
           (select count(*) from look)::int,
           (select jsonb_build_object('updated_at', _uat, 'id', _id) from page order by _uat desc, _id desc limit 1)
      into v_op_rows, v_op_count, v_op_last
      from page;
    v_op_statuses := jsonb_build_object(
      'rows', v_op_rows,
      'next_cursor', case when v_op_count > 0 then v_op_last else null end,
      'has_more', (v_op_count > v_limit));
  else
    v_op_statuses := jsonb_build_object('rows', '[]'::jsonb, 'next_cursor', null, 'has_more', false);
  end if;

  return jsonb_build_object(
    'ok', true,
    'server_ts', now(),
    'changes', v_changes,
    'operation_statuses', v_op_statuses);
end;
$$;

comment on function app.sync_pull(uuid, uuid, text[], jsonb, integer) is
  'RF-057 pull RPC, hardened by RF-059 (A3/T-003), extended by RF-109 (menu), the MVP `tables` floor entity, PSC-001C (order_service_rounds) and KITCHEN-MODE-001A. Session/device validation (A8), role-permitted entity set (A5), per-entity (updated_at,id) cursor (A1), tombstones inline (A9), limit default 500/cap 1000, current-device operation_statuses feed (A4), RF057-B1 lookahead, and kitchen money redaction are preserved verbatim. KITCHEN-MODE-001A: a kitchen_staff session in a `printer_only` branch resolves the money-free `tables` floor entity ONLY — no orders/order_items/order_item_modifiers/order_service_rounds — so an (accidentally) paired KDS renders a safe, honest EMPTY board; an explicit order-entity request rejects with the existing not-permitted 42501 (fail closed); the current-device operation_statuses feed is likewise SUPPRESSED to an empty collection for that session (HIGH-1 — target_id/result/conflict_info carry order identifiers and money-shaped keys such as change_due_minor, and the paper-only kitchen consumes no sync operations); the mode read fail-closes to kds; NO other role''s exposure changes; tenant/branch isolation unchanged (R-003). Faithful re-creation of the 20260722090000 body. KITCHEN-PRINT-DUAL-001C: for a caller whose session-backing device is a KDS (devices.device_type = ''kds''), the COMPLETE graph of every direct_print order (orders + order_items + order_item_modifiers + order_service_rounds) is dropped from the changes feed AFTER per-entity next_cursor/has_more are computed, so the KDS never stores that graph while its cursor still advances past it (no stall or re-scan when direct_print is the primary workflow); the filter is keyed on the trusted server-owned device kind, never the role or the client device_id; non-KDS callers (POS history/reports/payments/audit) are unchanged. Read-only; no audit.';

revoke all on function app.sync_pull(uuid, uuid, text[], jsonb, integer) from public;
grant execute on function app.sync_pull(uuid, uuid, text[], jsonb, integer) to authenticated;
