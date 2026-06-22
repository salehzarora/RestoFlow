-- ============================================================================
-- RF-056 — sync_operations (server inbox/ledger) + app.sync_push (idempotent push)
-- ============================================================================
-- The server-side PUSH half of offline sync (DECISION D-010). Builds on RF-014
-- (org/restaurant/branch + app.current_org_id/has_scope/set_updated_at), RF-016/051
-- (devices/device_sessions/pin_sessions + app.is_pin_session_valid), RF-017
-- (append-only audit_events), and the business RPCs it DISPATCHES to: RF-052
-- (submit_order), RF-053 (apply_discount), RF-054 (record_payment), RF-055
-- (open_shift, close_shift). Additive and FORWARD-ONLY: it NEVER edits a prior
-- migration and NEVER reimplements business logic — it only transports + dedups.
--
-- WHAT THIS DOES (API_CONTRACT §4.14 sync_push; DOMAIN_MODEL §10.1 sync_operations;
-- OFFLINE_SYNC_SPEC §3/§5/§8/§10/§16)
--   1. sync_operations — the server inbox / processed-operation ledger. One row per
--      (organization_id, device_id, local_operation_id) (D-022). Records each pushed
--      operation's status, result envelope (for replay), dependency edges, and
--      error/conflict classification. Tenant+branch scoped; RLS enabled+forced;
--      written ONLY by app.sync_push (D-011).
--   2. app.sync_push(p_pin_session_id, p_device_id, p_operations jsonb) — ingests an
--      ORDERED batch of outbox envelopes; validates the PIN session + active device;
--      per operation: dedups/replays via the ledger, checks dependency edges
--      (transient dependency_not_ready), DISPATCHES to the matching business RPC
--      inside a per-operation EXCEPTION subtransaction (so one failure never rolls
--      back already-applied ops), records the outcome, and returns a PER-OPERATION
--      result array. Money/sequences/receipt numbers stay server-authoritative
--      (D-007/D-021) inside the dispatched RPCs.
--
-- DECISIONS
--   * D-010 offline-first outbox/inbox. D-022 idempotency key = device_id +
--     local_operation_id (org-scoped here; content-hash is NOT the identity — A4).
--   * D-018 sync status enumeration (matches RF-018 local SyncOperationState).
--   * D-011 sensitive mutations only via SECURITY DEFINER RPC; no client direct writes.
--   * D-012 four layers; composite same-org FKs (layer 4). D-013 append-only audit.
--   * D-007 integer minor money (the dispatched RPCs enforce it; no float column here).
--
-- APPROVED INTERIM DECISIONS (RF-056; human-approved A1..A8)
--   * A1: DB/server core only — NO packages/sync drainer, NO packages/data_remote
--     client, NO Dart in this ticket. The client retry/backoff engine is a follow-up.
--   * A2: server-side dispatcher inside app.sync_push; dispatch to existing RPCs only.
--   * A3: operation_type set = {shift.open, order.submit, order.discount,
--     payment.create, shift.close}. NO void/reconcile/route/kitchen/pull/realtime.
--   * A4: identity = (organization_id, device_id, local_operation_id); a secondary
--     payload_fingerprint detects same-key/different-payload conflicts (NOT primary).
--   * A5: server classifies applied/rejected/conflict/pending(dependency_not_ready);
--     full client retry/backoff + the poison->dead scheduler are a follow-up.
--   * A6: sync-level audit for rejected/conflict (sync.operation_rejected /
--     sync.operation_conflict); success audits stay owned by the dispatched RPCs.
--   * A7: per-operation EXCEPTION subtransactions; a failed op never rolls back
--     already-applied ops; rejected/conflict results stored in the ledger.
--   * A8: sync_push takes (p_pin_session_id, p_device_id, p_operations); validates the
--     session + active device; derives org/restaurant/branch server-side; passes the
--     SAME PIN session + device to the dispatched RPCs; never trusts org/branch/role
--     from the payload.
--
-- OUT OF SCOPE: RF-057 pull sync / conflict RESOLUTION / revision tracking /
--   tombstone propagation; realtime; reports; printing; UI; void_order/void_item/
--   void_payment/reconcile_shift/route_to_kitchen dispatch; kitchen tables; the
--   client drain/retry engine (packages/sync, packages/data_remote); ledger
--   retention (Q-019); poison operator tooling (Q-020); any Dart/config/remote/secrets.
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. sync_operations — the server inbox / processed-operation ledger (D-010/D-022).
--    Identity = (organization_id, device_id, local_operation_id). Tenant+branch
--    scoped; cross-org/branch/device refs structurally impossible via composite
--    same-org FKs (D-012 layer 4). Written ONLY by app.sync_push; authenticated
--    gets SELECT only (writes revoked). No float/money columns (D-007).
-- ----------------------------------------------------------------------------
create table sync_operations (
  id                  uuid        not null default gen_random_uuid(),
  organization_id     uuid        not null references organizations (id) on delete restrict,
  restaurant_id       uuid        not null,
  branch_id           uuid        not null,
  device_id           uuid        not null,
  local_operation_id  text        not null,
  operation_type      text        not null
                        check (operation_type in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close')),
  target_entity       text,
  target_id           uuid,                                   -- soft reference to the affected row (no FK)
  payload             jsonb       not null,
  payload_fingerprint text        not null,                   -- md5(operation_type|payload::text); secondary same-key/different-payload guard (NOT identity)
  depends_on          jsonb       not null default '[]'::jsonb,
  status              text        not null default 'in_flight'
                        check (status in ('created', 'pending', 'in_flight', 'applied', 'rejected', 'dead', 'conflict', 'resolved')),
  result              jsonb,
  retry_count         integer     not null default 0 check (retry_count >= 0),
  last_error_code     text,
  last_error_class    text        check (last_error_class is null or last_error_class in ('transient', 'permanent', 'conflict')),
  conflict_info       jsonb,
  rejection_reason    text,
  client_created_at   timestamptz,
  server_received_at  timestamptz not null default now(),
  applied_at          timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  primary key (id),
  unique (organization_id, device_id, local_operation_id),    -- transport idempotency identity (D-022)
  constraint sync_operations_payload_is_object   check (jsonb_typeof(payload)    = 'object'),
  constraint sync_operations_depends_on_is_array check (jsonb_typeof(depends_on) = 'array'),
  foreign key (organization_id, restaurant_id, branch_id, device_id)
    references devices (organization_id, restaurant_id, branch_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict
);

comment on table sync_operations is
  'RF-056: server inbox / processed-operation ledger (D-010, API_CONTRACT §4.14, DOMAIN_MODEL §10.1). One row per (organization_id, device_id, local_operation_id) = the transport idempotency identity (D-022); a replay returns the stored result rather than re-dispatching. status mirrors the RF-018 local SyncOperationState (D-018). Written ONLY by app.sync_push (SECURITY DEFINER; D-011); authenticated SELECT-only. payload_fingerprint is a SECONDARY same-key/different-payload guard, never the identity (A4). No money columns: the dispatched RPCs are server-authoritative on money/sequences (D-007/D-021).';

create index sync_operations_device_status_idx on sync_operations (organization_id, device_id, status);
create index sync_operations_branch_idx        on sync_operations (organization_id, restaurant_id, branch_id);
create index sync_operations_target_idx        on sync_operations (organization_id, target_entity, target_id);

create trigger sync_operations_set_updated_at
  before update on sync_operations for each row execute function app.set_updated_at();

alter table sync_operations enable row level security;
alter table sync_operations force  row level security;

create policy sync_operations_scoped on sync_operations
  for all to authenticated
  using      (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id))
  with check (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));

grant select on sync_operations to authenticated;
revoke insert, update, delete on sync_operations from authenticated;

-- ----------------------------------------------------------------------------
-- 2. app.sync_push — the API_CONTRACT §4.14 batch push RPC. Validates the PIN
--    session + active device (A8), then processes the ordered batch one op at a
--    time: dedup/replay -> dependency guard -> dispatch (per-op EXCEPTION block) ->
--    record outcome. Returns a per-operation result array (NOT all-or-nothing; A7).
--    Actor + org/restaurant/branch are derived from the PIN session, never the payload.
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
  v_so_id        uuid;
  v_dispatch     jsonb;
  v_dispatch_ok  boolean;
  v_caught_state text;
  v_caught_msg   text;
  v_results      jsonb := '[]'::jsonb;
  v_op_result    jsonb;
begin
  -- (0) batch shape + a conservative size cap (no frozen limit in docs; 100 is the
  --     interim cap, surfaced here and in the tests — keeps a push transaction bounded).
  if p_operations is null or jsonb_typeof(p_operations) <> 'array' then
    raise exception 'sync_push: p_operations must be a JSON array' using errcode = '42501';
  end if;
  if jsonb_array_length(p_operations) > 100 then
    raise exception 'sync_push: batch too large (max 100 operations, got %)', jsonb_array_length(p_operations) using errcode = '42501';
  end if;

  -- (a) PIN session + backing device session/pairing active (A8). A revoked/expired
  --     device or session fails the WHOLE batch (RISK R-007). Scope is derived here.
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
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'sync_push: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'sync_push: device_id does not match the PIN session device' using errcode = '42501';
  end if;

  -- (b) per-operation loop (ordered)
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
    v_target_id  := nullif(v_op ->> 'target_id', '')::uuid;
    v_client_ts  := nullif(v_op ->> 'client_created_at', '')::timestamptz;

    -- (b1) envelope shape validation. Malformed envelopes are returned rejected
    --      WITHOUT a ledger row (they cannot be keyed/stored safely); they never dispatch.
    if v_local_op is null or btrim(v_local_op) = '' then
      v_results := v_results || jsonb_build_object('ok', false, 'error', 'invalid_envelope',
        'detail', 'local_operation_id is required', 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;
    if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close') then
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

    v_fingerprint := md5(v_op_type || '|' || v_payload::text);

    -- (b2) dedup / replay (transport identity = org + device + local_operation_id).
    select so.status, so.result, so.operation_type, so.payload_fingerprint
      into v_ex_status, v_ex_result, v_ex_optype, v_ex_fp
      from public.sync_operations so
      where so.organization_id = v_org and so.device_id = p_device_id and so.local_operation_id = v_local_op;
    if found then
      -- (RF056-B1) Compare the operation IDENTITY (operation_type + payload_fingerprint)
      -- FIRST, for EVERY existing status (created/pending/in_flight/applied/rejected/
      -- dead/conflict/resolved). A key reused with a DIFFERENT operation_type or payload
      -- is a conflict REGARDLESS of the stored status: it must never dispatch and must
      -- never overwrite the stored op (we `continue` BEFORE any upsert, so the original
      -- operation_type / payload / payload_fingerprint / status are preserved). Only once
      -- the identity MATCHES do we branch on status (terminal -> replay; non-terminal ->
      -- safe same-payload re-attempt). This closes the prior hole where pending/in_flight/
      -- created/resolved rows fell through as re-attempts without comparing identity.
      if v_ex_optype <> v_op_type or v_ex_fp <> v_fingerprint then
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_conflict', null, null,
                jsonb_build_object('local_operation_id', v_local_op, 'stored_operation_type', v_ex_optype, 'pushed_operation_type', v_op_type,
                                   'stored_status', v_ex_status, 'reason', 'idempotency_key_reused_with_different_operation_or_payload'));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'conflict', 'detail', 'idempotency key already used for a different operation/payload', 'status', 'conflict', 'idempotency_replay', false);
        continue;
      end if;
      -- identity matches the stored op
      if v_ex_status in ('applied', 'rejected', 'dead', 'conflict') then
        -- terminal -> return the stored result, do NOT re-dispatch
        v_results := v_results || (coalesce(v_ex_result, '{}'::jsonb)
          || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', v_ex_status, 'idempotency_replay', true));
        continue;
      end if;
      -- non-terminal (created/pending/in_flight/resolved) with the SAME identity:
      -- fall through as a safe same-payload re-attempt (dependency check + dispatch below).
    end if;

    -- (b3) dependency guard: every depends_on local_operation_id must already be
    --      'applied' for this (org, device). If not, this op is TRANSIENT
    --      dependency_not_ready (status pending) — NOT a permanent rejection; it never
    --      dispatches now and can apply on a later retry once the prerequisite applies.
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
      insert into public.sync_operations as so (
        organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type,
        target_entity, target_id, payload, payload_fingerprint, depends_on, status,
        last_error_code, last_error_class, client_created_at)
      values (v_org, v_rest, v_branch, p_device_id, v_local_op, v_op_type,
              v_target_ent, v_target_id, v_payload, v_fingerprint, v_depends, 'pending',
              'dependency_not_ready', 'transient', v_client_ts)
      on conflict (organization_id, device_id, local_operation_id) do update
        set status = 'pending', last_error_code = 'dependency_not_ready', last_error_class = 'transient',
            retry_count = so.retry_count + 1, updated_at = now();
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
        'error', 'dependency_not_ready', 'retryable', true, 'status', 'pending', 'idempotency_replay', false);
      continue;
    end if;

    -- (b4) mark in_flight (insert new, or bump a re-attempt)
    insert into public.sync_operations as so (
      organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type,
      target_entity, target_id, payload, payload_fingerprint, depends_on, status, client_created_at)
    values (v_org, v_rest, v_branch, p_device_id, v_local_op, v_op_type,
            v_target_ent, v_target_id, v_payload, v_fingerprint, v_depends, 'in_flight', v_client_ts)
    on conflict (organization_id, device_id, local_operation_id) do update
      set status = 'in_flight', retry_count = so.retry_count + 1, updated_at = now()
    returning so.id into v_so_id;

    -- (b5) dispatch to the matching business RPC inside a per-op EXCEPTION subtransaction
    --      (A7). Args are extracted from payload here, so a bad cast is caught and the op
    --      is rejected without aborting the batch. The dispatched RPC owns its own
    --      idempotency ledger + success audit (A6) + money authority (D-007/D-021); we
    --      pass the SAME pin session + device (A8). On RAISE the savepoint rolls back the
    --      dispatched mutation; on a returned {ok:false} (e.g. permission_denied) it commits.
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
      end case;
      v_dispatch_ok := coalesce((v_dispatch ->> 'ok')::boolean, false);
    exception
      when others then
        v_caught_state := SQLSTATE;
        v_caught_msg   := SQLERRM;
    end;

    -- (b6) finalize the operation outcome
    if v_caught_state is not null then
      -- a RAISE from the dispatched RPC (its mutation was rolled back by the savepoint)
      if v_caught_state = '40001' then
        -- optimistic-concurrency / order-bound key conflict -> conflict (resolution = RF-057)
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
        -- validation / state / business-rule failure -> permanent rejected
        update public.sync_operations
          set status = 'rejected', last_error_code = v_caught_state, last_error_class = 'permanent',
              rejection_reason = v_caught_msg,
              result = jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', v_caught_state), updated_at = now()
          where id = v_so_id;
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected', v_caught_msg, null,
                jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'sqlstate', v_caught_state));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'rejected', 'sqlstate', v_caught_state, 'status', 'rejected', 'idempotency_replay', false);
      end if;
    elsif v_dispatch_ok then
      -- applied: business mutation + its own audit + its own ledger committed
      update public.sync_operations
        set status = 'applied', result = v_dispatch, applied_at = now(),
            target_id = coalesce(v_target_id, nullif(v_dispatch ->> 'order_id', '')::uuid, nullif(v_dispatch ->> 'shift_id', '')::uuid, nullif(v_dispatch ->> 'payment_id', '')::uuid),
            updated_at = now()
        where id = v_so_id;
      v_results := v_results || (v_dispatch
        || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', 'applied', 'idempotency_replay', false));
    else
      -- the dispatched RPC RETURNED {ok:false} (e.g. permission_denied denial path) -> rejected
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
  'RF-056 (API_CONTRACT §4.14, D-010/D-022) SECURITY DEFINER batch push RPC. Validates the PIN session + active device/pairing (A8; a revoked device fails the whole batch, R-007); derives org/restaurant/branch server-side (never from payload). Per operation, in order: dedup/replay via sync_operations (terminal -> stored result; same key + different payload/op -> conflict), dependency guard (transient dependency_not_ready, status pending), then DISPATCH to the matching business RPC (shift.open->open_shift, order.submit->submit_order, order.discount->apply_discount, payment.create->record_payment, shift.close->close_shift; A3) inside a per-op EXCEPTION subtransaction (A7) so one failure never rolls back applied ops. Applied/rejected(permanent)/conflict(40001) classified + stored; sync.operation_rejected / sync.operation_conflict audits written (A6); success audits + money authority stay with the dispatched RPCs (D-007/D-021). Returns a per-operation result array. Reimplements NO business logic (A2). RF-055 payment preconditions/locks are enforced by record_payment, not bypassed.';

revoke all on function app.sync_push(uuid, uuid, jsonb) from public;
grant execute on function app.sync_push(uuid, uuid, jsonb) to authenticated;

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; cleanliness gate is
-- `supabase db reset`. Reverse-dependency teardown:
-- ----------------------------------------------------------------------------
-- drop function if exists app.sync_push(uuid, uuid, jsonb);
-- drop table if exists sync_operations;
-- ============================================================================
