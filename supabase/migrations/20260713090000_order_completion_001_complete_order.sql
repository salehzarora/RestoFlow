-- ============================================================================
-- ORDER-COMPLETION-001 — one safe, authorized, idempotent served -> completed
-- workflow, reachable from the owner/manager Dashboard.
--
-- WHY THIS EXISTS: ACTIVE-ORDERS-001 shipped a read-only board of every order
-- still open. It cannot drain, because NO client ever writes 'completed': the
-- KDS is the only status writer and its highest value is 'served'. The canonical
-- writer app.update_order_status DOES permit served -> completed, but it is
-- PIN-SESSION + DEVICE-BOUND BY SIGNATURE (raises 42501 without a valid PIN
-- session and an active paired device) and has NO public wrapper — pgTAP even
-- asserts none may exist (mvp_order_status_sync_test.sql:248). The Dashboard is a
-- JWT (auth.uid()) principal with no PIN session, so it structurally cannot reach
-- the writer.
--
-- THE SHAPE (approved): ONE state machine, TWO actor-resolving fronts.
--   * NEW  app.apply_order_status_transition — the ACTOR-AGNOSTIC CORE. It owns
--          the ONLY copy of the transition rules (scope, legality, role gate,
--          payment gate, write, audit). It resolves no actor: the caller hands it
--          an already-authenticated, already-scoped actor.
--   * KEPT app.update_order_status — the PIN/device front. SAME SIGNATURE, same
--          gates, same errors, same audit; it now DELEGATES to the core. Every
--          existing caller (app.sync_push's 'order.status' dispatch, the KDS) and
--          every existing pgTAP assertion is unchanged.
--   * NEW  app.owner_complete_order (+ public SECURITY INVOKER wrapper) — the JWT
--          front. Resolves the actor from auth.uid() (the owner_* idiom), authorizes
--          over the ORDER's own scope, and delegates to the SAME core.
-- There is deliberately NO second implementation of the state machine, and NO
-- public.update_order_status wrapper (the hasnt_function assertion stays true).
--
-- D-025 PAYMENT GATE (behaviour change, deliberate and human-approved):
--   docs/STATE_MACHINES.md D-025 (frozen): "An order reaches `completed` only when
--   fulfillment is satisfied AND (for a chargeable order) payment is `completed`."
--   The shipped writer NEVER checked payments — it would happily complete an
--   UNPAID order, in violation of a frozen decision on a MONEY rule (RISK R-008).
--   The core now ENFORCES it: completing an order with no `completed` payment
--   returns the stable domain error `order_not_paid` and writes NOTHING.
--   Scope of the change: this affects ONLY the -> completed transition, which NO
--   live client performs today, so no shipped behaviour regresses. There is no
--   "chargeable" flag anywhere in the schema (the word appears only in prose), so
--   the rule is applied to every order; the escape routes are unchanged (settle
--   the order, or void it — an UNPAID void remains permitted).
--   PAYMENT STATE IS NEVER FABRICATED: completion creates no payment, marks nothing
--   paid, and touches no payments row. Payment and fulfillment remain independent
--   axes; this gate only makes fulfillment WAIT for payment, as D-025 requires.
--
-- AUDIT: NO new action key. The core keeps emitting the existing, already-covered
--   'order.status_updated' / 'order.status_update_denied' (app.audit_category maps
--   'order.status%' -> 'orders', so completion can never fall into "Other"). It now
--   additionally records the SAFE 'order_code' and, on completion, 'payment_status'
--   — both added to the app.audit_safe_detail allowlist below. Still money-free
--   (T-003): no *_minor figure is ever written by this path.
--
-- Additive / forward-only. No table, column, CHECK, RLS policy, trigger or index
-- changes. No historical order or audit row is rewritten.
-- PENDING: RISK R-003 human RLS/security sign-off. NOT applied to hosted DB here.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. app.apply_order_status_transition — THE ACTOR-AGNOSTIC CORE.
--    The single implementation of the order state machine. It NEVER resolves an
--    actor and NEVER trusts a client: its caller must already have authenticated
--    the actor and established that the actor covers the order's scope. The core
--    then re-verifies the order really is in that scope (defence in depth).
-- ---------------------------------------------------------------------------
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
  v_order_code text := '#' || upper(right(replace(p_order_id::text, '-', ''), 6));
begin
  -- (a) load the order FOR UPDATE (serializes concurrent status pushes); it MUST
  --     be in the actor's organization AND branch. Cross-tenant -> fail-closed
  --     raise, no write.
  select o.organization_id, o.branch_id, o.status, o.revision
    into v_o_org, v_o_branch, v_o_status, v_o_rev
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
    select exists (
      select 1 from public.payments p
      where p.organization_id = v_o_org
        and p.order_id        = p_order_id
        and p.deleted_at is null
        and p.status          = 'completed'
    ) into v_paid;
    if not v_paid then
      return jsonb_build_object('ok', false, 'error', 'order_not_paid',
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
    set status = p_new_status, revision = v_new_rev
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
          || case when p_new_status = 'completed'
                  then jsonb_build_object('payment_status', 'paid')
                  else '{}'::jsonb end);

  return jsonb_build_object('ok', true, 'entity', 'order', 'order_id', p_order_id,
                            'order_code', v_order_code,
                            'status', p_new_status, 'revision', v_new_rev,
                            'server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.apply_order_status_transition(uuid, text, uuid, uuid, uuid, text, uuid, uuid, uuid, uuid, text, integer) is
  'ORDER-COMPLETION-001: the ACTOR-AGNOSTIC CORE of the order state machine (D-018, STATE_MACHINES §1.1) — the SINGLE implementation of scope re-check, single-step transition legality, role authorization, the D-025 payment gate, the write and the audit. It resolves NO actor and trusts NO client: the caller (app.update_order_status for a PIN/device principal, app.owner_complete_order for a JWT principal) must already have authenticated the actor and established scope coverage. INTERNAL: not granted to any client role — reachable only from the SECURITY DEFINER fronts.';

-- ---------------------------------------------------------------------------
-- 2. app.update_order_status — the PIN/DEVICE front. UNCHANGED signature, gates,
--    errors and audit; it now delegates the state machine to the core. Every
--    existing caller (app.sync_push -> 'order.status' -> the KDS bump) and every
--    existing pgTAP assertion continues to hold. The ONLY behavioural difference
--    is the D-025 payment gate on -> completed, which NO live client performs.
--    Still NO public wrapper (dispatcher-reachable only, like app.submit_order).
-- ---------------------------------------------------------------------------
create or replace function app.update_order_status(
  p_pin_session_id     uuid,
  p_device_id          uuid,
  p_order_id           uuid,
  p_new_status         text,
  p_local_operation_id text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org        uuid;
  v_rest       uuid;
  v_branch     uuid;
  v_dsid       uuid;
  v_emp        uuid;
  v_membership uuid;
  v_ds_device  uuid;
  v_ds_active  boolean;
  v_ds_revoked timestamptz;
  v_pairing    text;
  v_role       text;
  v_m_status   text;
  v_m_deleted  timestamptz;
begin
  -- (a) PIN session + backing device session/pairing; derive actor + scope
  --     (identical gate to app.submit_order — never trusts client scope).
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'update_order_status: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'update_order_status: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'update_order_status: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'update_order_status: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  -- membership active (message keeps the exact 'resolved membership is not active'
  -- fragment so the RF-061 revoked_employee classification in sync_push still applies).
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'update_order_status: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) delegate the state machine to the single core. The PIN actor is an
  --     employee_profile (no app_user); expected_revision is null, preserving the
  --     existing lock-only concurrency behaviour for the device path.
  return app.apply_order_status_transition(
    p_order_id,
    p_new_status,
    v_org, v_rest, v_branch,
    v_role,
    null,          -- actor_app_user_id (device path has none)
    v_emp,         -- actor_employee_profile_id
    v_membership,
    p_device_id,
    p_local_operation_id,
    null           -- expected_revision: unchanged (lock-serialized) device behaviour
  );
end;
$$;

comment on function app.update_order_status(uuid, uuid, uuid, text, text) is
  'MVP order-status RPC (D-011, D-018, STATE_MACHINES §1.1). Actor/org/branch derived from the PIN session (submit_order gate: valid PIN session + active device session/pairing + device match + active membership), then DELEGATED to app.apply_order_status_transition (ORDER-COMPLETION-001 — the single state-machine core; this front is unchanged in signature, gates, errors and audit). The order is loaded FOR UPDATE and must be in the session org+branch (cross-tenant -> 42501, fail-closed). SINGLE-STEP forward transitions only: submitted->accepted / accepted->preparing / preparing->ready / ready->served (the KDS bump; kitchen_staff/cashier/manager/restaurant_owner/org_owner) and served->completed (cashier/manager/restaurant_owner/org_owner ONLY; kitchen_staff denied -> audited order.status_update_denied + returned permission_denied). Any other from/to -> returned invalid_transition, no write. ->completed additionally requires a `completed` payment (D-025) or returns order_not_paid, no write. Success bumps orders.revision + updated_at (trigger) and writes an append-only order.status_updated audit with NO money fields (T-003/D-013). Transport idempotency is the sync_operations ledger in app.sync_push (D-022). Dispatcher-reachable only: NO public wrapper (mirrors app.submit_order).';

-- ---------------------------------------------------------------------------
-- 3. app.owner_complete_order — the JWT (Dashboard) front.
--    Resolves the actor from auth.uid() (the owner_* idiom), authorizes over the
--    ORDER's own scope (downward-only), and delegates to the SAME core. It can
--    only ever request 'completed' — the target status is NOT a parameter, so a
--    Dashboard caller can never drive an arbitrary transition.
--    IDEMPOTENT: completing an already-completed order returns a stable success
--    (already_completed) with NO second write and NO second audit event.
-- ---------------------------------------------------------------------------
create or replace function app.owner_complete_order(
  p_organization_id   uuid,
  p_order_id          uuid,
  p_expected_revision integer default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor      uuid := app.current_app_user_id();
  v_rank       integer;
  v_o_rest     uuid;
  v_o_branch   uuid;
  v_o_status   text;
  v_o_rev      integer;
  v_role       text;
  v_membership uuid;
  v_order_code text;
begin
  if v_actor is null then
    raise exception 'owner_complete_order: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_order_id is null then
    raise exception 'owner_complete_order: organization_id and order_id are required' using errcode = '22023';
  end if;

  -- (a) TENANT GATE — FIRST, and BEFORE the order is even looked up. A caller with
  --     no active membership in the organization is rejected identically whether
  --     the order exists or not, so the not_found below can never become a
  --     CROSS-TENANT EXISTENCE ORACLE (RISK R-003). (An org-level
  --     actor_rank_in_scope(org, null, null) cannot be used here: its scope filter
  --     would reject a legitimately branch-scoped manager.)
  if not exists (
    select 1 from public.memberships m
    where m.app_user_id     = v_actor
      and m.organization_id = p_organization_id
      and m.status          = 'active'
      and m.deleted_at is null
  ) then
    raise exception 'owner_complete_order: caller has no active membership in the organization' using errcode = '42501';
  end if;

  -- (b) the order, scoped to the caller's organization. A miss (wrong tenant /
  --     nonexistent / deleted) is a clean not_found, and the tenant gate above
  --     means only an in-org caller can ever observe the difference.
  select o.restaurant_id, o.branch_id, o.status, o.revision
    into v_o_rest, v_o_branch, v_o_status, v_o_rev
    from public.orders o
    where o.id              = p_order_id
      and o.organization_id = p_organization_id
      and o.deleted_at is null;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'owner_complete_order');
  end if;
  v_order_code := '#' || upper(right(replace(p_order_id::text, '-', ''), 6));

  -- (c) authority over the ORDER's OWN scope (downward-only coverage), so a
  --     branch manager cannot complete a SIBLING branch's order.
  v_rank := app.actor_rank_in_scope(p_organization_id, v_o_rest, v_o_branch);
  if v_rank = 0 then
    raise exception 'owner_complete_order: caller has no active membership covering the order scope' using errcode = '42501';
  end if;

  -- (d) role: the SAME settlement allowlist the core enforces (kitchen_staff and
  --     accountant are NOT settlement roles). Pick the highest covering membership
  --     so the audit records the authority actually used. A denial is audited with
  --     the JWT actor and RETURNED (never raised, so the audit row persists).
  select m.role, m.id
    into v_role, v_membership
    from public.memberships m
    where m.app_user_id     = v_actor
      and m.organization_id = p_organization_id
      and m.status          = 'active'
      and m.deleted_at is null
      and m.role in ('cashier', 'manager', 'restaurant_owner', 'org_owner')
      and (m.restaurant_id is null or m.restaurant_id = v_o_rest)
      and (m.branch_id     is null or m.branch_id     = v_o_branch)
    order by case m.role
               when 'org_owner'        then 4
               when 'restaurant_owner' then 3
               when 'manager'          then 2
               else 1
             end desc
    limit 1;
  if not found then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (p_organization_id, v_o_rest, v_o_branch, v_actor, null, null,
            'order.status_update_denied', null, null,
            jsonb_build_object('attempted_action', 'owner_complete_order', 'order_id', p_order_id,
                               'order_code', v_order_code,
                               'from', v_o_status, 'to', 'completed'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_complete_order',
                              'order_id', p_order_id);
  end if;

  -- (e) IDEMPOTENCY: the order is already in the desired terminal state. Return a
  --     stable success WITHOUT a second write and WITHOUT a second audit event, so
  --     a retry (or a double-tap that raced) is safe and semantically inert.
  if v_o_status = 'completed' then
    return jsonb_build_object('ok', true, 'entity', 'order', 'order_id', p_order_id,
                              'order_code', v_order_code, 'status', 'completed',
                              'revision', v_o_rev, 'already_completed', true,
                              'server_ts', now(), 'idempotency_replay', true);
  end if;

  -- (f) delegate to the SINGLE core. The target status is hard-coded: this front
  --     can ONLY complete. The core re-verifies scope, legality, role and the
  --     D-025 payment gate, and writes the audit with the JWT actor.
  return app.apply_order_status_transition(
    p_order_id,
    'completed',
    p_organization_id, v_o_rest, v_o_branch,
    v_role,
    v_actor,       -- actor_app_user_id (JWT principal)
    null,          -- actor_employee_profile_id (no PIN session)
    v_membership,
    null,          -- device_id (no device)
    null,          -- local_operation_id (not a sync operation)
    p_expected_revision
  );
end;
$$;

comment on function app.owner_complete_order(uuid, uuid, integer) is
  'ORDER-COMPLETION-001 (write; D-011/D-013/D-018/D-025): the owner/manager Dashboard''s served -> completed action. The JWT front of the order state machine — identity from auth.uid() -> app.current_app_user_id() (null -> 42501), authority from app.actor_rank_in_scope over the ORDER''s OWN scope (0 -> 42501, downward-only, so a branch manager cannot complete a sibling branch''s order), settlement-role allowlist cashier/manager/restaurant_owner/org_owner (kitchen_staff + accountant -> audited order.status_update_denied + returned permission_denied). It then DELEGATES to app.apply_order_status_transition — there is no second state machine. The target status is HARD-CODED ''completed'': a client can never choose an arbitrary next status, supply an actor, or supply a timestamp. IDEMPOTENT: an already-completed order returns {ok:true, already_completed:true} with no second write and no second audit event. Optional p_expected_revision gives stale-client protection (revision_mismatch + server_revision). An UNPAID order is REJECTED with order_not_paid (D-025); completion creates no payment and changes no payments row. An out-of-scope/missing order -> {ok:false,error:not_found} (no cross-tenant leak). No anon/service_role.';

-- ---------------------------------------------------------------------------
-- 4. Thin public SECURITY INVOKER wrapper — the PostgREST-reachable surface.
--    (Deliberately NOT a public.update_order_status wrapper: that function stays
--    dispatcher-only, and the pgTAP hasnt_function assertion remains true.)
-- ---------------------------------------------------------------------------
create or replace function public.owner_complete_order(
  p_organization_id uuid, p_order_id uuid, p_expected_revision integer default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.owner_complete_order(p_organization_id, p_order_id, p_expected_revision); $$;

-- ---------------------------------------------------------------------------
-- 5. app.audit_safe_detail — faithfully re-created (AUDIT-COVERAGE-002 body) with
--    TWO additions to the safe scalar allowlist:
--      * order_code     — the SAFE human reference ('#XXXXXX'), the same code every
--                         other surface shows. NOT the order UUID.
--      * payment_status — 'paid'/'unpaid'. A STATE, not a money figure (T-003 holds:
--                         no *_minor value is added).
--    Everything else is byte-for-byte the AUDIT-COVERAGE-002 projection.
-- ---------------------------------------------------------------------------
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
    'order_code','payment_status'
  ] loop
    if p_values ? v_key
       and jsonb_typeof(p_values -> v_key) in ('string','number','boolean') then
      v_out := v_out || jsonb_build_object(v_key, p_values -> v_key);
    end if;
  end loop;

  -- The ONLY allowlisted nested object: `capabilities`, kept to its three
  -- canonical boolean capability keys (unknown nested keys dropped).
  if jsonb_typeof(p_values -> 'capabilities') = 'object' then
    select coalesce(jsonb_object_agg(k, p_values -> 'capabilities' -> k), '{}'::jsonb)
      into v_caps
      from unnest(array['apply_discount','void_order','close_shift']) as k
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
  'AUDIT-LOG-DASHBOARD-001 + AUDIT-COVERAGE-002 + ORDER-COMPLETION-001: ALLOWLIST projection of ONE audit payload (old or new) to canonical safe fields. Gated by app.audit_action_has_detail (unsupported action -> ''{}''). Emits only allowlisted scalar keys (status/scope/discount_type/value/attempted_action/order_type/roles/*_minor money/voided_item_count/failed_attempt_count/locked/timezone/name/receipt_prefix + order_code/payment_status) plus the nested `capabilities` object (3 canonical booleans). order_code is the SAFE ''#XXXXXX'' reference (never the order UUID); payment_status is a STATE (''paid''/''unpaid''), not a money figure (T-003). Every un-listed key (secret OR unknown) and every other nested structure is DROPPED. Malformed/non-object -> ''{}''; never throws. This is the server-side privacy boundary; the RPC returns NO raw payload JSON.';

-- ---------------------------------------------------------------------------
-- 6. Grants.
--    * the CORE is INTERNAL: no client role may execute it directly. The two
--      SECURITY DEFINER fronts run as the function owner and reach it that way.
--    * owner_complete_order: authenticated ONLY. `anon` is revoked EXPLICITLY on
--      both (revoke-from-PUBLIC does NOT remove the grant hosted Supabase's
--      ALTER DEFAULT PRIVILEGES hands to anon at CREATE time — the defect
--      AUDIT-LOG-DASHBOARD-001 had to correct). Never service_role (D-011).
-- ---------------------------------------------------------------------------
revoke all on function app.apply_order_status_transition(uuid, text, uuid, uuid, uuid, text, uuid, uuid, uuid, uuid, text, integer) from public;
revoke all on function app.apply_order_status_transition(uuid, text, uuid, uuid, uuid, text, uuid, uuid, uuid, uuid, text, integer) from anon;
revoke all on function app.apply_order_status_transition(uuid, text, uuid, uuid, uuid, text, uuid, uuid, uuid, uuid, text, integer) from authenticated;

revoke all on function app.update_order_status(uuid, uuid, uuid, text, text) from public;
revoke all on function app.update_order_status(uuid, uuid, uuid, text, text) from anon;
grant execute on function app.update_order_status(uuid, uuid, uuid, text, text) to authenticated;

revoke all on function app.owner_complete_order(uuid, uuid, integer)    from public;
revoke all on function app.owner_complete_order(uuid, uuid, integer)    from anon;
grant execute on function app.owner_complete_order(uuid, uuid, integer) to authenticated;

revoke all on function public.owner_complete_order(uuid, uuid, integer)    from public;
revoke all on function public.owner_complete_order(uuid, uuid, integer)    from anon;
grant execute on function public.owner_complete_order(uuid, uuid, integer) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists public.owner_complete_order(uuid, uuid, integer);
--   drop function if exists app.owner_complete_order(uuid, uuid, integer);
--   -- restore app.update_order_status + app.audit_safe_detail from their prior
--   -- migrations (20260702130000 / 20260711120000), then:
--   drop function if exists app.apply_order_status_transition(uuid, text, uuid, uuid, uuid, text, uuid, uuid, uuid, uuid, text, integer);
-- ============================================================================
